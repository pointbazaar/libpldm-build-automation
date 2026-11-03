#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=../config/recipe.env
source "$ROOT/config/recipe.env"

fail() {
    echo "error: $*" >&2
    return 1
}

stage() {
    if [[ -n ${STAGE:-} ]]; then echo '::endgroup::'; fi
    STAGE=$1
    echo "::group::$STAGE"
}

report_failure() {
    local status=$?
    if [[ -n ${STAGE:-} ]]; then echo '::endgroup::'; fi
    if (( status != 0 )); then
        echo "::error::${TARGET:-preparation}: ${STAGE:-initialization} failed ($status)"
        if [[ -n ${GITHUB_STEP_SUMMARY:-} ]]; then
            echo "- **${TARGET:-preparation} failed**: ${STAGE:-initialization} (exit $status)" >> "$GITHUB_STEP_SUMMARY"
        fi
    fi
    return "$status"
}
trap report_failure EXIT

sha256() {
    if command -v sha256sum >/dev/null; then
        sha256sum "$@"
    else
        shasum -a 256 "$@"
    fi
}

output() {
    echo "$1=$2"
    if [[ -n ${GITHUB_OUTPUT:-} ]]; then
        echo "$1=$2" >> "$GITHUB_OUTPUT"
    fi
}

fetch_commit() {
    local url=$1 commit=$2 destination=$3
    [[ $commit =~ ^[0-9a-f]{40}$ ]] || fail "Not an exact commit: $commit"
    [[ ! -e $destination ]] || fail "Destination already exists: $destination"
    git init -q "$destination"
    git -C "$destination" remote add origin "$url"
    git -C "$destination" fetch --depth=1 origin "$commit"
    git -C "$destination" -c advice.detachedHead=false checkout --detach FETCH_HEAD
    [[ $(git -C "$destination" rev-parse HEAD) == "$commit" ]]
}
