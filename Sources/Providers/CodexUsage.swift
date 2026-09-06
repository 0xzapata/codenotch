import Foundation

/// Only the account's main five-hour and weekly limits belong in the usage rings.
enum CodexUsage {
    private struct Response: Decodable {
        let rate_limit: RateLimit?
    }

    private struct RateLimit: Decodable {
        let primary_window: Window?
        let secondary_window: Window?
    }

    private struct Window: Decodable {
        let limit_window_seconds: Double
        let used_percent: Double?
        let reset_at: Double?
        let reset_after_seconds: Double?
    }

    static func windows(from data: Data, now: Date = Date()) throws -> [LimitWindow] {
        let response: Response
        do {
            response = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw UsageProviderError.badResponse(status: 0)
        }

        var windows: [LimitWindow] = []
        if let limits = response.rate_limit {
            for window in [limits.primary_window, limits.secondary_window].compactMap({ $0 }) {
                let id: String
                let label: String
                switch window.limit_window_seconds {
                case 18_000:
                    id = "session"
                    label = "5h limit"
                case 604_800:
                    id = "weekly"
                    label = "Weekly limit"
                default:
                    continue
                }
                guard let percent = window.used_percent else {
                    throw UsageProviderError.badResponse(status: 0)
                }
                guard !windows.contains(where: { $0.id == id }) else { continue }
                let resetsAt = window.reset_at.map { Date(timeIntervalSince1970: $0) }
                    ?? window.reset_after_seconds.map { now.addingTimeInterval($0) }
                windows.append(LimitWindow(
                    id: id, label: label, usedFraction: percent / 100, resetsAt: resetsAt
                ))
            }
        }
        guard !windows.isEmpty else {
            throw UsageProviderError.nothingMetered("Codex reported no 5-hour or weekly usage limits")
        }
        return windows.sorted { $0.id == "session" && $1.id != "session" }
    }
}
