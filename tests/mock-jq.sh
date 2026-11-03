#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Native jq.exe writes CRLF unless --binary is requested explicitly.
set -euo pipefail
if [[ ${MOCK_JQ_PLATFORM:-windows} == unix ]]; then
    if [[ ${1:-} == --binary ]]; then
        echo 'jq: Unknown option --binary' >&2
        exit 2
    fi
    exec "$REAL_JQ" "$@"
fi
if [[ ${1:-} == --binary ]]; then
    shift
    exec "$REAL_JQ" "$@"
fi
"$REAL_JQ" "$@" | sed 's/$/\r/'
