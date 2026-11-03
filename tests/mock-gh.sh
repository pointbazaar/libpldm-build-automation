#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Offline GitHub CLI double. Never contact GitHub from automation unit tests.
set -euo pipefail
printf '%s\n' "$*" >> "$MOCK_LOG"
if [[ $1 == api ]]; then
    if [[ ${2:-} == --method ]]; then
        cp "${@: -1}" "$MOCK_STORE/status-request.json"
        echo '{}'
    else
        cat "$MOCK_RELEASES"
    fi
    exit 0
fi
[[ $1 == release ]] || exit 90
case $2 in
    create|edit) ;;
    upload)
        [[ ${MOCK_FAIL_UPLOAD:-false} != true ]] || exit 91
        shift 3
        for file in "$@"; do
            [[ $file == --* ]] && break
            cp "$file" "$MOCK_STORE/"
        done
        ;;
    download)
        while (( $# )); do
            if [[ $1 == --dir ]]; then
                cp "$MOCK_STORE/"* "$2/"
                exit 0
            fi
            shift
        done
        exit 92
        ;;
    *) exit 93 ;;
esac
