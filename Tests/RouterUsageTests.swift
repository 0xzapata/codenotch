import XCTest
@testable import Codenotch

/// Parses the dashboard API shared by 9router and OmniRoute: the connection
/// list, and the per-connection quota shape their `open-sse` usage handlers
/// emit for Claude and Codex, summed across the accounts of one provider.
final class RouterUsageTests: XCTestCase {
    private let connections = Data("""
    { "connections": [
        { "id": "c1", "provider": "claude", "name": "work", "email": "me@x.com", "authType": "oauth", "isActive": true },
        { "id": "c2", "provider": "claude", "email": "me@x.com", "authType": "oauth" },
        { "id": "c3", "provider": "codex", "name": "cdx" },
        { "id": "c4", "provider": "glm", "name": "off", "isActive": false },
        { "provider": "broken" }
    ] }
    """.utf8)

    /// Verbatim shape from 9router `open-sse/services/usage/claude.js`.
    private func claude(session: Double, weekly: Double, reset: String) -> Data {
        Data("""
        { "plan": "Claude Code",
          "quotas": {
            "session (5h)": { "used": \(session), "total": 100, "remaining": \(100 - session),
                              "remainingPercentage": \(100 - session), "resetAt": "\(reset)", "unlimited": false },
            "weekly (7d)":  { "used": \(weekly), "total": 100, "remaining": \(100 - weekly),
                              "remainingPercentage": \(100 - weekly), "resetAt": null, "unlimited": false },
            "bonus": { "unlimited": true }
          } }
        """.utf8)
    }

    private var list: [RouterUsage.Connection] { try! RouterUsage.parseConnections(connections) }

    func testConnectionsSkipInactiveAndMalformed() {
        XCTAssertEqual(list.map(\.id), ["c1", "c2", "c3"])
        XCTAssertEqual(list[0].name, "work")
        XCTAssertEqual(list[1].name, "me@x.com")
    }

    /// 9router's allow-listed `client` route wraps the same list in paging.
    func testClientRouteShapeParses() {
        let paged = Data("""
        { "connections": [ { "id": "c9", "provider": "codex", "name": "me@x.com", "isActive": true } ],
          "providerOptions": ["codex"], "pagination": { "page": 1, "pageSize": 500, "total": 1 } }
        """.utf8)
        XCTAssertEqual(try RouterUsage.parseConnections(paged), [.init(id: "c9", provider: "codex", name: "me@x.com")])
    }

    func testLoginRequestCarriesThePasswordAsJSON() {
        let req = RouterUsage.loginRequest(base: URL(string: "https://host/9r")!, password: "pw ")
        XCTAssertEqual(req.url?.absoluteString, "https://host/9r/api/auth/login")
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let body = try! JSONSerialization.jsonObject(with: req.httpBody ?? Data()) as? [String: String]
        XCTAssertEqual(body, ["password": "pw "])
    }

    func testListingURLPerRouter() {
        let base = URL(string: "https://host/9r")!
        XCTAssertEqual(RouterUsage.connectionsURL(base: base, kind: .nineRouter).absoluteString,
                       "https://host/9r/api/providers/client?pageSize=500")
        XCTAssertEqual(RouterUsage.connectionsURL(base: base, kind: .omniRoute).absoluteString,
                       "https://host/9r/api/providers")
    }

    func testConnectionsGarbageThrows() {
        XCTAssertThrowsError(try RouterUsage.parseConnections(Data("[]".utf8)))
    }

    func testAccountsOfOneProviderAreSummed() {
        let windows = RouterUsage.aggregate([
            (list[0], claude(session: 12, weekly: 40.5, reset: "2026-09-09T12:00:00.000Z")),
            (list[1], claude(session: 30, weekly: 10, reset: "2026-09-09T12:00:00Z")),
            (list[2], Data(#"{"quotas":{"session":{"used":99,"total":100}}}"#.utf8)),
        ], provider: "claude")
        XCTAssertEqual(windows.map(\.label), ["session (5h)", "weekly (7d)"])
        XCTAssertEqual(windows[0].id, "claude.session (5h)")
        XCTAssertEqual(windows[0].usedFraction!, 0.21, accuracy: 1e-9)
        XCTAssertEqual(windows[1].usedFraction!, 0.2525, accuracy: 1e-9)
        // Both accounts agree on the session reset, so it is kept.
        XCTAssertEqual(windows[0].resetsAt, RouterUsage.parseDate("2026-09-09T12:00:00Z"))
        XCTAssertNil(windows[1].resetsAt)
    }

    func testResetIsOmittedWhenAccountsDisagree() {
        let windows = RouterUsage.aggregate([
            (list[0], claude(session: 12, weekly: 0, reset: "2026-09-09T12:00:00Z")),
            (list[1], claude(session: 30, weekly: 0, reset: "2026-09-09T15:00:00Z")),
        ], provider: "claude")
        XCTAssertNil(windows[0].resetsAt)
    }

    func testMessageOnlyUsageYieldsNoWindows() {
        XCTAssertTrue(RouterUsage.aggregate(
            [(list[0], Data(#"{"message":"Usage not available"}"#.utf8))], provider: "claude"
        ).isEmpty)
    }

    func testRemainingPercentageFallsBackWhenNoTotal() {
        let w = RouterUsage.aggregate(
            [(list[0], Data(#"{"quotas":{"q":{"percentRemaining":25}}}"#.utf8))], provider: "claude")
        XCTAssertEqual(w.first?.usedFraction, 0.75)
    }

    func testCLITokenMatches9routerDerivation() {
        // python: hashlib.sha256(b"abc9r-cli-authxyz").hexdigest()[:16]
        XCTAssertEqual(RouterCredentials.cliToken(machineID: "abc\n", secret: "xyz"), "98cac1ef961d4181")
    }
}
