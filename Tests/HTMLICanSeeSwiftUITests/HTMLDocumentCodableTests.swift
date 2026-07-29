import Foundation
import HTMLICanSeeSwiftUI
import Testing

struct HTMLDocumentCodableTests {
    @Test("Semantic document round-trips through its stable representation")
    func roundTrip() throws {
        let original = try fixtureDocument()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HTMLDocument.self, from: data)

        #expect(decoded == original)
    }

    @Test("Version 1 semantic JSON remains decodable and encodes identically")
    func stableRepresentation() throws {
        let fixtureURL = try #require(
            Bundle.module.url(
                forResource: "semantic-document-v1",
                withExtension: "json"
            )
        )
        let fixtureData = try Data(contentsOf: fixtureURL)
        let document = try JSONDecoder().decode(HTMLDocument.self, from: fixtureData)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

        let encoded = try encoder.encode(document)
        let fixtureObject = try JSONSerialization.jsonObject(with: fixtureData)
        let encodedObject = try JSONSerialization.jsonObject(with: encoded)

        #expect(encodedObject as? NSDictionary == fixtureObject as? NSDictionary)
    }

    @Test("Semantic values are hashable")
    func hashability() throws {
        let document = try fixtureDocument()
        let values: Set<HTMLDocument> = [document, document]

        #expect(values.count == 1)
    }

    @Test(
        "Malformed persisted link destinations decode without link behavior",
        arguments: [
            "https://example.com/%ZZ",
            "https://example.com/\u{001F}",
            "https://example.com/\u{0085}",
        ]
    )
    func malformedPersistedLink(rawValue: String) throws {
        let data = try JSONSerialization.data(
            withJSONObject: [
                "bold": false,
                "italic": false,
                "strikethrough": false,
                "link": rawValue,
            ]
        )
        let style = try JSONDecoder().decode(HTMLTextStyle.self, from: data)

        #expect(style.link == nil)
    }

    @Test("Public semantic values are sendable")
    func sendability() {
        requireSendable(HTMLDocument.self)
        requireSendable(HTMLBlock.self)
        requireSendable(HTMLList.self)
        requireSendable(HTMLListStyle.self)
        requireSendable(HTMLListItem.self)
        requireSendable(HTMLListItemPart.self)
        requireSendable(HTMLInline.self)
        requireSendable(HTMLTextStyle.self)
    }

    private func fixtureDocument() throws -> HTMLDocument {
        let link = try #require(URL(string: "https://example.com/path"))

        return HTMLDocument(
            blocks: [
                .paragraph([
                    .text(
                        "Hello",
                        style: HTMLTextStyle(isBold: true, link: link)
                    ),
                    .lineBreak,
                    .text(
                        "world",
                        style: HTMLTextStyle(
                            isItalic: true,
                            isStruckThrough: true
                        )
                    ),
                ]),
                .list(
                    HTMLList(
                        style: .ordered,
                        items: [
                            HTMLListItem(
                                content: [
                                    .text("One", style: .plain),
                                ]
                            ),
                        ]
                    )
                ),
            ]
        )
    }
}

private func requireSendable<T: Sendable>(_ type: T.Type) {}
