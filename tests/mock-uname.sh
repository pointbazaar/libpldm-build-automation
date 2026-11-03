#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail
[[ $# == 1 && $1 == -s ]]
printf '%s\n' "$MOCK_UNAME"
