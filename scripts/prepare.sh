#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail
source "$(dirname "$0")/common.sh"
source "$ROOT/scripts/releases.sh"

resolve() {
    local commit
    commit=$(git ls-remote https://github.com/openbmc/libpldm.git refs/heads/main | cut -f1)
    [[ $commit =~ ^[0-9a-f]{40}$ ]] || fail 'Cannot resolve upstream main'
    output upstream "$commit"
}

make_metadata() {
    local commit=$1 destination=$2 digest identity tag assets
    digest=$(bash "$ROOT/scripts/identity.sh")
    identity="$commit-$digest"
    tag="build-$identity-r${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}"
    assets=$(jq -cn --arg id "$identity" '[
        "libpldm-\($id)-windows-x86_64.tar.gz",
        "libpldm-\($id)-macos-arm64.tar.gz",
        "libpldm-\($id)-macos-x86_64.tar.gz",
        "libpldm-\($id)-source.tar.gz", "libpldm-\($id)-recipe.tar.gz",
        "build.json", "SHA256SUMS"]')
    jq -n --arg upstream "$commit" --arg automation "${GITHUB_SHA:-$(git -C "$ROOT" rev-parse HEAD)}" \
        --arg digest "$digest" --arg identity "$identity" --arg tag "$tag" \
        --argjson assets "$assets" --arg recipe "$RECIPE_REVISION" \
        '{upstream: $upstream, automation: $automation, digest: $digest,
          identity: $identity, attempt_tag: $tag, assets: $assets, recipe_revision: $recipe}' \
        > "$destination/build.json"
    output identity "$identity"
}

prepare() {
    local commit=$1 destination=$2 identity assets existing
    mkdir -p "$destination"
    destination=$(cd "$destination" && pwd)
    make_metadata "$commit" "$destination"
    identity=$(jq -r .identity "$destination/build.json")
    assets=$(jq -c .assets "$destination/build.json")
    if [[ ${PUBLISH_ALLOWED:-false} == true && ${FORCE_REBUILD:-false} != true ]]; then
        stage 'Check complete published identities'
        release_json > "$destination/releases.json"
        existing=$(complete_release "$destination/releases.json" "$identity" "$assets" || true)
        if [[ -n $existing ]]; then
            output skip true
            echo "Complete identity already published: $existing" >> "$GITHUB_STEP_SUMMARY"
            return
        fi
    fi
    output skip false
    bash "$ROOT/scripts/source.sh" "$commit" "$destination/libpldm"
    stage 'Archive reproducible source and recipe'
    bash "$ROOT/scripts/archive-source.sh" "$destination/libpldm" \
        "$destination/libpldm-$identity-source.tar.gz"
    tar -czf "$destination/libpldm-$identity-recipe.tar.gz" -C "$ROOT" \
        patches scripts config tests .github .gitattributes README.md LICENSE
    (cd "$destination" && sha256 libpldm-*.tar.gz build.json > preparation.sha256)
}

case ${1:-} in
    resolve) stage 'Resolve upstream main'; resolve ;;
    prepare) prepare "$2" "$3" ;;
    *) fail 'Usage: prepare.sh resolve | prepare COMMIT DESTINATION' ;;
esac
