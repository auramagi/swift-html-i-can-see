# Named character-reference generator

`entities.json` is a pinned copy of WHATWG's published named character-reference dataset. Running:

```sh
Tools/GenerateNamedCharacterReferences/generate.sh
```

validates its SHA-256 and deterministically regenerates
`Sources/HTMLICanSeeTokenizer/Generated/HTMLNamedCharacterReferences.swift`.
The generator checks that every `characters` value agrees with its `codepoints`
array before writing source.

Updating the data is an intentional baseline change:

1. Download `https://html.spec.whatwg.org/entities.json`.
2. Record the retrieval date and SHA-256 in `generate.sh`, `NOTICE`, and the
   conformance-baseline section of the root `README.md`.
3. Select and record the corresponding `whatwg/html` revision.
4. Replace this directory's `entities.json` and run `generate.sh`.
5. Review the generated diff and run the tokenizer conformance tests.

The source data is © WHATWG (Apple, Google, Mozilla, Microsoft). See
`LICENSES/WHATWG-HTML.txt` and the repository `NOTICE`.
