#!/usr/bin/env bash

set -euo pipefail

revision="${1:-224991ec10db04f056a89eed8b0bd8695fd2950e}"

if [[ ! "${revision}" =~ ^[0-9a-f]{40}$ ]]; then
    echo "revision must be a full, lowercase 40-character Git commit SHA" >&2
    exit 1
fi

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "${script_directory}/../.." && pwd)"
fixture_directory="${repository_root}/Tests/HTMLICanSeeTokenizerTests/Fixtures/html5lib-tests"
license_directory="${repository_root}/LICENSES"
temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/html5lib-tests.XXXXXX")"
archive="${temporary_directory}/html5lib-tests.tar.gz"
extract_directory="${temporary_directory}/extract"
archive_url="https://github.com/html5lib/html5lib-tests/archive/${revision}.tar.gz"

cleanup() {
    rm -rf "${temporary_directory}"
}
trap cleanup EXIT

mkdir -p "${extract_directory}" "${fixture_directory}" "${license_directory}"
curl --fail --location --silent --show-error "${archive_url}" --output "${archive}"
tar -xzf "${archive}" -C "${extract_directory}"

source_root="${extract_directory}/html5lib-tests-${revision}"
test -d "${source_root}/tokenizer"
test -f "${source_root}/LICENSE"
test -f "${source_root}/AUTHORS.rst"

find "${fixture_directory}" -maxdepth 1 -type f -name '*.test' -delete
rm -f "${fixture_directory}/FORMAT.md" "${fixture_directory}/SHA256SUMS"

cp "${source_root}"/tokenizer/*.test "${fixture_directory}/"
cp "${source_root}/tokenizer/README.md" "${fixture_directory}/FORMAT.md"
cp "${source_root}/LICENSE" "${license_directory}/html5lib-tests.txt"
cp "${source_root}/AUTHORS.rst" "${license_directory}/html5lib-tests-AUTHORS.rst"

(
    cd "${fixture_directory}"
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum ./*.test ./FORMAT.md
    else
        shasum -a 256 ./*.test ./FORMAT.md
    fi
) > "${fixture_directory}/SHA256SUMS"

echo "Imported html5lib tokenizer fixtures at ${revision}"
