import Foundation

/// Semantic styling for an ``HTMLInline/text(_:style:)`` run.
///
/// This type deliberately stores no fonts or colors. Its encoded keys are
/// `bold`, `italic`, `strikethrough`, and the optional absolute `link` string.
/// Unsupported link destinations are discarded during initialization and
/// decoding.
public struct HTMLTextStyle: Hashable, Sendable {
    public let isBold: Bool
    public let isItalic: Bool
    public let isStruckThrough: Bool
    public let link: URL?

    public init(
        isBold: Bool = false,
        isItalic: Bool = false,
        isStruckThrough: Bool = false,
        link: URL? = nil
    ) {
        self.init(
            isBold: isBold,
            isItalic: isItalic,
            isStruckThrough: isStruckThrough,
            validatedLink: link.flatMap(HTMLLinkDestination.acceptedURL)
        )
    }

    init(
        isBold: Bool,
        isItalic: Bool,
        isStruckThrough: Bool,
        validatedLink: URL?
    ) {
        self.isBold = isBold
        self.isItalic = isItalic
        self.isStruckThrough = isStruckThrough
        link = validatedLink
    }

    public static let plain = HTMLTextStyle()
}

extension HTMLTextStyle: Codable {
    private enum CodingKeys: String, CodingKey {
        case isBold = "bold"
        case isItalic = "italic"
        case isStruckThrough = "strikethrough"
        case link
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let linkString = try container.decodeIfPresent(String.self, forKey: .link)

        self.init(
            isBold: try container.decodeIfPresent(Bool.self, forKey: .isBold) ?? false,
            isItalic: try container.decodeIfPresent(Bool.self, forKey: .isItalic) ?? false,
            isStruckThrough: try container.decodeIfPresent(
                Bool.self,
                forKey: .isStruckThrough
            ) ?? false,
            validatedLink: linkString.flatMap(HTMLLinkDestination.parse)
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isBold, forKey: .isBold)
        try container.encode(isItalic, forKey: .isItalic)
        try container.encode(isStruckThrough, forKey: .isStruckThrough)
        try container.encodeIfPresent(link?.absoluteString, forKey: .link)
    }
}

enum HTMLLinkDestination {
    static func parse(_ rawValue: String) -> URL? {
        let candidate = rawValue.trimmingCharacters(in: htmlASCIIWhitespace)

        guard
            !candidate.isEmpty,
            candidate.unicodeScalars.allSatisfy(isAllowedURLScalar),
            hasValidPercentEscapes(candidate),
            let components = URLComponents(string: candidate),
            let scheme = components.scheme?.lowercased(),
            let url = components.url
        else {
            return nil
        }

        switch scheme {
        case "http", "https":
            guard
                candidate.dropFirst(scheme.count + 1).hasPrefix("//"),
                let host = components.host,
                !host.isEmpty
            else {
                return nil
            }
        case "mailto":
            guard
                components.host == nil,
                !components.path.isEmpty
            else {
                return nil
            }
        default:
            return nil
        }

        return acceptedURL(url)
    }

    static func acceptedURL(_ url: URL) -> URL? {
        guard url.baseURL == nil else {
            return nil
        }

        return parseUnchecked(url.absoluteString)
    }

    private static func parseUnchecked(_ value: String) -> URL? {
        guard
            value.unicodeScalars.allSatisfy(isAllowedURLScalar),
            hasValidPercentEscapes(value),
            let components = URLComponents(string: value),
            let scheme = components.scheme?.lowercased()
        else {
            return nil
        }

        switch scheme {
        case "http", "https":
            guard
                value.dropFirst(scheme.count + 1).hasPrefix("//"),
                let host = components.host,
                !host.isEmpty
            else {
                return nil
            }
        case "mailto":
            guard components.host == nil, !components.path.isEmpty else {
                return nil
            }
        default:
            return nil
        }

        return components.url
    }

    private static let htmlASCIIWhitespace = CharacterSet(
        charactersIn: "\u{0009}\u{000A}\u{000C}\u{000D}\u{0020}"
    )

    private static func isAllowedURLScalar(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x00...0x20, 0x7F...0x9F:
            false
        default:
            true
        }
    }

    private static func hasValidPercentEscapes(_ value: String) -> Bool {
        let scalars = value.unicodeScalars
        var index = scalars.startIndex

        while index != scalars.endIndex {
            guard scalars[index] == "%" else {
                index = scalars.index(after: index)
                continue
            }

            let firstIndex = scalars.index(after: index)
            guard firstIndex != scalars.endIndex else {
                return false
            }
            let secondIndex = scalars.index(after: firstIndex)
            guard
                secondIndex != scalars.endIndex,
                isASCIIHexDigit(scalars[firstIndex]),
                isASCIIHexDigit(scalars[secondIndex])
            else {
                return false
            }

            index = scalars.index(after: secondIndex)
        }

        return true
    }

    private static func isASCIIHexDigit(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x30...0x39, 0x41...0x46, 0x61...0x66:
            true
        default:
            false
        }
    }
}
