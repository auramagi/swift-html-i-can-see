import Foundation
import Testing
@testable import HTMLICanSeeTokenizer

@Suite("Pinned html5lib tokenizer fixtures")
struct HTMLTokenizerConformanceTests {
    @Test(
        "Matches imported fixture tokens and error codes",
        arguments: OfficialFixtureFile.allCases
    )
    func fixtureFile(_ file: OfficialFixtureFile) throws {
        let fixtures = try FixtureLoader.load(file)
        var failures: [String] = []
        var unrepresentableDescriptions: [String] = []
        var unsupportedInitialStates: [String] = []

        for fixture in fixtures {
            unsupportedInitialStates.append(
                contentsOf: fixture.unsupportedInitialStateNames.map {
                    "\(fixture.description): \($0)"
                }
            )
            let expandedCases = fixture.expandedCases
            if expandedCases.isEmpty {
                unrepresentableDescriptions.append(fixture.description)
            }
            for testCase in expandedCases {
                var tokenizer = HTMLTokenizer(
                    testCase.input,
                    initialState: testCase.initialState,
                    lastStartTagName: testCase.lastStartTag
                )
                let actualTokens = NormalizedToken.from(tokenizer.collect())
                let actualErrors = tokenizer.errors.map(\.code)

                if actualTokens != testCase.expectedTokens
                    || actualErrors != testCase.expectedErrors
                {
                    failures.append(
                        """
                        \(fixture.description) [\(testCase.initialState.rawValue)]
                          tokens: \(actualTokens)
                          expected: \(testCase.expectedTokens)
                          errors: \(actualErrors.map(\.rawValue))
                          expected errors: \(testCase.expectedErrors.map(\.rawValue))
                        """
                    )
                }
            }
        }

        #expect(
            unsupportedInitialStates.isEmpty,
            Comment(
                rawValue: "Unsupported fixture initial states:\n"
                    + unsupportedInitialStates.joined(separator: "\n")
            )
        )
        #expect(
            unrepresentableDescriptions == file.expectedUnrepresentableDescriptions,
            "Only the four pinned isolated-surrogate inputs may be excluded"
        )
        #expect(
            failures.isEmpty,
            Comment(
                rawValue: failures.prefix(20).joined(separator: "\n")
                    + (failures.count > 20 ? "\n… \(failures.count - 20) more failures" : "")
            )
        )
    }
}

enum OfficialFixtureFile: String, CaseIterable, Sendable, CustomTestStringConvertible {
    case contentModelFlags
    case domjs
    case entities
    case escapeFlag
    case namedEntities
    case numericEntities
    case pendingSpecChanges
    case test1
    case test2
    case test3
    case test4
    case unicodeChars
    case unicodeCharsProblematic

    var testDescription: String { rawValue }

    var expectedUnrepresentableDescriptions: [String] {
        guard self == .unicodeCharsProblematic else {
            return []
        }
        return [
            "Invalid Unicode character U+DFFF",
            "Invalid Unicode character U+D800",
            "Invalid Unicode character U+DFFF with valid preceding character",
            "Invalid Unicode character U+D800 with valid following character",
        ]
    }
}

private enum FixtureLoader {
    static func load(_ file: OfficialFixtureFile) throws -> [Fixture] {
        let url = try #require(
            Bundle.module.url(
                forResource: file.rawValue,
                withExtension: "test",
                subdirectory: "html5lib-tests"
            )
                ?? Bundle.module.url(
                    forResource: file.rawValue,
                    withExtension: "test",
                    subdirectory: "Fixtures/html5lib-tests"
                )
                ?? Bundle.module.url(
                    forResource: file.rawValue,
                    withExtension: "test"
                ),
            "Missing imported fixture \(file.rawValue).test"
        )
        let document = try JSONDecoder().decode(
            FixtureDocument.self,
            from: Data(contentsOf: url)
        )
        return document.tests
    }
}

private struct FixtureDocument: Decodable {
    let tests: [Fixture]
}

private struct Fixture: Decodable {
    let description: String
    let input: String
    let output: [FixtureToken]
    let initialStates: [String]?
    let lastStartTag: String?
    let errors: [FixtureError]?
    let doubleEscaped: Bool?

    var unsupportedInitialStateNames: [String] {
        (initialStates ?? ["Data state"]).filter {
            HTMLTokenizerState(fixtureName: $0) == nil
        }
    }

    var expandedCases: [FixtureCase] {
        let stateNames = initialStates ?? ["Data state"]
        return stateNames.compactMap { stateName in
            guard let state = HTMLTokenizerState(fixtureName: stateName) else {
                return nil
            }

            if doubleEscaped == true {
                guard
                    let decodedInput = input.decodingFixtureEscapes(),
                    let decodedOutput = output.decodingFixtureEscapes()
                else {
                    // Swift String cannot represent isolated UTF-16
                    // surrogates. Those cases are not expressible through the
                    // package's String-based API.
                    return nil
                }
                return FixtureCase(
                    input: decodedInput,
                    initialState: state,
                    lastStartTag: lastStartTag?.decodingFixtureEscapes(),
                    expectedTokens: decodedOutput.map(\.normalized),
                    expectedErrors: errors?.map(\.code) ?? []
                )
            }

            return FixtureCase(
                input: input,
                initialState: state,
                lastStartTag: lastStartTag,
                expectedTokens: output.map(\.normalized),
                expectedErrors: errors?.map(\.code) ?? []
            )
        }
    }
}

private struct FixtureCase {
    let input: String
    let initialState: HTMLTokenizerState
    let lastStartTag: String?
    let expectedTokens: [NormalizedToken]
    let expectedErrors: [HTMLParseError.Code]
}

private struct FixtureError: Decodable {
    let code: HTMLParseError.Code
}

private enum FixtureToken: Decodable {
    case doctype(
        name: String?,
        publicIdentifier: String?,
        systemIdentifier: String?,
        forceQuirks: Bool
    )
    case startTag(name: String, attributes: [String: String], selfClosing: Bool)
    case endTag(name: String)
    case comment(String)
    case character(String)

    init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        let kind = try container.decode(String.self)

        switch kind {
        case "DOCTYPE":
            let name = try container.decodeOptionalString()
            let publicIdentifier = try container.decodeOptionalString()
            let systemIdentifier = try container.decodeOptionalString()
            let isCorrect = try container.decode(Bool.self)
            self = .doctype(
                name: name,
                publicIdentifier: publicIdentifier,
                systemIdentifier: systemIdentifier,
                forceQuirks: !isCorrect
            )
        case "StartTag":
            let name = try container.decode(String.self)
            let attributes = try container.decode([String: String].self)
            let selfClosing = container.isAtEnd ? false : try container.decode(Bool.self)
            self = .startTag(
                name: name,
                attributes: attributes,
                selfClosing: selfClosing
            )
        case "EndTag":
            self = .endTag(name: try container.decode(String.self))
        case "Comment":
            self = .comment(try container.decode(String.self))
        case "Character":
            self = .character(try container.decode(String.self))
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown html5lib token kind: \(kind)"
            )
        }
    }

    var normalized: NormalizedToken {
        switch self {
        case let .doctype(name, publicIdentifier, systemIdentifier, forceQuirks):
            .doctype(
                name: name,
                publicIdentifier: publicIdentifier,
                systemIdentifier: systemIdentifier,
                forceQuirks: forceQuirks
            )
        case let .startTag(name, attributes, selfClosing):
            .startTag(name: name, attributes: attributes, selfClosing: selfClosing)
        case let .endTag(name):
            .endTag(name: name)
        case let .comment(data):
            .comment(data)
        case let .character(data):
            .character(data)
        }
    }

    func decodingFixtureEscapes() -> FixtureToken? {
        switch self {
        case let .doctype(name, publicIdentifier, systemIdentifier, forceQuirks):
            guard
                let decodedName = name.decodingOptionalFixtureEscapes(),
                let decodedPublic = publicIdentifier.decodingOptionalFixtureEscapes(),
                let decodedSystem = systemIdentifier.decodingOptionalFixtureEscapes()
            else {
                return nil
            }
            return .doctype(
                name: decodedName,
                publicIdentifier: decodedPublic,
                systemIdentifier: decodedSystem,
                forceQuirks: forceQuirks
            )
        case let .startTag(name, attributes, selfClosing):
            guard let decodedName = name.decodingFixtureEscapes() else {
                return nil
            }
            var decodedAttributes: [String: String] = [:]
            for (attributeName, value) in attributes {
                guard
                    let decodedAttributeName = attributeName.decodingFixtureEscapes(),
                    let decodedValue = value.decodingFixtureEscapes()
                else {
                    return nil
                }
                decodedAttributes[decodedAttributeName] = decodedValue
            }
            return .startTag(
                name: decodedName,
                attributes: decodedAttributes,
                selfClosing: selfClosing
            )
        case let .endTag(name):
            return name.decodingFixtureEscapes().map(FixtureToken.endTag)
        case let .comment(data):
            return data.decodingFixtureEscapes().map(FixtureToken.comment)
        case let .character(data):
            return data.decodingFixtureEscapes().map(FixtureToken.character)
        }
    }
}

private enum NormalizedToken: Equatable, CustomStringConvertible {
    case doctype(
        name: String?,
        publicIdentifier: String?,
        systemIdentifier: String?,
        forceQuirks: Bool
    )
    case startTag(name: String, attributes: [String: String], selfClosing: Bool)
    case endTag(name: String)
    case comment(String)
    case character(String)

    static func from(_ tokens: [HTMLToken]) -> [NormalizedToken] {
        var normalized: [NormalizedToken] = []
        for token in tokens {
            switch token {
            case let .doctype(doctype):
                normalized.append(
                    .doctype(
                        name: doctype.name,
                        publicIdentifier: doctype.publicIdentifier,
                        systemIdentifier: doctype.systemIdentifier,
                        forceQuirks: doctype.forceQuirks
                    )
                )
            case let .startTag(name, attributes, selfClosing):
                normalized.append(
                    .startTag(
                        name: name,
                        attributes: Dictionary(
                            uniqueKeysWithValues: attributes.map { ($0.name, $0.value) }
                        ),
                        selfClosing: selfClosing
                    )
                )
            case let .endTag(name):
                normalized.append(.endTag(name: name))
            case let .comment(data):
                normalized.append(.comment(data))
            case let .character(data):
                if case let .character(previous)? = normalized.last {
                    normalized[normalized.count - 1] = .character(previous + data)
                } else {
                    normalized.append(.character(data))
                }
            case .eof:
                break
            }
        }
        return normalized
    }

    var description: String {
        switch self {
        case let .doctype(name, publicIdentifier, systemIdentifier, forceQuirks):
            "DOCTYPE(\(name ?? "nil"), \(publicIdentifier ?? "nil"), \(systemIdentifier ?? "nil"), quirks: \(forceQuirks))"
        case let .startTag(name, attributes, selfClosing):
            "StartTag(\(name), \(attributes), selfClosing: \(selfClosing))"
        case let .endTag(name):
            "EndTag(\(name))"
        case let .comment(data):
            "Comment(\(String(reflecting: data)))"
        case let .character(data):
            "Character(\(String(reflecting: data)))"
        }
    }
}

private extension HTMLTokenizerState {
    init?(fixtureName: String) {
        switch fixtureName {
        case "Data state": self = .data
        case "RCDATA state": self = .rcdata
        case "RAWTEXT state": self = .rawtext
        case "Script data state": self = .scriptData
        case "PLAINTEXT state": self = .plaintext
        case "CDATA section state": self = .cdataSection
        default: return nil
        }
    }
}

private extension UnkeyedDecodingContainer {
    mutating func decodeOptionalString() throws -> String? {
        if try decodeNil() {
            return nil
        }
        return try decode(String.self)
    }
}

private extension Optional where Wrapped == String {
    func decodingOptionalFixtureEscapes() -> String?? {
        switch self {
        case let .some(value):
            value.decodingFixtureEscapes().map(Optional.some)
        case .none:
            .some(nil)
        }
    }
}

private extension Array where Element == FixtureToken {
    func decodingFixtureEscapes() -> [FixtureToken]? {
        var decoded: [FixtureToken] = []
        decoded.reserveCapacity(count)
        for token in self {
            guard let value = token.decodingFixtureEscapes() else {
                return nil
            }
            decoded.append(value)
        }
        return decoded
    }
}

private extension String {
    func decodingFixtureEscapes() -> String? {
        let scalars = Array(unicodeScalars)
        var decoded = ""
        var scalarIndex = 0

        while scalarIndex < scalars.count {
            guard
                scalars[scalarIndex].value == 0x5C,
                scalarIndex + 5 < scalars.count,
                scalars[scalarIndex + 1].value == 0x75,
                let firstUnit = Self.hexQuad(
                    scalars[(scalarIndex + 2)...(scalarIndex + 5)]
                )
            else {
                decoded.unicodeScalars.append(scalars[scalarIndex])
                scalarIndex += 1
                continue
            }

            if (0xD800...0xDBFF).contains(firstUnit) {
                guard
                    scalarIndex + 11 < scalars.count,
                    scalars[scalarIndex + 6].value == 0x5C,
                    scalars[scalarIndex + 7].value == 0x75,
                    let secondUnit = Self.hexQuad(
                        scalars[(scalarIndex + 8)...(scalarIndex + 11)]
                    ),
                    (0xDC00...0xDFFF).contains(secondUnit)
                else {
                    return nil
                }
                let value = 0x10000
                    + ((UInt32(firstUnit) - 0xD800) << 10)
                    + (UInt32(secondUnit) - 0xDC00)
                decoded.unicodeScalars.append(Unicode.Scalar(value)!)
                scalarIndex += 12
            } else if (0xDC00...0xDFFF).contains(firstUnit) {
                return nil
            } else {
                decoded.unicodeScalars.append(Unicode.Scalar(firstUnit)!)
                scalarIndex += 6
            }
        }

        return decoded
    }

    static func hexQuad(_ scalars: ArraySlice<Unicode.Scalar>) -> UInt16? {
        guard scalars.count == 4 else {
            return nil
        }
        var result: UInt16 = 0
        for scalar in scalars {
            let digit: UInt16
            switch scalar.value {
            case 0x30...0x39: digit = UInt16(scalar.value - 0x30)
            case 0x41...0x46: digit = UInt16(scalar.value - 0x41 + 10)
            case 0x61...0x66: digit = UInt16(scalar.value - 0x61 + 10)
            default: return nil
            }
            result = result * 16 + digit
        }
        return result
    }
}
