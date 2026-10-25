import Foundation
import Security

enum CredentialStore {
    // Keep the original Keychain service so the renamed app can use saved credentials.
    private static let service = "dev.tavodev.actions-bar"
    private static let account = "github-token"

    static func load() throws -> String? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service, kSecAttrAccount: account,
            kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne
        ] as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw CredentialError.keychain(status) }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ token: String) throws {
        let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword,
            kSecAttrService: service, kSecAttrAccount: account]
        let data = Data(token.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData] = data
            item[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else { throw CredentialError.keychain(added) }
        } else if status != errSecSuccess { throw CredentialError.keychain(status) }
    }

    static func delete() throws {
        let status = SecItemDelete([kSecClass: kSecClassGenericPassword,
            kSecAttrService: service, kSecAttrAccount: account] as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw CredentialError.keychain(status) }
    }

    static func githubCLIToken() async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let paths = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"]
            guard let path = paths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
                throw CredentialError.cliMissing
            }
            let process = Process(), output = Pipe()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = ["auth", "token", "--hostname", "github.com"]
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let token = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard process.terminationStatus == 0, !token.isEmpty else { throw CredentialError.cliSignedOut }
            return token
        }.value
    }
}

enum CredentialError: LocalizedError {
    case keychain(OSStatus), cliMissing, cliSignedOut
    var errorDescription: String? {
        switch self {
        case .keychain(let status): "No pudimos acceder a Keychain (\(status)). Intenta conectar de nuevo."
        case .cliMissing: "No encontramos GitHub CLI. Puedes conectar con un token personal."
        case .cliSignedOut: "GitHub CLI no tiene una sesión en github.com. Ejecuta gh auth login una vez o usa un token."
        }
    }
}
