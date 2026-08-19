import Foundation
import MacFanCore
import ServiceManagement

enum ThermalServiceClientError: Error {
    case unavailable
    case emptySnapshot
}

@MainActor
final class ThermalServiceClient {
    private let encoder: JSONEncoder = JSONEncoder()
    private let decoder: JSONDecoder = JSONDecoder()
    private let connection: NSXPCConnection

    init() {
        connection = NSXPCConnection(
            machServiceName: ThermalService.machServiceName,
            options: .privileged
        )
        connection.remoteObjectInterface = NSXPCInterface(
            with: ThermalServiceProtocol.self
        )
        connection.resume()
    }

    deinit {
        connection.invalidate()
    }

    func registerHelper() throws -> SMAppService.Status {
        let service: SMAppService = SMAppService.daemon(
            plistName: ThermalService.daemonPlistName
        )
        guard service.status != .enabled else {
            return service.status
        }
        try service.register()
        return service.status
    }

    func latestSnapshot() async throws -> ThermalSnapshot {
        let data: Data = try await withCheckedThrowingContinuation { continuation in
            guard let service: ThermalServiceProtocol = proxy(
                errorHandler: { continuation.resume(throwing: $0) }
            ) else {
                continuation.resume(throwing: ThermalServiceClientError.unavailable)
                return
            }

            service.latestSnapshot { data, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: ThermalServiceClientError.emptySnapshot)
                }
            }
        }
        return try decoder.decode(ThermalSnapshot.self, from: data)
    }

    func setPolicy(_ policy: FanPolicy, fanID: Int) async throws {
        let data: Data = try encoder.encode(policy)
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            guard let service: ThermalServiceProtocol = proxy(
                errorHandler: { continuation.resume(throwing: $0) }
            ) else {
                continuation.resume(throwing: ThermalServiceClientError.unavailable)
                return
            }

            service.setPolicy(data, fanID: fanID) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    func restoreAutomaticControl() {
        proxy(errorHandler: { _ in })?.restoreAutomaticControl(reply: {})
    }

    private func proxy(
        errorHandler: @escaping (Error) -> Void
    ) -> ThermalServiceProtocol? {
        connection.remoteObjectProxyWithErrorHandler(errorHandler)
            as? ThermalServiceProtocol
    }
}
