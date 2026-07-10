# Changelog

All notable changes to this fork are documented here. This is the playtini fork of
[anothrNick/github-tag-action](https://github.com/anothrNick/github-tag-action); entries
below describe changes relative to the fork, not upstream.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## 2026-07-10

### Fixed — hardening picked from upstream (`entrypoint.sh`)

These are correctness/robustness fixes cherry-picked from upstream. None of them change
this fork's tagging behavior (every tag still carries the `-$SUFFIX` suffix, default
`master`); they only harden the git plumbing around it.

- **Mark the workspace as a safe Git directory.** Added
  `git config --global --add safe.directory /github/workspace`. Since the
  [April 2022 Git security fix](https://github.blog/2022-04-12-git-security-vulnerability-announced/),
  Git refuses to operate on a repository owned by a different user ("detected dubious
  ownership"). Inside the Docker action the workspace is owned by a different UID, so
  without this line the action can fail at its first `git` command on modern runners.
- **Pipefail-safe tag lookup.** The latest tag is now found by collecting the git refs
  once into a variable and matching with `grep -E "$tagFmt" || true`, with `head` reading
  from a here-string instead of a pipe. Previously the `git for-each-ref | grep | head`
  pipeline could surface a spurious failure under `set -o pipefail` (SIGPIPE when `head`
  closes the pipe early). This also removes a redundant second `git for-each-ref`/`git tag`
  invocation that computed the identical value.
- **Guard tag lookup on a fresh repo.** `tag_commit=$(git rev-list -n 1 "$tag" || true)`
  no longer aborts the script when there are no tags yet, and `"$tag"` is now quoted.
