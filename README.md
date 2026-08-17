# HTML I Can See

> [!WARNING]
> This project is the result of some vibe coding sessions, and the source code is mostly unreviewed. Use at your own peril.

`swift-html-i-can-see` is a dependency-free Swift package for turning HTML into
a WHATWG-oriented token stream, a small persistent semantic document, and a
native SwiftUI view.

```text
HTML string
    ↓
WHATWG-compatible tokens
    ↓
Codable semantic document
    ↓
SwiftUI
```

It deliberately is not a browser engine. The tokenizer is generic; the
semantic layer recognizes a small documented HTML subset; and the renderer
uses SwiftUI without WebKit, a DOM, CSS, JavaScript, or Foundation's HTML
importer.

## Requirements

- Swift 6.2 or newer, in Swift 6 language mode (Xcode 26+ on Apple platforms)
- iOS 26+, macOS 26+, tvOS 26+, watchOS 26+, or visionOS 26+
- Linux for the tokenizer module

The package exposes one library product, `HTMLICanSee`, composed of:

- `HTMLICanSeeTokenizer`, with no Apple UI-framework dependency
- `HTMLICanSeeSwiftUI`, which depends on SwiftUI and the tokenizer

The runtime package has no package dependencies.

When declaring this package in another Swift package, depend on its single
product:

```swift
.product(
    name: "HTMLICanSee",
    package: "swift-html-i-can-see"
)
```

Import the module whose APIs are needed.

## Tokenizing HTML

`HTMLTokenizer` is a streaming value type. It operates on Unicode scalars,
performs HTML input preprocessing, reports recoverable parse errors, and emits
EOF as the final token.

```swift
import HTMLICanSeeTokenizer

var tokenizer = HTMLTokenizer("<p class=lead>Hello &amp; goodbye</p>")

while true {
    let token = tokenizer.nextToken()
    print(token)
    if token == .eof {
        break
    }
}

let diagnostics = tokenizer.errors
```

`collect()` gathers the remainder of a stream, including EOF. For one-shot
use, `HTMLTokenizer.tokenize(_:)` returns the complete stream:

```swift
let tokens = HTMLTokenizer.tokenize("<strong>Hello</strong>")
```

Parse errors are diagnostics, not thrown failures. They are collected as
`HTMLParseError` values while tokenization continues according to the
specification.

### Caller-controlled tokenizer states

HTML tokenization is not completely autonomous. In a browser, tree
construction decides when the tokenizer enters RCDATA, RAWTEXT, script-data,
or PLAINTEXT states and supplies the last emitted start-tag name. This package
does not implement tree construction, so advanced callers must provide that
policy.

An initial state and appropriate last start tag can be supplied directly:

```swift
var tokenizer = HTMLTokenizer(
    "A &amp; B</title>",
    initialState: .rcdata,
    lastStartTagName: "title"
)
let tokens = tokenizer.collect()
```

Use `switchTo(_:)` only between `nextToken()` calls when a higher-level parser
needs to change state. Ordinary full-document tokenization begins in `.data`.

## Stable token model

Tokens contain only specification-level data:

- DOCTYPE name, public/system identifiers, and force-quirks flag
- start-tag name, ordered attributes, and self-closing flag
- end-tag name
- comment data
- character data
- EOF

`HTMLToken`, `HTMLAttribute`, `HTMLDOCTYPE`, `HTMLParseError`, and
`HTMLTokenizerState` are `Codable`, `Hashable`, and `Sendable`. Source
locations are diagnostic metadata on parse errors; they are not embedded in
token equality or persisted token values.

### Encoded token representation

`HTMLToken` uses an explicit keyed representation with a `type`
discriminator. It does not use Swift's synthesized associated-value layout.
The checked-in
[`token-stream-v1.json`](Tests/HTMLICanSeeTokenizerTests/Fixtures/token-stream-v1.json)
file is the normative compatibility example for the complete token surface.

| Token | Encoded fields |
| --- | --- |
| DOCTYPE | `type: "doctype"`, `doctype: { name?, publicIdentifier?, systemIdentifier?, forceQuirks }` |
| Start tag | `type: "startTag"`, `name`, `attributes: [{ name, value }]`, `selfClosing` |
| End tag | `type: "endTag"`, `name` |
| Comment | `type: "comment"`, `data` |
| Character | `type: "character"`, `data` |
| EOF | `type: "eof"` |

Optional DOCTYPE identifiers are omitted by encoders such as `JSONEncoder`
when nil. Attribute array order is significant and preserved.
`HTMLTokenizerState` and `HTMLParseError.Code` encode as their documented
string raw values. `HTMLParseError` encodes as
`{ "code": "<spec-error-code>", "scalarOffset": 0 }`, where the offset is
zero-based in the preprocessed Unicode-scalar input.

## Semantic documents and rendering

The SwiftUI module maps a token stream into a stable semantic document before
rendering. A document owns its text, paragraph/list structure, inline styles,
and accepted link destinations. It does not retain the original HTML or
private tokenizer state, so it can be encoded, stored, decoded, and rendered
without reparsing.

Build directly from HTML, or map a token stream that was produced elsewhere:

```swift
import Foundation
import SwiftUI
import HTMLICanSeeSwiftUI
import HTMLICanSeeTokenizer

let builder = HTMLDocumentBuilder()
let document = builder.build(
    from: "<p>Hello <strong>from SwiftUI</strong>.</p>"
)

let tokens = HTMLTokenizer.tokenize("<p>The same pipeline</p>")
let tokenBuiltDocument = builder.build(from: tokens)
```

The document is the fundamental rendering input:

```swift
struct ArticleBody: View {
    let document: HTMLDocument

    var body: some View {
        HTMLDocumentView(document)
            .htmlDocumentStyle(
                HTMLDocumentStyle(
                    blockSpacing: 16,
                    listIndentation: 24,
                    underlinesLinks: true
                )
            )
    }
}
```

Persist the semantic document with any `Encoder` and render the decoded value
later; neither operation needs the source HTML:

```swift
let data = try JSONEncoder().encode(document)
let restored = try JSONDecoder().decode(HTMLDocument.self, from: data)
```

The initial semantic surface is intentionally limited:

| HTML | Semantic behavior |
| --- | --- |
| `p` | paragraph |
| `ol`, `ul`, `li` | ordered/unordered and nested lists |
| `strong`, `b` | bold |
| `em`, `i` | italic |
| `del` | strikethrough |
| `br` | hard inline break |
| `a` | link when `href` is accepted |

For links, only `href` affects the document. Absolute `http`, `https`, and
`mailto` destinations are accepted. Relative, protocol-relative, malformed,
control-character-containing, and unsupported-scheme destinations retain
their visible text without link behavior. Percent escapes must contain exactly
two hexadecimal digits. `name`, `target`, event handlers, styles, scripts, and
embedded resources are never interpreted.

Unsupported tags are discarded while their visible text ordinarily survives.
The contents of `script`, `style`, and `template` are suppressed. Comments and
doctypes do not become visible content. Mapping malformed markup is
deterministic and does not fail the whole document:

- a new paragraph or list closes the current top-level paragraph;
- a new list item closes the preceding item in the innermost list;
- a list end tag closes nested lists through the nearest matching list;
- an inline end tag removes the nearest matching open inline tag; and
- formatting opened inside a paragraph or list item does not leak into the
  following paragraph or item.

Ordinary HTML ASCII whitespace is collapsed within visible text where
appropriate, and source formatting between blocks does not create visible
text by itself. Non-whitespace Unicode is preserved, `<br>` remains a hard
break, intentional empty paragraphs can remain visible, and adjacent runs
with identical semantics are coalesced. If no visible content remains, the
builder returns a document with an empty `blocks` array, which is safe to
render.

The default SwiftUI presentation inherits surrounding typography and supports
multiline layout, Dynamic Type, accessibility, right-to-left layout, and text
selection on platforms that expose it. Accepted links are rendered as native
SwiftUI attributed links and use SwiftUI's URL-opening environment.
Presentation choices such as block spacing, list indentation, bullet
appearance, and link styling belong to renderer configuration, not to the
persisted document.

### Encoded semantic representation

Semantic document types use explicit coding keys and discriminators rather
than compiler-synthesized enum layouts. Their JSON compatibility fixtures are
the normative examples of the encoded representation; see
[`semantic-document-v1.json`](Tests/HTMLICanSeeSwiftUITests/Fixtures/semantic-document-v1.json).

| Value | Encoded form |
| --- | --- |
| `HTMLDocument` | `{ "blocks": [...] }` |
| Paragraph block | `{ "type": "paragraph", "content": [...] }` |
| List block | `{ "type": "list", "list": { "style": "...", "items": [...] } }` |
| `HTMLListStyle` | `"ordered"` or `"unordered"` |
| List item | `{ "parts": [...] }` |
| Inline item part | `{ "type": "inlines", "content": [...] }` |
| Nested-list item part | `{ "type": "list", "list": {...} }` |
| Text inline | `{ "type": "text", "text": "...", "style": {...} }` |
| Hard break inline | `{ "type": "lineBreak" }` |
| Text style | `{ "bold": false, "italic": false, "strikethrough": false, "link": "..."? }` |

Block, item-part, and inline order is significant. Keeping inline and
nested-list parts in one sequence preserves content on both sides of a nested
list. A style's `link` field is omitted when absent. Concrete fonts, colors,
and other environment-dependent presentation values are not persisted.

Both the public token shape and semantic document shape are durable API.
Changing a discriminator, field name, field meaning, or required field is a
semantic-versioning concern just like changing a public Swift declaration.
Additive decoding-compatible changes require deliberate compatibility tests;
incompatible persisted-format changes require a major release.

## Conformance baseline

The HTML Standard is a Living Standard, so this repository pins intentional
maintenance baselines:

- WHATWG HTML Standard:
  [`b94ff8886e9afdcc761fcb1565d1488976fa60ba`](https://github.com/whatwg/html/commit/b94ff8886e9afdcc761fcb1565d1488976fa60ba),
  committed 2026-06-25 06:37:07 UTC
- Named character references:
  [`https://html.spec.whatwg.org/entities.json`](https://html.spec.whatwg.org/entities.json),
  retrieved 2026-07-30 (Asia/Tokyo), SHA-256
  `d741d877ac77c4194c4ad526b5b4a19aef8dfe411ab840a466891cdbb9f362e6`
- html5lib-tests:
  [`224991ec10db04f056a89eed8b0bd8695fd2950e`](https://github.com/html5lib/html5lib-tests/commit/224991ec10db04f056a89eed8b0bd8695fd2950e),
  committed 2026-06-26 11:52:08 UTC

The WHATWG snapshot is intentionally the exact latest revision before
[`320c05f679e2e0795acde90d0704caf7ade03fdc`](https://github.com/whatwg/html/commit/320c05f679e2e0795acde90d0704caf7ade03fdc)
added processing-instruction tokens, states, and parse errors on 2026-06-25.
The package's required public token model does not include a processing
instruction token; under this pinned baseline, `<?...>` follows the traditional
bogus-comment behavior. Adopting the newer algorithm requires an intentional
public-model and persistence-format decision.

The complete html5lib tokenizer fixture directory at that revision is checked
in under `Tests/HTMLICanSeeTokenizerTests/Fixtures/html5lib-tests`. Its
`BASELINE.md` explains the import and `SHA256SUMS` verifies each upstream
file. The conformance harness runs the 13 standard tokenizer fixture files and
compares both normalized token output and ordered parse-error codes.
`xmlViolation.test` has a separate legacy infoset-coercion contract and is
retained but not treated as a token-stream fixture. Double-escaped cases that
require an isolated UTF-16 surrogate cannot be expressed by the package's
well-formed Swift `String` input: exactly four such cases in
`unicodeCharsProblematic.test` are skipped explicitly by the loader. Numeric
surrogate character-reference behavior remains representable and covered.

Named-reference generation is reproducible from the checked-in source
dataset:

```sh
Tools/GenerateNamedCharacterReferences/generate.sh
```

The html5lib tokenizer fixtures can be reproduced at the pinned revision with:

```sh
Tools/UpdateHTML5libTokenizerFixtures/update.sh
```

Both tools document the intentional update procedure. Baseline changes should
be reviewed with their generated or fixture diffs and the full conformance
suite.

## Scope and security

This package implements HTML input preprocessing and tokenization, plus a
deliberately small token-to-document mapper. It does not implement WHATWG tree
construction, a DOM, arbitrary-element rendering, CSS, JavaScript, browser
layout, WebKit rendering, or HTML sanitization for reuse in another context.

The SwiftUI semantic layer never executes HTML content, but that does not make
the original string safe to interpolate into a web page, SQL query, shell
command, or another parser. Apply the escaping or sanitization rules of the
eventual output context.

## License and attribution

Original work is available under the MIT License; see `LICENSE`.

The generated named-reference table and its source data retain WHATWG
copyright and license terms. Imported html5lib tokenizer fixtures retain their
MIT license and contributor attribution. Exact sources, revisions, checksums,
and license locations are recorded in `NOTICE` and `LICENSES/`.
