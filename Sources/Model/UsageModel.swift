import Foundation

/// How much to trust a provider's numbers. The UI never presents a derived or
/// manual figure as if a vendor had published it.
enum Fidelity: String, Codable, Equatable {
    case official
    case derived
    case manual

    /// Prefix shown in front of a percentage that we worked out ourselves.
    var qualifier: String { self == .official ? "" : "~" }
}

enum ProviderStatus: Equatable {
    case ok
    case stale(since: Date)
    case needsAuth
    /// macOS was asked for a credential that exists, and refused.
    case accessDenied
    case unsupported(String)
    case error(String)

    var isStale: Bool { if case .stale = self { return true }; return false }

    /// When the reading behind this status was actually taken.
    var staleSince: Date? { if case .stale(let since) = self { return since }; return nil }
}

/// One metered window a provider exposes — Claude has two (the rolling session
/// and the longer all-models window), others have one.
struct LimitWindow: Identifiable, Codable, Equatable {
    /// How the date on this window should be read.
    ///
    /// A rate-limit window *resets*. A paid plan *renews*. Those are different
    /// facts, and writing "Resets Oct 1" next to a subscription date is what
    /// made the weekly credit rollover look like the bill.
    enum Rollover: String, Codable, Equatable {
        case resets
        case renews
    }

    let id: String
    let label: String
    /// 0...1+, where 1 means the limit is spent. Nil when the provider reports
    /// what is left but never says what the limit was — Perplexity does exactly
    /// this, and a percentage would have to invent the denominator.
    let usedFraction: Double?
    /// How many are left, when that is what the provider reports.
    let remaining: Int?
    /// How many have been spent, when the provider counts up rather than down
    /// and never states the ceiling. Cursor does this.
    let used: Int?
    /// Nil when the provider does not say when the window rolls over.
    let resetsAt: Date?
    /// Absent in archived readings from before this existed, which is `.resets`.
    let rollover: Rollover?

    init(id: String, label: String, usedFraction: Double? = nil,
         remaining: Int? = nil, used: Int? = nil, resetsAt: Date? = nil,
         rollover: Rollover? = nil) {
        self.id = id
        self.label = label
        self.usedFraction = usedFraction
        self.remaining = remaining
        self.used = used
        self.resetsAt = resetsAt
        self.rollover = rollover
    }

    var rollsOverAs: Rollover { rollover ?? .resets }

    /// What the tooltip says on the line under the bar.
    var summary: String {
        if let usedFraction {
            // Both ends of the same figure. Vendors do not agree on which to
            // show — Codex writes "87% remaining", Claude writes "% used" — so
            // a notch that picks one side leaves the user converting in their
            // head, and "12% Used" beside Codex's "87% remaining" reads as two
            // different numbers rather than one seen from either end. That is
            // what made a correct reading look wrong.
            let used = Int((usedFraction * 100).rounded())
            return "\(used)% Used · \(max(0, 100 - used))% left"
        }
        if let remaining {
            return remaining == 1 ? "1 left" : "\(remaining) left"
        }
        if let used {
            return used == 1 ? "1 used" : "\(used) used"
        }
        // A subscription row is the date; "No reading" under "Renews Oct 1"
        // would look like the date was a guess.
        if rollsOverAs == .renews { return "" }
        return "No reading"
    }
}

/// A limit that has been *reached*, even where the headline still shows room.
///
/// Vendors meter some capabilities separately from the plan's main allowance,
/// so "84% left" and "paused until 4:13 PM" are both true at once. A ring that
/// only knows the headline reports the first and hides the second, which is
/// the reading that actually stops you working.
struct UsageBlock: Equatable {
    /// What is paused, in the vendor's own terms.
    let reason: String
    /// When it lifts, where the vendor says.
    let resetsAt: Date?

    /// The line the tooltip leads with.
    func summary(now: Date = Date(), calendar: Calendar = .current) -> String {
        guard let resetsAt, resetsAt > now else { return reason }
        let formatter = ResetCopy.formatter(for: calendar)
        // The same clock the vendor's own banner uses — "4:13 PM" — rather
        // than a countdown, because that is what you are waiting for.
        formatter.dateFormat = ResetCopy.daysApart(from: now, to: resetsAt,
                                                   calendar: calendar) >= 1
            ? "E h:mm a" : "h:mm a"
        return "\(reason) until \(formatter.string(from: resetsAt))"
    }
}

struct ProviderSnapshot: Identifiable, Equatable {
    let id: String
    let displayName: String
    let glyph: ProviderGlyph
    let fidelity: Fidelity
    var status: ProviderStatus
    let windows: [LimitWindow]
    /// Which window the ring means, declared by the provider rather than left to
    /// position. Without it the headline is "whichever window happens to be
    /// first", and a window dropping out of the response silently promotes
    /// another one — the ring keeps its shape and quietly changes its subject.
    var headlineID: String?
    /// Set when something is blocked right now. Deliberately separate from the
    /// windows: it is not a measurement, it is a door being shut.
    var block: UsageBlock?
    /// The fetch succeeded but the bill date was not in this response. Keep
    /// the last known `.renews` window: a timeout on `/billing` must not
    /// archive a credits-only snapshot and erase "Renews Oct 1".
    var preservePriorRenewal: Bool = false

    /// The number on the cell: the provider's declared primary window — for
    /// Claude, the current session.
    ///
    /// Not the most-constrained window, which is what the design spec asks for.
    /// Picking whichever limit is highest means the headline silently changes
    /// meaning — session one minute, weekly the next — and disagrees with
    /// Claude's own panel, which always leads with the session.
    ///
    /// If the declared window is missing from the response the cell shows no
    /// reading rather than promoting a different one. A blank is honest; a
    /// weekly percentage wearing the session's place is not.
    var headline: LimitWindow? {
        if let headlineID {
            return windows.first { $0.id == headlineID }
        }
        // Archives from before `headlineID` was stored fall through here.
        // A renewal row has no percentage; using it as the ring would draw
        // a dash over a perfectly good usage window sitting next to it.
        return windows.first { $0.usedFraction != nil } ?? windows.first
    }

    var usedFraction: Double? { headline?.usedFraction }

    /// The plan's billing date, when a window is marked as a renewal rather
    /// than a rate-limit reset. Separate from the headline: the ring is usage,
    /// this is when the subscription itself rolls.
    var renewal: LimitWindow? { windows.first { $0.rollsOverAs == .renews } }

    /// Windows the tooltip draws as usage rows. A date-only renewal is a line
    /// of copy, not a bar — putting it in this list buried "Renews Oct 1"
    /// next to the weekly credits reset. A metered window that also renews
    /// still belongs here: `.renews` is the date wording, not "has no bar".
    var usageWindows: [LimitWindow] {
        windows.filter { window in
            if window.rollsOverAs == .renews,
               window.usedFraction == nil, window.remaining == nil, window.used == nil {
                return false
            }
            return true
        }
    }

    func renewalCopy(now: Date = Date()) -> String? {
        renewal?.resetsAt.map { ResetCopy.text(for: $0, now: now, rollover: .renews) }
    }

    /// Credits can land while the bill request fails. Keep the last known
    /// renewal rather than archiving a snapshot that pretends there isn't one.
    func preservingPriorRenewal(from previous: ProviderSnapshot?) -> ProviderSnapshot {
        guard preservePriorRenewal, renewal == nil, let prior = previous?.renewal else {
            return self
        }
        return ProviderSnapshot(
            id: id, displayName: displayName, glyph: glyph, fidelity: fidelity,
            status: status, windows: [prior] + windows,
            headlineID: headlineID, block: block
        )
    }

    /// What the cell prints under the ring.
    var headlineText: String {
        if let usedFraction { return "\(Int((usedFraction * 100).rounded()))%" }
        if let remaining = headline?.remaining { return "\(remaining)" }
        if let used = headline?.used { return "\(used)" }
        return "—"
    }

    /// True when there is no reading to show — the cell draws an empty ring and
    /// a dash rather than an authoritative-looking 0%.
    var hasReading: Bool { !windows.isEmpty }

    /// A ring can only be drawn when the provider said what the limit was.
    var ringFraction: Double? { usedFraction }

    /// Signing in means something different per provider, so the prompt has to
    /// say which door to knock on.
    private var authPrompt: String {
        switch id {
        case "claude":     return "Sign in to Claude Code to read your usage"
        // A profile is signed in by running Claude Code against its directory,
        // which is worth saying: plain `claude` signs the default one in.
        case _ where ClaudeProfile.isClaude(providerID: id):
            let slug = ClaudeProfile.slug(fromProviderID: id) ?? ""
            return "Sign in to Claude Code in ~/.claude-\(slug) to read your usage"
        case "cursor":     return "Sign in to Cursor in the editor"
        case "codex":      return "Sign in to Codex to read your usage"
        case "gemini":     return "Sign in to Antigravity to read your usage"
        case "glm":        return "Set up a GLM Coding Plan key for a coding tool to read your usage"
        case "grok":       return "Run grok login to read your usage"
        default:           return "Sign in to \(displayName) to read your usage"
        }
    }

    /// What the tooltip says instead of limit rows when there is nothing to show.
    var statusMessage: String? {
        if hasReading { return nil }
        switch status {
        case .needsAuth:      return authPrompt
        case .accessDenied:
            // Says what happened and what fixes it. "Sign in to Claude Code"
            // would send someone who *is* signed in to fix the wrong thing.
            return "Codenotch was refused access to \(displayName)'s saved "
                 + "login. Click this ring to ask again, and choose Always Allow."
        case .unsupported(let why): return why
        case .error(let why): return "Couldn't read usage — \(why)"
        case .stale, .ok:     return "Waiting for the first reading…"
        }
    }
}
