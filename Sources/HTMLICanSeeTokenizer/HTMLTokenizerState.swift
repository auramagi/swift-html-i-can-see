/// A tokenizer state that may be selected by a tokenizer's caller.
///
/// Tree construction normally chooses RCDATA, RAWTEXT, script data, and
/// PLAINTEXT based on the element being parsed. This package intentionally does
/// not implement tree construction, so advanced callers and conformance tests
/// can select those entry states directly.
public enum HTMLTokenizerState: String, Codable, CaseIterable, Hashable, Sendable {
    case data
    case rcdata
    case rawtext
    case scriptData
    case plaintext
    case cdataSection

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        guard let value = Self(rawValue: rawValue) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown HTML tokenizer state: \(rawValue)"
            )
        }
        self = value
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
