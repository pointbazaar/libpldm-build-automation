#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail
source "$(dirname "$0")/common.sh"
source "$ROOT/scripts/releases.sh"
TARGET=publication
directory=$(cd "$1" && pwd)
metadata="$directory/build.json"
identity=$(jq -r .identity "$metadata")
automation=$(jq -r .automation "$metadata")
tag=$(jq -r .attempt_tag "$metadata")
expected=$(jq -c .assets "$metadata")

check_trust() {
    [[ ${GITHUB_EVENT_NAME:-} == schedule || ${GITHUB_EVENT_NAME:-} == workflow_dispatch ]] \
        || fail 'Publication requires a scheduled or manual run'
    [[ $GITHUB_REF == "refs/heads/$DEFAULT_BRANCH" ]] || fail 'Publish only from the default branch'
    [[ $automation == "$GITHUB_SHA" ]] || fail 'Automation revision mismatch'
    [[ $identity =~ ^[0-9a-f]{40}-[0-9a-f]{64}$ ]] || fail 'Invalid build identity'
    [[ $tag =~ ^build-$identity-r[0-9]+-[0-9]+$ ]] || fail 'Invalid release tag'
}

validate_assets() {
    local file target
    for target in windows-x86_64 macos-arm64 macos-x86_64; do
        file="$directory/libpldm-$identity-$target.tar.gz"
        [[ -s $file ]] || fail "Missing target: $target"
        # Read just JSON, never execute scripts supplied by a build artifact.
        tar -xOf "$file" "libpldm-$identity-$target/share/libpldm/build/identity.json" \
            | jq -e --arg id "$identity" --arg rev "$automation" \
                '.identity == $id and .automation == $rev' > /dev/null
        tar -xOf "$file" "libpldm-$identity-$target/share/libpldm/build/target.json" \
            | jq -e --arg target "$target" '.target == $target' > /dev/null
    done
    [[ -s $directory/libpldm-$identity-source.tar.gz ]]
    [[ -s $directory/libpldm-$identity-recipe.tar.gz ]]
    (cd "$directory" && sha256sum libpldm-*.tar.gz build.json > SHA256SUMS)
    diff -u <(jq -r '.assets[]' "$metadata" | sort) \
        <(find "$directory" -maxdepth 1 -type f -printf '%f\n' | sort)
}

publish() {
    local releases notes draft existing
    releases=$(mktemp)
    notes=$(mktemp)
    release_json > "$releases"
    if [[ ${FORCE_REBUILD:-false} != true ]]; then
        existing=$(complete_release "$releases" "$identity" "$expected" || true)
        if [[ -n $existing ]]; then
            echo "Already published: $existing"
            return
        fi
    fi
    printf 'Unofficial downstream build of upstream development sources.\n\nBuild identity: %s\nAutomation revision: %s\nUpstream commit: %s\n\nAll three native targets passed tests and relocated-package smoke checks.\nSee build metadata for toolchain, baseline and ABI limitations.\n' \
        "$identity" "$automation" "$(jq -r .upstream "$metadata")" > "$notes"
    draft=$(jq -r --arg id "$identity" --arg rev "$automation" '
        [.[] | select(.draft and .target_commitish == $rev)
         | select(.body | contains("Build identity: " + $id + "\n"))]
        | first | .tag_name // empty' "$releases")
    if [[ -n $draft ]]; then
        tag=$draft
        gh release edit "$tag" --notes-file "$notes" --repo "$GITHUB_REPOSITORY"
    else
        gh release create "$tag" --draft --target "$automation" \
            --title "Unofficial libpldm ${identity:0:12} / ${identity:41:12}" \
            --notes-file "$notes" --repo "$GITHUB_REPOSITORY"
    fi
    gh release upload "$tag" "$directory"/* --clobber --repo "$GITHUB_REPOSITORY"
    verify_uploaded_assets "$tag" "$directory"
    gh release edit "$tag" --draft=false --latest --repo "$GITHUB_REPOSITORY"
    echo "Published complete downstream build: $tag" >> "$GITHUB_STEP_SUMMARY"
}

stage 'Validate publication trust and complete local asset set'
check_trust
validate_assets
stage 'Upload, verify draft, then publish and advance latest'
publish
