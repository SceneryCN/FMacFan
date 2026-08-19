import Foundation

public enum ThermalService {
    public static let machServiceName: String = "com.evolte.MacFan.helper"
    public static let daemonPlistName: String = "com.evolte.MacFan.helper.plist"
}

@objc public protocol ThermalServiceProtocol {
    func latestSnapshot(
        reply: @escaping @Sendable (Data?, NSError?) -> Void
    )

    func setPolicy(
        _ encodedPolicy: Data,
        fanID: Int,
        reply: @escaping @Sendable (NSError?) -> Void
    )

    func restoreAutomaticControl(
        reply: @escaping @Sendable () -> Void
    )
}
