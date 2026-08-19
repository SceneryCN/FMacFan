import Darwin
import Foundation
import MacFanCore

private final class ThermalServiceImplementation:
    NSObject,
    ThermalServiceProtocol,
    @unchecked Sendable {
    private let controller: ThermalController
    private let encoder: JSONEncoder = JSONEncoder()
    private let decoder: JSONDecoder = JSONDecoder()
    private let lock: NSLock = NSLock()

    private var snapshot: ThermalSnapshot?
    private var startupError: NSError?
    private var lastContact: Date = Date()

    init(controller: ThermalController) {
        self.controller = controller
        super.init()

        Task {
            let stream: AsyncStream<ThermalSnapshot> = await controller.snapshots()
            do {
                try await controller.start()
                for await snapshot: ThermalSnapshot in stream {
                    store(snapshot: snapshot)
                }
            } catch {
                store(error: error as NSError)
            }
        }

        Task {
            while !Task.isCancelled {
                try? await Task.sleep(
                    nanoseconds: ThermalDefaults.watchdogIntervalNanoseconds
                )
                if isClientHeartbeatExpired() {
                    await controller.stop()
                    Darwin.exit(EXIT_SUCCESS)
                }
            }
        }
    }

    func latestSnapshot(
        reply: @escaping @Sendable (Data?, NSError?) -> Void
    ) {
        touch()
        lock.lock()
        let currentSnapshot: ThermalSnapshot? = snapshot
        let currentError: NSError? = startupError
        lock.unlock()

        guard let currentSnapshot else {
            reply(nil, currentError)
            return
        }

        do {
            reply(try encoder.encode(currentSnapshot), nil)
        } catch {
            reply(nil, error as NSError)
        }
    }

    func setPolicy(
        _ encodedPolicy: Data,
        fanID: Int,
        reply: @escaping @Sendable (NSError?) -> Void
    ) {
        touch()
        do {
            let policy: FanPolicy = try decoder.decode(FanPolicy.self, from: encodedPolicy)
            Task {
                await controller.setPolicy(policy, fanID: fanID)
                reply(nil)
            }
        } catch {
            reply(error as NSError)
        }
    }

    func restoreAutomaticControl(reply: @escaping @Sendable () -> Void) {
        touch()
        Task {
            await controller.restoreAutomaticPolicies()
            reply()
        }
    }

    private func store(snapshot: ThermalSnapshot) {
        lock.lock()
        self.snapshot = snapshot
        lock.unlock()
    }

    private func store(error: NSError) {
        lock.lock()
        startupError = error
        lock.unlock()
    }

    private func touch() {
        lock.lock()
        lastContact = Date()
        lock.unlock()
    }

    private func isClientHeartbeatExpired() -> Bool {
        lock.lock()
        let elapsed: TimeInterval = Date().timeIntervalSince(lastContact)
        lock.unlock()
        return elapsed >= ThermalDefaults.clientHeartbeatTimeout
    }
}

private final class ServiceDelegate: NSObject, NSXPCListenerDelegate {
    private let service: ThermalServiceImplementation
    private let verifier: ClientVerifier = ClientVerifier()

    init(service: ThermalServiceImplementation) {
        self.service = service
    }

    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection connection: NSXPCConnection
    ) -> Bool {
        guard verifier.isTrusted(connection) else {
            return false
        }
        connection.exportedInterface = NSXPCInterface(with: ThermalServiceProtocol.self)
        connection.exportedObject = service
        connection.resume()
        return true
    }
}

@main
private enum MacFanHelper {
    static func main() throws {
        let smc: SMCClient = try SMCClient()
        let controller: ThermalController = ThermalController(smc: smc)
        let service: ThermalServiceImplementation = ThermalServiceImplementation(
            controller: controller
        )
        let delegate: ServiceDelegate = ServiceDelegate(service: service)
        let listener: NSXPCListener = NSXPCListener(
            machServiceName: ThermalService.machServiceName
        )
        listener.delegate = delegate
        listener.resume()
        RunLoop.current.run()
    }
}
