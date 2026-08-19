import Foundation
import Security

struct ClientVerifier {
    private static let appIdentifier: String = "com.evolte.MacFan"

    func isTrusted(_ connection: NSXPCConnection) -> Bool {
        guard let clientInfo: [CFString: Any] = signingInformation(
            processIdentifier: connection.processIdentifier
        ),
        clientInfo[kSecCodeInfoIdentifier] as? String == Self.appIdentifier else {
            return false
        }

        let helperTeam: String? = ownSigningInformation()?[kSecCodeInfoTeamIdentifier]
            as? String
        let clientTeam: String? = clientInfo[kSecCodeInfoTeamIdentifier] as? String

        if let helperTeam {
            return clientTeam == helperTeam
        }

        return clientTeam == nil
    }

    private func signingInformation(
        processIdentifier: pid_t
    ) -> [CFString: Any]? {
        let attributes: CFDictionary = [
            kSecGuestAttributePid: NSNumber(value: processIdentifier),
        ] as CFDictionary
        var code: SecCode?
        guard SecCodeCopyGuestWithAttributes(
            nil,
            attributes,
            [],
            &code
        ) == errSecSuccess,
        let code else {
            return nil
        }
        return signingInformation(for: code)
    }

    private func ownSigningInformation() -> [CFString: Any]? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else {
            return nil
        }
        return signingInformation(for: code)
    }

    private func signingInformation(for code: SecCode) -> [CFString: Any]? {
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess,
              let staticCode else {
            return nil
        }

        var information: CFDictionary?
        guard SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &information
        ) == errSecSuccess else {
            return nil
        }
        return information as? [CFString: Any]
    }
}
