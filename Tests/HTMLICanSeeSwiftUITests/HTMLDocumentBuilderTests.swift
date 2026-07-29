import Foundation
import HTMLICanSeeSwiftUI
import HTMLICanSeeTokenizer
import Testing

struct HTMLDocumentBuilderTests {
    private let builder = HTMLDocumentBuilder()

    @Test("Supported inline elements compose their semantic styles")
    func supportedInlineElements() {
        let document = builder.build(
            from: """
            <p><strong><em><del>all</del></em></strong><b> bold</b><i> italic</i><br>end</p>
            """
        )

        #expect(
            document == HTMLDocument(
                blocks: [
                    .paragraph([
                        .text(
                            "all",
                            style: HTMLTextStyle(
                                isBold: true,
                                isItalic: true,
                                isStruckThrough: true
                            )
                        ),
                        .text(
                            " bold",
                            style: HTMLTextStyle(isBold: true)
                        ),
                        .text(
                            " italic",
                            style: HTMLTextStyle(isItalic: true)
                        ),
                        .lineBreak,
                        .text("end", style: .plain),
                    ]),
                ]
            )
        )
    }

    @Test("Adjacent runs with equal styles are coalesced")
    func adjacentRunCoalescing() {
        let document = builder.build(
            from: "<p><strong>one<!-- split -->two</strong></p>"
        )

        #expect(
            document.blocks == [
                .paragraph([
                    .text(
                        "onetwo",
                        style: HTMLTextStyle(isBold: true)
                    ),
                ]),
            ]
        )
    }

    @Test("ASCII whitespace collapses without changing other Unicode")
    func whitespaceNormalization() {
        let document = builder.build(
            from: "\n <p>  Hello\tworld \n </p> \n <p>A\u{00A0}\u{00A0}日é B</p> \n"
        )

        #expect(
            document.blocks == [
                .paragraph([
                    .text("Hello world", style: .plain),
                ]),
                .paragraph([
                    .text("A\u{00A0}\u{00A0}日é B", style: .plain),
                ]),
            ]
        )
    }

    @Test("A break preserves an intentionally empty paragraph")
    func emptyParagraphWithBreak() {
        let document = builder.build(from: "<p><br></p>")

        #expect(document.blocks == [.paragraph([.lineBreak])])
    }

    @Test("Unsupported tags are transparent to visible children")
    func unsupportedTagsPreserveText() {
        let document = builder.build(
            from: "<article>A<span>B</span><unknown>C</unknown></article>"
        )

        #expect(
            document.blocks == [
                .paragraph([
                    .text("ABC", style: .plain),
                ]),
            ]
        )
    }

    @Test("Script, style, and template contents are suppressed")
    func suppressedContents() {
        let document = builder.build(
            from: """
            <p>A<script>if (a < b) { window.x = "</not-script>"; }</script>B<style>.x::before { content: "<p>no</p>"; }</style>C<template><strong>D</strong></template>E</p>
            """
        )

        #expect(
            document.blocks == [
                .paragraph([
                    .text("ABCE", style: .plain),
                ]),
            ]
        )
    }

    @Test(
        "Accepted links become semantic URLs",
        arguments: [
            ("http://example.com/path", "http://example.com/path"),
            ("https://example.com/a?b=c#d", "https://example.com/a?b=c#d"),
            ("https://example.com/a%20b", "https://example.com/a%20b"),
            ("mailto:hello@example.com", "mailto:hello@example.com"),
            (" \nhttps://example.com/trimmed\t", "https://example.com/trimmed"),
        ]
    )
    func acceptedLinks(rawValue: String, expected: String) throws {
        let style = try onlyTextStyle(
            in: builder.build(
                from: "<p><a href=\"\(rawValue)\">link</a></p>"
            )
        )

        #expect(style.link?.absoluteString == expected)
    }

    @Test(
        "Rejected links retain text without link behavior",
        arguments: [
            "/relative",
            "//example.com/path",
            "javascript:alert(1)",
            "data:text/plain,hello",
            "https://",
            "https://exa mple.com",
            "https://example.com/%",
            "https://example.com/%0",
            "https://example.com/%0Z",
            "https://example.com/%ZZ",
            "https://example.com/\u{001F}",
            "https://example.com/\u{0085}",
            "mailto:",
        ]
    )
    func rejectedLinks(rawValue: String) throws {
        let document = builder.build(
            from: "<p><a href=\"\(rawValue)\">visible</a></p>"
        )
        let style = try onlyTextStyle(in: document)

        #expect(style.link == nil)
        #expect(
            document.blocks == [
                .paragraph([
                    .text("visible", style: .plain),
                ]),
            ]
        )
    }

    @Test("Only href affects link semantics")
    func ignoredAnchorAttributes() throws {
        let style = try onlyTextStyle(
            in: builder.build(
                from: """
                <p><a name="anchor" target="_blank" href="https://example.com">link</a></p>
                """
            )
        )

        #expect(style.link?.absoluteString == "https://example.com")
    }

    @Test("Ordered, unordered, and nested list semantics are retained")
    func nestedLists() {
        let document = builder.build(
            from: """
            <ol>
              <li>One</li>
              <li>Two
                <ul><li><strong>Nested</strong></li></ul>
              </li>
            </ol>
            """
        )

        #expect(
            document.blocks == [
                .list(
                    HTMLList(
                        style: .ordered,
                        items: [
                            HTMLListItem(
                                content: [.text("One", style: .plain)]
                            ),
                            HTMLListItem(
                                content: [.text("Two", style: .plain)],
                                nestedLists: [
                                    HTMLList(
                                        style: .unordered,
                                        items: [
                                            HTMLListItem(
                                                content: [
                                                    .text(
                                                        "Nested",
                                                        style: HTMLTextStyle(
                                                            isBold: true
                                                        )
                                                    ),
                                                ]
                                            ),
                                        ]
                                    ),
                                ]
                            ),
                        ]
                    )
                ),
            ]
        )
    }

    @Test("Inline content retains its order around a nested list")
    func interleavedListItemContent() {
        let document = builder.build(
            from: "<ul><li>before<ul><li>nested</li></ul>after</li></ul>"
        )
        let nested = HTMLList(
            style: .unordered,
            items: [
                HTMLListItem(
                    content: [.text("nested", style: .plain)]
                ),
            ]
        )

        #expect(
            document.blocks == [
                .list(
                    HTMLList(
                        style: .unordered,
                        items: [
                            HTMLListItem(
                                parts: [
                                    .inlines([
                                        .text("before", style: .plain),
                                    ]),
                                    .list(nested),
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
    }

    @Test("An empty list has no visible semantic block")
    func emptyListIsDropped() {
        #expect(builder.build(from: "<ul></ul>").blocks.isEmpty)
    }

    @Test("An explicit empty list item retains its visible marker")
    func emptyListItemIsRetained() {
        let document = builder.build(from: "<ul><li></li></ul>")

        #expect(
            document.blocks == [
                .list(
                    HTMLList(
                        style: .unordered,
                        items: [HTMLListItem()]
                    )
                ),
            ]
        )
    }

    @Test(
        "Inputs with no visible content produce an empty document",
        arguments: [
            "",
            " \n\t",
            "<!-- comment --><!doctype html>",
            "<script>visible?</script><style>x</style><template>y</template>",
            "<ol> \n </ol>",
        ]
    )
    func emptyDocuments(html: String) {
        #expect(builder.build(from: html).blocks.isEmpty)
    }

    @Test("Escaped markup remains visible literal text")
    func escapedLiteralMarkup() {
        let document = builder.build(
            from: "&lt;p&gt;Maybe html?&lt;/p&gt;"
        )

        #expect(
            document.blocks == [
                .paragraph([
                    .text("<p>Maybe html?</p>", style: .plain),
                ]),
            ]
        )
    }

    @Test("Malformed overlapping markup recovers deterministically")
    func malformedMarkup() {
        let html = """
        <p><strong>A<em>B</strong>C</p><ul><li>One<li>Two</ul>
        """
        let expected = HTMLDocument(
            blocks: [
                .paragraph([
                    .text("A", style: HTMLTextStyle(isBold: true)),
                    .text(
                        "B",
                        style: HTMLTextStyle(isBold: true, isItalic: true)
                    ),
                    .text("C", style: HTMLTextStyle(isItalic: true)),
                ]),
                .list(
                    HTMLList(
                        style: .unordered,
                        items: [
                            HTMLListItem(
                                content: [.text("One", style: .plain)]
                            ),
                            HTMLListItem(
                                content: [.text("Two", style: .plain)]
                            ),
                        ]
                    )
                ),
            ]
        )

        #expect(builder.build(from: html) == expected)
        #expect(builder.build(from: html) == builder.build(from: html))
    }

    @Test("Unclosed inline formatting does not leak to the next block or item")
    func formattingScopeRecovery() {
        let document = builder.build(
            from: """
            <ul><li><strong>A</li><li>B</li></ul><p><em>C</p><p>D</p>
            """
        )

        #expect(
            document.blocks == [
                .list(
                    HTMLList(
                        style: .unordered,
                        items: [
                            HTMLListItem(
                                content: [
                                    .text(
                                        "A",
                                        style: HTMLTextStyle(isBold: true)
                                    ),
                                ]
                            ),
                            HTMLListItem(
                                content: [.text("B", style: .plain)]
                            ),
                        ]
                    )
                ),
                .paragraph([
                    .text("C", style: HTMLTextStyle(isItalic: true)),
                ]),
                .paragraph([
                    .text("D", style: .plain),
                ]),
            ]
        )
    }

    @Test("Formatting scope tracks frame identity rather than stack depth")
    func overlappingFormattingScopeRecovery() {
        let document = builder.build(
            from: "<strong><p>X</strong><em>Y</p><p>Z</p>"
        )

        #expect(
            document.blocks == [
                .paragraph([
                    .text("X", style: HTMLTextStyle(isBold: true)),
                    .text("Y", style: HTMLTextStyle(isItalic: true)),
                ]),
                .paragraph([
                    .text("Z", style: .plain),
                ]),
            ]
        )
    }

    @Test(
        "Large unmatched end-tag streams stay linear",
        .timeLimit(.minutes(1))
    )
    func adversarialFormattingStream() throws {
        let repetitionCount = 10_000
        var tokens: [HTMLToken] = [
            .startTag(name: "p", attributes: [], selfClosing: false),
        ]
        tokens.reserveCapacity(repetitionCount * 3 + 3)
        tokens.append(
            contentsOf: repeatElement(
                .startTag(
                    name: "strong",
                    attributes: [],
                    selfClosing: false
                ),
                count: repetitionCount
            )
        )
        for _ in 0..<repetitionCount {
            tokens.append(.character("x"))
            tokens.append(.endTag(name: "em"))
        }
        tokens.append(.endTag(name: "p"))
        tokens.append(.eof)

        let document = builder.build(from: tokens)
        let block = try #require(document.blocks.first)
        guard case let .paragraph(content) = block else {
            Issue.record("Expected a paragraph block.")
            return
        }

        #expect(
            content == [
                .text(
                    String(repeating: "x", count: repetitionCount),
                    style: HTMLTextStyle(isBold: true)
                ),
            ]
        )
    }

    @Test(
        "Formatting changes do not repeatedly parse an accepted long link",
        .timeLimit(.minutes(1))
    )
    func longLinkFormattingStream() throws {
        let repetitionCount = 2_000
        let href = "https://example.com/" + String(
            repeating: "a",
            count: 16_384
        )
        var tokens: [HTMLToken] = [
            .startTag(name: "p", attributes: [], selfClosing: false),
            .startTag(
                name: "a",
                attributes: [HTMLAttribute(name: "href", value: href)],
                selfClosing: false
            ),
        ]
        tokens.reserveCapacity(repetitionCount * 2 + 5)
        for _ in 0..<repetitionCount {
            tokens.append(
                .startTag(
                    name: "strong",
                    attributes: [],
                    selfClosing: false
                )
            )
            tokens.append(.endTag(name: "strong"))
        }
        tokens.append(.character("linked"))
        tokens.append(.endTag(name: "p"))
        tokens.append(.eof)

        let style = try onlyTextStyle(in: builder.build(from: tokens))

        #expect(style.link?.absoluteString == href)
        #expect(!style.isBold)
    }

    @Test("Building from HTML and its token stream produces equal documents")
    func htmlAndTokenStreamParity() {
        let html = """
        <p>Hello <strong>world</strong><br>again</p><ul><li>One</li></ul>
        """
        let tokens = HTMLTokenizer.tokenize(html)

        #expect(builder.build(from: html) == builder.build(from: tokens))
    }

    @Test("A token stream need not contain EOF")
    func tokenStreamWithoutEOF() {
        let tokens: [HTMLToken] = [
            .startTag(name: "p", attributes: [], selfClosing: false),
            .character("Hello"),
            .endTag(name: "p"),
        ]

        #expect(
            builder.build(from: tokens).blocks == [
                .paragraph([
                    .text("Hello", style: .plain),
                ]),
            ]
        )
    }

    @Test("Many adjacent character tokens coalesce into one run")
    func largeAdjacentTokenStream() throws {
        var tokens: [HTMLToken] = [
            .startTag(name: "p", attributes: [], selfClosing: false),
        ]
        tokens.reserveCapacity(20_003)
        tokens.append(
            contentsOf: repeatElement(.character("x"), count: 20_000)
        )
        tokens.append(.endTag(name: "p"))
        tokens.append(.eof)

        let document = builder.build(from: tokens)
        let block = try #require(document.blocks.first)
        guard case let .paragraph(content) = block else {
            Issue.record("Expected a paragraph block.")
            return
        }
        let inline = try #require(content.first)
        guard case let .text(text, style) = inline else {
            Issue.record("Expected a text inline.")
            return
        }

        #expect(content.count == 1)
        #expect(text.count == 20_000)
        #expect(style == .plain)
    }
}

private func onlyTextStyle(in document: HTMLDocument) throws -> HTMLTextStyle {
    let block = try #require(document.blocks.first)
    let content: [HTMLInline]

    switch block {
    case let .paragraph(inlines):
        content = inlines
    case .list:
        Issue.record("Expected a paragraph block.")
        return .plain
    }

    let inline = try #require(content.first)
    switch inline {
    case let .text(_, style):
        return style
    case .lineBreak:
        Issue.record("Expected a text inline.")
        return .plain
    }
}
