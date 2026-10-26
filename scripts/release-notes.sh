#!/usr/bin/env bash
# Prints the canonical store release notes as a "## Store release notes" markdown block.
# Usage: scripts/release-notes.sh [versionCode]   (defaults to the +N in pubspec.yaml)
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
changelog_dir="${repo_root}/fastlane/metadata/android/en-US/changelogs"

version_code="${1:-}"
if [[ -z "$version_code" ]]; then
  version_code="$(sed -n 's/^version:[[:space:]]*[^+]*+\([0-9][0-9]*\)[[:space:]]*$/\1/p' "${repo_root}/pubspec.yaml")"
fi

notes_file="${changelog_dir}/default.txt"
if [[ -n "$version_code" && -f "${changelog_dir}/${version_code}.txt" ]]; then
  notes_file="${changelog_dir}/${version_code}.txt"
fi

if [[ ! -f "$notes_file" ]]; then
  echo "release-notes: no changelog found at ${notes_file}" >&2
  exit 1
fi

printf '## Store release notes\n\n'
cat "$notes_file"
echo
