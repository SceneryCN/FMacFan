import Foundation

public enum ThermalSide: String, Codable, CaseIterable, Sendable {
    case left
    case right
}

public enum FanControlMode: String, Codable, CaseIterable, Sendable {
    case automatic
    case curve
    case fixed
}

public struct CurvePoint: Codable, Equatable, Sendable {
    public let temperature: Double
    public let speedFraction: Double

    public init(temperature: Double, speedFraction: Double) {
        self.temperature = temperature
        self.speedFraction = speedFraction
    }
}

public struct FanPolicy: Codable, Equatable, Sendable {
    public var mode: FanControlMode
    public var fixedSpeedFraction: Double
    public var curve: [CurvePoint]

    public init(
        mode: FanControlMode = .automatic,
        fixedSpeedFraction: Double = 0.5,
        curve: [CurvePoint] = ThermalDefaults.standardCurve
    ) {
        self.mode = mode
        self.fixedSpeedFraction = fixedSpeedFraction
        self.curve = curve
    }
}

public struct FanDescriptor: Codable, Equatable, Identifiable, Sendable {
    public let id: Int
    public let side: ThermalSide
    public let minimumRPM: Double
    public let maximumRPM: Double

    public init(
        id: Int,
        side: ThermalSide,
        minimumRPM: Double,
        maximumRPM: Double
    ) {
        self.id = id
        self.side = side
        self.minimumRPM = minimumRPM
        self.maximumRPM = maximumRPM
    }
}

public struct FanSnapshot: Codable, Equatable, Identifiable, Sendable {
    public let descriptor: FanDescriptor
    public let actualRPM: Double
    public let targetRPM: Double
    public let temperature: Double?
    public let policy: FanPolicy

    public var id: Int { descriptor.id }

    public init(
        descriptor: FanDescriptor,
        actualRPM: Double,
        targetRPM: Double,
        temperature: Double?,
        policy: FanPolicy
    ) {
        self.descriptor = descriptor
        self.actualRPM = actualRPM
        self.targetRPM = targetRPM
        self.temperature = temperature
        self.policy = policy
    }
}

public struct ThermalSnapshot: Codable, Equatable, Sendable {
    public let fans: [FanSnapshot]
    public let timestamp: Date

    public init(fans: [FanSnapshot], timestamp: Date = Date()) {
        self.fans = fans
        self.timestamp = timestamp
    }
}

public enum ThermalDefaults {
    public static let standardCurve: [CurvePoint] = [
        CurvePoint(temperature: 40, speedFraction: 0),
        CurvePoint(temperature: 60, speedFraction: 0.30),
        CurvePoint(temperature: 75, speedFraction: 0.65),
        CurvePoint(temperature: 90, speedFraction: 1),
    ]

    public static let emergencyTemperature: Double = 100
    public static let sensorValidityRange: ClosedRange<Double> = -10...125
    public static let controlInterval: Duration = .milliseconds(500)
    public static let idleInterval: Duration = .seconds(2)
    public static let clientHeartbeatTimeout: TimeInterval = 5
    public static let watchdogIntervalNanoseconds: UInt64 = 2_000_000_000
    public static let maximumRPMChangePerSecond: Double = 1_200
    public static let minimumRPMWriteDelta: Double = 20
    public static let temperatureSmoothingFactor: Double = 0.25
}
