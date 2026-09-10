import Foundation

/// Which self-hosted LLM router a `RouterProvider` reads.
///
/// 9router and OmniRoute (a fork of 9router) share one dashboard API:
/// `GET /api/providers` lists the upstream accounts the router holds, and
/// `GET /api/usage/{connectionId}` asks each account's own quota endpoint on
/// the router's behalf. So one provider type serves both; only the name, the
/// default port and how the router is authenticated differ.
struct RouterKind: Equatable {
    let id: String
    let displayName: String
    let glyph: ProviderGlyph
    let defaultBaseURL: String
    /// Where the router keeps its data directory, for the borrowed CLI token.
    let dataDirectory: String?
    /// Which listing to read. 9router's `/api/providers` blanks four token
    /// fields but leaves `providerSpecificData` (client secrets, cookies)
    /// intact; its `/api/providers/client` is an allow-list and flags which
    /// connections can report usage. OmniRoute's `client` route is the
    /// opposite — it returns every token on purpose, for cloud sync — so it
    /// reads the plain listing, which masks keys.
    let connectionsPath: String
    let connectionsQuery: [URLQueryItem]

    /// https://github.com/decolua/9router — `x-9r-cli-token` or a dashboard
    /// JWT gates `/api/usage`; the CLI token can be derived from `~/.9router`.
    static let nineRouter = RouterKind(
        id: "9router", displayName: "9router", glyph: .nineRouter,
        defaultBaseURL: "http://127.0.0.1:20128", dataDirectory: ".9router",
        // ponytail: one page of 500 — the route's ceiling; page when a router holds more.
        connectionsPath: "api/providers/client", connectionsQuery: [URLQueryItem(name: "pageSize", value: "500")]
    )
    /// https://github.com/diegosouzapw/OmniRoute — `/api/usage` is a management
    /// route: `Authorization: Bearer oma_live_…` or a `manage`-scoped `sk-` key.
    static let omniRoute = RouterKind(
        id: "omniroute", displayName: "OmniRoute", glyph: .omniRoute,
        defaultBaseURL: "http://127.0.0.1:20128", dataDirectory: nil,
        connectionsPath: "api/providers", connectionsQuery: []
    )
}

/// Parses the router dashboard API.
///
/// `GET /api/providers`:
/// ```json
/// { "connections": [ { "id": "c1", "provider": "claude", "name": "work",
///                      "email": "me@x.com", "authType": "oauth", "isActive": true } ] }
/// ```
/// `GET /api/usage/{id}` (9router `open-sse/services/usage/claude.js`):
/// ```json
/// { "plan": "Claude Code",
///   "quotas": { "session (5h)": { "used": 12, "total": 100, "remaining": 88,
///                                 "resetAt": "2026-09-09T12:00:00.000Z", "unlimited": false },
///               "weekly (7d)":  { ... } } }
/// ```
/// A connection without usage answers `{ "message": "Usage not available…" }`
/// instead of `quotas`; it is skipped rather than shown as an error.
///
/// `used`/`total` are percentages of one account (`total` is always 100 in
/// both routers' handlers), so summing them weights every account equally.
enum RouterUsage {
    struct Connection: Equatable {
        let id: String
        let provider: String
        let name: String
    }

    /// The listing URL for one router, base path kept (`https://host/9r` stays
    /// under `/9r`) and the query added only where the route takes one.
    static func connectionsURL(base: URL, kind: RouterKind) -> URL {
        var parts = URLComponents(url: base.appendingPathComponent(kind.connectionsPath), resolvingAgainstBaseURL: false)!
        parts.queryItems = kind.connectionsQuery.isEmpty ? nil : kind.connectionsQuery
        return parts.url!
    }

    static func parseConnections(_ data: Data) throws -> [Connection] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = root["connections"] as? [[String: Any]]
        else { throw UsageProviderError.badResponse(status: 0) }
        return list.compactMap { item in
            guard let id = item["id"] as? String, !id.isEmpty else { return nil }
            if let active = item["isActive"] as? Bool, !active { return nil }
            let provider = item["provider"] as? String ?? "unknown"
            let name = [item["name"] as? String, item["email"] as? String]
                .compactMap { $0 }.first { !$0.isEmpty } ?? provider
            return Connection(id: id, provider: provider, name: name)
        }
    }

    /// One window per quota key, summed across every account of one upstream
    /// provider: two Claude accounts at 12/100 and 40/100 read as 26%. Each
    /// window keeps its reset date only when every account agrees on it — a
    /// summed figure has no single reset otherwise, and showing one account's
    /// would be a guess.
    static func aggregate(_ usages: [(connection: Connection, data: Data)],
                          provider: String) -> [LimitWindow] {
        struct Sum { var used = 0.0; var total = 0.0; var remaining = 0; var resets: [Date?] = [] }
        var sums: [String: Sum] = [:]
        for (connection, data) in usages where connection.provider == provider {
            guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let quotas = root["quotas"] as? [String: Any]
            else { continue }
            for (key, value) in quotas {
                guard let quota = value as? [String: Any],
                      quota["unlimited"] as? Bool != true
                else { continue }
                var sum = sums[key] ?? Sum()
                if let total = number(quota["total"]), total > 0, let used = number(quota["used"]) {
                    sum.used += min(max(used, 0), total); sum.total += total
                } else if let pct = number(quota["remainingPercentage"]) ?? number(quota["percentRemaining"]) {
                    sum.used += min(max(100 - pct, 0), 100); sum.total += 100
                } else if let remaining = number(quota["remaining"]) {
                    sum.remaining += Int(remaining)
                } else { continue }
                sum.resets.append((quota["resetAt"] as? String).flatMap(parseDate))
                sums[key] = sum
            }
        }
        return sums.keys.sorted().map { key in
            let sum = sums[key]!
            let agreed = sum.resets.first.flatMap { first in
                sum.resets.allSatisfy { $0 == first } ? first : nil
            }
            return LimitWindow(
                id: "\(provider).\(key)", label: key,
                usedFraction: sum.total > 0 ? sum.used / sum.total : nil,
                remaining: sum.total > 0 ? nil : sum.remaining,
                resetsAt: agreed
            )
        }
    }

    private static func number(_ value: Any?) -> Double? {
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String { return Double(s) }
        return nil
    }

    static func parseDate(_ text: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
}
