/// An attribute on an HTML start tag.
///
/// Attribute order is preserved. The tokenizer lowercases ASCII uppercase
/// letters in attribute names and drops later attributes with duplicate names,
/// as required by the HTML tokenization algorithm.
public struct HTMLAttribute: Codable, Hashable, Sendable {
    public let name: String
    public let value: String

    public init(name: String, value: String) {
        self.name = name
        self.value = value
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case value
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        value = try container.decode(String.self, forKey: .value)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(value, forKey: .value)
    }
}

/// The fields carried by an HTML DOCTYPE token.
public struct HTMLDOCTYPE: Codable, Hashable, Sendable {
    public let name: String?
    public let publicIdentifier: String?
    public let systemIdentifier: String?
    public let forceQuirks: Bool

    public init(
        name: String?,
        publicIdentifier: String? = nil,
        systemIdentifier: String? = nil,
        forceQuirks: Bool = false
    ) {
        self.name = name
        self.publicIdentifier = publicIdentifier
        self.systemIdentifier = systemIdentifier
        self.forceQuirks = forceQuirks
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case publicIdentifier
        case systemIdentifier
        case forceQuirks
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        publicIdentifier = try container.decodeIfPresent(String.self, forKey: .publicIdentifier)
        systemIdentifier = try container.decodeIfPresent(String.self, forKey: .systemIdentifier)
        forceQuirks = try container.decode(Bool.self, forKey: .forceQuirks)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(publicIdentifier, forKey: .publicIdentifier)
        try container.encodeIfPresent(systemIdentifier, forKey: .systemIdentifier)
        try container.encode(forceQuirks, forKey: .forceQuirks)
    }
}

/// A token emitted by ``HTMLTokenizer``.
///
/// The encoded form is a keyed object with a `type` discriminator. Associated
/// fields are stored alongside that discriminator rather than using Swift's
/// synthesized enum representation, keeping the persisted format stable.
public enum HTMLToken: Hashable, Sendable {
    case doctype(HTMLDOCTYPE)
    case startTag(name: String, attributes: [HTMLAttribute], selfClosing: Bool)
    case endTag(name: String)
    case comment(String)
    case character(String)
    case eof
}

extension HTMLToken: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case doctype
        case name
        case attributes
        case selfClosing
        case data
    }

    private enum Kind: String, Codable {
        case doctype
        case startTag
        case endTag
        case comment
        case character
        case eof
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .type)

        switch kind {
        case .doctype:
            self = .doctype(try container.decode(HTMLDOCTYPE.self, forKey: .doctype))
        case .startTag:
            self = .startTag(
                name: try container.decode(String.self, forKey: .name),
                attributes: try container.decode([HTMLAttribute].self, forKey: .attributes),
                selfClosing: try container.decode(Bool.self, forKey: .selfClosing)
            )
        case .endTag:
            self = .endTag(name: try container.decode(String.self, forKey: .name))
        case .comment:
            self = .comment(try container.decode(String.self, forKey: .data))
        case .character:
            self = .character(try container.decode(String.self, forKey: .data))
        case .eof:
            self = .eof
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case let .doctype(doctype):
            try container.encode(Kind.doctype, forKey: .type)
            try container.encode(doctype, forKey: .doctype)
        case let .startTag(name, attributes, selfClosing):
            try container.encode(Kind.startTag, forKey: .type)
            try container.encode(name, forKey: .name)
            try container.encode(attributes, forKey: .attributes)
            try container.encode(selfClosing, forKey: .selfClosing)
        case let .endTag(name):
            try container.encode(Kind.endTag, forKey: .type)
            try container.encode(name, forKey: .name)
        case let .comment(data):
            try container.encode(Kind.comment, forKey: .type)
            try container.encode(data, forKey: .data)
        case let .character(data):
            try container.encode(Kind.character, forKey: .type)
            try container.encode(data, forKey: .data)
        case .eof:
            try container.encode(Kind.eof, forKey: .type)
        }
    }
}
