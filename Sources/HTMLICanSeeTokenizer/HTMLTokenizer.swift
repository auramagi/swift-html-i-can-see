/// A streaming tokenizer that follows the state machine in the WHATWG HTML
/// parsing specification.
///
/// Tokenization begins in the data state by default. A tree constructor is
/// normally responsible for selecting RCDATA, RAWTEXT, script data, or
/// PLAINTEXT after certain start tags. Call ``switchTo(_:)`` between
/// ``nextToken()`` calls when implementing that policy.
public struct HTMLTokenizer: Sendable {
    public private(set) var errors: [HTMLParseError]

    private let input: [Unicode.Scalar]
    private var validatedInput: [Bool]
    private var index: Int
    private var machineState: State
    private var returnState: State
    private var lastStartTagName: String?
    private var currentTag: TagBuilder?
    private var currentAttribute: AttributeBuilder?
    private var currentAttributeIsDuplicate: Bool
    private var currentComment: String
    private var currentDoctype: DoctypeBuilder?
    private var temporaryBuffer: String
    private var characterBuffer: String
    private var pendingTokens: [HTMLToken]
    private var emittedEOF: Bool

    public init(
        _ input: String,
        initialState: HTMLTokenizerState = .data,
        lastStartTagName: String? = nil
    ) {
        let preprocessed = Self.preprocess(input)
        self.input = preprocessed
        validatedInput = Array(repeating: false, count: preprocessed.count)
        index = 0
        machineState = State(initialState)
        returnState = .data
        self.lastStartTagName = lastStartTagName.map(Self.asciiLowercased)
        currentTag = nil
        currentAttribute = nil
        currentAttributeIsDuplicate = false
        currentComment = ""
        currentDoctype = nil
        temporaryBuffer = ""
        characterBuffer = ""
        pendingTokens = []
        emittedEOF = false
        errors = []
    }

    /// Selects a caller-controlled tokenizer state.
    ///
    /// Call this only immediately after receiving a token, before requesting
    /// the next one. This mirrors the point where WHATWG tree construction can
    /// change the tokenizer's state.
    public mutating func switchTo(_ state: HTMLTokenizerState) {
        machineState = State(state)
    }

    /// Returns the next token in the stream.
    ///
    /// Once EOF has been returned, later calls return EOF again.
    public mutating func nextToken() -> HTMLToken {
        if emittedEOF, pendingTokens.isEmpty, characterBuffer.isEmpty {
            return .eof
        }

        while pendingTokens.isEmpty {
            processNextInputCharacter()
        }

        return pendingTokens.removeFirst()
    }

    /// Collects the remaining token stream, including EOF.
    ///
    /// This operation is implemented entirely in terms of ``nextToken()``.
    public mutating func collect() -> [HTMLToken] {
        var tokens: [HTMLToken] = []
        while true {
            let token = nextToken()
            tokens.append(token)
            if token == .eof {
                return tokens
            }
        }
    }

    /// Tokenizes an input string and returns the complete stream, including EOF.
    public static func tokenize(
        _ input: String,
        initialState: HTMLTokenizerState = .data,
        lastStartTagName: String? = nil
    ) -> [HTMLToken] {
        var tokenizer = HTMLTokenizer(
            input,
            initialState: initialState,
            lastStartTagName: lastStartTagName
        )
        return tokenizer.collect()
    }
}

private extension HTMLTokenizer {
    enum State: Sendable {
        case data
        case rcdata
        case rawtext
        case scriptData
        case plaintext
        case tagOpen
        case endTagOpen
        case tagName
        case rcdataLessThanSign
        case rcdataEndTagOpen
        case rcdataEndTagName
        case rawtextLessThanSign
        case rawtextEndTagOpen
        case rawtextEndTagName
        case scriptDataLessThanSign
        case scriptDataEndTagOpen
        case scriptDataEndTagName
        case scriptDataEscapeStart
        case scriptDataEscapeStartDash
        case scriptDataEscaped
        case scriptDataEscapedDash
        case scriptDataEscapedDashDash
        case scriptDataEscapedLessThanSign
        case scriptDataEscapedEndTagOpen
        case scriptDataEscapedEndTagName
        case scriptDataDoubleEscapeStart
        case scriptDataDoubleEscaped
        case scriptDataDoubleEscapedDash
        case scriptDataDoubleEscapedDashDash
        case scriptDataDoubleEscapedLessThanSign
        case scriptDataDoubleEscapeEnd
        case beforeAttributeName
        case attributeName
        case afterAttributeName
        case beforeAttributeValue
        case attributeValueDoubleQuoted
        case attributeValueSingleQuoted
        case attributeValueUnquoted
        case afterAttributeValueQuoted
        case selfClosingStartTag
        case bogusComment
        case markupDeclarationOpen
        case commentStart
        case commentStartDash
        case comment
        case commentLessThanSign
        case commentLessThanSignBang
        case commentLessThanSignBangDash
        case commentLessThanSignBangDashDash
        case commentEndDash
        case commentEnd
        case commentEndBang
        case doctype
        case beforeDoctypeName
        case doctypeName
        case afterDoctypeName
        case afterDoctypePublicKeyword
        case beforeDoctypePublicIdentifier
        case doctypePublicIdentifierDoubleQuoted
        case doctypePublicIdentifierSingleQuoted
        case afterDoctypePublicIdentifier
        case betweenDoctypePublicAndSystemIdentifiers
        case afterDoctypeSystemKeyword
        case beforeDoctypeSystemIdentifier
        case doctypeSystemIdentifierDoubleQuoted
        case doctypeSystemIdentifierSingleQuoted
        case afterDoctypeSystemIdentifier
        case bogusDoctype
        case cdataSection
        case cdataSectionBracket
        case cdataSectionEnd

        init(_ state: HTMLTokenizerState) {
            switch state {
            case .data: self = .data
            case .rcdata: self = .rcdata
            case .rawtext: self = .rawtext
            case .scriptData: self = .scriptData
            case .plaintext: self = .plaintext
            case .cdataSection: self = .cdataSection
            }
        }
    }

    struct TagBuilder: Sendable {
        var isEndTag: Bool
        var name: String
        var attributes: [HTMLAttribute]
        var attributeNames: Set<String>
        var selfClosing: Bool
    }

    struct AttributeBuilder: Sendable {
        var name: String
        var value: String
    }

    struct DoctypeBuilder: Sendable {
        var name: String?
        var publicIdentifier: String?
        var systemIdentifier: String?
        var forceQuirks: Bool
    }

    static let replacementCharacter = Unicode.Scalar(0xFFFD)!
    static let ampersand = Unicode.Scalar(0x26)!
    static let lessThan = Unicode.Scalar(0x3C)!
    static let greaterThan = Unicode.Scalar(0x3E)!
    static let null = Unicode.Scalar(0)!

    static func preprocess(_ string: String) -> [Unicode.Scalar] {
        let source = Array(string.unicodeScalars)
        var output: [Unicode.Scalar] = []
        output.reserveCapacity(source.count)
        var sourceIndex = 0

        while sourceIndex < source.count {
            let scalar = source[sourceIndex]
            if scalar.value == 0x0D {
                output.append(Unicode.Scalar(0x0A)!)
                if sourceIndex + 1 < source.count, source[sourceIndex + 1].value == 0x0A {
                    sourceIndex += 1
                }
            } else {
                output.append(scalar)
            }
            sourceIndex += 1
        }

        return output
    }

    static func asciiLowercased(_ string: String) -> String {
        var result = ""
        result.reserveCapacity(string.utf8.count)
        for scalar in string.unicodeScalars {
            append(asciiLowercased(scalar), to: &result)
        }
        return result
    }

    static func asciiLowercased(_ scalar: Unicode.Scalar) -> Unicode.Scalar {
        if (0x41...0x5A).contains(scalar.value) {
            return Unicode.Scalar(scalar.value + 0x20)!
        }
        return scalar
    }

    static func append(_ scalar: Unicode.Scalar, to string: inout String) {
        string.unicodeScalars.append(scalar)
    }

    static func isASCIIUpperAlpha(_ scalar: Unicode.Scalar) -> Bool {
        (0x41...0x5A).contains(scalar.value)
    }

    static func isASCIILowerAlpha(_ scalar: Unicode.Scalar) -> Bool {
        (0x61...0x7A).contains(scalar.value)
    }

    static func isASCIIAlpha(_ scalar: Unicode.Scalar) -> Bool {
        isASCIIUpperAlpha(scalar) || isASCIILowerAlpha(scalar)
    }

    static func isASCIIDigit(_ scalar: Unicode.Scalar) -> Bool {
        (0x30...0x39).contains(scalar.value)
    }

    static func isASCIIHexDigit(_ scalar: Unicode.Scalar) -> Bool {
        isASCIIDigit(scalar)
            || (0x41...0x46).contains(scalar.value)
            || (0x61...0x66).contains(scalar.value)
    }

    static func isASCIIAlphanumeric(_ scalar: Unicode.Scalar) -> Bool {
        isASCIIAlpha(scalar) || isASCIIDigit(scalar)
    }

    static func isASCIIWhitespace(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x09, 0x0A, 0x0C, 0x20:
            true
        default:
            false
        }
    }

    static func isNoncharacter(_ value: UInt32) -> Bool {
        (0xFDD0...0xFDEF).contains(value)
            || (value <= 0x10FFFF && value & 0xFFFE == 0xFFFE)
    }

    static func isInputStreamControl(_ value: UInt32) -> Bool {
        (0x01...0x08).contains(value)
            || value == 0x0B
            || (0x0E...0x1F).contains(value)
            || (0x7F...0x9F).contains(value)
    }
}

private extension HTMLTokenizer {
    mutating func consume() -> Unicode.Scalar? {
        guard index < input.count else {
            return nil
        }

        let consumedIndex = index
        let scalar = input[index]
        index += 1

        validateInput(at: consumedIndex)

        return scalar
    }

    mutating func validateInput(at inputIndex: Int) {
        guard input.indices.contains(inputIndex), !validatedInput[inputIndex] else {
            return
        }
        validatedInput[inputIndex] = true
        let scalar = input[inputIndex]
        if Self.isNoncharacter(scalar.value) {
            record(.noncharacterInInputStream, at: inputIndex)
        } else if Self.isInputStreamControl(scalar.value) {
            record(.controlCharacterInInputStream, at: inputIndex)
        }
    }

    mutating func reconsume(in state: State) {
        precondition(index > 0)
        index -= 1
        machineState = state
    }

    mutating func record(_ code: HTMLParseError.Code, at offset: Int? = nil) {
        errors.append(
            HTMLParseError(
                code: code,
                scalarOffset: offset ?? max(0, min(index - 1, input.count))
            )
        )
    }

    mutating func emitCharacter(_ scalar: Unicode.Scalar) {
        Self.append(scalar, to: &characterBuffer)
    }

    mutating func emitCharacters(_ string: String) {
        characterBuffer.append(contentsOf: string)
    }

    mutating func emit(_ token: HTMLToken) {
        if !characterBuffer.isEmpty {
            pendingTokens.append(.character(characterBuffer))
            characterBuffer = ""
        }

        if case let .startTag(name, _, _) = token {
            lastStartTagName = name
        }
        if token == .eof {
            emittedEOF = true
        }
        pendingTokens.append(token)
    }

    mutating func emitEOF() {
        emit(.eof)
    }

    mutating func startTag(isEndTag: Bool, initialNameScalar: Unicode.Scalar? = nil) {
        currentTag = TagBuilder(
            isEndTag: isEndTag,
            name: "",
            attributes: [],
            attributeNames: [],
            selfClosing: false
        )
        currentAttribute = nil
        currentAttributeIsDuplicate = false
        if let initialNameScalar {
            Self.append(Self.asciiLowercased(initialNameScalar), to: &currentTag!.name)
        }
    }

    mutating func startAttribute(initialScalar: Unicode.Scalar? = nil) {
        commitCurrentAttribute()
        currentAttribute = AttributeBuilder(name: "", value: "")
        currentAttributeIsDuplicate = false
        if let initialScalar {
            Self.append(Self.asciiLowercased(initialScalar), to: &currentAttribute!.name)
        }
    }

    mutating func finishAttributeName() {
        guard
            let attribute = currentAttribute,
            let tag = currentTag,
            !currentAttributeIsDuplicate
        else {
            return
        }

        if tag.attributeNames.contains(attribute.name) {
            currentAttributeIsDuplicate = true
            record(.duplicateAttribute)
        }
    }

    mutating func commitCurrentAttribute() {
        guard let attribute = currentAttribute else {
            return
        }
        finishAttributeName()
        if !currentAttributeIsDuplicate {
            currentTag?.attributes.append(
                HTMLAttribute(name: attribute.name, value: attribute.value)
            )
            currentTag?.attributeNames.insert(attribute.name)
        }
        currentAttribute = nil
        currentAttributeIsDuplicate = false
    }

    mutating func emitCurrentTag() {
        commitCurrentAttribute()
        guard let tag = currentTag else {
            return
        }

        if tag.isEndTag {
            if !tag.attributes.isEmpty {
                record(.endTagWithAttributes)
            }
            if tag.selfClosing {
                record(.endTagWithTrailingSolidus)
            }
            emit(.endTag(name: tag.name))
        } else {
            emit(
                .startTag(
                    name: tag.name,
                    attributes: tag.attributes,
                    selfClosing: tag.selfClosing
                )
            )
        }
        currentTag = nil
    }

    mutating func startComment() {
        currentComment = ""
    }

    mutating func emitCurrentComment() {
        emit(.comment(currentComment))
        currentComment = ""
    }

    mutating func startDoctype() {
        currentDoctype = DoctypeBuilder(
            name: nil,
            publicIdentifier: nil,
            systemIdentifier: nil,
            forceQuirks: false
        )
    }

    mutating func emitCurrentDoctype() {
        guard let doctype = currentDoctype else {
            return
        }
        emit(
            .doctype(
                HTMLDOCTYPE(
                    name: doctype.name,
                    publicIdentifier: doctype.publicIdentifier,
                    systemIdentifier: doctype.systemIdentifier,
                    forceQuirks: doctype.forceQuirks
                )
            )
        )
        currentDoctype = nil
    }

    func inputMatchesASCII(_ literal: String, caseInsensitive: Bool = false) -> Bool {
        let expected = Array(literal.unicodeScalars)
        guard index + expected.count <= input.count else {
            return false
        }

        for expectedIndex in expected.indices {
            let actualScalar = input[index + expectedIndex]
            let expectedScalar = expected[expectedIndex]
            if caseInsensitive {
                if Self.asciiLowercased(actualScalar) != Self.asciiLowercased(expectedScalar) {
                    return false
                }
            } else if actualScalar != expectedScalar {
                return false
            }
        }
        return true
    }

    mutating func consumeASCII(_ literal: String) {
        index += literal.unicodeScalars.count
    }

    func isAppropriateEndTag() -> Bool {
        guard
            let tag = currentTag,
            tag.isEndTag,
            let lastStartTagName
        else {
            return false
        }
        return tag.name == lastStartTagName
    }

    mutating func processNextInputCharacter() {
        switch machineState {
        case .data:
            processData()
        case .rcdata:
            processRCDATA()
        case .rawtext:
            processRAWTEXT()
        case .scriptData:
            processScriptData()
        case .plaintext:
            processPLAINTEXT()
        case .tagOpen:
            processTagOpen()
        case .endTagOpen:
            processEndTagOpen()
        case .tagName:
            processTagName()
        case .rcdataLessThanSign:
            processTextLessThanSign(baseState: .rcdata, endTagOpenState: .rcdataEndTagOpen)
        case .rcdataEndTagOpen:
            processTextEndTagOpen(baseState: .rcdata, endTagNameState: .rcdataEndTagName)
        case .rcdataEndTagName:
            processTextEndTagName(fallbackState: .rcdata)
        case .rawtextLessThanSign:
            processTextLessThanSign(baseState: .rawtext, endTagOpenState: .rawtextEndTagOpen)
        case .rawtextEndTagOpen:
            processTextEndTagOpen(baseState: .rawtext, endTagNameState: .rawtextEndTagName)
        case .rawtextEndTagName:
            processTextEndTagName(fallbackState: .rawtext)
        case .scriptDataLessThanSign:
            processScriptDataLessThanSign()
        case .scriptDataEndTagOpen:
            processTextEndTagOpen(baseState: .scriptData, endTagNameState: .scriptDataEndTagName)
        case .scriptDataEndTagName:
            processTextEndTagName(fallbackState: .scriptData)
        case .scriptDataEscapeStart:
            processScriptDataEscapeStart()
        case .scriptDataEscapeStartDash:
            processScriptDataEscapeStartDash()
        case .scriptDataEscaped:
            processScriptDataEscaped()
        case .scriptDataEscapedDash:
            processScriptDataEscapedDash()
        case .scriptDataEscapedDashDash:
            processScriptDataEscapedDashDash()
        case .scriptDataEscapedLessThanSign:
            processScriptDataEscapedLessThanSign()
        case .scriptDataEscapedEndTagOpen:
            processTextEndTagOpen(
                baseState: .scriptDataEscaped,
                endTagNameState: .scriptDataEscapedEndTagName
            )
        case .scriptDataEscapedEndTagName:
            processTextEndTagName(fallbackState: .scriptDataEscaped)
        case .scriptDataDoubleEscapeStart:
            processScriptDataDoubleEscapeStart()
        case .scriptDataDoubleEscaped:
            processScriptDataDoubleEscaped()
        case .scriptDataDoubleEscapedDash:
            processScriptDataDoubleEscapedDash()
        case .scriptDataDoubleEscapedDashDash:
            processScriptDataDoubleEscapedDashDash()
        case .scriptDataDoubleEscapedLessThanSign:
            processScriptDataDoubleEscapedLessThanSign()
        case .scriptDataDoubleEscapeEnd:
            processScriptDataDoubleEscapeEnd()
        case .beforeAttributeName:
            processBeforeAttributeName()
        case .attributeName:
            processAttributeName()
        case .afterAttributeName:
            processAfterAttributeName()
        case .beforeAttributeValue:
            processBeforeAttributeValue()
        case .attributeValueDoubleQuoted:
            processQuotedAttributeValue(quote: 0x22)
        case .attributeValueSingleQuoted:
            processQuotedAttributeValue(quote: 0x27)
        case .attributeValueUnquoted:
            processUnquotedAttributeValue()
        case .afterAttributeValueQuoted:
            processAfterAttributeValueQuoted()
        case .selfClosingStartTag:
            processSelfClosingStartTag()
        case .bogusComment:
            processBogusComment()
        case .markupDeclarationOpen:
            processMarkupDeclarationOpen()
        case .commentStart:
            processCommentStart()
        case .commentStartDash:
            processCommentStartDash()
        case .comment:
            processComment()
        case .commentLessThanSign:
            processCommentLessThanSign()
        case .commentLessThanSignBang:
            processCommentLessThanSignBang()
        case .commentLessThanSignBangDash:
            processCommentLessThanSignBangDash()
        case .commentLessThanSignBangDashDash:
            processCommentLessThanSignBangDashDash()
        case .commentEndDash:
            processCommentEndDash()
        case .commentEnd:
            processCommentEnd()
        case .commentEndBang:
            processCommentEndBang()
        case .doctype:
            processDOCTYPE()
        case .beforeDoctypeName:
            processBeforeDoctypeName()
        case .doctypeName:
            processDoctypeName()
        case .afterDoctypeName:
            processAfterDoctypeName()
        case .afterDoctypePublicKeyword:
            processAfterDoctypePublicKeyword()
        case .beforeDoctypePublicIdentifier:
            processBeforeDoctypePublicIdentifier()
        case .doctypePublicIdentifierDoubleQuoted:
            processDoctypePublicIdentifier(quote: 0x22)
        case .doctypePublicIdentifierSingleQuoted:
            processDoctypePublicIdentifier(quote: 0x27)
        case .afterDoctypePublicIdentifier:
            processAfterDoctypePublicIdentifier()
        case .betweenDoctypePublicAndSystemIdentifiers:
            processBetweenDoctypePublicAndSystemIdentifiers()
        case .afterDoctypeSystemKeyword:
            processAfterDoctypeSystemKeyword()
        case .beforeDoctypeSystemIdentifier:
            processBeforeDoctypeSystemIdentifier()
        case .doctypeSystemIdentifierDoubleQuoted:
            processDoctypeSystemIdentifier(quote: 0x22)
        case .doctypeSystemIdentifierSingleQuoted:
            processDoctypeSystemIdentifier(quote: 0x27)
        case .afterDoctypeSystemIdentifier:
            processAfterDoctypeSystemIdentifier()
        case .bogusDoctype:
            processBogusDoctype()
        case .cdataSection:
            processCDATASection()
        case .cdataSectionBracket:
            processCDATASectionBracket()
        case .cdataSectionEnd:
            processCDATASectionEnd()
        }
    }
}

// MARK: - Data and tag states

private extension HTMLTokenizer {
    mutating func processData() {
        guard let scalar = consume() else {
            emitEOF()
            return
        }

        switch scalar.value {
        case 0x26:
            emitCharacters(consumeCharacterReference(inAttribute: false, additionalAllowed: nil))
        case 0x3C:
            machineState = .tagOpen
        case 0:
            record(.unexpectedNullCharacter)
            emitCharacter(scalar)
        default:
            emitCharacter(scalar)
        }
    }

    mutating func processRCDATA() {
        guard let scalar = consume() else {
            emitEOF()
            return
        }

        switch scalar.value {
        case 0x26:
            emitCharacters(consumeCharacterReference(inAttribute: false, additionalAllowed: nil))
        case 0x3C:
            machineState = .rcdataLessThanSign
        case 0:
            record(.unexpectedNullCharacter)
            emitCharacter(Self.replacementCharacter)
        default:
            emitCharacter(scalar)
        }
    }

    mutating func processRAWTEXT() {
        guard let scalar = consume() else {
            emitEOF()
            return
        }

        switch scalar.value {
        case 0x3C:
            machineState = .rawtextLessThanSign
        case 0:
            record(.unexpectedNullCharacter)
            emitCharacter(Self.replacementCharacter)
        default:
            emitCharacter(scalar)
        }
    }

    mutating func processScriptData() {
        guard let scalar = consume() else {
            emitEOF()
            return
        }

        switch scalar.value {
        case 0x3C:
            machineState = .scriptDataLessThanSign
        case 0:
            record(.unexpectedNullCharacter)
            emitCharacter(Self.replacementCharacter)
        default:
            emitCharacter(scalar)
        }
    }

    mutating func processPLAINTEXT() {
        guard let scalar = consume() else {
            emitEOF()
            return
        }

        if scalar.value == 0 {
            record(.unexpectedNullCharacter)
            emitCharacter(Self.replacementCharacter)
        } else {
            emitCharacter(scalar)
        }
    }

    mutating func processTagOpen() {
        guard let scalar = consume() else {
            record(.eofBeforeTagName)
            emitCharacter(Self.lessThan)
            emitEOF()
            return
        }

        switch scalar.value {
        case 0x21:
            machineState = .markupDeclarationOpen
        case 0x2F:
            machineState = .endTagOpen
        case 0x3F:
            record(.unexpectedQuestionMarkInsteadOfTagName)
            startComment()
            reconsume(in: .bogusComment)
        default:
            if Self.isASCIIAlpha(scalar) {
                startTag(isEndTag: false)
                reconsume(in: .tagName)
            } else {
                record(.invalidFirstCharacterOfTagName)
                emitCharacter(Self.lessThan)
                reconsume(in: .data)
            }
        }
    }

    mutating func processEndTagOpen() {
        guard let scalar = consume() else {
            record(.eofBeforeTagName)
            emitCharacters("</")
            emitEOF()
            return
        }

        if Self.isASCIIAlpha(scalar) {
            startTag(isEndTag: true)
            reconsume(in: .tagName)
        } else if scalar.value == 0x3E {
            record(.missingEndTagName)
            machineState = .data
        } else {
            record(.invalidFirstCharacterOfTagName)
            startComment()
            reconsume(in: .bogusComment)
        }
    }

    mutating func processTagName() {
        guard let scalar = consume() else {
            record(.eofInTag)
            emitEOF()
            return
        }

        switch scalar.value {
        case 0x09, 0x0A, 0x0C, 0x20:
            machineState = .beforeAttributeName
        case 0x2F:
            machineState = .selfClosingStartTag
        case 0x3E:
            machineState = .data
            emitCurrentTag()
        case 0:
            record(.unexpectedNullCharacter)
            Self.append(Self.replacementCharacter, to: &currentTag!.name)
        default:
            Self.append(Self.asciiLowercased(scalar), to: &currentTag!.name)
        }
    }

    mutating func processTextLessThanSign(baseState: State, endTagOpenState: State) {
        guard let scalar = consume() else {
            emitCharacter(Self.lessThan)
            emitEOF()
            return
        }

        if scalar.value == 0x2F {
            temporaryBuffer = ""
            machineState = endTagOpenState
        } else {
            emitCharacter(Self.lessThan)
            reconsume(in: baseState)
        }
    }

    mutating func processTextEndTagOpen(baseState: State, endTagNameState: State) {
        guard let scalar = consume() else {
            emitCharacters("</")
            emitEOF()
            return
        }

        if Self.isASCIIAlpha(scalar) {
            startTag(isEndTag: true)
            temporaryBuffer = ""
            reconsume(in: endTagNameState)
        } else {
            emitCharacters("</")
            reconsume(in: baseState)
        }
    }

    mutating func processTextEndTagName(fallbackState: State) {
        guard let scalar = consume() else {
            emitCharacters("</")
            emitCharacters(temporaryBuffer)
            emitEOF()
            return
        }

        if Self.isASCIIAlpha(scalar) {
            Self.append(Self.asciiLowercased(scalar), to: &currentTag!.name)
            Self.append(scalar, to: &temporaryBuffer)
            return
        }

        if isAppropriateEndTag() {
            if Self.isASCIIWhitespace(scalar) {
                machineState = .beforeAttributeName
                return
            }
            if scalar.value == 0x2F {
                machineState = .selfClosingStartTag
                return
            }
            if scalar.value == 0x3E {
                machineState = .data
                emitCurrentTag()
                return
            }
        }

        currentTag = nil
        emitCharacters("</")
        emitCharacters(temporaryBuffer)
        reconsume(in: fallbackState)
    }
}

// MARK: - Attribute states

private extension HTMLTokenizer {
    mutating func processBeforeAttributeName() {
        guard let scalar = consume() else {
            record(.eofInTag)
            emitEOF()
            return
        }

        if Self.isASCIIWhitespace(scalar) {
            return
        }

        switch scalar.value {
        case 0x2F, 0x3E:
            reconsume(in: .afterAttributeName)
        case 0x3D:
            record(.unexpectedEqualsSignBeforeAttributeName)
            startAttribute(initialScalar: scalar)
            machineState = .attributeName
        default:
            startAttribute()
            reconsume(in: .attributeName)
        }
    }

    mutating func processAttributeName() {
        guard let scalar = consume() else {
            finishAttributeName()
            record(.eofInTag)
            emitEOF()
            return
        }

        if Self.isASCIIWhitespace(scalar) || scalar.value == 0x2F || scalar.value == 0x3E {
            finishAttributeName()
            reconsume(in: .afterAttributeName)
            return
        }

        switch scalar.value {
        case 0x3D:
            finishAttributeName()
            machineState = .beforeAttributeValue
        case 0:
            record(.unexpectedNullCharacter)
            Self.append(Self.replacementCharacter, to: &currentAttribute!.name)
        case 0x22, 0x27, 0x3C:
            record(.unexpectedCharacterInAttributeName)
            Self.append(scalar, to: &currentAttribute!.name)
        default:
            Self.append(Self.asciiLowercased(scalar), to: &currentAttribute!.name)
        }
    }

    mutating func processAfterAttributeName() {
        guard let scalar = consume() else {
            commitCurrentAttribute()
            record(.eofInTag)
            emitEOF()
            return
        }

        if Self.isASCIIWhitespace(scalar) {
            return
        }

        switch scalar.value {
        case 0x2F:
            commitCurrentAttribute()
            machineState = .selfClosingStartTag
        case 0x3D:
            machineState = .beforeAttributeValue
        case 0x3E:
            machineState = .data
            emitCurrentTag()
        default:
            startAttribute()
            reconsume(in: .attributeName)
        }
    }

    mutating func processBeforeAttributeValue() {
        guard let scalar = consume() else {
            record(.eofInTag)
            emitEOF()
            return
        }

        if Self.isASCIIWhitespace(scalar) {
            return
        }

        switch scalar.value {
        case 0x22:
            machineState = .attributeValueDoubleQuoted
        case 0x27:
            machineState = .attributeValueSingleQuoted
        case 0x3E:
            record(.missingAttributeValue)
            machineState = .data
            emitCurrentTag()
        default:
            reconsume(in: .attributeValueUnquoted)
        }
    }

    mutating func processQuotedAttributeValue(quote: UInt32) {
        guard let scalar = consume() else {
            record(.eofInTag)
            emitEOF()
            return
        }

        if scalar.value == quote {
            machineState = .afterAttributeValueQuoted
        } else if scalar.value == 0x26 {
            currentAttribute!.value.append(
                contentsOf: consumeCharacterReference(
                    inAttribute: true,
                    additionalAllowed: Unicode.Scalar(quote)!
                )
            )
        } else if scalar.value == 0 {
            record(.unexpectedNullCharacter)
            Self.append(Self.replacementCharacter, to: &currentAttribute!.value)
        } else {
            Self.append(scalar, to: &currentAttribute!.value)
        }
    }

    mutating func processUnquotedAttributeValue() {
        guard let scalar = consume() else {
            commitCurrentAttribute()
            record(.eofInTag)
            emitEOF()
            return
        }

        if Self.isASCIIWhitespace(scalar) {
            commitCurrentAttribute()
            machineState = .beforeAttributeName
            return
        }

        switch scalar.value {
        case 0x26:
            currentAttribute!.value.append(
                contentsOf: consumeCharacterReference(
                    inAttribute: true,
                    additionalAllowed: Self.greaterThan
                )
            )
        case 0x3E:
            machineState = .data
            emitCurrentTag()
        case 0:
            record(.unexpectedNullCharacter)
            Self.append(Self.replacementCharacter, to: &currentAttribute!.value)
        case 0x22, 0x27, 0x3C, 0x3D, 0x60:
            record(.unexpectedCharacterInUnquotedAttributeValue)
            Self.append(scalar, to: &currentAttribute!.value)
        default:
            Self.append(scalar, to: &currentAttribute!.value)
        }
    }

    mutating func processAfterAttributeValueQuoted() {
        guard let scalar = consume() else {
            commitCurrentAttribute()
            record(.eofInTag)
            emitEOF()
            return
        }

        if Self.isASCIIWhitespace(scalar) {
            commitCurrentAttribute()
            machineState = .beforeAttributeName
            return
        }

        switch scalar.value {
        case 0x2F:
            commitCurrentAttribute()
            machineState = .selfClosingStartTag
        case 0x3E:
            machineState = .data
            emitCurrentTag()
        default:
            record(.missingWhitespaceBetweenAttributes)
            commitCurrentAttribute()
            reconsume(in: .beforeAttributeName)
        }
    }

    mutating func processSelfClosingStartTag() {
        guard let scalar = consume() else {
            record(.eofInTag)
            emitEOF()
            return
        }

        if scalar.value == 0x3E {
            currentTag?.selfClosing = true
            machineState = .data
            emitCurrentTag()
        } else {
            record(.unexpectedSolidusInTag)
            reconsume(in: .beforeAttributeName)
        }
    }
}

// MARK: - Character references

private extension HTMLTokenizer {
    static let maximumNamedReferenceLength: Int = {
        HTMLNamedCharacterReferences.values.keys.lazy
            .map { max(0, $0.unicodeScalars.count - 1) }
            .max() ?? 0
    }()

    mutating func consumeCharacterReference(
        inAttribute: Bool,
        additionalAllowed: Unicode.Scalar?
    ) -> String {
        let referenceStart = index - 1
        guard let first = input[safe: index] else {
            return "&"
        }

        if Self.isASCIIWhitespace(first)
            || first == Self.lessThan
            || first == Self.ampersand
            || first == additionalAllowed
        {
            return "&"
        }

        if first.value == 0x23 {
            return consumeNumericCharacterReference(referenceStart: referenceStart)
        }

        var candidate = "&"
        var matchedLength = 0
        var matchedKey: String?
        var matchedValue: String?
        let availableLength = min(Self.maximumNamedReferenceLength, input.count - index)

        if availableLength > 0 {
            for length in 1...availableLength {
                let scalar = input[index + length - 1]
                guard Self.isASCIIAlphanumeric(scalar) || scalar.value == 0x3B else {
                    break
                }
                Self.append(scalar, to: &candidate)
                if let replacement = HTMLNamedCharacterReferences.values[candidate] {
                    matchedLength = length
                    matchedKey = candidate
                    matchedValue = replacement
                }
                if scalar.value == 0x3B {
                    break
                }
            }
        }

        guard let matchedKey, let matchedValue else {
            if Self.isASCIIAlphanumeric(first) {
                var lookahead = index
                while let scalar = input[safe: lookahead], Self.isASCIIAlphanumeric(scalar) {
                    lookahead += 1
                }
                if input[safe: lookahead]?.value == 0x3B {
                    record(.unknownNamedCharacterReference, at: referenceStart)
                }
            }
            return "&"
        }

        let hasSemicolon = matchedKey.unicodeScalars.last?.value == 0x3B
        let following = input[safe: index + matchedLength]
        if inAttribute,
            !hasSemicolon,
            following.map({ Self.isASCIIAlphanumeric($0) || $0.value == 0x3D }) == true
        {
            return "&"
        }

        index += matchedLength
        if !hasSemicolon {
            record(.missingSemicolonAfterCharacterReference, at: referenceStart)
        }
        return matchedValue
    }

    mutating func consumeNumericCharacterReference(referenceStart: Int) -> String {
        let originalIndex = index
        index += 1 // "#"

        var radix: UInt32 = 10
        if let scalar = input[safe: index], scalar.value == 0x78 || scalar.value == 0x58 {
            radix = 16
            index += 1
        }

        let digitsStart = index
        var value: UInt32 = 0
        var overflowed = false
        while let scalar = input[safe: index] {
            let digit: UInt32?
            if (0x30...0x39).contains(scalar.value) {
                digit = scalar.value - 0x30
            } else if radix == 16, (0x41...0x46).contains(scalar.value) {
                digit = scalar.value - 0x41 + 10
            } else if radix == 16, (0x61...0x66).contains(scalar.value) {
                digit = scalar.value - 0x61 + 10
            } else {
                digit = nil
            }

            guard let digit else {
                break
            }

            if value > 0x10FFFF / radix {
                overflowed = true
            } else {
                let multiplied = value * radix
                if multiplied > 0x10FFFF - min(digit, 0x10FFFF) {
                    overflowed = true
                } else {
                    value = multiplied + digit
                }
            }
            index += 1
        }

        guard index > digitsStart else {
            record(.absenceOfDigitsInNumericCharacterReference, at: referenceStart)
            index = originalIndex
            return "&"
        }

        if input[safe: index]?.value == 0x3B {
            index += 1
        } else {
            record(.missingSemicolonAfterCharacterReference, at: referenceStart)
        }

        if overflowed || value > 0x10FFFF {
            record(.characterReferenceOutsideUnicodeRange, at: referenceStart)
            return String(Self.replacementCharacter)
        }
        if value == 0 {
            record(.nullCharacterReference, at: referenceStart)
            return String(Self.replacementCharacter)
        }
        if (0xD800...0xDFFF).contains(value) {
            record(.surrogateCharacterReference, at: referenceStart)
            return String(Self.replacementCharacter)
        }
        if Self.isNoncharacter(value) {
            record(.noncharacterCharacterReference, at: referenceStart)
        }
        if Self.isNumericReferenceControl(value) {
            record(.controlCharacterReference, at: referenceStart)
        }

        let remappedValue = Self.numericReferenceReplacement(for: value) ?? value
        guard let scalar = Unicode.Scalar(remappedValue) else {
            record(.characterReferenceOutsideUnicodeRange, at: referenceStart)
            return String(Self.replacementCharacter)
        }
        return String(scalar)
    }

    static func isNumericReferenceControl(_ value: UInt32) -> Bool {
        (0x01...0x08).contains(value)
            || value == 0x0B
            || (0x0D...0x1F).contains(value)
            || (0x7F...0x9F).contains(value)
    }

    static func numericReferenceReplacement(for value: UInt32) -> UInt32? {
        switch value {
        case 0x80: 0x20AC
        case 0x82: 0x201A
        case 0x83: 0x0192
        case 0x84: 0x201E
        case 0x85: 0x2026
        case 0x86: 0x2020
        case 0x87: 0x2021
        case 0x88: 0x02C6
        case 0x89: 0x2030
        case 0x8A: 0x0160
        case 0x8B: 0x2039
        case 0x8C: 0x0152
        case 0x8E: 0x017D
        case 0x91: 0x2018
        case 0x92: 0x2019
        case 0x93: 0x201C
        case 0x94: 0x201D
        case 0x95: 0x2022
        case 0x96: 0x2013
        case 0x97: 0x2014
        case 0x98: 0x02DC
        case 0x99: 0x2122
        case 0x9A: 0x0161
        case 0x9B: 0x203A
        case 0x9C: 0x0153
        case 0x9E: 0x017E
        case 0x9F: 0x0178
        default: nil
        }
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Markup declarations and comments

private extension HTMLTokenizer {
    mutating func processMarkupDeclarationOpen() {
        if index < input.count {
            // Markup declaration matching looks ahead before consuming the
            // scalar. Surface input-stream validation in preprocessing order.
            validateInput(at: index)
        }
        if inputMatchesASCII("--") {
            consumeASCII("--")
            startComment()
            machineState = .commentStart
        } else if inputMatchesASCII("DOCTYPE", caseInsensitive: true) {
            consumeASCII("DOCTYPE")
            machineState = .doctype
        } else if inputMatchesASCII("[CDATA[") {
            consumeASCII("[CDATA[")
            record(.cdataInHTMLContent)
            currentComment = "[CDATA["
            machineState = .bogusComment
        } else {
            record(.incorrectlyOpenedComment)
            startComment()
            machineState = .bogusComment
        }
    }

    mutating func processBogusComment() {
        guard let scalar = consume() else {
            emitCurrentComment()
            emitEOF()
            return
        }

        switch scalar.value {
        case 0x3E:
            machineState = .data
            emitCurrentComment()
        case 0:
            record(.unexpectedNullCharacter)
            Self.append(Self.replacementCharacter, to: &currentComment)
        default:
            Self.append(scalar, to: &currentComment)
        }
    }

    mutating func processCommentStart() {
        guard let scalar = consume() else {
            record(.eofInComment)
            emitCurrentComment()
            emitEOF()
            return
        }

        switch scalar.value {
        case 0x2D:
            machineState = .commentStartDash
        case 0x3E:
            record(.abruptClosingOfEmptyComment)
            machineState = .data
            emitCurrentComment()
        default:
            reconsume(in: .comment)
        }
    }

    mutating func processCommentStartDash() {
        guard let scalar = consume() else {
            record(.eofInComment)
            emitCurrentComment()
            emitEOF()
            return
        }

        switch scalar.value {
        case 0x2D:
            machineState = .commentEnd
        case 0x3E:
            record(.abruptClosingOfEmptyComment)
            machineState = .data
            emitCurrentComment()
        default:
            currentComment.append("-")
            reconsume(in: .comment)
        }
    }

    mutating func processComment() {
        guard let scalar = consume() else {
            record(.eofInComment)
            emitCurrentComment()
            emitEOF()
            return
        }

        switch scalar.value {
        case 0x3C:
            currentComment.append("<")
            machineState = .commentLessThanSign
        case 0x2D:
            machineState = .commentEndDash
        case 0:
            record(.unexpectedNullCharacter)
            Self.append(Self.replacementCharacter, to: &currentComment)
        default:
            Self.append(scalar, to: &currentComment)
        }
    }

    mutating func processCommentLessThanSign() {
        guard let scalar = consume() else {
            record(.eofInComment)
            emitCurrentComment()
            emitEOF()
            return
        }

        switch scalar.value {
        case 0x21:
            currentComment.append("!")
            machineState = .commentLessThanSignBang
        case 0x3C:
            currentComment.append("<")
        default:
            reconsume(in: .comment)
        }
    }

    mutating func processCommentLessThanSignBang() {
        guard let scalar = consume() else {
            record(.eofInComment)
            emitCurrentComment()
            emitEOF()
            return
        }

        if scalar.value == 0x2D {
            machineState = .commentLessThanSignBangDash
        } else {
            reconsume(in: .comment)
        }
    }

    mutating func processCommentLessThanSignBangDash() {
        guard let scalar = consume() else {
            record(.eofInComment)
            emitCurrentComment()
            emitEOF()
            return
        }

        if scalar.value == 0x2D {
            machineState = .commentLessThanSignBangDashDash
        } else {
            reconsume(in: .commentEndDash)
        }
    }

    mutating func processCommentLessThanSignBangDashDash() {
        guard let scalar = consume() else {
            record(.eofInComment)
            emitCurrentComment()
            emitEOF()
            return
        }

        if scalar.value != 0x3E {
            record(.nestedComment)
        }
        reconsume(in: .commentEnd)
    }

    mutating func processCommentEndDash() {
        guard let scalar = consume() else {
            record(.eofInComment)
            emitCurrentComment()
            emitEOF()
            return
        }

        if scalar.value == 0x2D {
            machineState = .commentEnd
        } else {
            currentComment.append("-")
            reconsume(in: .comment)
        }
    }

    mutating func processCommentEnd() {
        guard let scalar = consume() else {
            record(.eofInComment)
            emitCurrentComment()
            emitEOF()
            return
        }

        switch scalar.value {
        case 0x3E:
            machineState = .data
            emitCurrentComment()
        case 0x21:
            machineState = .commentEndBang
        case 0x2D:
            currentComment.append("-")
        default:
            currentComment.append("--")
            reconsume(in: .comment)
        }
    }

    mutating func processCommentEndBang() {
        guard let scalar = consume() else {
            record(.eofInComment)
            emitCurrentComment()
            emitEOF()
            return
        }

        switch scalar.value {
        case 0x2D:
            currentComment.append("--!")
            machineState = .commentEndDash
        case 0x3E:
            record(.incorrectlyClosedComment)
            machineState = .data
            emitCurrentComment()
        default:
            currentComment.append("--!")
            reconsume(in: .comment)
        }
    }
}

// MARK: - DOCTYPE states

private extension HTMLTokenizer {
    mutating func processDOCTYPE() {
        guard let scalar = consume() else {
            record(.eofInDoctype)
            startDoctype()
            currentDoctype?.forceQuirks = true
            emitCurrentDoctype()
            emitEOF()
            return
        }

        if Self.isASCIIWhitespace(scalar) {
            machineState = .beforeDoctypeName
        } else if scalar.value == 0x3E {
            record(.missingDoctypeName)
            startDoctype()
            currentDoctype?.forceQuirks = true
            machineState = .data
            emitCurrentDoctype()
        } else {
            record(.missingWhitespaceBeforeDoctypeName)
            reconsume(in: .beforeDoctypeName)
        }
    }

    mutating func processBeforeDoctypeName() {
        guard let scalar = consume() else {
            record(.eofInDoctype)
            startDoctype()
            currentDoctype?.forceQuirks = true
            emitCurrentDoctype()
            emitEOF()
            return
        }

        if Self.isASCIIWhitespace(scalar) {
            return
        }

        startDoctype()
        switch scalar.value {
        case 0x3E:
            record(.missingDoctypeName)
            currentDoctype?.forceQuirks = true
            machineState = .data
            emitCurrentDoctype()
        case 0:
            record(.unexpectedNullCharacter)
            currentDoctype?.name = String(Self.replacementCharacter)
            machineState = .doctypeName
        default:
            currentDoctype?.name = String(Self.asciiLowercased(scalar))
            machineState = .doctypeName
        }
    }

    mutating func processDoctypeName() {
        guard let scalar = consume() else {
            record(.eofInDoctype)
            currentDoctype?.forceQuirks = true
            emitCurrentDoctype()
            emitEOF()
            return
        }

        if Self.isASCIIWhitespace(scalar) {
            machineState = .afterDoctypeName
            return
        }

        switch scalar.value {
        case 0x3E:
            machineState = .data
            emitCurrentDoctype()
        case 0:
            record(.unexpectedNullCharacter)
            Self.append(Self.replacementCharacter, to: &currentDoctype!.name!)
        default:
            Self.append(Self.asciiLowercased(scalar), to: &currentDoctype!.name!)
        }
    }

    mutating func processAfterDoctypeName() {
        guard let scalar = consume() else {
            record(.eofInDoctype)
            currentDoctype?.forceQuirks = true
            emitCurrentDoctype()
            emitEOF()
            return
        }

        if Self.isASCIIWhitespace(scalar) {
            return
        }
        if scalar.value == 0x3E {
            machineState = .data
            emitCurrentDoctype()
            return
        }

        index -= 1
        if inputMatchesASCII("PUBLIC", caseInsensitive: true) {
            consumeASCII("PUBLIC")
            machineState = .afterDoctypePublicKeyword
        } else if inputMatchesASCII("SYSTEM", caseInsensitive: true) {
            consumeASCII("SYSTEM")
            machineState = .afterDoctypeSystemKeyword
        } else {
            record(.invalidCharacterSequenceAfterDoctypeName)
            currentDoctype?.forceQuirks = true
            machineState = .bogusDoctype
        }
    }

    mutating func processAfterDoctypePublicKeyword() {
        guard let scalar = consume() else {
            record(.eofInDoctype)
            currentDoctype?.forceQuirks = true
            emitCurrentDoctype()
            emitEOF()
            return
        }

        if Self.isASCIIWhitespace(scalar) {
            machineState = .beforeDoctypePublicIdentifier
            return
        }

        switch scalar.value {
        case 0x22:
            record(.missingWhitespaceAfterDoctypePublicKeyword)
            currentDoctype?.publicIdentifier = ""
            machineState = .doctypePublicIdentifierDoubleQuoted
        case 0x27:
            record(.missingWhitespaceAfterDoctypePublicKeyword)
            currentDoctype?.publicIdentifier = ""
            machineState = .doctypePublicIdentifierSingleQuoted
        case 0x3E:
            record(.missingDoctypePublicIdentifier)
            currentDoctype?.forceQuirks = true
            machineState = .data
            emitCurrentDoctype()
        default:
            record(.missingQuoteBeforeDoctypePublicIdentifier)
            currentDoctype?.forceQuirks = true
            reconsume(in: .bogusDoctype)
        }
    }

    mutating func processBeforeDoctypePublicIdentifier() {
        guard let scalar = consume() else {
            record(.eofInDoctype)
            currentDoctype?.forceQuirks = true
            emitCurrentDoctype()
            emitEOF()
            return
        }

        if Self.isASCIIWhitespace(scalar) {
            return
        }

        switch scalar.value {
        case 0x22:
            currentDoctype?.publicIdentifier = ""
            machineState = .doctypePublicIdentifierDoubleQuoted
        case 0x27:
            currentDoctype?.publicIdentifier = ""
            machineState = .doctypePublicIdentifierSingleQuoted
        case 0x3E:
            record(.missingDoctypePublicIdentifier)
            currentDoctype?.forceQuirks = true
            machineState = .data
            emitCurrentDoctype()
        default:
            record(.missingQuoteBeforeDoctypePublicIdentifier)
            currentDoctype?.forceQuirks = true
            reconsume(in: .bogusDoctype)
        }
    }

    mutating func processDoctypePublicIdentifier(quote: UInt32) {
        guard let scalar = consume() else {
            record(.eofInDoctype)
            currentDoctype?.forceQuirks = true
            emitCurrentDoctype()
            emitEOF()
            return
        }

        if scalar.value == quote {
            machineState = .afterDoctypePublicIdentifier
        } else if scalar.value == 0 {
            record(.unexpectedNullCharacter)
            Self.append(Self.replacementCharacter, to: &currentDoctype!.publicIdentifier!)
        } else if scalar.value == 0x3E {
            record(.abruptDoctypePublicIdentifier)
            currentDoctype?.forceQuirks = true
            machineState = .data
            emitCurrentDoctype()
        } else {
            Self.append(scalar, to: &currentDoctype!.publicIdentifier!)
        }
    }

    mutating func processAfterDoctypePublicIdentifier() {
        guard let scalar = consume() else {
            record(.eofInDoctype)
            currentDoctype?.forceQuirks = true
            emitCurrentDoctype()
            emitEOF()
            return
        }

        if Self.isASCIIWhitespace(scalar) {
            machineState = .betweenDoctypePublicAndSystemIdentifiers
            return
        }

        switch scalar.value {
        case 0x3E:
            machineState = .data
            emitCurrentDoctype()
        case 0x22:
            record(.missingWhitespaceBetweenDoctypePublicAndSystemIdentifiers)
            currentDoctype?.systemIdentifier = ""
            machineState = .doctypeSystemIdentifierDoubleQuoted
        case 0x27:
            record(.missingWhitespaceBetweenDoctypePublicAndSystemIdentifiers)
            currentDoctype?.systemIdentifier = ""
            machineState = .doctypeSystemIdentifierSingleQuoted
        default:
            record(.missingQuoteBeforeDoctypeSystemIdentifier)
            currentDoctype?.forceQuirks = true
            reconsume(in: .bogusDoctype)
        }
    }

    mutating func processBetweenDoctypePublicAndSystemIdentifiers() {
        guard let scalar = consume() else {
            record(.eofInDoctype)
            currentDoctype?.forceQuirks = true
            emitCurrentDoctype()
            emitEOF()
            return
        }

        if Self.isASCIIWhitespace(scalar) {
            return
        }

        switch scalar.value {
        case 0x3E:
            machineState = .data
            emitCurrentDoctype()
        case 0x22:
            currentDoctype?.systemIdentifier = ""
            machineState = .doctypeSystemIdentifierDoubleQuoted
        case 0x27:
            currentDoctype?.systemIdentifier = ""
            machineState = .doctypeSystemIdentifierSingleQuoted
        default:
            record(.missingQuoteBeforeDoctypeSystemIdentifier)
            currentDoctype?.forceQuirks = true
            reconsume(in: .bogusDoctype)
        }
    }

    mutating func processAfterDoctypeSystemKeyword() {
        guard let scalar = consume() else {
            record(.eofInDoctype)
            currentDoctype?.forceQuirks = true
            emitCurrentDoctype()
            emitEOF()
            return
        }

        if Self.isASCIIWhitespace(scalar) {
            machineState = .beforeDoctypeSystemIdentifier
            return
        }

        switch scalar.value {
        case 0x22:
            record(.missingWhitespaceAfterDoctypeSystemKeyword)
            currentDoctype?.systemIdentifier = ""
            machineState = .doctypeSystemIdentifierDoubleQuoted
        case 0x27:
            record(.missingWhitespaceAfterDoctypeSystemKeyword)
            currentDoctype?.systemIdentifier = ""
            machineState = .doctypeSystemIdentifierSingleQuoted
        case 0x3E:
            record(.missingDoctypeSystemIdentifier)
            currentDoctype?.forceQuirks = true
            machineState = .data
            emitCurrentDoctype()
        default:
            record(.missingQuoteBeforeDoctypeSystemIdentifier)
            currentDoctype?.forceQuirks = true
            reconsume(in: .bogusDoctype)
        }
    }

    mutating func processBeforeDoctypeSystemIdentifier() {
        guard let scalar = consume() else {
            record(.eofInDoctype)
            currentDoctype?.forceQuirks = true
            emitCurrentDoctype()
            emitEOF()
            return
        }

        if Self.isASCIIWhitespace(scalar) {
            return
        }

        switch scalar.value {
        case 0x22:
            currentDoctype?.systemIdentifier = ""
            machineState = .doctypeSystemIdentifierDoubleQuoted
        case 0x27:
            currentDoctype?.systemIdentifier = ""
            machineState = .doctypeSystemIdentifierSingleQuoted
        case 0x3E:
            record(.missingDoctypeSystemIdentifier)
            currentDoctype?.forceQuirks = true
            machineState = .data
            emitCurrentDoctype()
        default:
            record(.missingQuoteBeforeDoctypeSystemIdentifier)
            currentDoctype?.forceQuirks = true
            reconsume(in: .bogusDoctype)
        }
    }

    mutating func processDoctypeSystemIdentifier(quote: UInt32) {
        guard let scalar = consume() else {
            record(.eofInDoctype)
            currentDoctype?.forceQuirks = true
            emitCurrentDoctype()
            emitEOF()
            return
        }

        if scalar.value == quote {
            machineState = .afterDoctypeSystemIdentifier
        } else if scalar.value == 0 {
            record(.unexpectedNullCharacter)
            Self.append(Self.replacementCharacter, to: &currentDoctype!.systemIdentifier!)
        } else if scalar.value == 0x3E {
            record(.abruptDoctypeSystemIdentifier)
            currentDoctype?.forceQuirks = true
            machineState = .data
            emitCurrentDoctype()
        } else {
            Self.append(scalar, to: &currentDoctype!.systemIdentifier!)
        }
    }

    mutating func processAfterDoctypeSystemIdentifier() {
        guard let scalar = consume() else {
            record(.eofInDoctype)
            currentDoctype?.forceQuirks = true
            emitCurrentDoctype()
            emitEOF()
            return
        }

        if Self.isASCIIWhitespace(scalar) {
            return
        }

        if scalar.value == 0x3E {
            machineState = .data
            emitCurrentDoctype()
        } else {
            record(.unexpectedCharacterAfterDoctypeSystemIdentifier)
            reconsume(in: .bogusDoctype)
        }
    }

    mutating func processBogusDoctype() {
        guard let scalar = consume() else {
            emitCurrentDoctype()
            emitEOF()
            return
        }

        if scalar.value == 0x3E {
            machineState = .data
            emitCurrentDoctype()
        } else if scalar.value == 0 {
            record(.unexpectedNullCharacter)
        }
    }
}

// MARK: - Script data states

private extension HTMLTokenizer {
    mutating func processScriptDataLessThanSign() {
        guard let scalar = consume() else {
            emitCharacter(Self.lessThan)
            emitEOF()
            return
        }

        switch scalar.value {
        case 0x2F:
            temporaryBuffer = ""
            machineState = .scriptDataEndTagOpen
        case 0x21:
            emitCharacters("<!")
            machineState = .scriptDataEscapeStart
        default:
            emitCharacter(Self.lessThan)
            reconsume(in: .scriptData)
        }
    }

    mutating func processScriptDataEscapeStart() {
        guard let scalar = consume() else {
            emitEOF()
            return
        }

        if scalar.value == 0x2D {
            emitCharacters("-")
            machineState = .scriptDataEscapeStartDash
        } else {
            reconsume(in: .scriptData)
        }
    }

    mutating func processScriptDataEscapeStartDash() {
        guard let scalar = consume() else {
            emitEOF()
            return
        }

        if scalar.value == 0x2D {
            emitCharacters("-")
            machineState = .scriptDataEscapedDashDash
        } else {
            reconsume(in: .scriptData)
        }
    }

    mutating func processScriptDataEscaped() {
        guard let scalar = consume() else {
            record(.eofInScriptHTMLCommentLikeText)
            emitEOF()
            return
        }

        switch scalar.value {
        case 0x2D:
            emitCharacter(scalar)
            machineState = .scriptDataEscapedDash
        case 0x3C:
            machineState = .scriptDataEscapedLessThanSign
        case 0:
            record(.unexpectedNullCharacter)
            emitCharacter(Self.replacementCharacter)
        default:
            emitCharacter(scalar)
        }
    }

    mutating func processScriptDataEscapedDash() {
        guard let scalar = consume() else {
            record(.eofInScriptHTMLCommentLikeText)
            emitEOF()
            return
        }

        switch scalar.value {
        case 0x2D:
            emitCharacter(scalar)
            machineState = .scriptDataEscapedDashDash
        case 0x3C:
            machineState = .scriptDataEscapedLessThanSign
        case 0:
            record(.unexpectedNullCharacter)
            emitCharacter(Self.replacementCharacter)
            machineState = .scriptDataEscaped
        default:
            emitCharacter(scalar)
            machineState = .scriptDataEscaped
        }
    }

    mutating func processScriptDataEscapedDashDash() {
        guard let scalar = consume() else {
            record(.eofInScriptHTMLCommentLikeText)
            emitEOF()
            return
        }

        switch scalar.value {
        case 0x2D:
            emitCharacter(scalar)
        case 0x3C:
            machineState = .scriptDataEscapedLessThanSign
        case 0x3E:
            emitCharacter(scalar)
            machineState = .scriptData
        case 0:
            record(.unexpectedNullCharacter)
            emitCharacter(Self.replacementCharacter)
            machineState = .scriptDataEscaped
        default:
            emitCharacter(scalar)
            machineState = .scriptDataEscaped
        }
    }

    mutating func processScriptDataEscapedLessThanSign() {
        guard let scalar = consume() else {
            emitCharacter(Self.lessThan)
            record(.eofInScriptHTMLCommentLikeText)
            emitEOF()
            return
        }

        if scalar.value == 0x2F {
            temporaryBuffer = ""
            machineState = .scriptDataEscapedEndTagOpen
        } else if Self.isASCIIAlpha(scalar) {
            temporaryBuffer = ""
            emitCharacter(Self.lessThan)
            reconsume(in: .scriptDataDoubleEscapeStart)
        } else {
            emitCharacter(Self.lessThan)
            reconsume(in: .scriptDataEscaped)
        }
    }

    mutating func processScriptDataDoubleEscapeStart() {
        guard let scalar = consume() else {
            record(.eofInScriptHTMLCommentLikeText)
            emitEOF()
            return
        }

        if Self.isASCIIAlpha(scalar) {
            Self.append(Self.asciiLowercased(scalar), to: &temporaryBuffer)
            emitCharacter(scalar)
        } else if Self.isASCIIWhitespace(scalar) || scalar.value == 0x2F || scalar.value == 0x3E {
            emitCharacter(scalar)
            machineState = temporaryBuffer == "script"
                ? .scriptDataDoubleEscaped
                : .scriptDataEscaped
        } else {
            reconsume(in: .scriptDataEscaped)
        }
    }

    mutating func processScriptDataDoubleEscaped() {
        guard let scalar = consume() else {
            record(.eofInScriptHTMLCommentLikeText)
            emitEOF()
            return
        }

        switch scalar.value {
        case 0x2D:
            emitCharacter(scalar)
            machineState = .scriptDataDoubleEscapedDash
        case 0x3C:
            emitCharacter(scalar)
            machineState = .scriptDataDoubleEscapedLessThanSign
        case 0:
            record(.unexpectedNullCharacter)
            emitCharacter(Self.replacementCharacter)
        default:
            emitCharacter(scalar)
        }
    }

    mutating func processScriptDataDoubleEscapedDash() {
        guard let scalar = consume() else {
            record(.eofInScriptHTMLCommentLikeText)
            emitEOF()
            return
        }

        switch scalar.value {
        case 0x2D:
            emitCharacter(scalar)
            machineState = .scriptDataDoubleEscapedDashDash
        case 0x3C:
            emitCharacter(scalar)
            machineState = .scriptDataDoubleEscapedLessThanSign
        case 0:
            record(.unexpectedNullCharacter)
            emitCharacter(Self.replacementCharacter)
            machineState = .scriptDataDoubleEscaped
        default:
            emitCharacter(scalar)
            machineState = .scriptDataDoubleEscaped
        }
    }

    mutating func processScriptDataDoubleEscapedDashDash() {
        guard let scalar = consume() else {
            record(.eofInScriptHTMLCommentLikeText)
            emitEOF()
            return
        }

        switch scalar.value {
        case 0x2D:
            emitCharacter(scalar)
        case 0x3C:
            emitCharacter(scalar)
            machineState = .scriptDataDoubleEscapedLessThanSign
        case 0x3E:
            emitCharacter(scalar)
            machineState = .scriptData
        case 0:
            record(.unexpectedNullCharacter)
            emitCharacter(Self.replacementCharacter)
            machineState = .scriptDataDoubleEscaped
        default:
            emitCharacter(scalar)
            machineState = .scriptDataDoubleEscaped
        }
    }

    mutating func processScriptDataDoubleEscapedLessThanSign() {
        guard let scalar = consume() else {
            record(.eofInScriptHTMLCommentLikeText)
            emitEOF()
            return
        }

        if scalar.value == 0x2F {
            emitCharacter(scalar)
            temporaryBuffer = ""
            machineState = .scriptDataDoubleEscapeEnd
        } else {
            reconsume(in: .scriptDataDoubleEscaped)
        }
    }

    mutating func processScriptDataDoubleEscapeEnd() {
        guard let scalar = consume() else {
            record(.eofInScriptHTMLCommentLikeText)
            emitEOF()
            return
        }

        if Self.isASCIIAlpha(scalar) {
            Self.append(Self.asciiLowercased(scalar), to: &temporaryBuffer)
            emitCharacter(scalar)
        } else if Self.isASCIIWhitespace(scalar) || scalar.value == 0x2F || scalar.value == 0x3E {
            emitCharacter(scalar)
            machineState = temporaryBuffer == "script"
                ? .scriptDataEscaped
                : .scriptDataDoubleEscaped
        } else {
            reconsume(in: .scriptDataDoubleEscaped)
        }
    }
}

// MARK: - CDATA states

private extension HTMLTokenizer {
    mutating func processCDATASection() {
        guard let scalar = consume() else {
            record(.eofInCdata)
            emitEOF()
            return
        }

        if scalar.value == 0x5D {
            machineState = .cdataSectionBracket
        } else {
            emitCharacter(scalar)
        }
    }

    mutating func processCDATASectionBracket() {
        guard let scalar = consume() else {
            emitCharacters("]")
            record(.eofInCdata)
            emitEOF()
            return
        }

        if scalar.value == 0x5D {
            machineState = .cdataSectionEnd
        } else {
            emitCharacters("]")
            reconsume(in: .cdataSection)
        }
    }

    mutating func processCDATASectionEnd() {
        guard let scalar = consume() else {
            emitCharacters("]]")
            record(.eofInCdata)
            emitEOF()
            return
        }

        switch scalar.value {
        case 0x5D:
            emitCharacters("]")
        case 0x3E:
            machineState = .data
        default:
            emitCharacters("]]")
            reconsume(in: .cdataSection)
        }
    }
}
