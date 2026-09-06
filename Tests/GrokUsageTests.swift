import XCTest
@testable import Codenotch

/// Pinned to responses recorded from a live SuperGrok CLI session. Credits
/// is the weekly Grok Build allowance. The charge date is the 18th, not the
/// calendar-month `billingPeriodEnd` on the 1st.
final class GrokUsageTests: XCTestCase {
    private let credits = """
    {"config":{"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY",\
    "start":"2026-09-05T08:21:18.802818+00:00",\
    "end":"2026-09-12T08:21:18.802818+00:00"},\
    "creditUsagePercent":8.0,\
    "onDemandCap":{"val":0},"onDemandUsed":{"val":0},\
    "productUsage":[{"product":"GrokBuild","usagePercent":8.0}],\
    "isUnifiedBillingUser":true,"prepaidBalance":{"val":0},\
    "topUpMethod":"TOP_UP_METHOD_SAVED_PAYMENT_METHOD",\
    "billingPeriodStart":"2026-09-05T08:21:18.802818+00:00",\
    "billingPeriodEnd":"2026-09-12T08:21:18.802818+00:00"}}
    """

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/London")!
        return c
    }

    private let now = ISO8601DateFormatter().date(from: "2026-09-05T12:00:00Z")!

    private func windows() throws -> [LimitWindow] {
        try GrokUsage.windows(creditsJSON: credits, now: now, calendar: calendar)
    }

    func testTheRingIsTheCreditsPercentage() throws {
        let credits = try XCTUnwrap(windows().first { $0.id == "credits" })
        XCTAssertEqual(credits.label, "Grok Build")
        XCTAssertEqual(credits.usedFraction ?? -1, 0.08, accuracy: 0.0001)
        XCTAssertEqual(credits.rollsOverAs, .resets)
    }

    /// The credits payload's billingPeriodEnd is Sep 12. The unformatted
    /// `/billing` period ends on Oct 1. Neither is the charge date: the 18th.
    func testTheSubscriptionDateIsTheEighteenthNotTheFirst() throws {
        let w = try windows()
        let sub = try XCTUnwrap(w.first { $0.id == "subscription" })
        XCTAssertEqual(sub.label, "Monthly renewal")
        XCTAssertEqual(sub.rollsOverAs, .renews)
        let date = try XCTUnwrap(sub.resetsAt)
        XCTAssertEqual(calendar.component(.month, from: date), 9)
        XCTAssertEqual(calendar.component(.day, from: date), 18)
        XCTAssertNotEqual(calendar.component(.day, from: date), 1,
                          "the calendar-month ledger is not the bill")
        XCTAssertNotEqual(calendar.component(.day, from: date), 12,
                          "the weekly credits window is not the bill")
    }

    func testWeeklyCreditsStillHaveTheirOwnReset() throws {
        let credits = try XCTUnwrap(windows().first { $0.id == "credits" })
        let reset = try XCTUnwrap(credits.resetsAt)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        XCTAssertEqual(utc.component(.month, from: reset), 9)
        XCTAssertEqual(utc.component(.day, from: reset), 12)
    }

    func testTheSnapshotLeadsWithTheMonthlyDate() throws {
        let snap = ProviderSnapshot(
            id: "grok", displayName: "Grok", glyph: .grok,
            fidelity: .official, status: .ok, windows: try windows(),
            headlineID: "credits"
        )
        XCTAssertEqual(snap.headline?.id, "credits")
        XCTAssertEqual(snap.renewal?.id, "subscription")
        XCTAssertEqual(snap.usageWindows.map(\.id), ["credits"],
                       "the bill is a line of copy, not a second usage row")
        let text = try XCTUnwrap(snap.renewalCopy(now: now))
        XCTAssertTrue(text.hasPrefix("Renews "), text)
        XCTAssertTrue(text.contains("18"), text)
        XCTAssertFalse(text.contains("Oct 1"), "the ledger's 1st leaked onto the bill: \(text)")
        let billed = NotchLayout.cardHeight(for: snap)
        XCTAssertGreaterThan(billed, NotchLayout.cardHeight(windowCount: 1),
                             "the date line has to claim height or the card clips it")
        XCTAssertLessThan(billed, NotchLayout.cardHeight(windowCount: 2),
                          "charging the date as a full usage window is what hid it")
    }

    /// A coinciding date is still two facts. The weekly allowance can reset
    /// on the same morning the plan renews; hiding the renewal would drop the
    /// thing this row exists to show.
    func testACoincidingRenewalIsStillShown() throws {
        let w = try windows()
        XCTAssertEqual(w.map(\.id), ["subscription", "credits"])
    }

    func testARenewalAloneIsNotASuccessfulReading() {
        XCTAssertThrowsError(try GrokUsage.windows(
            creditsJSON: #"{"config":{}}"#
        )) { error in
            guard case UsageProviderError.nothingMetered = error else {
                return XCTFail("expected nothingMetered, got \(error)")
            }
        }
    }

    func testCreditsAlwaysCarryTheChargeDate() throws {
        let w = try GrokUsage.windows(creditsJSON: credits, now: now, calendar: calendar)
        XCTAssertEqual(w.map(\.id), ["subscription", "credits"])
    }

    /// `creditUsagePercent` is absent; the product array is the reading. The
    /// ring is still declared as `headlineID: "credits"`.
    func testProductOnlyCreditsStillUseTheHeadlineID() throws {
        let productOnly = """
        {"config":{"productUsage":[{"product":"GrokBuild","usagePercent":33.0}],\
        "billingPeriodEnd":"2026-09-12T08:21:18.802818+00:00"}}
        """
        let w = try GrokUsage.windows(creditsJSON: productOnly, now: now, calendar: calendar)
        let credits = try XCTUnwrap(w.first { $0.id == "credits" })
        XCTAssertEqual(credits.label, "Grok Build")
        XCTAssertEqual(credits.usedFraction ?? -1, 0.33, accuracy: 0.0001)
        let snap = ProviderSnapshot(
            id: "grok", displayName: "Grok", glyph: .grok,
            fidelity: .official, status: .ok, windows: w, headlineID: "credits"
        )
        XCTAssertEqual(snap.headline?.id, "credits")
        XCTAssertEqual(snap.usedFraction ?? -1, 0.33, accuracy: 0.0001)
    }

    /// A timeout on a fetch that omitted the bill must not archive over a
    /// date we already had.
    func testAFailedBillKeepsTheLastKnownRenewal() throws {
        let creditsOnly = ProviderSnapshot(
            id: "grok", displayName: "Grok", glyph: .grok,
            fidelity: .official, status: .ok,
            windows: [LimitWindow(id: "credits", label: "Grok Build", usedFraction: 0.08)],
            headlineID: "credits", preservePriorRenewal: true
        )
        let previous = ProviderSnapshot(
            id: "grok", displayName: "Grok", glyph: .grok,
            fidelity: .official, status: .ok, windows: try windows(),
            headlineID: "credits"
        )
        XCTAssertNil(creditsOnly.renewal)
        let merged = creditsOnly.preservingPriorRenewal(from: previous)
        XCTAssertEqual(merged.renewal?.id, "subscription")
        XCTAssertEqual(merged.headline?.id, "credits")
        XCTAssertEqual(merged.usageWindows.map(\.id), ["credits"])
    }

    func testGarbageIsABadResponseRatherThanAGuess() {
        XCTAssertThrowsError(try GrokUsage.windows(creditsJSON: "not json")) { error in
            guard case UsageProviderError.badResponse = error else {
                return XCTFail("expected badResponse, got \(error)")
            }
        }
    }

    func testHumanizesTheProductNameTheWayTheModalWritesIt() {
        XCTAssertEqual(GrokUsage.humanize("GrokBuild"), "Grok Build")
    }
}

final class GrokCredentialsTests: XCTestCase {
    private var url: URL!

    override func setUpWithError() throws {
        url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("grok-auth-\(UUID().uuidString).json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: url)
    }

    private func write(_ json: String) throws {
        try Data(json.utf8).write(to: url)
    }

    func testItReadsTheEmailAndToken() throws {
        try write("""
        {"https://auth.x.ai::client":{\
        "email":"a@b.c","key":"tok","expires_at":"2126-09-05T22:00:00.000Z"}}
        """)
        let creds = try GrokCredentials.load(from: url)
        XCTAssertEqual(creds.email, "a@b.c")
        XCTAssertEqual(creds.accessToken, "tok")
        XCTAssertFalse(creds.isExpired)
        XCTAssertEqual(GrokCredentials.account(from: url)?.label, "a@b.c")
        XCTAssertEqual(GrokCredentials.account(from: url)?.source, "Grok")
    }

    func testAnExpiredTokenIsRecognisedRatherThanSignedOut() throws {
        try write("""
        {"https://auth.x.ai::client":{\
        "email":"a@b.c","key":"tok","expires_at":"2020-01-01T00:00:00Z"}}
        """)
        XCTAssertTrue(try GrokCredentials.load(from: url).isExpired)
    }

    func testAMissingFileIsNeedsAuth() {
        XCTAssertThrowsError(try GrokCredentials.load(from: url)) { error in
            guard case UsageProviderError.needsAuth = error else {
                return XCTFail("expected needsAuth, got \(error)")
            }
        }
    }

    func testALiveEntryWinsWhenSeveralSitInTheFile() throws {
        try write("""
        {"https://auth.x.ai::old":{"email":"old@x.ai","key":"old","expires_at":"2020-01-01T00:00:00Z"},\
         "https://auth.x.ai::live":{"email":"live@x.ai","key":"live","expires_at":"2126-01-01T00:00:00Z"}}
        """)
        XCTAssertEqual(try GrokCredentials.load(from: url).email, "live@x.ai")
    }

    /// A customer IdP session is for that customer's proxy. Picking it would
    /// send their token to cli-chat-proxy.grok.com.
    func testACustomIssuerIsNotSentToThePublicEndpoint() throws {
        try write("""
        {"https://acme.okta.com::0oa":{\
        "email":"you@acme.com","key":"enterprise","expires_at":"2126-01-01T00:00:00Z",\
        "oidc_issuer":"https://acme.okta.com"}}
        """)
        XCTAssertThrowsError(try GrokCredentials.load(from: url)) { error in
            guard case UsageProviderError.needsAuth = error else {
                return XCTFail("expected needsAuth, got \(error)")
            }
        }
        XCTAssertNil(GrokCredentials.account(from: url))
    }
}

final class GrokActivityTests: XCTestCase {
    private var root: URL!
    private var active: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("grok-act-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        active = root.appendingPathComponent("active.json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    @discardableResult
    private func session(id: String, cwd: String, modified: Date, pid: Int32 = 1) throws -> URL {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let encoded = cwd.addingPercentEncoding(withAllowedCharacters: allowed) ?? cwd
        let dir = root.appendingPathComponent(encoded).appendingPathComponent(id)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let updates = dir.appendingPathComponent("updates.jsonl")
        try "{}".write(to: updates, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: modified],
                                              ofItemAtPath: updates.path)
        let row: [String: Any] = [
            "session_id": id, "pid": pid, "cwd": cwd,
            "opened_at": ISO8601DateFormatter().string(from: modified)
        ]
        try JSONSerialization.data(withJSONObject: [row]).write(to: active)
        return dir
    }

    func testAJustWrittenSessionReadsAsWorking() throws {
        try session(id: "s1", cwd: "/tmp/proj", modified: Date(),
                    pid: Int32(ProcessInfo.processInfo.processIdentifier))
        let sessions = GrokActivity.read(activeURL: active, sessionsRoot: root, staleAfter: 45)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.state, .busy)
        XCTAssertEqual(sessions.first?.name, "proj")
    }

    func testAnOldTurnIsNotWorking() throws {
        try session(id: "s1", cwd: "/tmp/proj", modified: Date().addingTimeInterval(-600),
                    pid: Int32(ProcessInfo.processInfo.processIdentifier))
        XCTAssertTrue(GrokActivity.read(activeURL: active, sessionsRoot: root,
                                        staleAfter: 45).isEmpty)
    }

    func testADeadPidIsNotASession() throws {
        try session(id: "s1", cwd: "/tmp/proj", modified: Date(), pid: Int32.max - 1)
        XCTAssertTrue(GrokActivity.read(activeURL: active, sessionsRoot: root,
                                        staleAfter: 45).isEmpty)
    }
}

final class GrokGlyphTests: XCTestCase {
    func testItIsTwoClosedLoopsFromTheOfficialMark() {
        XCTAssertEqual(GlyphOutline.grok.count, 2)
        for loop in GlyphOutline.grok {
            XCTAssertGreaterThan(loop.count, 50, "the curves were not flattened into enough points")
            for p in loop {
                XCTAssertTrue((0...1).contains(p.x), "x outside the unit box: \(p.x)")
                XCTAssertTrue((0...1).contains(p.y), "y outside the unit box: \(p.y)")
            }
        }
    }

    func testItFillsTheBox() {
        let pts = GlyphOutline.grok.flatMap { $0 }
        let xs = pts.map(\.x), ys = pts.map(\.y)
        XCTAssertEqual(Double((xs.max() ?? 0) - (xs.min() ?? 0)), 1, accuracy: 0.01)
        XCTAssertEqual(Double((ys.max() ?? 0) - (ys.min() ?? 0)), 1, accuracy: 0.01)
    }
}
