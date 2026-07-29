#if canImport(SwiftUI)
import Foundation
import SwiftUI

/// Renders a previously built ``HTMLDocument`` without retaining or reparsing
/// its source HTML.
public struct HTMLDocumentView: View {
    private let document: HTMLDocument

    @Environment(\.htmlDocumentStyle) private var style

    public init(_ document: HTMLDocument) {
        self.document = document
    }

    public var body: some View {
        #if os(iOS) || os(macOS) || os(visionOS)
        HTMLDocumentContent(blocks: document.blocks, style: style)
            .textSelection(.enabled)
        #else
        HTMLDocumentContent(blocks: document.blocks, style: style)
        #endif
    }
}

private struct HTMLDocumentContent: View {
    let blocks: [HTMLBlock]
    let style: HTMLDocumentStyle

    var body: some View {
        VStack(alignment: .leading, spacing: style.blockSpacing) {
            // Semantic blocks intentionally carry no presentation identity.
            // Their position is stable for this immutable document value, and
            // these rows own no transient view state.
            ForEach(blocks.indices, id: \.self) { index in
                HTMLBlockView(block: blocks[index], style: style)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct HTMLBlockView: View {
    let block: HTMLBlock
    let style: HTMLDocumentStyle

    var body: some View {
        switch block {
        case let .paragraph(content):
            HTMLInlineText(content: content, style: style)
                .frame(maxWidth: .infinity, alignment: .leading)
        case let .list(list):
            HTMLListView(list: list, style: style)
        }
    }
}

private struct HTMLListView: View {
    let list: HTMLList
    let style: HTMLDocumentStyle

    var body: some View {
        let presentation = HTMLListPresentation(list: list, style: style)

        VStack(alignment: .leading, spacing: style.listItemSpacing) {
            ForEach(presentation.rows.indices, id: \.self) { index in
                HTMLListItemView(
                    item: presentation.rows[index].item,
                    marker: presentation.rows[index].marker,
                    style: style
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}

struct HTMLListPresentation: Equatable {
    struct Row: Equatable {
        let marker: String
        let item: HTMLListItem
    }

    let rows: [Row]

    init(list: HTMLList, style: HTMLDocumentStyle) {
        rows = list.items.enumerated().map { index, item in
            let marker = switch list.style {
            case .unordered:
                style.unorderedListMarker
            case .ordered:
                "\(index + 1)\(style.orderedListMarkerSuffix)"
            }
            return Row(marker: marker, item: item)
        }
    }
}

private struct HTMLListItemView: View {
    let item: HTMLListItem
    let marker: String
    let style: HTMLDocumentStyle

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: style.markerSpacing) {
            // Keep the marker accessible because stack-rendered lists do not
            // otherwise expose native list semantics to VoiceOver.
            Text(marker)
                .foregroundStyle(style.markerColor)

            VStack(alignment: .leading, spacing: style.nestedListSpacing) {
                ForEach(item.parts.indices, id: \.self) { index in
                    switch item.parts[index] {
                    case let .inlines(content):
                        HTMLInlineText(content: content, style: style)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    case let .list(list):
                        HTMLListView(list: list, style: style)
                            .padding(.leading, style.listIndentation)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}

private struct HTMLInlineText: View {
    let content: [HTMLInline]
    let style: HTMLDocumentStyle

    var body: some View {
        Text(HTMLAttributedStringBuilder(style: style).build(content))
            .tint(style.linkColor)
    }
}

struct HTMLAttributedStringBuilder {
    let style: HTMLDocumentStyle

    func build(_ content: [HTMLInline]) -> AttributedString {
        var result = AttributedString()

        for inline in content {
            switch inline {
            case let .text(text, semanticStyle):
                result.append(fragment(text, semanticStyle: semanticStyle))
            case .lineBreak:
                result.append(AttributedString("\n"))
            }
        }

        return result
    }

    private func fragment(
        _ text: String,
        semanticStyle: HTMLTextStyle
    ) -> AttributedString {
        var fragment = AttributedString(text)
        var presentationIntent: InlinePresentationIntent = []

        if semanticStyle.isBold {
            presentationIntent.insert(.stronglyEmphasized)
        }
        if semanticStyle.isItalic {
            presentationIntent.insert(.emphasized)
        }
        if semanticStyle.isStruckThrough {
            presentationIntent.insert(.strikethrough)
        }
        if !presentationIntent.isEmpty {
            fragment.inlinePresentationIntent = presentationIntent
        }
        if let link = semanticStyle.link {
            fragment.link = link
            if style.underlinesLinks {
                fragment.underlineStyle = .single
            }
        }

        return fragment
    }
}
#endif
