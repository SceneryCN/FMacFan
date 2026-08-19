import Foundation
import MacFanCore
import ServiceManagement

@MainActor
final class AppModel: ObservableObject {
    enum ConnectionStatus: String {
        case connecting
        case active
        case approvalRequired
        case unavailable

        var localizationKey: String {
            "status.\(rawValue)"
        }
    }

    private static let refreshIntervalNanoseconds: UInt64 = 1_000_000_000

    @Published private(set) var snapshot: ThermalSnapshot?
    @Published private(set) var status: ConnectionStatus = .connecting
    @Published private(set) var launchAtLoginEnabled: Bool
    @Published var policies: [Int: FanPolicy] = [:]

    private let service: ThermalServiceClient
    private var refreshTask: Task<Void, Never>?

    convenience init() {
        self.init(service: ThermalServiceClient())
    }

    init(service: ThermalServiceClient) {
        self.service = service
        launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
    }

    deinit {
        refreshTask?.cancel()
    }

    func start() {
        guard refreshTask == nil else {
            return
        }

        do {
            if try service.registerHelper() != .enabled {
                status = .approvalRequired
            }
        } catch {
            status = .approvalRequired
        }

        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(
                    nanoseconds: Self.refreshIntervalNanoseconds
                )
            }
        }
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
        service.restoreAutomaticControl()
    }

    func policy(for fan: FanSnapshot) -> FanPolicy {
        policies[fan.id] ?? fan.policy
    }

    func setMode(_ mode: FanControlMode, fan: FanSnapshot) {
        var policy: FanPolicy = self.policy(for: fan)
        policy.mode = mode
        policies[fan.id] = policy
        commit(policy: policy, fanID: fan.id)
    }

    func setFixedSpeedFraction(_ fraction: Double, fan: FanSnapshot) {
        var policy: FanPolicy = self.policy(for: fan)
        policy.fixedSpeedFraction = min(max(fraction, 0), 1)
        policies[fan.id] = policy
    }

    func setCurveSpeedFraction(
        _ fraction: Double,
        pointIndex: Int,
        fan: FanSnapshot
    ) {
        var policy: FanPolicy = self.policy(for: fan)
        guard policy.curve.indices.contains(pointIndex) else {
            return
        }
        let point: CurvePoint = policy.curve[pointIndex]
        policy.curve[pointIndex] = CurvePoint(
            temperature: point.temperature,
            speedFraction: min(max(fraction, 0), 1)
        )
        policies[fan.id] = policy
    }

    func commit(fan: FanSnapshot) {
        commit(policy: policy(for: fan), fanID: fan.id)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
        } catch {
            launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
        }
    }

    private func refresh() async {
        do {
            let snapshot: ThermalSnapshot = try await service.latestSnapshot()
            self.snapshot = snapshot
            for fan: FanSnapshot in snapshot.fans where policies[fan.id] == nil {
                policies[fan.id] = fan.policy
            }
            status = .active
        } catch {
            if status != .approvalRequired {
                status = .unavailable
            }
        }
    }

    private func commit(policy: FanPolicy, fanID: Int) {
        Task {
            do {
                try await service.setPolicy(policy, fanID: fanID)
            } catch {
                status = .unavailable
            }
        }
    }
}
