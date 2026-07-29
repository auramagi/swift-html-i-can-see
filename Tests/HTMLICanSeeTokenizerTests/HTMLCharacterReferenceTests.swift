import Testing
@testable import HTMLICanSeeTokenizer

@Suite("HTML character references")
struct HTMLCharacterReferenceTests {
    @Test(
        "Decodes named references using longest-prefix matching",
        arguments: [
            ("&amp;", "&", []),
            ("&AElig;", "Æ", []),
            ("&NotEqualTilde;", "≂̸", []),
            ("&notin;", "∉", []),
            ("&amp", "&", [.missingSemicolonAfterCharacterReference]),
            ("&notit;", "¬it;", [.missingSemicolonAfterCharacterReference]),
            ("&doesnotexist;", "&doesnotexist;", [.unknownNamedCharacterReference]),
        ] as [(String, String, [HTMLParseError.Code])]
    )
    func namedReferences(
        input: String,
        expected: String,
        expectedErrors: [HTMLParseError.Code]
    ) {
        var tokenizer = HTMLTokenizer(input)
        #expect(tokenizer.collect() == [.character(expected), .eof])
        #expect(tokenizer.errors.map(\.code) == expectedErrors)
    }

    @Test(
        "Decodes decimal and hexadecimal references",
        arguments: [
            ("&#65;", "A", []),
            ("&#x1F642;", "🙂", []),
            ("&#x80;", "€", [.controlCharacterReference]),
            ("&#0;", "\u{FFFD}", [.nullCharacterReference]),
            ("&#xD800;", "\u{FFFD}", [.surrogateCharacterReference]),
            ("&#x110000;", "\u{FFFD}", [.characterReferenceOutsideUnicodeRange]),
            (
                "&#xFDD0;",
                String(Unicode.Scalar(0xFDD0)!),
                [.noncharacterCharacterReference]
            ),
            ("&#65", "A", [.missingSemicolonAfterCharacterReference]),
            ("&#x;", "&#x;", [.absenceOfDigitsInNumericCharacterReference]),
        ] as [(String, String, [HTMLParseError.Code])]
    )
    func numericReferences(
        input: String,
        expected: String,
        expectedErrors: [HTMLParseError.Code]
    ) {
        var tokenizer = HTMLTokenizer(input)
        #expect(tokenizer.collect() == [.character(expected), .eof])
        #expect(tokenizer.errors.map(\.code) == expectedErrors)
    }

    @Test("Legacy semicolonless references are restricted in attributes")
    func attributeAmbiguity() {
        let tokens = HTMLTokenizer.tokenize(
            "<p first='&notit;' second='&not;' third='&amp='>"
        )

        #expect(tokens == [
            .startTag(
                name: "p",
                attributes: [
                    HTMLAttribute(name: "first", value: "&notit;"),
                    HTMLAttribute(name: "second", value: "¬"),
                    HTMLAttribute(name: "third", value: "&amp="),
                ],
                selfClosing: false
            ),
            .eof,
        ])
    }
}
