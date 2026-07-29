import Foundation
import Testing
@testable import HTMLICanSeeTokenizer

@Suite("Stable tokenizer values")
struct HTMLTokenCodableTests {
    @Test("All token cases round-trip through JSON")
    func tokenRoundTrip() throws {
        let tokens: [HTMLToken] = [
            .doctype(
                HTMLDOCTYPE(
                    name: "html",
                    publicIdentifier: "-//W3C//DTD HTML 4.01//EN",
                    systemIdentifier: "about:legacy-compat",
                    forceQuirks: true
                )
            ),
            .startTag(
                name: "a",
                attributes: [HTMLAttribute(name: "href", value: "https://example.com")],
                selfClosing: false
            ),
            .endTag(name: "a"),
            .comment("comment"),
            .character("text"),
            .eof,
        ]

        let encoded = try JSONEncoder().encode(tokens)
        let decoded = try JSONDecoder().decode([HTMLToken].self, from: encoded)
        #expect(decoded == tokens)
    }

    @Test("Version 1 token JSON remains decodable and encodes identically")
    func stableRepresentation() throws {
        let fixtureURL = try #require(
            Bundle.module.url(
                forResource: "token-stream-v1",
                withExtension: "json"
            )
        )
        let fixtureData = try Data(contentsOf: fixtureURL)
        let tokens = try JSONDecoder().decode([HTMLToken].self, from: fixtureData)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

        let encoded = try encoder.encode(tokens)
        let fixtureObject = try JSONSerialization.jsonObject(with: fixtureData)
        let encodedObject = try JSONSerialization.jsonObject(with: encoded)

        #expect(tokens.count == 6)
        #expect(encodedObject as? NSArray == fixtureObject as? NSArray)
    }

    @Test("Character token has a stable keyed representation")
    func stableCharacterFixture() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        let data = try encoder.encode(HTMLToken.character("hello"))
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json == #"{"data":"hello","type":"character"}"#)
    }

    @Test("Start-tag token has a stable keyed representation")
    func stableStartTagFixture() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let token = HTMLToken.startTag(
            name: "a",
            attributes: [HTMLAttribute(name: "href", value: "mailto:a@example.com")],
            selfClosing: false
        )

        let data = try encoder.encode(token)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(
            json
                == #"{"attributes":[{"name":"href","value":"mailto:a@example.com"}],"name":"a","selfClosing":false,"type":"startTag"}"#
        )
    }

    @Test("DOCTYPE token has a stable keyed representation")
    func stableDoctypeFixture() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let token = HTMLToken.doctype(
            HTMLDOCTYPE(
                name: "html",
                publicIdentifier: nil,
                systemIdentifier: nil,
                forceQuirks: false
            )
        )

        let data = try encoder.encode(token)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(
            json
                == #"{"doctype":{"forceQuirks":false,"name":"html"},"type":"doctype"}"#
        )
    }

    @Test("Public values are hashable and sendable")
    func valueSemantics() {
        let values: Set<HTMLToken> = [
            .character("same"),
            .character("same"),
            .eof,
        ]
        #expect(values.count == 2)

        requireSendable(HTMLAttribute(name: "name", value: "value"))
        requireSendable(
            HTMLDOCTYPE(name: "html", forceQuirks: false)
        )
        requireSendable(HTMLToken.character("text"))
        requireSendable(HTMLTokenizerState.data)
        requireSendable(
            HTMLParseError(code: .unexpectedNullCharacter, scalarOffset: 0)
        )
        requireSendable(HTMLTokenizer(""))
    }

    @Test("Tokenizer state and parse error have stable representations")
    func stableDiagnosticFixtures() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        let stateData = try encoder.encode(HTMLTokenizerState.scriptData)
        let stateJSON = try #require(String(data: stateData, encoding: .utf8))
        #expect(stateJSON == #""scriptData""#)

        let error = HTMLParseError(
            code: .missingSemicolonAfterCharacterReference,
            scalarOffset: 7
        )
        let errorData = try encoder.encode(error)
        let errorJSON = try #require(String(data: errorData, encoding: .utf8))
        #expect(
            errorJSON
                == #"{"code":"missing-semicolon-after-character-reference","scalarOffset":7}"#
        )

        #expect(
            try JSONDecoder().decode(HTMLTokenizerState.self, from: stateData)
                == .scriptData
        )
        #expect(
            try JSONDecoder().decode(HTMLParseError.self, from: errorData)
                == error
        )
    }

    private func requireSendable<T: Sendable>(_: T) {}
}
