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
    "libpldm-\($id)-linux-x86_64.tar.gz",
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
        '.[0].assets[0].state = "new"' '.[0].body = "wrong identity"' \
        '.[0].assets |= map(select(.name | endswith("-linux-x86_64.tar.gz") | not))'; do
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
    cp "$ROOT/.gitattributes" "$copy/"
    cp -R "$ROOT/.github/workflows" "$copy/.github/"
    original=$(bash "$copy/scripts/identity.sh")
    echo 'documentation edit' > "$copy/README.md"
    echo '{"check": "heartbeat only"}' > "$copy/.github/sync-status.json"
    [[ $(bash "$copy/scripts/identity.sh") == "$original" ]]
    echo '# external toolchain refresh' >> "$copy/config/recipe.env"
    [[ $(bash "$copy/scripts/identity.sh") != "$original" ]]
    echo 'Recipe identity excludes docs/heartbeat, includes configuration: OK'
}

test_checksum_markers() {
    local bin="$temporary/checksums" unix windows
    mkdir -p "$bin"
    export REAL_SHA256SUM
    REAL_SHA256SUM=$(command -v sha256sum)
    cp "$ROOT/tests/mock-sha256sum.sh" "$bin/sha256sum"
    chmod +x "$bin/sha256sum"
    unix=$(PATH="$bin:$PATH" MOCK_CHECKSUM_MARKER=' ' bash "$ROOT/scripts/identity.sh")
    windows=$(PATH="$bin:$PATH" MOCK_CHECKSUM_MARKER='*' bash "$ROOT/scripts/identity.sh")
    [[ $unix == "$digest" && $windows == "$digest" ]]
    echo 'Recipe identity is independent of Unix/MSYS2 checksum markers: OK'
}

test_checkout_line_endings() {
    local checkout="$temporary/checkout" object
    git init -q "$checkout"
    cp "$ROOT/.gitattributes" "$checkout/"
    object=$(printf 'recipe\n' | git -C "$checkout" hash-object -w --stdin)
    git -C "$checkout" -c core.autocrlf=true -c core.eol=crlf \
        cat-file --filters --path=scripts/recipe.sh "$object" > "$temporary/filtered.sh"
    cmp "$temporary/filtered.sh" <(printf 'recipe\n')
    echo 'Recipe checkout retains LF even with Windows CRLF defaults: OK'
}

test_native_jq_output() {
    local bin="$temporary/native-jq" unfixed fixed platform
    mkdir -p "$bin"
    export REAL_JQ
    REAL_JQ=$(type -P jq)
    cp "$ROOT/tests/mock-jq.sh" "$bin/jq"
    cp "$ROOT/tests/mock-uname.sh" "$bin/uname"
    chmod +x "$bin/jq" "$bin/uname"
    unfixed=$(PATH="$bin:$PATH" command jq -r .digest "$temporary/prepared/build.json")
    [[ $unfixed == "$digest"$'\r' ]]
    for platform in MINGW64_NT-10.0 MSYS_NT-10.0 CYGWIN_NT-10.0; do
        fixed=$(PATH="$bin:$PATH" MOCK_UNAME="$platform" bash -c \
            'source "$1"; jq -r .digest "$2"' \
            bash "$ROOT/scripts/common.sh" "$temporary/prepared/build.json")
        [[ $fixed == "$digest" ]]
    done
    for platform in Linux Darwin; do
        fixed=$(PATH="$bin:$PATH" MOCK_UNAME="$platform" MOCK_JQ_PLATFORM=unix bash -c \
            'source "$1"; jq -r .digest "$2"' \
            bash "$ROOT/scripts/common.sh" "$temporary/prepared/build.json")
        [[ $fixed == "$digest" ]]
    done
    echo 'Windows jq.exe uses binary output; Unix jq needs no binary option: OK'
}

test_read_only_push() {
    local directory=$1 bin="$temporary/push-bin"
    mkdir -p "$bin"
    cp "$ROOT/tests/mock-git.sh" "$bin/git"
    chmod +x "$bin/git"
    : > "$MOCK_LOG"
    if GITHUB_EVENT_NAME=push bash "$ROOT/scripts/publish.sh" "$directory" \
        > "$temporary/push-publication.log" 2>&1; then
        fail 'Push event must not publish a release'
    fi
    grep -q 'Publication requires a scheduled or manual run' "$temporary/push-publication.log"
    if PATH="$bin:$PATH" GITHUB_EVENT_NAME=push bash "$ROOT/scripts/keepalive.sh" "$upstream" \
        > "$temporary/push-keepalive.log" 2>&1; then
        fail 'Push event must not write sync status'
    fi
    grep -q 'Untrusted keepalive event' "$temporary/push-keepalive.log"
    [[ ! -s $MOCK_LOG ]]
    echo 'Push events cannot publish releases or update sync status: OK'
}

test_source_archive() {
    local source="$temporary/source fixture/libpldm" archive="$temporary/source.tar.gz" target
    mkdir -p "$source/scripts" "$source/docs/checklists" "$source/.git" "$temporary/extracted"
    # Deliberately create the link before its target, matching the failing dump.
    ln -s pre-submit "$source/scripts/run-ci"
    printf '#!/bin/sh\nprintf "upstream CI fixture\\n"\n' > "$source/scripts/pre-submit"
    chmod +x "$source/scripts/pre-submit"
    ln -s ../../CONTRIBUTING.md "$source/docs/checklists/changes.md"
    printf 'contributor fixture\n' > "$source/CONTRIBUTING.md"
    printf 'Git metadata fixture\n' > "$source/.git/config"
    bash "$ROOT/scripts/archive-source.sh" "$source" "$archive"
    tar -tvzf "$archive" > "$temporary/source-listing.txt"
    if grep -Eq '^[lh]' "$temporary/source-listing.txt"; then
        fail 'Source archive still requires symlink or hardlink extraction'
    fi
    tar -xzf "$archive" -C "$temporary/extracted"
    cmp "$source/scripts/pre-submit" "$temporary/extracted/libpldm/scripts/run-ci"
    cmp "$source/CONTRIBUTING.md" "$temporary/extracted/libpldm/docs/checklists/changes.md"
    [[ -x $temporary/extracted/libpldm/scripts/run-ci ]]
    [[ ! -e $temporary/extracted/libpldm/.git ]]
    printf 'outside fixture\n' > "$temporary/outside.txt"
    for target in missing "$temporary/outside.txt" scripts .git/config; do
        ln -s "$target" "$source/invalid"
        if bash "$ROOT/scripts/archive-source.sh" "$source" "$temporary/invalid.tar.gz" \
            > "$temporary/invalid-source.log" 2>&1; then
            fail "Unsafe source symlink was accepted: $target"
        fi
        [[ ! -e $temporary/invalid.tar.gz ]]
        rm -- "$source/invalid"
    done
    echo 'Source archives materialize forward file links without Git metadata or unsafe targets: OK'
}

make_test_assets() {
    local directory=$1 target name
    cp "$temporary/prepared/build.json" "$directory/"
    for target in linux-x86_64 windows-x86_64 macos-arm64 macos-x86_64; do
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
    test_read_only_push "$directory"
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
    mv "$directory/libpldm-$identity-linux-x86_64.tar.gz" "$temporary/withheld.tar.gz"
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
test_checksum_markers
test_checkout_line_endings
test_native_jq_output
test_source_archive
test_publication
test_keepalive
