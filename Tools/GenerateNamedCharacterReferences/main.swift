import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

private struct Entity: Decodable {
    let codepoints: [UInt32]
    let characters: String
}

private enum GenerationError: Error, CustomStringConvertible {
    case invalidArguments
    case invalidEntityName(String)
    case invalidCodePoint(UInt32, entity: String)
    case inconsistentCharacters(String)

    var description: String {
        switch self {
        case .invalidArguments:
            return """
            usage: swift main.swift <entities.json> <output.swift> \
              <source-url> <source-sha256> <retrieved-date> <html-revision>
            """
        case let .invalidEntityName(name):
            return "invalid named character reference key: \(name)"
        case let .invalidCodePoint(codePoint, entity):
            return "invalid Unicode scalar U+\(String(codePoint, radix: 16, uppercase: true)) in \(entity)"
        case let .inconsistentCharacters(entity):
            return "characters and codepoints disagree for \(entity)"
        }
    }
}

private func swiftValueLiteral(_ value: String) -> String {
    let escapedScalars = value.unicodeScalars.map {
        "\\u{\(String($0.value, radix: 16, uppercase: true))}"
    }
    return "\"\(escapedScalars.joined())\""
}

private func run() throws {
    guard CommandLine.arguments.count == 7 else {
        throw GenerationError.invalidArguments
    }

    let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
    let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
    let sourceURL = CommandLine.arguments[3]
    let sourceSHA256 = CommandLine.arguments[4]
    let retrievedDate = CommandLine.arguments[5]
    let htmlRevision = CommandLine.arguments[6]

    let input = try Data(contentsOf: inputURL)
    let entities = try JSONDecoder().decode([String: Entity].self, from: input)
    let validNameCharacters = CharacterSet(
        charactersIn: "&;ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
    )

    var lines = [
        "// Generated file. Do not edit by hand.",
        "//",
        "// Source: \(sourceURL)",
        "// Dataset retrieved and table generated: \(retrievedDate)",
        "// Source SHA-256: \(sourceSHA256)",
        "// WHATWG HTML baseline: \(htmlRevision)",
        "//",
        "// The source data is © WHATWG (Apple, Google, Mozilla, Microsoft).",
        "// See LICENSES/WHATWG-HTML.txt and NOTICE for license and attribution.",
        "",
        "internal enum HTMLNamedCharacterReferences {",
        "    static let values: [String: String] = [",
    ]

    for name in entities.keys.sorted() {
        guard name.first == "&",
              name.unicodeScalars.allSatisfy({ validNameCharacters.contains($0) })
        else {
            throw GenerationError.invalidEntityName(name)
        }

        guard let entity = entities[name] else {
            preconditionFailure("A key obtained from a dictionary must have a value")
        }

        var reconstructed = ""
        for codePoint in entity.codepoints {
            guard let scalar = Unicode.Scalar(codePoint) else {
                throw GenerationError.invalidCodePoint(codePoint, entity: name)
            }
            reconstructed.unicodeScalars.append(scalar)
        }

        guard reconstructed == entity.characters else {
            throw GenerationError.inconsistentCharacters(name)
        }

        lines.append("        \"\(name)\": \(swiftValueLiteral(entity.characters)),")
    }

    lines.append(contentsOf: [
        "    ]",
        "}",
        "",
    ])

    let output = lines.joined(separator: "\n")
    try FileManager.default.createDirectory(
        at: outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try Data(output.utf8).write(to: outputURL, options: .atomic)
}

do {
    try run()
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(EXIT_FAILURE)
}
