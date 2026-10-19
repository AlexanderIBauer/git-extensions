# base — a `BASE` ref for git

Adds the notion of a branch's **base**: the commit it forks from. It is stored
the way git stores everything else — as refs — so it works with `rev-parse`,
`log`, `for-each-ref`, gc protection, worktrees, and the reflog.

```
refs/base/<branch>   the base commit of each branch   (mirrors refs/heads/<branch>)
BASE                 per-worktree symbolic ref -> refs/base/<current branch>
```

`BASE` behaves like `HEAD`: it is scoped to each worktree, so `git rev-parse
BASE`, `git log BASE..HEAD`, and `git diff BASE...HEAD` always talk about the
current branch's own commits.

## Install

```sh
../install.sh                 # symlink git-set-base / git-base into ~/.local/bin
cd /path/to/some/repo
git base install              # wire up this repo's hooks
```

`git base install` options:

- `--reflog` — record `refs/base/*` history, so `git reflog refs/base/<branch>`
  shows every base change (off by default; uses per-ref `--create-reflog`).
- `--seed` — set the current branch's base to `HEAD` right now.

Existing hooks are preserved: a foreign `post-checkout` etc. is moved to
`<hook>.local` and chained. `git base uninstall` restores them.

## Usage

Set / fix bases (the base is static — set it once; these are for corrections):

```sh
git set-base                   # base(current) = HEAD
git set-base <ref>             # base(current) = <ref>
git set-base <branch> <ref>    # base(<branch>) = <ref>
git set-base -d <branch>       # delete a branch's base
git set-base --unset           # delete current branch's base and clear BASE
git set-base -l                # list all bases
```

Inspect:

```sh
git base                       # current branch, its base, commits ahead
git base list                  # every refs/base/* (? marks an orphaned base)
```

Use it:

```sh
git log --oneline BASE..HEAD   # just this branch's commits
git diff BASE...HEAD           # this branch's changes vs its fork point
git rebase -i BASE             # reshape only your own commits
```

## When the base moves on its own

The hooks maintain bases automatically: a branch is based when created, re-based
when you `git rebase` onto a different commit, carried across a `git branch -m`
rename, and dropped when the branch is deleted. Merges, commits, resets and
in-place `rebase -i` leave it alone.

The full, tested matrix of every git operation is in
[`docs/hook-scenarios.md`](docs/hook-scenarios.md).

## Layout

```
base/
  bin/git-set-base      set/fix a branch's base
  bin/git-base          inspect, install, hook dispatch, worker
  bin/git-base-install  alias for `git base install`
  lib/base-common.sh    shared helpers
  docs/hook-scenarios.md behavior matrix + safety notes
```

## Requirements

POSIX `sh`, git ≥ 2.28 (for the `reference-transaction` hook; developed on
2.56). `setsid` and `logger` are used when present for safe backgrounding and
journal logging, with graceful fallbacks.

## Uninstall

```sh
git base uninstall             # per repo: remove hooks, restore chained ones
```

Refs are left intact; remove them with `git set-base --unset` or
`git update-ref -d refs/base/<branch>` and `git update-ref -d BASE`.
