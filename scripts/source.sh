#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail
source "$(dirname "$0")/common.sh"

commit=$1
destination=$2
stage 'Fetch exact upstream source'
fetch_commit https://github.com/openbmc/libpldm.git "$commit" "$destination"
stage 'Apply compatibility series'
while IFS= read -r patch; do
    [[ -z $patch || $patch == \#* ]] && continue
    [[ $patch != */* && $patch == *.patch ]] || fail "Invalid patch name: $patch"
    git -C "$destination" apply --check "$ROOT/patches/$patch"
    git -C "$destination" apply "$ROOT/patches/$patch"
done < "$ROOT/patches/series"
stage 'Fetch pinned test dependency'
fetch_commit https://github.com/google/googletest.git "$GOOGLETEST_COMMIT" \
    "$destination/subprojects/googletest"
printf '%s\n' "$commit" > "$destination/UPSTREAM-COMMIT"
printf '%s\n' "$GOOGLETEST_COMMIT" > "$destination/GOOGLETEST-COMMIT"
