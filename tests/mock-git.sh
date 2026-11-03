#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Only used for the keepalive tests; isolate them from any real repository.
set -euo pipefail
[[ $1 != -C ]] || shift 2
case $1 in
    fetch) ;;
    ls-tree)
        if [[ -n ${MOCK_STATUS:-} ]]; then
            printf '100644 blob abcdef\t.github/sync-status.json\n'
        fi
        ;;
    show) cat "$MOCK_STATUS" ;;
    *) exit 94 ;;
esac
