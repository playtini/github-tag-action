# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A **Docker-based GitHub Action** that bumps and pushes a SemVer git tag on push/merge. This is the **playtini fork** of `anothrNick/github-tag-action`. All logic lives in a single bash script; there is no build step and no test suite.

- `entrypoint.sh` — the entire action logic (bash).
- `Dockerfile` — Alpine image; installs `bash git curl jq nodejs npm` and `npm install -g semver`. The `semver` CLI does the version math.
- `action.yml` — action metadata; `using: docker`, `image: Dockerfile`. Declares outputs `new_tag`, `tag`, `part`.
- `.github/workflows/main.yml` — dogfoods the action: on push to `master`, runs `anothrNick/github-tag-action@master` to tag itself.

## Changelog convention

Record every notable change in `CHANGELOG.md` (Keep a Changelog format). Changes are pushed
the same day they are made, so add entries under a heading for the **current date**
(`## YYYY-MM-DD`) — there is no `[Unreleased]` section. Entries describe changes relative to
this fork, not upstream. Add the changelog entry in the same change that makes the code
change — don't leave it for later.

## Fork divergence — read before editing `entrypoint.sh`

**The README documents upstream behavior, NOT this fork's actual behavior.** The `entrypoint.sh` here differs from what the README describes:

- Uses a `SUFFIX` env var (default `master`), **not** the upstream `PRERELEASE_SUFFIX`.
- **Every** new tag gets `-$suffix` appended unconditionally (`new=$new-$suffix`), regardless of branch. There is no release-vs-prerelease branch logic in this fork despite `RELEASE_BRANCHES` still being read into a variable.
- Tag discovery only matches tags of the form `^v?[0-9]+\.[0-9]+\.[0-9]+(-$suffix)$` — tags without the suffix are invisible to it.

When changing tagging logic, treat `entrypoint.sh` as the source of truth and keep the README in mind as potentially stale.

## Control flow of `entrypoint.sh`

1. Read config from env vars (all have defaults except `GITHUB_TOKEN`).
2. `git fetch --tags`, then find the latest matching tag via `git for-each-ref` (`TAG_CONTEXT=repo`, default) or `git tag --merged HEAD` (`TAG_CONTEXT=branch`).
3. If no tag found, start at `INITIAL_VERSION` (default `0.0.0`).
4. If `HEAD` is already the tagged commit → exit early, emit `tag` output only.
5. Choose bump from commit-message keywords `#major` / `#minor` / `#patch` / `#none`, else fall back to `DEFAULT_BUMP` (default `minor`). `#none` or `DEFAULT_BUMP=none` skips.
6. Compute `new` with the `semver` CLI, append `-$suffix`, optionally prefix `v` (`WITH_V=true`), or override entirely with `CUSTOM_TAG`.
7. Write outputs to `$GITHUB_OUTPUT` (`new_tag`, `part`, `tag`).
8. Unless `DRY_RUN=true`: create a local lightweight tag and POST it to the GitHub refs API (`git_refs_url` pulled from `$GITHUB_EVENT_PATH` via `jq`), using `curl` + `$GITHUB_TOKEN`. Verify the response ref matches.

Outputs are emitted via `>> $GITHUB_OUTPUT` (migrated from the deprecated `::set-output`; do not reintroduce `::set-output`).

## Testing changes

**Automated:** `test/smoke.bats` runs the entrypoint (in `DRY_RUN`) against throwaway git
repos and asserts the emitted outputs. It runs in CI via `.github/workflows/test.yml` on
every push/PR. To run locally you need `bats`, `git`, `jq`, and `semver` on PATH, then:

```bash
bats test/
```

Each case must create its repo under `mktemp -d` and `cd` into it (with a hard failure
guard) — the script issues real `git commit`/`git tag` calls, so a failed `cd` would run
them against this repo. Set `HOME` to a temp dir per case so the entrypoint's
`git config --global` doesn't touch your real `~/.gitconfig`.

**Manual:** run the container against a real (or throwaway) git repo with env set, e.g.:

```bash
docker build -t github-tag-action .
docker run --rm \
  -e GITHUB_TOKEN=... -e GITHUB_WORKSPACE=/repo -e DRY_RUN=true \
  -v "$PWD":/repo github-tag-action
```

Use `DRY_RUN=true` to see the computed tag without pushing. `VERBOSE=true` (default) prints git logs.
