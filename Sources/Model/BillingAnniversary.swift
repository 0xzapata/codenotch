import Foundation

/// The day of the month the plan is charged — not a usage-window reset.
///
/// Grok's unformatted `/billing` reports a calendar-month period ending on
/// the 1st. That is when the usage ledger rolls, not when the card is
/// charged. Claude and Codex never published a charge date at all. These
/// days are the account's actual renewal:
/// Grok the 18th, Claude the 17th, Codex the 7th.
enum BillingAnniversary {
    static let grokDay = 18
    static let claudeDay = 17
    static let codexDay = 7

    static func window(day: Int, now: Date = Date(),
                       calendar: Calendar = .current) -> LimitWindow {
        LimitWindow(
            id: "subscription",
            label: "Monthly renewal",
            resetsAt: nextDate(day: day, from: now, calendar: calendar),
            rollover: .renews
        )
    }

    static func prepending(day: Int, to windows: [LimitWindow],
                           now: Date = Date(),
                           calendar: Calendar = .current) -> [LimitWindow] {
        [window(day: day, now: now, calendar: calendar)] + windows
    }

    /// Noon on the next charge day, in `calendar`. Noon so the calendar day
    /// survives a zone conversion; "today" still counts as this month's bill
    /// until tomorrow morning.
    static func nextDate(day: Int, from now: Date = Date(),
                         calendar: Calendar = .current) -> Date {
        let wanted = min(max(day, 1), 31)
        let today = calendar.startOfDay(for: now)

        func inMonth(containing date: Date) -> Date? {
            guard let start = calendar.date(from: calendar.dateComponents([.year, .month], from: date)),
                  let last = calendar.range(of: .day, in: .month, for: start)?.count
            else { return nil }
            var parts = calendar.dateComponents([.year, .month], from: start)
            parts.day = min(wanted, last)
            parts.hour = 12
            parts.minute = 0
            parts.second = 0
            return calendar.date(from: parts)
        }

        if let thisMonth = inMonth(containing: today),
           calendar.startOfDay(for: thisMonth) >= today {
            return thisMonth
        }
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: today) ?? today
        return inMonth(containing: nextMonth) ?? nextMonth
    }
}
