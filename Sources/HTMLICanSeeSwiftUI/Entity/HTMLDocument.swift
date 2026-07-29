/// A durable, presentation-independent document produced from HTML.
///
/// The encoded representation is an object with a single `blocks` array. Its
/// shape is part of the public persistence contract.
public struct HTMLDocument: Codable, Hashable, Sendable {
    public let blocks: [HTMLBlock]

    public init(blocks: [HTMLBlock] = []) {
        self.blocks = blocks
    }

    private enum CodingKeys: String, CodingKey {
        case blocks
    }
}
