import Testing
@testable import HTMLICanSeeTokenizer

@Suite("Tokenizer recovery and robustness")
struct HTMLTokenizerRecoveryTests {
    @Test("Emits comments and complete DOCTYPE fields")
    func commentsAndDoctypes() {
        let tokens = HTMLTokenizer.tokenize(
            #"<!DOCTYPE HTML PUBLIC "-//Example//DTD" "example.dtd"><!--ok-->"#
        )

        #expect(tokens == [
            .doctype(
                HTMLDOCTYPE(
                    name: "html",
                    publicIdentifier: "-//Example//DTD",
                    systemIdentifier: "example.dtd",
                    forceQuirks: false
                )
            ),
            .comment("ok"),
            .eof,
        ])
    }

    @Test("Recovers from malformed attributes and tags")
    func malformedMarkup() {
        var tokenizer = HTMLTokenizer("<p =x a=\"one\"b='two' c=>tail</>")

        #expect(tokenizer.collect() == [
            .startTag(
                name: "p",
                attributes: [
                    HTMLAttribute(name: "=x", value: ""),
                    HTMLAttribute(name: "a", value: "one"),
                    HTMLAttribute(name: "b", value: "two"),
                    HTMLAttribute(name: "c", value: ""),
                ],
                selfClosing: false
            ),
            .character("tail"),
            .eof,
        ])
        #expect(tokenizer.errors.map(\.code) == [
            .unexpectedEqualsSignBeforeAttributeName,
            .missingWhitespaceBetweenAttributes,
            .missingAttributeValue,
            .missingEndTagName,
        ])
    }

    @Test(
        "EOF is recoverable in major states",
        arguments: [
            ("<", HTMLTokenizerState.data, nil, [HTMLToken.character("<"), .eof], [.eofBeforeTagName]),
            ("<p", .data, nil, [.eof], [.eofInTag]),
            ("<!--x", .data, nil, [.comment("x"), .eof], [.eofInComment]),
            (
                "<!DOCTYPE html",
                .data,
                nil,
                [.doctype(HTMLDOCTYPE(name: "html", forceQuirks: true)), .eof],
                [.eofInDoctype]
            ),
            (
                "<!--x",
                .scriptData,
                "script",
                [.character("<!--x"), .eof],
                [.eofInScriptHTMLCommentLikeText]
            ),
            ("x", .cdataSection, nil, [.character("x"), .eof], [.eofInCdata]),
        ] as [(
            String,
            HTMLTokenizerState,
            String?,
            [HTMLToken],
            [HTMLParseError.Code]
        )]
    )
    func eofRecovery(
        input: String,
        state: HTMLTokenizerState,
        lastStartTagName: String?,
        expectedTokens: [HTMLToken],
        expectedErrors: [HTMLParseError.Code]
    ) {
        var tokenizer = HTMLTokenizer(
            input,
            initialState: state,
            lastStartTagName: lastStartTagName
        )
        #expect(tokenizer.collect() == expectedTokens)
        #expect(tokenizer.errors.map(\.code) == expectedErrors)
    }

    @Test("Handles large adversarial input without recursion or backtracking")
    func largeInput() {
        let text = String(repeating: "a", count: 100_000)
        let references = String(repeating: "&notit;", count: 2_000)
        var tokenizer = HTMLTokenizer(text + references)
        let tokens = tokenizer.collect()

        #expect(tokens.count == 2)
        guard case let .character(output) = tokens.first else {
            Issue.record("Expected one coalesced character token")
            return
        }
        #expect(output.hasPrefix(text))
        #expect(output.count == text.count + 4 * 2_000)
        #expect(
            tokenizer.errors.filter {
                $0.code == .missingSemicolonAfterCharacterReference
            }.count == 2_000
        )
    }
}
