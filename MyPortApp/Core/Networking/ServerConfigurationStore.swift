import Foundation

@MainActor
final class ServerConfigurationStore: ObservableObject {
    private enum DefaultsKeys {
        static let baseURLString = "myport.server.baseURLString"
        static let useMockServer = "myport.server.useMockServer"
    }

    private enum KeychainKeys {
        static let bearerToken = "myport.server.bearerToken"
    }

    @Published var baseURLString: String {
        didSet {
            defaults.set(baseURLString, forKey: DefaultsKeys.baseURLString)
        }
    }

    @Published var useMockServer: Bool {
        didSet {
            defaults.set(useMockServer, forKey: DefaultsKeys.useMockServer)
        }
    }

    @Published var bearerToken: String {
        didSet {
            let trimmed = bearerToken.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmed.isEmpty {
                keychain.delete(account: KeychainKeys.bearerToken)
            } else {
                keychain.write(trimmed, account: KeychainKeys.bearerToken)
            }
        }
    }

    private let defaults: UserDefaults
    private let keychain: KeychainValueStore

    init(
        defaults: UserDefaults = .standard,
        keychain: KeychainValueStore = .shared
    ) {
        self.defaults = defaults
        self.keychain = keychain
        self.baseURLString = defaults.string(forKey: DefaultsKeys.baseURLString) ?? ""
        self.useMockServer = defaults.object(forKey: DefaultsKeys.useMockServer) as? Bool ?? true
        self.bearerToken = keychain.read(account: KeychainKeys.bearerToken) ?? ""
    }

    var normalizedBaseURL: URL? {
        let trimmed = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }
        return URL(string: trimmed)
    }

    var trimmedBearerToken: String {
        bearerToken.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
