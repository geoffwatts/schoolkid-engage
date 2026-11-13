import SwiftUI

/// A loading indicator that keeps a wait light: a spinner and a rotating line, starting at a random one. VoiceOver
/// hears only `accessibilityLabel`, which says plainly what's loading.
struct RotatingLoadingIndicator: View {
    let messages: [String]
    let accessibilityLabel: String
    @State private var index: Int?
    @State private var showing = true
    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text(messages[index ?? 0]).opacity(showing ? 1 : 0)
        }
        .font(.subheadline).padding(.horizontal, 18).padding(.vertical, 12)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
        .task {
            if index == nil { index = Int.random(in: 0..<messages.count) }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2.4))
                guard !Task.isCancelled else { return }
                // Out, change, back in: a crossfade would overlap two lines of different lengths.
                withAnimation(.easeOut(duration: 0.2)) { showing = false }
                try? await Task.sleep(for: .milliseconds(200))
                index = ((index ?? 0) + 1) % messages.count
                withAnimation(.easeIn(duration: 0.2)) { showing = true }
            }
        }
        .accessibilityElement(children: .ignore).accessibilityLabel(accessibilityLabel)
    }
}

/// The reading screens' loading indicator (updates, news, assessments, reports, the timetable).
struct SchoolLoadingIndicator: View {
    /// What VoiceOver hears, e.g. "Reading assessments".
    let accessibilityLabel: String
    static let messages = [
        "Sitting up straight…", "Polishing an apple for the teacher…", "Sharpening every pencil…",
        "Covering books in contact…", "Finding the other shoe…", "No hat, no play…", "Lining up for assembly…",
        "Signing the permission slip…", "Rummaging through lost property…", "Copying down the homework…",
        "Blaming the dog…", "Waiting for the bell…", "Putting a hand up…", "Rubbing out the smudges…",
        "Re-reading the rubric…", "Folding the newsletter into a plane…", "Tucking the shirt in…",
        "Finding a pen that works…"
    ]
    var body: some View {
        RotatingLoadingIndicator(messages: Self.messages, accessibilityLabel: accessibilityLabel)
    }
}
