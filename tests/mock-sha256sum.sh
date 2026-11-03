#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Model the different default checksum markers on Unix and MSYS2.
set -euo pipefail
marker=${MOCK_CHECKSUM_MARKER:-' '}
case ${1:-} in
    -b|--binary) marker='*'; shift ;;
esac
checksum=$("$REAL_SHA256SUM" --binary "$@")
printf '%s %s%s\n' "${checksum%% *}" "$marker" "${1:--}"
