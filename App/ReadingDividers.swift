import SwiftUI

/// The shared typographic hierarchy for the flat reading layouts.
///
/// Keep reading screens to these levels rather than picking sizes and weights ad hoc:
/// - `title`: the one thing the screen is about (assessment or notice title)
/// - `item`: anything scanned or tapped by name (criterion, attachment, lesson)
/// - `content`: prose (overview, feedback, notice body)
/// - `meta`: dates, page numbers, statuses and other supporting detail
/// - `label`: small all-caps section markers; the only uppercase style
enum ReadingTextStyle { case title, item, content, meta, label }

private struct ReadingTextModifier: ViewModifier {
    let style: ReadingTextStyle
    func body(content: Content) -> some View {
        switch style {
        case .title: content.font(.title2.bold()).foregroundStyle(Color(.label))
        case .item: content.font(.headline)
        case .content: content.font(.body)
        case .meta: content.font(.footnote).foregroundStyle(Color(.secondaryLabel))
        case .label: content.font(.caption2.weight(.semibold)).tracking(1.4).textCase(.uppercase)
            .foregroundStyle(Color(.secondaryLabel))
        }
    }
}

extension View {
    func readingStyle(_ style: ReadingTextStyle) -> some View { modifier(ReadingTextModifier(style: style)) }
}

/// The single divider weight used across reading layouts. Section breaks come from spacing and a label, not a heavier rule.
struct ReadingRule: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.12))
            .frame(height: 0.5)
            .accessibilityHidden(true)
    }
}

/// A section's label. It scrolls with its content (`readingSection(_:)`) rather than being a list section header, which
/// plain lists pin over the content beneath. The rule that separates sections closes each one rather than opening the next.
struct ReadingSectionHeader: View {
    let title: String
    var body: some View {
        Text(title).readingStyle(.label)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 2)
    }
}

extension View {
    /// A labelled reading section: the label, this content, then the closing rule.
    func readingSection(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: 8) { ReadingSectionHeader(title: title); self }.readingSectionEnd()
    }
    /// Closes a reading section with the shared rule, attached to the section's content rather than added as its own row
    /// (a separate row brings a full row's padding, and plain-list footers pin while scrolling).
    func readingSectionEnd() -> some View {
        VStack(alignment: .leading, spacing: 10) { self; ReadingRule() }
    }
}
