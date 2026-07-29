# html5lib tokenizer fixture baseline

- Repository: <https://github.com/html5lib/html5lib-tests>
- Revision:
  [`224991ec10db04f056a89eed8b0bd8695fd2950e`](https://github.com/html5lib/html5lib-tests/commit/224991ec10db04f056a89eed8b0bd8695fd2950e)
- Upstream commit date: 2026-06-26 11:52:08 UTC
- Retrieved: 2026-07-30 (Asia/Tokyo)
- Imported source:
  [`tokenizer/`](https://github.com/html5lib/html5lib-tests/tree/224991ec10db04f056a89eed8b0bd8695fd2950e/tokenizer)

This directory contains all 14 `.test` files from that tokenizer directory.
`FORMAT.md` is the upstream tokenizer README, renamed without content changes.
`SHA256SUMS` records a SHA-256 for every imported upstream file.

The `xmlViolation.test` file uses a distinct, legacy output contract described
in `FORMAT.md`; a conforming HTML token-stream harness may intentionally skip
it. Any other exclusions should be explicit in the Swift conformance test and
documented with a reason.

The fixtures are MIT-licensed. The exact upstream license and contributor list
are retained at `LICENSES/html5lib-tests.txt` and
`LICENSES/html5lib-tests-AUTHORS.rst`.

Use `Tools/UpdateHTML5libTokenizerFixtures/update.sh` to reproduce or
intentionally update this import.
