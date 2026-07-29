# html5lib tokenizer-fixture updater

Run the updater with no arguments to reproduce the repository's pinned fixture
set:

```sh
Tools/UpdateHTML5libTokenizerFixtures/update.sh
```

Pass a full commit SHA to prepare an intentional baseline update:

```sh
Tools/UpdateHTML5libTokenizerFixtures/update.sh <40-character-commit-sha>
```

The updater downloads the commit archive, imports only `tokenizer/*.test` and
the tokenizer format documentation, refreshes the upstream license and author
files, and writes per-file SHA-256 values. It does not import the remainder of
the upstream repository.

When changing the revision, also update `BASELINE.md`, the root `README.md`,
and `NOTICE`, then review the fixture diff and run the full conformance suite.
