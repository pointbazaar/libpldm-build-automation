#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail
source "$(dirname "$0")/../scripts/common.sh"
source "$ROOT/scripts/releases.sh"
mkdir -p "${RUNNER_TEMP:-/tmp/opencode}"
temporary=$(mktemp -d "${RUNNER_TEMP:-/tmp/opencode}/automation-test.XXXXXX")
trap 'rm -rf "$temporary"' EXIT
export MOCK_RELEASES="$temporary/releases.json" MOCK_LOG="$temporary/gh.log"
export MOCK_STORE="$temporary/store"
mkdir -p "$temporary/bin" "$MOCK_STORE"
cp "$ROOT/tests/mock-gh.sh" "$temporary/bin/gh"
chmod +x "$temporary/bin/gh"
export PATH="$temporary/bin:$PATH"
export GITHUB_REPOSITORY=offline/test GITHUB_EVENT_NAME=schedule
export DEFAULT_BRANCH=master GITHUB_REF=refs/heads/master
export GITHUB_SHA=53dd645bd72ac0741d84decf1f7f38709658f73b8
export GITHUB_RUN_ID=123 GITHUB_RUN_ATTEMPT=1
export GITHUB_STEP_SUMMARY="$temporary/summary"
export GITHUB_OUTPUT="$temporary/output"
upstream=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
digest=$(bash "$ROOT/scripts/identity.sh")
identity="$upstream-$digest"
assets=$(jq -cn --arg id "$identity" '[
    "libpldm-\($id)-windows-x86_64.tar.gz", "libpldm-\($id)-macos-arm64.tar.gz",
    "libpldm-\($id)-macos-x86_64.tar.gz", "libpldm-\($id)-source.tar.gz",
    "libpldm-\($id)-recipe.tar.gz", "build.json", "SHA256SUMS"]')

release_fixture() {
    jq -n --arg id "$identity" --argjson assets "$assets" --arg rev "$GITHUB_SHA" '
        [{draft: false, prerelease: false, tag_name: "previous-success",
          target_commitish: $rev, body: ("Build identity: " + $id + "\n"),
          assets: [$assets[] | {name: ., size: 100, state: "uploaded"}]}]' \
        > "$MOCK_RELEASES"
}

test_release_validation() {
    local filter
    release_fixture
    [[ $(complete_release "$MOCK_RELEASES" "$identity" "$assets") == previous-success ]]
    for filter in '.[0].draft = true' '.[0].prerelease = true' \
        '.[0].assets |= .[1:]' '.[0].assets[0].size = 0' \
        '.[0].assets[0].state = "new"' '.[0].body = "wrong identity"'; do
        release_fixture
        jq "$filter" "$MOCK_RELEASES" > "$temporary/incomplete.json"
        if complete_release "$temporary/incomplete.json" "$identity" "$assets"; then
            fail "Invalid release accepted: $filter"
        fi
    done
    release_fixture
    PUBLISH_ALLOWED=true bash "$ROOT/scripts/prepare.sh" prepare "$upstream" "$temporary/prepared"
    grep -qx 'skip=true' "$GITHUB_OUTPUT"
    [[ ! -d $temporary/prepared/libpldm ]]
    echo 'Complete-only skip and incomplete/failed identity retry checks: OK'
}

test_identity_scope() {
    local copy="$temporary/recipe" original
    mkdir -p "$copy/.github"
    cp -R "$ROOT/scripts" "$ROOT/patches" "$ROOT/config" "$ROOT/tests" "$copy/"
    cp -R "$ROOT/.github/workflows" "$copy/.github/"
    original=$(bash "$copy/scripts/identity.sh")
    echo 'documentation edit' > "$copy/README.md"
    echo '{"check": "heartbeat only"}' > "$copy/.github/sync-status.json"
    [[ $(bash "$copy/scripts/identity.sh") == "$original" ]]
    echo '# external toolchain refresh' >> "$copy/config/recipe.env"
    [[ $(bash "$copy/scripts/identity.sh") != "$original" ]]
    echo 'Recipe identity excludes docs/heartbeat, includes configuration: OK'
}

make_test_assets() {
    local directory=$1 target name
    cp "$temporary/prepared/build.json" "$directory/"
    for target in windows-x86_64 macos-arm64 macos-x86_64; do
        name="libpldm-$identity-$target"
        mkdir -p "$temporary/package/$name/share/libpldm/build"
        cp "$directory/build.json" "$temporary/package/$name/share/libpldm/build/identity.json"
        jq -n --arg target "$target" '{target: $target}' \
            > "$temporary/package/$name/share/libpldm/build/target.json"
        tar -czf "$directory/$name.tar.gz" -C "$temporary/package" "$name"
    done
    tar -czf "$directory/libpldm-$identity-source.tar.gz" -C "$temporary/prepared" build.json
    cp "$directory/libpldm-$identity-source.tar.gz" "$directory/libpldm-$identity-recipe.tar.gz"
}

test_publication() {
    local directory="$temporary/release"
    mkdir -p "$directory"
    make_test_assets "$directory"
    release_fixture
    : > "$MOCK_LOG"
    bash "$ROOT/scripts/publish.sh" "$directory"
    if grep -q '^release create' "$MOCK_LOG"; then fail 'Skip created a release'; fi
    : > "$MOCK_LOG"
    if FORCE_REBUILD=true MOCK_FAIL_UPLOAD=true bash "$ROOT/scripts/publish.sh" "$directory" \
        > "$temporary/expected-upload-failure.log" 2>&1; then
        fail 'An upload failure must block publication'
    fi
    if grep -q -- '--draft=false' "$MOCK_LOG"; then fail 'Failed upload published a release'; fi
    : > "$MOCK_LOG"
    FORCE_REBUILD=true bash "$ROOT/scripts/publish.sh" "$directory"
    grep -q "^release create build-$identity-r123-1 --draft" "$MOCK_LOG"
    grep -q -- '--draft=false --latest' "$MOCK_LOG"
    release_fixture
    jq '.[0].draft = true | .[0].tag_name = "interrupted-draft"' "$MOCK_RELEASES" \
        > "$temporary/draft.json"
    cp "$temporary/draft.json" "$MOCK_RELEASES"
    : > "$MOCK_LOG"
    FORCE_REBUILD=true bash "$ROOT/scripts/publish.sh" "$directory"
    if grep -q '^release create' "$MOCK_LOG"; then fail 'Draft recovery created a second release'; fi
    grep -q 'release edit interrupted-draft --draft=false --latest' "$MOCK_LOG"
    mv "$directory/libpldm-$identity-macos-arm64.tar.gz" "$temporary/withheld.tar.gz"
    : > "$MOCK_LOG"
    if bash "$ROOT/scripts/publish.sh" "$directory" > "$temporary/expected-missing-target.log" 2>&1; then
        fail 'Missing required target accepted'
    fi
    [[ ! -s $MOCK_LOG ]]
    echo 'Force revisions, draft recovery, upload failure and incomplete-target blocking: OK'
}

test_keepalive() {
    cp "$ROOT/tests/mock-git.sh" "$temporary/bin/git"
    chmod +x "$temporary/bin/git"
    : > "$MOCK_LOG"
    bash "$ROOT/scripts/keepalive.sh" "$upstream"
    jq -e '.content | @base64d | fromjson | .upstream_main == "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"' \
        "$MOCK_STORE/status-request.json" > /dev/null
    grep -q 'contents/.github/sync-status.json' "$MOCK_LOG"
    export MOCK_STATUS="$temporary/status.json"
    jq -n --argjson epoch "$(date -u +%s)" '{checked_epoch: $epoch}' > "$MOCK_STATUS"
    : > "$MOCK_LOG"
    bash "$ROOT/scripts/keepalive.sh" "$upstream"
    [[ ! -s $MOCK_LOG ]]
    echo 'Keepalive records genuine checks and avoids daily commits: OK'
}

test_release_validation
test_identity_scope
test_publication
test_keepalive
