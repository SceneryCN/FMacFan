import Foundation

public actor ThermalController {
    private let smc: SMCClient
    private let clock: ContinuousClock = ContinuousClock()

    private var policies: [Int: FanPolicy] = [:]
    private var smoothedTemperatures: [ThermalSide: Double] = [:]
    private var previousTargets: [Int: Double] = [:]
    private var manualFanIDs: Set<Int> = []
    private var descriptors: [FanDescriptor] = []
    private var temperatureKeys: [String] = []
    private var temperatureKeysBySide: [ThermalSide: [String]] = [:]
    private var task: Task<Void, Never>?
    private var continuation: AsyncStream<ThermalSnapshot>.Continuation?

    public init(smc: SMCClient) {
        self.smc = smc
    }

    deinit {
        task?.cancel()
    }

    public func snapshots() -> AsyncStream<ThermalSnapshot> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            self.continuation = continuation
        }
    }

    public func start() async throws {
        guard task == nil else {
            return
        }

        descriptors = try discoverFans()
        temperatureKeys = try smc.temperatureKeys()
        temperatureKeysBySide = makeTemperatureTopology(keys: temperatureKeys)
        for descriptor: FanDescriptor in descriptors {
            policies[descriptor.id] = FanPolicy()
        }

        task = Task { [weak self] in
            await self?.runControlLoop()
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
        smc.restoreAutomaticControl(fanCount: descriptors.count)
        continuation?.finish()
    }

    public func setPolicy(_ policy: FanPolicy, fanID: Int) {
        guard descriptors.contains(where: { $0.id == fanID }) else {
            return
        }
        policies[fanID] = policy
    }

    public func restoreAutomaticPolicies() {
        for descriptor: FanDescriptor in descriptors {
            policies[descriptor.id] = FanPolicy(mode: .automatic)
        }
        manualFanIDs.removeAll(keepingCapacity: true)
        smc.restoreAutomaticControl(fanCount: descriptors.count)
    }

    private func discoverFans() throws -> [FanDescriptor] {
        let count: Int = try smc.fanCount()
        return try (0..<count).map { index in
            let minimum: Double = try smc.fanValue(index: index, suffix: "Mn")
            let maximum: Double = try smc.fanValue(index: index, suffix: "Mx")
            let side: ThermalSide = index == 0 ? .left : .right
            return FanDescriptor(
                id: index,
                side: side,
                minimumRPM: minimum,
                maximumRPM: maximum
            )
        }
    }

    private func runControlLoop() async {
        while !Task.isCancelled {
            let hasManualPolicy: Bool = policies.values.contains { $0.mode != .automatic }
            await sampleAndControl()

            do {
                let interval: Duration = hasManualPolicy
                    ? ThermalDefaults.controlInterval
                    : ThermalDefaults.idleInterval
                try await clock.sleep(
                    until: clock.now.advanced(by: interval)
                )
            } catch {
                break
            }
        }
        smc.restoreAutomaticControl(fanCount: descriptors.count)
    }

    private func sampleAndControl() async {
        let readings: [String: Double] = smc.temperatures(keys: temperatureKeys)
        guard let fallbackTemperature: Double = readings.values.max() else {
            manualFanIDs.removeAll(keepingCapacity: true)
            smc.restoreAutomaticControl(fanCount: descriptors.count)
            return
        }

        let snapshots: [FanSnapshot] = descriptors.compactMap { descriptor in
            let sideKeys: [String] = temperatureKeysBySide[descriptor.side] ?? []
            let rawTemperature: Double = sideKeys
                .compactMap { readings[$0] }
                .max() ?? fallbackTemperature
            let temperature: Double = smooth(rawTemperature, side: descriptor.side)
            let policy: FanPolicy = policies[descriptor.id] ?? FanPolicy()

            guard let actualRPM: Double = try? smc.fanValue(
                index: descriptor.id,
                suffix: "Ac"
            ) else {
                return nil
            }

            let targetRPM: Double = apply(
                policy: policy,
                descriptor: descriptor,
                temperature: temperature
            )

            return FanSnapshot(
                descriptor: descriptor,
                actualRPM: actualRPM,
                targetRPM: targetRPM,
                temperature: temperature,
                policy: policy
            )
        }

        continuation?.yield(ThermalSnapshot(fans: snapshots))
    }

    private func makeTemperatureTopology(
        keys: [String]
    ) -> [ThermalSide: [String]] {
        let cpuKeys: [String] = keys.filter {
            $0.hasPrefix("Tp") || $0.hasPrefix("Te")
        }
        let gpuKeys: [String] = keys.filter {
            $0.hasPrefix("Tg")
        }

        return [
            .left: cpuKeys.isEmpty ? keys : cpuKeys,
            .right: gpuKeys.isEmpty ? keys : gpuKeys,
        ]
    }

    private func apply(
        policy: FanPolicy,
        descriptor: FanDescriptor,
        temperature: Double
    ) -> Double {
        guard policy.mode != .automatic else {
            if manualFanIDs.remove(descriptor.id) != nil {
                try? smc.setManualMode(index: descriptor.id, enabled: false)
            }
            previousTargets[descriptor.id] = descriptor.minimumRPM
            return descriptor.minimumRPM
        }

        let requestedFraction: Double
        if temperature >= ThermalDefaults.emergencyTemperature {
            requestedFraction = 1
        } else if policy.mode == .fixed {
            requestedFraction = policy.fixedSpeedFraction
        } else {
            requestedFraction = FanCurve(points: policy.curve)
                .speedFraction(at: temperature)
        }

        let clampedFraction: Double = min(max(requestedFraction, 0), 1)
        let requestedRPM: Double = descriptor.minimumRPM
            + ((descriptor.maximumRPM - descriptor.minimumRPM) * clampedFraction)
        let previousRPM: Double = previousTargets[descriptor.id] ?? descriptor.minimumRPM
        let maximumStep: Double = ThermalDefaults.maximumRPMChangePerSecond
            * ThermalDefaults.controlInterval.seconds
        let targetRPM: Double
        if temperature >= ThermalDefaults.emergencyTemperature {
            targetRPM = descriptor.maximumRPM
        } else {
            targetRPM = min(
                max(requestedRPM, previousRPM - maximumStep),
                previousRPM + maximumStep
            )
        }

        do {
            let needsInitialWrite: Bool = !manualFanIDs.contains(descriptor.id)
            if needsInitialWrite {
                try smc.setManualMode(index: descriptor.id, enabled: true)
                manualFanIDs.insert(descriptor.id)
            }
            if needsInitialWrite
                || abs(targetRPM - previousRPM) >= ThermalDefaults.minimumRPMWriteDelta {
                try smc.setFanTarget(index: descriptor.id, rpm: targetRPM)
            }
            previousTargets[descriptor.id] = targetRPM
            return targetRPM
        } catch {
            try? smc.setManualMode(index: descriptor.id, enabled: false)
            manualFanIDs.remove(descriptor.id)
            previousTargets[descriptor.id] = descriptor.minimumRPM
            return descriptor.minimumRPM
        }
    }

    private func smooth(_ temperature: Double, side: ThermalSide) -> Double {
        let previous: Double = smoothedTemperatures[side] ?? temperature
        let factor: Double = ThermalDefaults.temperatureSmoothingFactor
        let smoothed: Double = previous + ((temperature - previous) * factor)
        smoothedTemperatures[side] = smoothed
        return smoothed
    }
}

private extension Duration {
    var seconds: Double {
        let components: (seconds: Int64, attoseconds: Int64) = self.components
        return Double(components.seconds)
            + (Double(components.attoseconds) / 1_000_000_000_000_000_000)
    }
}
