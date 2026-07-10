#!/usr/bin/env bats
#
# Minimal smoke tests for entrypoint.sh (this fork's -SUFFIX tagging model).
# Runs the action with DRY_RUN=true so nothing is pushed. Expandable — add cases here.
#
# Requires: bats, git, jq, semver on PATH. Run with: bats test/

setup() {
    ENTRYPOINT="${BATS_TEST_DIRNAME}/../entrypoint.sh"
    REPO="$(mktemp -d)"
    OUTPUT="$(mktemp)"
    cd "$REPO"
    git init -q
    git config user.email test@example.com
    git config user.name test
    git commit -q --allow-empty -m "initial commit"
}

teardown() {
    rm -rf "$REPO" "$OUTPUT"
}

# run the action against the temp repo; any extra args become env-var assignments
run_action() {
    env GITHUB_WORKSPACE="$REPO" GITHUB_OUTPUT="$OUTPUT" DRY_RUN=true VERBOSE=false \
        "$@" bash "$ENTRYPOINT"
}

@test "no existing tag: default minor bump from initial version" {
    run_action
    grep -qx 'new_tag=0.1.0-master' "$OUTPUT"
}

@test "#patch token bumps the patch component" {
    git tag 1.2.3-master
    git commit -q --allow-empty -m "a fix #patch"
    run_action
    grep -qx 'new_tag=1.2.4-master' "$OUTPUT"
}

@test "#none token skips the bump and keeps the current tag" {
    git tag 1.2.3-master
    git commit -q --allow-empty -m "chore #none"
    run_action
    grep -qx 'new_tag=1.2.3-master' "$OUTPUT"
}

@test "old_tag output reports the previous tag" {
    git tag 1.2.3-master
    git commit -q --allow-empty -m "a fix #patch"
    run_action
    grep -qx 'old_tag=1.2.3-master' "$OUTPUT"
}

@test "custom MINOR_STRING_TOKEN is honored" {
    git tag 2.0.0-master
    git commit -q --allow-empty -m "feature ::minor::"
    run_action MINOR_STRING_TOKEN='::minor::'
    grep -qx 'new_tag=2.1.0-master' "$OUTPUT"
}
