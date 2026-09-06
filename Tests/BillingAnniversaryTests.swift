import XCTest
@testable import Codenotch

final class BillingAnniversaryTests: XCTestCase {
    private var london: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/London")!
        return c
    }

    private func date(_ iso: String, calendar: Calendar? = nil) -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = (calendar ?? london).timeZone
        return f.date(from: iso)!
    }

    func testTheKnownChargeDays() {
        XCTAssertEqual(BillingAnniversary.grokDay, 18)
        XCTAssertEqual(BillingAnniversary.claudeDay, 17)
        XCTAssertEqual(BillingAnniversary.codexDay, 7)
    }

    func testBeforeTheDayItIsThisMonth() {
        let now = date("2026-09-05T12:00:00Z")
        let grok = BillingAnniversary.nextDate(day: 18, from: now, calendar: london)
        XCTAssertEqual(london.component(.month, from: grok), 9)
        XCTAssertEqual(london.component(.day, from: grok), 18)

        let claude = BillingAnniversary.nextDate(day: 17, from: now, calendar: london)
        XCTAssertEqual(london.component(.day, from: claude), 17)

        let codex = BillingAnniversary.nextDate(day: 7, from: now, calendar: london)
        XCTAssertEqual(london.component(.day, from: codex), 7)
        XCTAssertEqual(london.component(.month, from: codex), 9)
    }

    func testOnTheDayItIsStillThisMonth() {
        let now = date("2026-09-18T21:00:00+01:00")
        let grok = BillingAnniversary.nextDate(day: 18, from: now, calendar: london)
        XCTAssertEqual(london.component(.month, from: grok), 9)
        XCTAssertEqual(london.component(.day, from: grok), 18)
    }

    func testAfterTheDayItIsNextMonth() {
        let now = date("2026-09-19T09:00:00+01:00")
        let grok = BillingAnniversary.nextDate(day: 18, from: now, calendar: london)
        XCTAssertEqual(london.component(.month, from: grok), 10)
        XCTAssertEqual(london.component(.day, from: grok), 18)
    }

    func testFebruaryDoesNotInventTheThirtyFirst() {
        let now = date("2026-02-01T12:00:00Z")
        let date = BillingAnniversary.nextDate(day: 31, from: now, calendar: london)
        XCTAssertEqual(london.component(.month, from: date), 2)
        XCTAssertEqual(london.component(.day, from: date), 28)
    }

    func testPrependingDoesNotReplaceUsageWindows() {
        let usage = LimitWindow(id: "credits", label: "Grok Build", usedFraction: 0.2)
        let windows = BillingAnniversary.prepending(day: 18, to: [usage],
                                                    now: date("2026-09-05T12:00:00Z"),
                                                    calendar: london)
        XCTAssertEqual(windows.map(\.id), ["subscription", "credits"])
        XCTAssertEqual(windows[0].rollsOverAs, .renews)
    }

    func testCopyNamesTheEighteenthNotTheFirst() {
        let now = date("2026-09-05T12:00:00Z")
        let window = BillingAnniversary.window(day: 18, now: now, calendar: london)
        let text = ResetCopy.text(for: window.resetsAt!, now: now,
                                  calendar: london, rollover: .renews)
        XCTAssertTrue(text.contains("18"), text)
        XCTAssertFalse(text.contains("Oct 1"), text)
    }
}
