/// A recoverable error reported while tokenizing HTML.
public struct HTMLParseError: Codable, Hashable, Sendable {
    public let code: Code

    /// The zero-based offset in the preprocessed Unicode-scalar input.
    ///
    /// This is diagnostic metadata only and is not part of token persistence.
    public let scalarOffset: Int

    public init(code: Code, scalarOffset: Int) {
        self.code = code
        self.scalarOffset = scalarOffset
    }

    private enum CodingKeys: String, CodingKey {
        case code
        case scalarOffset
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try container.decode(Code.self, forKey: .code)
        scalarOffset = try container.decode(Int.self, forKey: .scalarOffset)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(code, forKey: .code)
        try container.encode(scalarOffset, forKey: .scalarOffset)
    }
}

extension HTMLParseError {
    /// Parse-error codes used by the WHATWG tokenization algorithm.
    public enum Code: String, Codable, CaseIterable, Hashable, Sendable {
        case abruptClosingOfEmptyComment = "abrupt-closing-of-empty-comment"
        case abruptDoctypePublicIdentifier = "abrupt-doctype-public-identifier"
        case abruptDoctypeSystemIdentifier = "abrupt-doctype-system-identifier"
        case absenceOfDigitsInNumericCharacterReference = "absence-of-digits-in-numeric-character-reference"
        case cdataInHTMLContent = "cdata-in-html-content"
        case characterReferenceOutsideUnicodeRange = "character-reference-outside-unicode-range"
        case controlCharacterInInputStream = "control-character-in-input-stream"
        case controlCharacterReference = "control-character-reference"
        case endTagWithAttributes = "end-tag-with-attributes"
        case duplicateAttribute = "duplicate-attribute"
        case endTagWithTrailingSolidus = "end-tag-with-trailing-solidus"
        case eofBeforeTagName = "eof-before-tag-name"
        case eofInCdata = "eof-in-cdata"
        case eofInComment = "eof-in-comment"
        case eofInDoctype = "eof-in-doctype"
        case eofInElementThatCanContainOnlyText = "eof-in-element-that-can-contain-only-text"
        case eofInScriptHTMLCommentLikeText = "eof-in-script-html-comment-like-text"
        case eofInTag = "eof-in-tag"
        case incorrectlyClosedComment = "incorrectly-closed-comment"
        case incorrectlyOpenedComment = "incorrectly-opened-comment"
        case invalidCharacterSequenceAfterDoctypeName = "invalid-character-sequence-after-doctype-name"
        case invalidFirstCharacterOfTagName = "invalid-first-character-of-tag-name"
        case missingAttributeValue = "missing-attribute-value"
        case missingDoctypeName = "missing-doctype-name"
        case missingDoctypePublicIdentifier = "missing-doctype-public-identifier"
        case missingDoctypeSystemIdentifier = "missing-doctype-system-identifier"
        case missingEndTagName = "missing-end-tag-name"
        case missingQuoteBeforeDoctypePublicIdentifier = "missing-quote-before-doctype-public-identifier"
        case missingQuoteBeforeDoctypeSystemIdentifier = "missing-quote-before-doctype-system-identifier"
        case missingSemicolonAfterCharacterReference = "missing-semicolon-after-character-reference"
        case missingWhitespaceAfterDoctypePublicKeyword = "missing-whitespace-after-doctype-public-keyword"
        case missingWhitespaceAfterDoctypeSystemKeyword = "missing-whitespace-after-doctype-system-keyword"
        case missingWhitespaceBeforeDoctypeName = "missing-whitespace-before-doctype-name"
        case missingWhitespaceBetweenAttributes = "missing-whitespace-between-attributes"
        case missingWhitespaceBetweenDoctypePublicAndSystemIdentifiers = "missing-whitespace-between-doctype-public-and-system-identifiers"
        case nestedComment = "nested-comment"
        case noncharacterCharacterReference = "noncharacter-character-reference"
        case noncharacterInInputStream = "noncharacter-in-input-stream"
        case nonVoidHTMLStartTagWithTrailingSolidus = "non-void-html-element-start-tag-with-trailing-solidus"
        case nullCharacterReference = "null-character-reference"
        case surrogateCharacterReference = "surrogate-character-reference"
        case surrogateInInputStream = "surrogate-in-input-stream"
        case unexpectedCharacterAfterDoctypeSystemIdentifier = "unexpected-character-after-doctype-system-identifier"
        case unexpectedCharacterInAttributeName = "unexpected-character-in-attribute-name"
        case unexpectedCharacterInUnquotedAttributeValue = "unexpected-character-in-unquoted-attribute-value"
        case unexpectedEqualsSignBeforeAttributeName = "unexpected-equals-sign-before-attribute-name"
        case unexpectedNullCharacter = "unexpected-null-character"
        case unexpectedQuestionMarkInsteadOfTagName = "unexpected-question-mark-instead-of-tag-name"
        case unexpectedSolidusInTag = "unexpected-solidus-in-tag"
        case unknownNamedCharacterReference = "unknown-named-character-reference"

        public init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            let rawValue = try container.decode(String.self)
            guard let value = Self(rawValue: rawValue) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Unknown HTML parse-error code: \(rawValue)"
                )
            }
            self = value
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(rawValue)
        }
    }
}
