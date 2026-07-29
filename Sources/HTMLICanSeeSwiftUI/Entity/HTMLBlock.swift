/// A block-level unit in an ``HTMLDocument``.
///
/// Paragraphs encode as `{"type":"paragraph","content":[...]}` and lists
/// encode as `{"type":"list","list":{...}}`.
public enum HTMLBlock: Hashable, Sendable {
    case paragraph([HTMLInline])
    case list(HTMLList)
}

extension HTMLBlock: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case content
        case list
    }

    private enum Kind: String, Codable {
        case paragraph
        case list
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        switch try container.decode(Kind.self, forKey: .type) {
        case .paragraph:
            self = .paragraph(
                try container.decode([HTMLInline].self, forKey: .content)
            )
        case .list:
            self = .list(
                try container.decode(HTMLList.self, forKey: .list)
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case let .paragraph(content):
            try container.encode(Kind.paragraph, forKey: .type)
            try container.encode(content, forKey: .content)
        case let .list(list):
            try container.encode(Kind.list, forKey: .type)
            try container.encode(list, forKey: .list)
        }
    }
}

/// A semantic ordered or unordered list.
///
/// The encoded representation uses the explicit `style` and `items` keys.
public struct HTMLList: Codable, Hashable, Sendable {
    public let style: HTMLListStyle
    public let items: [HTMLListItem]

    public init(style: HTMLListStyle, items: [HTMLListItem]) {
        self.style = style
        self.items = items
    }

    private enum CodingKeys: String, CodingKey {
        case style
        case items
    }
}

/// The marker semantics of an ``HTMLList``.
///
/// Values encode as the strings `"unordered"` and `"ordered"`.
public enum HTMLListStyle: String, Hashable, Sendable {
    case unordered
    case ordered
}

extension HTMLListStyle: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)

        guard let value = Self(rawValue: rawValue) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown HTML list style '\(rawValue)'."
            )
        }

        self = value
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// An ordered semantic part of an ``HTMLListItem``.
///
/// Inline runs and child lists share one sequence so content appearing after
/// a nested list is not reordered during persistence or rendering.
public enum HTMLListItemPart: Hashable, Sendable {
    case inlines([HTMLInline])
    case list(HTMLList)
}

extension HTMLListItemPart: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case content
        case list
    }

    private enum Kind: String, Codable {
        case inlines
        case list
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        switch try container.decode(Kind.self, forKey: .type) {
        case .inlines:
            self = .inlines(
                try container.decode([HTMLInline].self, forKey: .content)
            )
        case .list:
            self = .list(
                try container.decode(HTMLList.self, forKey: .list)
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case let .inlines(content):
            try container.encode(Kind.inlines, forKey: .type)
            try container.encode(content, forKey: .content)
        case let .list(list):
            try container.encode(Kind.list, forKey: .type)
            try container.encode(list, forKey: .list)
        }
    }
}

/// The ordered inline and nested-list content belonging to one list item.
public struct HTMLListItem: Codable, Hashable, Sendable {
    public let parts: [HTMLListItemPart]

    public init(parts: [HTMLListItemPart]) {
        self.parts = parts
    }

    /// Creates an item whose inline content precedes all nested lists.
    ///
    /// Use ``init(parts:)`` when inline content follows a nested list.
    public init(
        content: [HTMLInline] = [],
        nestedLists: [HTMLList] = []
    ) {
        var parts: [HTMLListItemPart] = []
        if !content.isEmpty {
            parts.append(.inlines(content))
        }
        parts.append(contentsOf: nestedLists.map(HTMLListItemPart.list))
        self.parts = parts
    }

    /// All inline parts, flattened in their relative inline order.
    ///
    /// Use ``parts`` when their position relative to nested lists matters.
    public var content: [HTMLInline] {
        parts.reduce(into: []) { result, part in
            if case let .inlines(content) = part {
                result.append(contentsOf: content)
            }
        }
    }

    /// All nested lists in their relative list order.
    ///
    /// Use ``parts`` when their position relative to inline content matters.
    public var nestedLists: [HTMLList] {
        parts.compactMap {
            guard case let .list(list) = $0 else {
                return nil
            }
            return list
        }
    }

    private enum CodingKeys: String, CodingKey {
        case parts
    }
}
