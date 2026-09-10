import SwiftUI

/// The speech-bubble tail, its point aimed at the hovered cell.
///
/// Its shoulders leave the card tangent to the card's edge. That continuous
/// tangent is what makes the two pieces read as one moulded silhouette rather
/// than a triangle pasted onto a rounded rectangle.
private struct TooltipTail: Shape {
    /// Which way the card sits relative to the notch — the tip points back the
    /// other way, at the cell.
    let direction: NotchEdge.TooltipDirection

    func path(in rect: CGRect) -> Path {
        // The tip and the two ends of the base opposite it. Each curve starts
        // or finishes parallel to the card edge, rounding both joins while the
        // point stays crisp and continues to land on the hovered ring.
        let (tip, a, b, aShoulder, aTip, bTip, bShoulder):
            (CGPoint, CGPoint, CGPoint, CGPoint, CGPoint, CGPoint, CGPoint)
        switch direction {
        case .leading:   // card on the left, tip to the right
            tip = CGPoint(x: rect.maxX, y: rect.midY)
            (a, b) = (CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.minX, y: rect.maxY))
            aShoulder = CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.25)
            aTip = CGPoint(x: rect.maxX - rect.width * 0.42, y: rect.midY - rect.height * 0.12)
            bTip = CGPoint(x: rect.maxX - rect.width * 0.42, y: rect.midY + rect.height * 0.12)
            bShoulder = CGPoint(x: rect.minX, y: rect.maxY - rect.height * 0.25)
        case .trailing:  // card on the right, tip to the left
            tip = CGPoint(x: rect.minX, y: rect.midY)
            (a, b) = (CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.maxY))
            aShoulder = CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.25)
            aTip = CGPoint(x: rect.minX + rect.width * 0.42, y: rect.midY - rect.height * 0.12)
            bTip = CGPoint(x: rect.minX + rect.width * 0.42, y: rect.midY + rect.height * 0.12)
            bShoulder = CGPoint(x: rect.maxX, y: rect.maxY - rect.height * 0.25)
        case .down:      // card below, tip upward
            tip = CGPoint(x: rect.midX, y: rect.minY)
            (a, b) = (CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY))
            aShoulder = CGPoint(x: rect.minX + rect.width * 0.25, y: rect.maxY)
            aTip = CGPoint(x: rect.midX - rect.width * 0.12, y: rect.minY + rect.height * 0.42)
            bTip = CGPoint(x: rect.midX + rect.width * 0.12, y: rect.minY + rect.height * 0.42)
            bShoulder = CGPoint(x: rect.maxX - rect.width * 0.25, y: rect.maxY)
        case .up:        // card above, tip downward
            tip = CGPoint(x: rect.midX, y: rect.maxY)
            (a, b) = (CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY))
            aShoulder = CGPoint(x: rect.minX + rect.width * 0.25, y: rect.minY)
            aTip = CGPoint(x: rect.midX - rect.width * 0.12, y: rect.maxY - rect.height * 0.42)
            bTip = CGPoint(x: rect.midX + rect.width * 0.12, y: rect.maxY - rect.height * 0.42)
            bShoulder = CGPoint(x: rect.maxX - rect.width * 0.25, y: rect.minY)
        }

        var path = Path()
        path.move(to: a)
        path.addCurve(to: tip, control1: aShoulder, control2: aTip)
        path.addCurve(to: b, control1: bTip, control2: bShoulder)
        path.closeSubpath()
        return path
    }

    /// Long in the direction it points, wide across it.
    static func size(for direction: NotchEdge.TooltipDirection) -> CGSize {
        switch direction {
        case .leading, .trailing:
            return CGSize(width: NotchLayout.tailLength, height: NotchLayout.tailHeight)
        case .up, .down:
            return CGSize(width: NotchLayout.tailHeight, height: NotchLayout.tailLength)
        }
    }
}

/// The card chrome every tooltip shares: fixed width, the frame's padding and
/// corner, and the tail welded on so there is no seam between them.
private struct TooltipShell<Content: View>: View {
    /// Given explicitly rather than left to the contents.
    ///
    /// Sized by its contents, the card's height changes the instant they do —
    /// and the tail, centred on that height, jumps with it while the card's
    /// position is still gliding. The two halves then visibly come apart.
    let height: CGFloat
    /// Which side of the notch the card is on, so the tail goes on the other one.
    let direction: NotchEdge.TooltipDirection
    @ViewBuilder let content: Content

    @Environment(\.codenotchReduceTransparency) private var reduceTransparency

    private var card: some View {
        // The same arrangement that makes the notch fold work: the contents
        // are laid out once at their natural size and never move, and it is
        // the *mask* that changes size over them.
        //
        // The obvious alternative — putting the contents inside a frame of
        // the animating height — makes SwiftUI re-align them on every frame
        // of the animation, so the rows drift vertically inside the card and
        // the top ones slide out under the clip. Nothing should move here
        // except the boundary.
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: NotchLayout.cardCorner, style: .circular)
                .fill(Palette.card)
                .frame(width: NotchLayout.cardWidth, height: height)

            content
                .padding(NotchLayout.cardPadding)
                .frame(width: NotchLayout.cardWidth, alignment: .topLeading)
        }
        .frame(width: NotchLayout.cardWidth, height: height, alignment: .top)
        .clipShape(
            RoundedRectangle(cornerRadius: NotchLayout.cardCorner, style: .circular)
        )
        .overlay {
            if reduceTransparency {
                RoundedRectangle(cornerRadius: NotchLayout.cardCorner, style: .circular)
                    .strokeBorder(Palette.ringTrack, lineWidth: 1)
            }
        }
    }

    private var tail: some View {
        let size = TooltipTail.size(for: direction)
        // The tail is deliberately outside the clip: it is part of the card's
        // silhouette, not of its contents.
        return TooltipTail(direction: direction)
            .fill(Palette.card)
            .frame(width: size.width, height: size.height)
    }

    var body: some View {
        // Card first or tail first, laid out along whichever axis the tail
        // points. The pair is one silhouette either way.
        switch direction {
        case .leading:
            HStack(spacing: 0) { card; tail }
        case .trailing:
            HStack(spacing: 0) { tail; card }
        case .down:
            VStack(spacing: 0) { tail; card }
        case .up:
            VStack(spacing: 0) { card; tail }
        }
    }
}

private struct TooltipHeader<Mark: View>: View {
    let title: String
    /// Sits on the header's own line, so saying when a reading was taken costs
    /// the card no extra height.
    var note: String?
    @ViewBuilder let mark: Mark

    var body: some View {
        HStack(spacing: NotchLayout.headerGap) {
            mark
            Text(title)
                .font(Typography.cardTitle)
                .foregroundStyle(Palette.textPrimary)
            if let note {
                Spacer(minLength: Design.px(20))
                Text(note)
                    .font(Typography.cardBody)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
            }
        }
    }
}

/// A label on the left and a quieter value on the right — the row shape the
/// design frame uses throughout.
private struct SplitRow<Accessory: View>: View {
    let leading: String
    let trailing: String
    var leadingColor: Color = Palette.textPrimary
    var trailingColor: Color = Palette.textSecondary
    /// Sits immediately before the trailing text, inside the same group, so it
    /// travels with the word instead of drifting to the middle of the row.
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        HStack(spacing: Design.px(20)) {
            Text(leading).foregroundStyle(leadingColor)
            Spacer(minLength: 0)
            HStack(spacing: NotchLayout.statusDotGap) {
                accessory()
                Text(trailing).foregroundStyle(trailingColor)
            }
        }
        .font(Typography.cardBody)
        .lineLimit(1)
    }
}

extension SplitRow where Accessory == EmptyView {
    init(leading: String,
         trailing: String,
         leadingColor: Color = Palette.textPrimary,
         trailingColor: Color = Palette.textSecondary) {
        self.init(leading: leading, trailing: trailing,
                  leadingColor: leadingColor, trailingColor: trailingColor,
                  accessory: { EmptyView() })
    }
}

/// The ring beside a session's status.
///
/// Turning while the agent is working, still when it is not — so the row says
/// what is happening before the word is read.
private struct StatusRing: View {
    let state: AgentSession.State
    let color: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// One turn, in seconds. Slow enough to read as deliberate rather than as
    /// something struggling.
    private static let period: Double = 1.4

    var body: some View {
        Group {
            switch state {
            case .busy:
                if reduceMotion {
                    // Still, but still three-quarters: the gap alone says
                    // "in progress" without anything moving.
                    ring(trim: 0.75)
                } else {
                    // A timeline rather than `repeatForever`. An endless
                    // animation has to be cancelled to stop, and setting the
                    // value it is already heading towards does not cancel it —
                    // which is exactly how the refresh ring here once span for
                    // ever. Derived from the clock, it simply stops being drawn.
                    TimelineView(.animation) { context in
                        ring(trim: 0.75)
                            .rotationEffect(.degrees(angle(at: context.date)))
                    }
                }
            case .waiting:
                // Half a ring, held still: blocked, not progressing.
                ring(trim: 0.5)
            case .idle:
                ring(trim: 1)
            }
        }
        .frame(width: NotchLayout.statusDot, height: NotchLayout.statusDot)
    }

    private func ring(trim: CGFloat) -> some View {
        Circle()
            .trim(from: 0, to: trim)
            .stroke(color,
                    style: StrokeStyle(lineWidth: NotchLayout.statusDotStroke, lineCap: .round))
            // Start the gap at the top, where the eye lands first.
            .rotationEffect(.degrees(-90))
    }

    private func angle(at date: Date) -> Double {
        let turns = date.timeIntervalSinceReferenceDate / Self.period
        return turns.truncatingRemainder(dividingBy: 1) * 360
    }
}

// MARK: - Providers

/// One metered window: label and reset copy on a line, a track bar, then the
/// percentage burned.
private struct LimitWindowRow: View {
    let window: LimitWindow
    var inset: CGFloat = 0
    let fidelity: Fidelity
    let now: Date
    let resetTimeFormat: ResetTimeFormat
    let showsUsagePace: Bool
    @Environment(\.codenotchAccentColor) private var accentColor
    @AppStorage(Preferences.ringShowsRemainingKey) private var showsRemaining = true

    private var band: UsageBand { UsageBand.band(for: window.usedFraction ?? 0) }
    private var trackWidth: CGFloat { NotchLayout.cardWidth - 2 * NotchLayout.cardPadding - inset }
    /// Fills the same way the ring sweeps, so the card and the notch agree.
    private var fillWidth: CGFloat {
        let used = CGFloat(min(max(window.usedFraction ?? 0, 0), 1))
        return max(NotchLayout.barHeight, trackWidth * (showsRemaining ? 1 - used : used))
    }

    private var paceText: Text {
        guard showsUsagePace, let pace = window.usagePace(now: now) else {
            return Text("")
        }
        return Text(" · \(pace.summary)")
            .foregroundColor(pace.isDeficit ? .orange : Palette.textSecondary)
    }

    /// Blank rather than invented: some providers never say when the window rolls.
    private var resetText: String {
        window.resetsAt.map { ResetCopy.text(for: $0, now: now, format: resetTimeFormat) } ?? ""
    }

    /// A count-only row (no fraction, no reset) — like Ollama's per-model request
    /// counts — renders as a single table line: name left, count right.
    private var isCountRow: Bool {
        window.usedFraction == nil && window.used != nil
    }

    var body: some View {
        if isCountRow {
            SplitRow(leading: window.label, trailing: "\(window.used ?? 0)",
                     trailingColor: Palette.textSecondary)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                SplitRow(leading: window.label, trailing: resetText)

                // No bar without a denominator — an empty track would read as "none
                // used", which is not what "we do not know the limit" means.
                if window.usedFraction != nil {
                    ZStack(alignment: .leading) {
                        Capsule().fill(Palette.barTrack)
                        Capsule().fill(band.color(accent: accentColor)).frame(width: fillWidth)
                    }
                    .frame(width: trackWidth, height: NotchLayout.barHeight)
                    .padding(.top, NotchLayout.labelToBar)
                }

                Text("\(window.usedFraction == nil ? "" : fidelity.qualifier)\(window.summary)\(paceText)")
                    .font(Typography.cardBody)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .padding(.top, NotchLayout.barToUsed)
            }
        }
    }
}

private struct ProviderTooltip: View {
    let snapshot: ProviderSnapshot
    let now: Date
    let resetTimeFormat: ResetTimeFormat
    let showUsagePace: Bool

    /// Only worth saying when the numbers are not current. A remembered reading
    /// has to be dated, or it quietly passes itself off as live.
    private var readingAge: String? {
        guard snapshot.hasReading, let since = snapshot.status.staleSince,
              since != .distantPast
        else { return nil }
        return ElapsedCopy.ago(since: since, now: now)
    }

    private struct WindowGroup: Identifiable {
        let id: String
        let title: String?
        var windows: [LimitWindow]
    }

    private var groupedWindows: [WindowGroup] {
        var result: [WindowGroup] = []
        for window in snapshot.windows {
            if let last = result.last, last.title == window.group {
                result[result.count - 1].windows.append(window)
            } else {
                result.append(WindowGroup(id: window.group ?? window.id, title: window.group, windows: [window]))
            }
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TooltipHeader(title: "\(snapshot.displayName) Usage", note: readingAge) {
                ProviderGlyphView(glyph: snapshot.glyph)
                    .foregroundStyle(Palette.textPrimary)
            }

            if let block = snapshot.block {
                BlockedRow(text: block.summary(now: now))
                    .padding(.top, NotchLayout.headerToBlock)
            }

            if let message = snapshot.statusMessage {
                Text(message)
                    .font(Typography.cardBody)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, NotchLayout.headerToBlock)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(groupedWindows.enumerated()), id: \.element.id) { groupIndex, group in
                        if let title = group.title {
                            VStack(alignment: .leading, spacing: Design.px(12)) {
                                Text(title)
                                    .font(Typography.cardBody)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Palette.textPrimary)
                                    .padding(.leading, Design.px(4))
                                
                                VStack(alignment: .leading, spacing: NotchLayout.blockSpacing) {
                                    ForEach(Array(group.windows.enumerated()), id: \.element.id) { windowIndex, window in
                                        LimitWindowRow(window: window, inset: 2 * Design.px(16), fidelity: snapshot.fidelity, now: now, resetTimeFormat: resetTimeFormat, showsUsagePace: showUsagePace)
                                            .padding(.top, windowIndex == 0 ? 0 : NotchLayout.blockSpacing)
                                    }
                                }
                                .padding(Design.px(16))
                                .overlay(
                                    RoundedRectangle(cornerRadius: Design.px(20))
                                        .stroke(Color.white.opacity(0.25), lineWidth: Design.px(1.5))
                                )
                            }
                            .padding(.top, groupIndex == 0 ? NotchLayout.headerToBlock : Design.px(28))
                        } else {
                            ForEach(Array(group.windows.enumerated()), id: \.element.id) { windowIndex, window in
                                LimitWindowRow(window: window, fidelity: snapshot.fidelity, now: now, resetTimeFormat: resetTimeFormat, showsUsagePace: showUsagePace)
                                    .padding(.top, (groupIndex == 0 && windowIndex == 0) ? NotchLayout.headerToBlock : NotchLayout.blockSpacing)
                            }
                        }
                    }
                }
                .padding(.bottom, groupedWindows.contains(where: { $0.title != nil }) ? Design.px(8) : 0)
            }
        }
    }
}

private enum UsageFormat {
    static func tokens(_ value: Int?) -> String {
        guard let value else { return "—" }
        switch value {
        case 1_000_000_000...:
            return String(format: "%.2fB", locale: Locale(identifier: "en_US_POSIX"),
                          Double(value) / 1_000_000_000)
        case 1_000_000...:
            return String(format: "%.1fM", locale: Locale(identifier: "en_US_POSIX"),
                          Double(value) / 1_000_000)
        case 1_000...:
            return String(format: "%.0fK", locale: Locale(identifier: "en_US_POSIX"),
                          Double(value) / 1_000)
        default:
            return "\(value)"
        }
    }

    static func duration(seconds: Double?) -> String {
        guard let seconds, seconds.isFinite, seconds > 0 else { return "—" }
        let minutes = max(1, Int((seconds / 60).rounded()))
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours > 0 {
            return remainder == 0 ? "\(hours)h" : "\(hours)h \(remainder)m"
        }
        return "\(minutes)m"
    }

    static func days(_ value: Int?) -> String {
        guard let value else { return "—" }
        return "\(value)d"
    }
}

private struct CodexMetric: Identifiable {
    let id: String
    let value: String
    let label: String
}

private struct CodexMetricList: View {
    let metrics: [CodexMetric]

    var body: some View {
        VStack(alignment: .leading, spacing: NotchLayout.codexMetricRowGap) {
            ForEach(metrics) { metric in
                HStack(alignment: .firstTextBaseline, spacing: Design.px(20)) {
                    Text(metric.label)
                        .font(Typography.cardBody)
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    Text(metric.value)
                        .font(Typography.cardBody)
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(1)
                        .monospacedDigit()
                }
                .frame(height: NotchLayout.codexMetricRowHeight)
            }
        }
        .frame(height: NotchLayout.codexMetricHeight)
    }
}

private struct CodexDailyUsageChart: View {
    let buckets: [CodexTokenUsage.DailyBucket]
    let maximum: Int

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomLeading) {
                Rectangle()
                    .fill(Palette.ringTrack)
                    .frame(height: NotchLayout.hairline)

                HStack(alignment: .bottom, spacing: Design.px(4)) {
                    ForEach(buckets) { bucket in
                        RoundedRectangle(cornerRadius: Design.px(3), style: .continuous)
                            .fill(Palette.textSecondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: proxy.size.height
                                   * CGFloat(bucket.tokens) / CGFloat(maximum))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
        }
        .frame(height: NotchLayout.codexChartHeight)
        .clipped()
    }
}

/// Account-wide Codex activity. Unlike the quota rows above, this is sourced
/// from the Codex profile usage endpoint and is not a local estimate.
private struct CodexUsageSection: View {
    let usage: CodexTokenUsage
    let now: Date

    private var buckets: [CodexTokenUsage.DailyBucket] {
        usage.last30Days(now: now)
    }

    private var maximum: Int {
        max(1, buckets.map(\.tokens).max() ?? 0)
    }

    private var todayText: String {
        usage.usageToday(now: now).map { UsageFormat.tokens($0) } ?? "Pending"
    }

    private var metrics: [CodexMetric] {
        let summary = usage.summary
        return [
            CodexMetric(id: "lifetime", value: UsageFormat.tokens(summary?.lifetimeTokens),
                        label: "Lifetime tokens"),
            CodexMetric(id: "peak", value: UsageFormat.tokens(summary?.peakDailyTokens),
                        label: "Peak tokens"),
            CodexMetric(id: "longest", value: UsageFormat.duration(
                seconds: summary?.longestRunningTurnSeconds), label: "Longest chat"),
            CodexMetric(id: "current-streak", value: UsageFormat.days(
                summary?.currentStreakDays), label: "Current streak"),
            CodexMetric(id: "longest-streak", value: UsageFormat.days(
                summary?.longestStreakDays), label: "Longest streak")
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(Palette.ringTrack)
                .frame(height: NotchLayout.hairline)
                .padding(.top, NotchLayout.codexUsageTop)

            CodexMetricList(metrics: metrics)
                .padding(.top, NotchLayout.codexMetricTop)
                .padding(.bottom, NotchLayout.codexMetricBottom)

            Rectangle()
                .fill(Palette.ringTrack)
                .frame(height: NotchLayout.hairline)

            SplitRow(leading: "Today", trailing: todayText)
                .padding(.top, NotchLayout.blockSpacing)
            SplitRow(leading: "30-day tokens",
                     trailing: UsageFormat.tokens(usage.usageInLast30Days(now: now)))
                .padding(.top, NotchLayout.codexUsageRowGap)
            CodexDailyUsageChart(buckets: buckets, maximum: maximum)
                .padding(.top, NotchLayout.codexChartTop)
        }
    }
}

/// The line that says you are stopped.
///
/// Deliberately loud where the rest of the card is quiet: it is the one thing
/// here that changes what you can do next, and it can be true while the
/// percentage beside it still reads comfortable.
private struct BlockedRow: View {
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: NotchLayout.statusDotGap) {
            Image(systemName: "pause.circle.fill")
                .font(.system(size: NotchLayout.statusDot))
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .font(Typography.cardBody)
        .foregroundStyle(Palette.critical)
    }
}

// MARK: - Activity

private struct SessionRow: View {
    let session: AgentSession
    let now: Date
    @Environment(\.codenotchAccentColor) private var accentColor

    private var stateColor: Color {
        switch session.state {
        case .busy:    return accentColor
        case .waiting: return Palette.watch
        case .idle:    return Palette.textSecondary
        }
    }

    private var stateWord: String {
        switch session.state {
        case .busy:    return "working"
        case .waiting: return "waiting"
        case .idle:    return "idle"
        }
    }

    /// While blocked, what it is blocked on matters more than where it lives.
    private var detail: String {
        if session.state == .waiting, let waitingFor = session.waitingFor, !waitingFor.isEmpty {
            return waitingFor
        }
        return session.detail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SplitRow(leading: session.name, trailing: stateWord,
                     trailingColor: stateColor) {
                StatusRing(state: session.state, color: stateColor)
            }
            SplitRow(
                leading: detail,
                trailing: ElapsedCopy.text(since: session.since, now: now),
                leadingColor: Palette.textSecondary
            )
            .padding(.top, NotchLayout.sessionRowGap)
        }
    }
}

/// The live sessions for this provider, under a rule that separates them from
/// the limit windows above — they answer a different question.
private struct SessionList: View {
    let summary: ActivitySummary
    let now: Date
    /// How many rows this screen has room for; the rest are counted.
    let cap: Int

    /// Busy sessions first, so what is hidden is what matters least.
    private var ordered: [AgentSession] {
        summary.sessions.sorted { a, b in
            let rank: (AgentSession) -> Int = {
                switch $0.state { case .waiting: 0; case .busy: 1; case .idle: 2 }
            }
            return rank(a) == rank(b) ? a.since > b.since : rank(a) < rank(b)
        }
    }

    private var shown: [AgentSession] { Array(ordered.prefix(max(0, cap))) }
    private var hidden: Int { max(0, summary.sessions.count - shown.count) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(Palette.ringTrack)
                .frame(height: NotchLayout.hairline)
                .padding(.top, NotchLayout.blockSpacing)

            // Only as many as the card's budgeted height can hold. The rest
            // are counted rather than drawn: the card is clipped, not scrolled,
            // so anything past the budget silently pushes the title off the top.
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, session in
                SessionRow(session: session, now: now)
                    .padding(.top, NotchLayout.blockSpacing)
            }

            if hidden > 0 {
                Text("and \(hidden) more")
                    .font(Typography.cardBody)
                    .foregroundStyle(Palette.textSecondary)
                    .padding(.top, NotchLayout.blockSpacing)
            }
        }
    }
}

// MARK: - Entry point

struct TooltipCard: View {
    let snapshot: ProviderSnapshot
    var activity: ActivitySummary?
    let now: Date
    /// Which way the card sits from the notch, which follows from the edge.
    var direction: NotchEdge.TooltipDirection = .leading
    /// How many sessions this screen has room to list. Solved from the display
    /// rather than fixed, so a big screen hides nothing.
    var sessionCap: Int = NotchLayout.defaultSessionCap
    var resetTimeFormat: ResetTimeFormat = .automatic
    @AppStorage(Preferences.showUsagePaceKey) private var showUsagePace = false

    private var groupCount: Int {
        var groups = Set<String>()
        var count = 0
        for window in snapshot.windows {
            if let group = window.group, !groups.contains(group) {
                groups.insert(group)
                count += 1
            }
        }
        return count
    }

    /// The same figure the hover region uses, so what is drawn and what is
    /// reachable can never drift apart.
    private var height: CGFloat {
        NotchLayout.cardHeight(
            windowCount: snapshot.windows.count,
            groupCount: groupCount,
            sessionCount: activity?.sessions.count ?? 0,
            sessionCap: sessionCap,
            statusMessage: snapshot.statusMessage,
            blockMessage: snapshot.block?.summary(now: now),
            hasTokenUsage: snapshot.tokenUsage != nil,
            compactRowCount: snapshot.compactRowCount
        )
    }

    var body: some View {
        TooltipShell(height: height, direction: direction) {
            // Stacked, not replaced in place: during a swap both sets of rows
            // exist for a moment, and in a ZStack they overlap and dissolve
            // instead of shoving each other around. Top-aligned so neither
            // drifts while the card resizes around them.
            ZStack(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 0) {
                    ProviderTooltip(snapshot: snapshot, now: now, resetTimeFormat: resetTimeFormat,
                                    showUsagePace: showUsagePace)
                    if let tokenUsage = snapshot.tokenUsage {
                        CodexUsageSection(usage: tokenUsage, now: now)
                    }
                    if let activity {
                        SessionList(summary: activity, now: now, cap: sessionCap)
                    }
                }
                // An identity, so one provider's rows are never interpolated
                // into another's — that is what slid text through positions
                // belonging to neither layout. A crossfade rather than an
                // instant swap, so the change is part of the movement instead
                // of a cut in the middle of it.
                .id(snapshot.id)
                .transition(.opacity.animation(NotchMotion.crossfade))
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}
