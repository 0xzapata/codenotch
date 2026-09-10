import SwiftUI

/// The ring around a provider glyph: a grey track with a coloured arc that
/// starts at 12 o'clock and sweeps clockwise by the fraction used.
///
/// When that provider is doing something right now, a second, much thinner arc
/// appears *inside* the ring, in the gap between the glyph and the track. It is
/// deliberately a different radius, a different weight and a neutral colour, so
/// it reads as a separate fact rather than as the usage number moving.
struct ProviderRing: View {
    /// Nil when the provider reports what is left but never says out of what —
    /// there is no arc to draw, and inventing one would be a lie in a shape.
    let usedFraction: Double?
    /// The next window (weekly, say), as a thinner blue arc just inside the
    /// main one. Nil draws nothing there.
    var secondaryFraction: Double? = nil
    let glyph: ProviderGlyph
    var isStale: Bool = false
    /// Blocked right now. Shown as spent whatever the arc says, because that is
    /// what it means for you — a ring reading 16% while the account is paused
    /// is technically true and practically a lie.
    var isBlocked: Bool = false
    var activity: ActivitySummary?
    /// A fetch this cell asked for, in flight.
    var isRefreshing: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.codenotchReduceTransparency) private var reduceTransparency
    @Environment(\.codenotchAccentColor) private var accentColor
    @AppStorage(Preferences.ringShowsRemainingKey) private var showsRemaining = true
    @State private var spin: Double = 0

    // The colour is about how close the limit is, whichever way the arc runs.
    private var band: UsageBand {
        isBlocked ? .exhausted : UsageBand.band(for: usedFraction ?? 0)
    }
    private var sweep: CGFloat { sweep(for: usedFraction) }
    private var secondarySweep: CGFloat { sweep(for: secondaryFraction) }
    private func sweep(for fraction: Double?) -> CGFloat {
        let used = CGFloat(min(max(fraction ?? 0, 0), 1))
        return showsRemaining ? 1 - used : used
    }

    var body: some View {
        ZStack {
            // Dimming applies to the usage reading only. Whether Claude is
            // working right now is known first-hand and stays at full strength
            // even when the percentage behind it has gone stale.
            ZStack {
                Circle()
                    .strokeBorder(Palette.ringTrack, lineWidth: NotchLayout.trackStroke)

                // Alone, the arc runs down the middle of the track; paired
                // with a weekly, it moves to the outer half so the two sit
                // side by side at the same weight.
                if usedFraction != nil {
                    Circle()
                        .inset(by: secondaryFraction == nil ? NotchLayout.trackStroke / 2 : NotchLayout.progressStroke / 2)
                        .trim(from: 0, to: sweep)
                        .stroke(
                            band.color(accent: accentColor),
                            style: StrokeStyle(lineWidth: NotchLayout.progressStroke, lineCap: .round)
                        )
                        // Refreshing spins the reading itself rather than
                        // overlaying a separate spinner: the thing being
                        // refetched is the thing that should move, and a second
                        // arc on the same track only competes with it.
                        .rotationEffect(.degrees(-90 + spin))
                        // A ring that snaps to a new value reads as a glitch; one
                        // that sweeps reads as a measurement being taken.
                        .animation(NotchMotion.reading, value: sweep)
                        .animation(NotchMotion.reading, value: band)
                }

                // Same weight as the session arc, on the inner half of the
                // track. ponytail: one fixed blue, whatever the weekly band;
                // colour it by band too if a blue arc at 95% ever reads as calm.
                if secondaryFraction != nil {
                    Circle()
                        .inset(by: (NotchLayout.ringDiameter - NotchLayout.secondaryDiameter) / 2)
                        .trim(from: 0, to: secondarySweep)
                        .stroke(
                            Palette.secondary,
                            style: StrokeStyle(lineWidth: NotchLayout.secondaryStroke, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90 + spin))
                        .animation(NotchMotion.reading, value: secondarySweep)
                }

                ProviderGlyphView(glyph: glyph)
                    .foregroundStyle(Palette.textPrimary)
                    // A spent limit dims its glyph so the ring reads as "waiting".
                    // Under reduce-transparency, boost opacity so it stays legible without low alpha.
                    .opacity(band == .exhausted ? (reduceTransparency ? 0.7 : 0.35) : 1)
            }
            .opacity(isStale ? (reduceTransparency ? 0.75 : 0.45) : 1)

            if let activity, activity.state != .idle {
                ActivityArc(summary: activity)
            }
        }
        .frame(width: NotchLayout.ringDiameter, height: NotchLayout.ringDiameter)
        // Pressed in while it works, and released when the answer lands. The
        // ring is the button, so the ring is what should feel pressed.
        .scaleEffect(isRefreshing ? 0.93 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.62), value: isRefreshing)
        .onChange(of: isRefreshing) { _, refreshing in
            guard refreshing, !reduceMotion else { return }
            // Exactly one turn, and it stops by itself.
            //
            // The obvious spelling is a `repeatForever` linear spin started on
            // the way in and cancelled on the way out — but `repeatForever` does
            // not stop when you set the value back, and if the value you set is
            // the one it is already animating toward, nothing changes and it
            // simply keeps going. The ring then spins for ever after a refresh
            // that finished half a second in.
            //
            // A single finite turn has no cancellation problem at all: 360° is
            // the same angle as 0°, so it lands exactly where the reading
            // belongs. It eases out, so it settles rather than stopping dead.
            withAnimation(.timingCurve(0.32, 0, 0.14, 1, duration: 0.95)) {
                spin += 360
            }
        }
    }
}

/// The inner indicator: a short arc that spins while work is happening, and a
/// full pulsing ring when something is blocked waiting on you.
private struct ActivityArc: View {
    let summary: ActivitySummary

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.codenotchReduceTransparency) private var reduceTransparency
    @State private var spinning = false
    @State private var pulsing = false

    /// How much of the circle the moving arc covers.
    private let arcFraction: CGFloat = 0.25

    private var inset: CGFloat {
        (NotchLayout.ringDiameter - NotchLayout.activityDiameter) / 2
    }

    var body: some View {
        Group {
            switch summary.state {
            case .working: spinner
            case .waiting: pulse
            case .idle:    EmptyView()
            }
        }
        .frame(width: NotchLayout.ringDiameter, height: NotchLayout.ringDiameter)
    }

    private var spinner: some View {
        Circle()
            .inset(by: inset)
            .trim(from: 0, to: arcFraction)
            .stroke(
                summary.color,
                style: StrokeStyle(lineWidth: NotchLayout.activityStroke, lineCap: .round)
            )
            .rotationEffect(.degrees(spinning ? 360 : 0))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                    spinning = true
                }
            }
            .onDisappear { spinning = false }
    }

    private var pulse: some View {
        Circle()
            .inset(by: inset)
            .stroke(summary.color, lineWidth: NotchLayout.activityStroke)
            .opacity(pulsing ? (reduceTransparency ? 0.65 : 0.3) : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    pulsing = true
                }
            }
            .onDisappear { pulsing = false }
    }
}

/// A ring and the percent burned underneath it.
struct ProviderCell: View {
    let snapshot: ProviderSnapshot
    var activity: ActivitySummary?
    var isRefreshing: Bool = false

    @AppStorage(Preferences.ringShowsRemainingKey) private var showsRemaining = true

    /// A dash, not "0%": nothing read is not the same as nothing used.
    private var percentText: String {
        snapshot.hasReading ? snapshot.headlineText(remaining: showsRemaining) : "—"
    }

    var body: some View {
        VStack(spacing: NotchLayout.ringLabelGap) {
            ProviderRing(
                usedFraction: snapshot.hasReading ? snapshot.ringFraction : nil,
                secondaryFraction: snapshot.hasReading ? snapshot.secondaryFraction : nil,
                glyph: snapshot.glyph,
                isStale: snapshot.status.isStale || !snapshot.hasReading,
                isBlocked: snapshot.block != nil,
                activity: activity,
                isRefreshing: isRefreshing
            )
            Text(percentText)
                .font(Typography.percent)
                .foregroundStyle(Palette.textPrimary)
                // Never squeezed: across a horizontal edge the cell is only as
                // wide as the ring, and a label wider than that would be
                // truncated rather than allowed to overhang into the spacing
                // that is already there for it.
                .fixedSize(horizontal: true, vertical: false)
                .frame(height: NotchLayout.percentLineHeight)
                .contentTransition(.numericText())
                .animation(NotchMotion.reading, value: percentText)
        }
        .frame(height: NotchLayout.cellExtent)
    }
}
