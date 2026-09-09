import CryptoKit
import Foundation

/// The base URL and token for one router, both typed into Settings.
///
/// The URL is plain preference data and lives in `UserDefaults`; the token is
/// a secret and lives in the login keychain, the way Ollama's key does. For
/// 9router there is a third source that needs no typing at all: the router's
/// CLI derives its own auth token from two files in `~/.9router`, and the same
/// derivation here borrows it — the credential the tool already holds, which is
/// how every other ring in this app is read.
enum RouterCredentials {
    static let keychainAccount = "codenotch"

    static func keychainService(_ kind: RouterKind) -> String { "\(kind.id)-token" }
    static func baseURLKey(_ kind: RouterKind) -> String { "\(kind.id)BaseURL" }
    /// Which upstream provider the ring shows, e.g. `claude`. Empty means the
    /// first one the router lists.
    static func providerKey(_ kind: RouterKind) -> String { "\(kind.id)Provider" }
    /// Comma-joined providers seen on the last fetch, so the Settings picker
    /// can offer them without a fetch of its own.
    static func knownProvidersKey(_ kind: RouterKind) -> String { "\(kind.id)KnownProviders" }

    static func selectedProvider(_ kind: RouterKind, defaults: UserDefaults = .standard) -> String? {
        let value = defaults.string(forKey: providerKey(kind)) ?? ""
        return value.isEmpty ? nil : value
    }

    static func baseURL(_ kind: RouterKind, defaults: UserDefaults = .standard) -> URL? {
        let stored = defaults.string(forKey: baseURLKey(kind)) ?? ""
        let text = stored.isEmpty ? kind.defaultBaseURL : stored
        guard let url = URL(string: text), let scheme = url.scheme,
              ["http", "https"].contains(scheme), url.host != nil
        else { return nil }
        return url
    }

    /// Whether anything was set up at all. A typed URL counts even without a
    /// token: both routers accept unauthenticated dashboard calls when their
    /// login requirement is switched off.
    static func isConfigured(_ kind: RouterKind, defaults: UserDefaults = .standard) -> Bool {
        !(defaults.string(forKey: baseURLKey(kind)) ?? "").isEmpty || token(kind) != nil
    }

    /// Whatever the user saved, else the token borrowed from the router's own files.
    static func token(_ kind: RouterKind) -> String? {
        KeychainItem.read(service: keychainService(kind), account: keychainAccount)
            ?? borrowedCLIToken(kind)
    }

    @discardableResult
    static func store(_ token: String, for kind: RouterKind) -> Bool {
        KeychainItem.store(service: keychainService(kind), account: keychainAccount, value: token)
    }

    @discardableResult
    static func delete(_ kind: RouterKind) -> Bool {
        KeychainItem.delete(service: keychainService(kind), account: keychainAccount)
    }

    /// 9router's `getConsistentMachineId("9r-cli-auth")`, from
    /// `src/shared/utils/machineId.js`: the first 16 hex characters of
    /// `sha256(machineId + salt + cliSecret)`, both files under `DATA_DIR`.
    static func borrowedCLIToken(_ kind: RouterKind, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> String? {
        guard let dir = kind.dataDirectory else { return nil }
        let root = home.appendingPathComponent(dir)
        guard let machineID = try? String(contentsOf: root.appendingPathComponent("machine-id"), encoding: .utf8),
              let secret = try? String(contentsOf: root.appendingPathComponent("auth/cli-secret"), encoding: .utf8)
        else { return nil }
        return cliToken(machineID: machineID, secret: secret)
    }

    static func cliToken(machineID: String, secret: String) -> String {
        let raw = machineID.trimmingCharacters(in: .whitespacesAndNewlines)
        let sec = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        let digest = SHA256.hash(data: Data((raw + "9r-cli-auth" + sec).utf8))
        return String(digest.map { String(format: "%02x", $0) }.joined().prefix(16))
    }
}
