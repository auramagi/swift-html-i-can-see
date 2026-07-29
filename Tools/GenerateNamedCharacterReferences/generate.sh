#!/usr/bin/env bash

set -euo pipefail

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "${script_directory}/../.." && pwd)"
input="${script_directory}/entities.json"
output="${repository_root}/Sources/HTMLICanSeeTokenizer/Generated/HTMLNamedCharacterReferences.swift"
module_cache="${repository_root}/.build/tool-module-cache"

source_url="https://html.spec.whatwg.org/entities.json"
source_sha256="d741d877ac77c4194c4ad526b5b4a19aef8dfe411ab840a466891cdbb9f362e6"
retrieved_date="2026-07-30"
html_revision="b94ff8886e9afdcc761fcb1565d1488976fa60ba"

if command -v sha256sum >/dev/null 2>&1; then
    actual_sha256="$(sha256sum "${input}" | awk '{ print $1 }')"
else
    actual_sha256="$(shasum -a 256 "${input}" | awk '{ print $1 }')"
fi

if [[ "${actual_sha256}" != "${source_sha256}" ]]; then
    echo "entities.json checksum mismatch" >&2
    echo "expected: ${source_sha256}" >&2
    echo "actual:   ${actual_sha256}" >&2
    exit 1
fi

mkdir -p "${module_cache}"

swift -module-cache-path "${module_cache}" "${script_directory}/main.swift" \
    "${input}" \
    "${output}" \
    "${source_url}" \
    "${source_sha256}" \
    "${retrieved_date}" \
    "${html_revision}"

echo "Generated ${output}"
