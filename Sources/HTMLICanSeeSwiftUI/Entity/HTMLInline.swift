/// Inline semantic content in a paragraph or list item.
///
/// Text encodes as
/// `{"type":"text","text":"...","style":{...}}`. A hard line break
/// encodes as `{"type":"lineBreak"}`.
public enum HTMLInline: Hashable, Sendable {
    case text(String, style: HTMLTextStyle)
    case lineBreak
}

extension HTMLInline: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case style
    }

    private enum Kind: String, Codable {
        case text
        case lineBreak
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        switch try container.decode(Kind.self, forKey: .type) {
        case .text:
            self = .text(
                try container.decode(String.self, forKey: .text),
                style: try container.decode(HTMLTextStyle.self, forKey: .style)
            )
        case .lineBreak:
            self = .lineBreak
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case let .text(text, style):
            try container.encode(Kind.text, forKey: .type)
            try container.encode(text, forKey: .text)
            try container.encode(style, forKey: .style)
        case .lineBreak:
            try container.encode(Kind.lineBreak, forKey: .type)
        }
    }
}
