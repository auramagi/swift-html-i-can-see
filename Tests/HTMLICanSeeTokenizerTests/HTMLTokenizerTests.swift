import Testing
@testable import HTMLICanSeeTokenizer

@Suite("HTML tokenizer")
struct HTMLTokenizerTests {
    @Test("Tokenizes tags, ordered attributes, text, and EOF")
    func basicTokenization() {
        let tokens = HTMLTokenizer.tokenize("<P id=first class='lead'>Hello<br/></P>")

        #expect(tokens == [
            .startTag(
                name: "p",
                attributes: [
                    HTMLAttribute(name: "id", value: "first"),
                    HTMLAttribute(name: "class", value: "lead"),
                ],
                selfClosing: false
            ),
            .character("Hello"),
            .startTag(name: "br", attributes: [], selfClosing: true),
            .endTag(name: "p"),
            .eof,
        ])
    }

    @Test("Streaming and collection produce the same tokens")
    func streamingMatchesCollection() {
        let html = "<p>one &amp; two</p><!-- done -->"
        let expected = HTMLTokenizer.tokenize(html)
        var tokenizer = HTMLTokenizer(html)
        var streamed: [HTMLToken] = []

        while streamed.last != .eof {
            streamed.append(tokenizer.nextToken())
        }

        #expect(streamed == expected)
    }

    @Test("Preprocesses CRLF and CR and reports data-state nulls")
    func inputPreprocessing() {
        var tokenizer = HTMLTokenizer("one\r\ntwo\rthree\u{0}four")

        #expect(tokenizer.collect() == [
            .character("one\ntwo\nthree\u{0}four"),
            .eof,
        ])
        #expect(tokenizer.errors.map(\.code) == [.unexpectedNullCharacter])
    }

    @Test("Drops later duplicate attributes")
    func duplicateAttributes() {
        var tokenizer = HTMLTokenizer("<p A=first a=second b>")

        #expect(tokenizer.collect() == [
            .startTag(
                name: "p",
                attributes: [
                    HTMLAttribute(name: "a", value: "first"),
                    HTMLAttribute(name: "b", value: ""),
                ],
                selfClosing: false
            ),
            .eof,
        ])
        #expect(tokenizer.errors.map(\.code) == [.duplicateAttribute])
    }

    @Test(
        "Caller-selectable text states",
        arguments: [
            (HTMLTokenizerState.rcdata, "&lt;</title>", "title", "<", true),
            (.rawtext, "&lt;</style>", "style", "&lt;", true),
            (.scriptData, "1 < 2</script>", "script", "1 < 2", true),
            (.plaintext, "<b>&amp;", "plaintext", "<b>&amp;", false),
            (.cdataSection, "<b>&amp;]]>", "foreign", "<b>&amp;", false),
        ]
    )
    func textStates(
        state: HTMLTokenizerState,
        input: String,
        lastStartTag: String,
        expectedText: String,
        emitsEndTag: Bool
    ) {
        let tokens = HTMLTokenizer.tokenize(
            input,
            initialState: state,
            lastStartTagName: lastStartTag
        )

        var expected: [HTMLToken] = [.character(expectedText)]
        if emitsEndTag {
            expected.append(.endTag(name: lastStartTag))
        }
        expected.append(.eof)
        #expect(tokens == expected)
    }

    @Test("State can be controlled between streamed tokens")
    func explicitStateControl() {
        var tokenizer = HTMLTokenizer("<style>body { color: red }</style>")
        #expect(
            tokenizer.nextToken()
                == .startTag(name: "style", attributes: [], selfClosing: false)
        )

        tokenizer.switchTo(.rawtext)
        // State changes do not synthesize tree-construction context. The start
        // tag just emitted above supplies the appropriate-end-tag context.
        #expect(tokenizer.nextToken() == .character("body { color: red }"))
        #expect(tokenizer.nextToken() == .endTag(name: "style"))
        #expect(tokenizer.nextToken() == .eof)
    }
}
