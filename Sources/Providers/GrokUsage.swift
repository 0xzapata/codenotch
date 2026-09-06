import Foundation

/// Parses Grok CLI's billing endpoints, recorded from a live SuperGrok session:
///
/// `GET https://cli-chat-proxy.grok.com/v1/billing?format=credits`
/// ```json
/// { "config": {
///     "currentPeriod": { "type": "USAGE_PERIOD_TYPE_WEEKLY",
///                        "start": "2026-09-05T08:21:18.802818+00:00",
///                        "end":   "2026-09-12T08:21:18.802818+00:00" },
///     "creditUsagePercent": 8.0,
///     "productUsage": [{ "product": "GrokBuild", "usagePercent": 8.0 }],
///     "billingPeriodStart": "2026-09-05T08:21:18.802818+00:00",
///     "billingPeriodEnd":   "2026-09-12T08:21:18.802818+00:00" } }
/// ```
///
/// The unformatted `/billing` payload's `billingPeriodEnd` is the calendar
/// month (the 1st). That is the usage ledger, not the charge date — this
/// account renews on the 18th. The credits payload is the ring.
enum GrokUsage {
    static func windows(creditsJSON: String, now: Date = Date(),
                        calendar: Calendar = .current) throws -> [LimitWindow] {
        guard let credits = object(creditsJSON)?["config"] as? [String: Any] else {
            throw UsageProviderError.badResponse(status: 0)
        }

        var windows: [LimitWindow] = []

        let creditsReset = date(period(credits["currentPeriod"])?["end"])
            ?? date(credits["billingPeriodEnd"])

        if let fraction = percent(credits["creditUsagePercent"]) {
            windows.append(LimitWindow(
                id: "credits",
                label: productLabel(credits) ?? "Grok Build",
                usedFraction: fraction,
                resetsAt: creditsReset
            ))
        } else if let products = credits["productUsage"] as? [[String: Any]] {
            for product in products {
                guard let fraction = percent(product["usagePercent"]) else { continue }
                let name = (product["product"] as? String).map(humanize) ?? "Usage"
                // The ring is declared as `headlineID: "credits"`. Using the
                // wire product name here left a valid bar in the tooltip and
                // a dash on the cell.
                windows.append(LimitWindow(
                    id: windows.isEmpty ? "credits" : ((product["product"] as? String) ?? name),
                    label: name,
                    usedFraction: fraction,
                    resetsAt: creditsReset
                ))
            }
        }

        // A renewal row must not be the thing that makes this a success. If
        // credits produced nothing, the ring has no subject; attaching
        // the charge date would hide that behind a dash and a date.
        guard !windows.isEmpty else {
            throw UsageProviderError.nothingMetered("Grok has nothing metered on this account yet")
        }

        windows.insert(
            BillingAnniversary.window(day: BillingAnniversary.grokDay,
                                      now: now, calendar: calendar),
            at: 0
        )
        return windows
    }

    private static func productLabel(_ credits: [String: Any]) -> String? {
        guard let products = credits["productUsage"] as? [[String: Any]],
              let name = products.first?["product"] as? String
        else { return nil }
        return humanize(name)
    }

    /// "GrokBuild" → "Grok Build". The wire name is one word; the usage modal
    /// writes two.
    static func humanize(_ name: String) -> String {
        var result = ""
        for character in name {
            if character.isUppercase, !result.isEmpty { result.append(" ") }
            result.append(character)
        }
        return result
    }

    private static func percent(_ any: Any?) -> Double? {
        guard let number = any as? NSNumber else { return nil }
        return number.doubleValue / 100
    }

    private static func period(_ any: Any?) -> [String: Any]? {
        any as? [String: Any]
    }

    private static func object(_ json: String?) -> [String: Any]? {
        guard let json, let data = json.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func date(_ any: Any?) -> Date? {
        GrokCredentials.date(any)
    }
}
