#if canImport(SwiftUI)
import Foundation
import SwiftUI
@testable import HTMLICanSeeSwiftUI
import Testing

struct HTMLDocumentViewTests {
    @Test("Inline semantics become SwiftUI AttributedString attributes")
    func attributedStringSemantics() throws {
        let link = try #require(URL(string: "https://example.com"))
        let style = HTMLDocumentStyle(underlinesLinks: true)
        let output = HTMLAttributedStringBuilder(style: style).build([
            .text(
                "Styled",
                style: HTMLTextStyle(
                    isBold: true,
                    isItalic: true,
                    isStruckThrough: true,
                    link: link
                )
            ),
            .lineBreak,
            .text("Plain", style: .plain),
        ])
        let firstRun = try #require(output.runs.first)

        #expect(String(output.characters) == "Styled\nPlain")
        #expect(
            firstRun.inlinePresentationIntent?.contains(
                .stronglyEmphasized
            ) == true
        )
        #expect(
            firstRun.inlinePresentationIntent?.contains(.emphasized) == true
        )
        #expect(
            firstRun.inlinePresentationIntent?.contains(.strikethrough) == true
        )
        #expect(firstRun.link == link)
        #expect(firstRun.underlineStyle == .single)
    }

    @MainActor
    @Test("An empty decoded document can be rendered directly")
    func emptyDocument() throws {
        let data = Data(#"{"blocks":[]}"#.utf8)
        let document = try JSONDecoder().decode(HTMLDocument.self, from: data)
        let view = HTMLDocumentView(document)
            .frame(width: 100, height: 100)
        let renderer = ImageRenderer(content: view)

        _ = try #require(renderer.cgImage)
        #expect(document.blocks.isEmpty)
    }

    @Test("Renderer style is a sendable value")
    func rendererStyle() {
        let style = HTMLDocumentStyle(
            blockSpacing: 18,
            paragraphAlignment: .center,
            listItemSpacing: 7,
            nestedListSpacing: 9,
            listIndentation: 24,
            markerSpacing: 10,
            unorderedListMarker: "◦",
            orderedListMarkerSuffix: ")",
            markerColor: .orange,
            linkColor: .purple,
            underlinesLinks: true
        )

        requireRendererSendable(HTMLDocumentStyle.self)
        #expect(style.blockSpacing == 18)
        #expect(style.paragraphAlignment == .center)
        #expect(style.listIndentation == 24)
        #expect(style.unorderedListMarker == "◦")
        #expect(style.linkColor == .purple)
    }

    @Test("List presentation preserves markers and interleaved part order")
    func listPresentation() {
        let nestedList = HTMLList(
            style: .unordered,
            items: [
                HTMLListItem(
                    content: [.text("nested", style: .plain)]
                ),
            ]
        )
        let item = HTMLListItem(
            parts: [
                .inlines([.text("before", style: .plain)]),
                .list(nestedList),
                .inlines([.text("after", style: .plain)]),
            ]
        )
        let list = HTMLList(style: .ordered, items: [item, HTMLListItem()])
        let style = HTMLDocumentStyle(orderedListMarkerSuffix: ")")
        let presentation = HTMLListPresentation(list: list, style: style)

        #expect(presentation.rows.map(\.marker) == ["1)", "2)"])
        #expect(presentation.rows[0].item.parts == item.parts)
        #expect(
            presentation.rows[0].item.parts == [
                .inlines([.text("before", style: .plain)]),
                .list(nestedList),
                .inlines([.text("after", style: .plain)]),
            ]
        )
    }

    @MainActor
    @Test("Dynamic Type, RTL, and accessibility environments render a list")
    func adaptiveEnvironmentRendering() throws {
        let document = HTMLDocument(
            blocks: [
                .list(
                    HTMLList(
                        style: .ordered,
                        items: [
                            HTMLListItem(
                                parts: [
                                    .inlines([
                                        .text("before", style: .plain),
                                    ]),
                                    .list(
                                        HTMLList(
                                            style: .unordered,
                                            items: [
                                                HTMLListItem(
                                                    content: [
                                                        .text(
                                                            "nested",
                                                            style: .plain
                                                        ),
                                                    ]
                                                ),
                                            ]
                                        )
                                    ),
                                    .inlines([
                                        .text("after", style: .plain),
                                    ]),
                                ]
                            ),
                        ]
                    )
                ),
            ]
        )
        let view = HTMLDocumentView(document)
            .htmlDocumentStyle(
                HTMLDocumentStyle(
                    unorderedListMarker: "◦",
                    orderedListMarkerSuffix: ")"
                )
            )
            .environment(\.dynamicTypeSize, .accessibility5)
            .environment(\.layoutDirection, .rightToLeft)
            .accessibilityElement(children: .contain)
            .frame(width: 320)
        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = ProposedViewSize(width: 320, height: nil)

        _ = try #require(renderer.cgImage)
    }
}

private func requireRendererSendable<T: Sendable>(_ type: T.Type) {}
#endif
