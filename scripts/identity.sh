#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail
source "$(dirname "$0")/common.sh"

# Hash filenames as well as bytes; include untracked recipe files for local tests.
# Deliberately exclude docs, sync-status, and the repository commit itself.
cd "$ROOT"
find .github/workflows patches scripts config tests -type f ! -name '*.md' \
    | LC_ALL=C sort | while IFS= read -r file; do
        sha256 "$file"
    done | sha256 | cut -d ' ' -f 1
