import Foundation
import os

/// Reads the upstream accounts a self-hosted LLM router holds, through the
/// router's own dashboard API. The ring stands for one upstream provider
/// chosen in Settings — say, every Claude account behind 9router — with the
/// accounts' limits summed into one set of windows.
///
/// The numbers are the upstream providers' own — the router asks Anthropic,
/// OpenAI and the rest with the account's stored token — so they are
/// `.official`, not derived from request counts.
actor RouterProvider: UsageProvider {
    nonisolated let kind: RouterKind
    nonisolated var id: String { kind.id }
    nonisolated var displayName: String { kind.displayName }
    nonisolated var glyph: ProviderGlyph { kind.glyph }
    /// Two dark rings for routers nobody runs would be the default for
    /// everyone; like the local Ollama daemon, a router earns its ring by
    /// being set up — a URL typed, a token saved, or `~/.9router` present.
    nonisolated var isVisibleWhenAbsent: Bool { false }

    private let session: URLSession
    /// Reset each fetch: the base to log in against, and whether a dashboard
    /// login has already been tried this fetch, so a wall of 401s from the
    /// parallel usage calls cannot each fire their own login.
    private var authBase: URL?
    private var loginTried = false

    init(kind: RouterKind, session: URLSession = .shared) {
        self.kind = kind
        self.session = session
    }

    nonisolated var signInRoute: SignInRoute {
        .guidance("Enter the \(kind.displayName) URL and a dashboard token below, then start the router.")
    }

    nonisolated func account() -> ProviderAccount? {
        guard RouterCredentials.isConfigured(kind), let url = RouterCredentials.baseURL(kind) else { return nil }
        return ProviderAccount(
            label: [RouterCredentials.selectedProvider(kind), url.host].compactMap { $0 }.joined(separator: " @ "),
            plan: nil,
            source: kind.displayName,
            manageURL: url.appendingPathComponent("dashboard")
        )
    }

    func fetchSnapshot() async throws -> ProviderSnapshot {
        guard let typed = RouterCredentials.baseURL(kind) else { throw UsageProviderError.needsAuth }
        let token = RouterCredentials.token(kind)
        authBase = typed
        loginTried = false

        let connections = try RouterUsage.parseConnections(
            try await get(RouterUsage.connectionsURL(base: typed, kind: kind), token: token)
        )
        let base = typed

        var known: [String] = []
        for c in connections where !known.contains(c.provider) { known.append(c.provider) }
        UserDefaults.standard.set(known.joined(separator: ","), forKey: RouterCredentials.knownProvidersKey(kind))
        guard let provider = RouterCredentials.selectedProvider(kind) ?? known.first else {
            throw UsageProviderError.nothingMetered("No accounts connected in \(kind.displayName) yet.")
        }
        let chosen = connections.filter { $0.provider == provider }
        guard !chosen.isEmpty else {
            throw UsageProviderError.nothingMetered("\(kind.displayName) has no \(provider) account connected.")
        }

        // Each usage call makes the router ask an upstream quota endpoint, so
        // they run together rather than one after another.
        let usages = await withTaskGroup(of: (RouterUsage.Connection, Data)?.self) { group in
            for connection in chosen {
                group.addTask {
                    let url = base.appendingPathComponent("api/usage/\(connection.id)")
                    // A single account whose token lapsed answers 401; that is
                    // its problem, not the router's, so it drops out quietly.
                    guard let data = try? await self.get(url, token: token) else { return nil }
                    return (connection, data)
                }
            }
            return await group.reduce(into: [(connection: RouterUsage.Connection, data: Data)]()) {
                if let pair = $1 { $0.append(pair) }
            }
        }
        let windows = RouterUsage.aggregate(usages, provider: provider)
        let defaults = UserDefaults.standard
        defaults.set(try? JSONEncoder().encode(windows), forKey: RouterCredentials.windowsKey(kind))
        defaults.set(usages.count, forKey: RouterCredentials.accountCountKey(kind))

        guard !windows.isEmpty else {
            throw UsageProviderError.nothingMetered(
                "\(kind.displayName) reports no usage windows for \(provider)."
            )
        }

        return ProviderSnapshot(
            id: id, displayName: displayName, glyph: glyph,
            fidelity: .official, status: .ok, windows: windows,
            // ponytail: first metered window alphabetically, "session (5h)" for
            // Claude. Add a headline-window setting if a router ever lists a
            // window that sorts before the session one.
            headlineID: windows.first { $0.usedFraction != nil }?.id
        )
    }

    private func get(_ url: URL, token: String?) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        if let token {
            // OmniRoute reads the bearer; 9router reads its CLI header and
            // ignores the bearer on dashboard routes. Sending both keeps one
            // token field for both routers.
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue(token, forHTTPHeaderField: "x-9r-cli-token")
        }
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 || status == 403 {
            // The headers were refused. On a login-required 9router the token
            // is a dashboard password: log in once, and the retry rides the
            // cookie the session now holds. One attempt per fetch.
            if let token, let base = authBase, !loginTried {
                loginTried = true
                if await login(base: base, password: token) {
                    return try await get(url, token: token)
                }
            }
            throw UsageProviderError.needsAuth
        }
        guard (200..<300).contains(status) else { throw UsageProviderError.badResponse(status: status) }
        // Bodies stay out of the log: the listing carries client secrets
        // and OmniRoute's carries masked keys; the shape is covered by tests.
        Log.usage.debug("\(self.kind.id, privacy: .public) \(url.path, privacy: .public) -> \(data.count) bytes")
        return data
    }

    /// Exchanges the dashboard password for the `auth_token` cookie the shared
    /// session then sends on every later request. True when the router accepts
    /// it, so the caller knows a retry is worth it.
    private func login(base: URL, password: String) async -> Bool {
        guard let (_, response) = try? await session.data(for: RouterUsage.loginRequest(base: base, password: password))
        else { return false }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    nonisolated func signOut() async { RouterCredentials.delete(kind) }
    nonisolated func forgetCachedCredential() {}
}
