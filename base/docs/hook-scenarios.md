# BASE behavior matrix

What happens to a branch's base ref (`refs/base/<branch>`) and to the
per-worktree `BASE` pointer under each git operation. Every row marked
**[tested]** was verified against git 2.56 in the integration tests.

**Actions**

| Action | Meaning |
| --- | --- |
| **init** | create `refs/base/<branch>` at the branch's start commit |
| **move** | change `refs/base/<branch>` to a new commit |
| **delete** | remove `refs/base/<branch>` |
| **leave** | no change |
| **repoint** | point `BASE` → `refs/base/<current branch>` |
| **clear** | delete the `BASE` pseudoref (so it never resolves to an unexpected ref) |

**Model.** A base is the commit a branch *forks from*. It is **static**: it is
fixed when the branch is created and only changes on an explicit `git set-base`
or on a **rebase that re-bases the branch onto a different commit**. Merges,
commits, resets, amends and in-place interactive rebases never move it.

---

## Everyday operations

| Scenario | Command | Hook | `refs/base/<branch>` | `BASE` |
| --- | --- | --- | --- | --- |
| First commit (unborn branch) | `git commit` | reference-transaction (create) | **init** = that commit | **repoint** [tested] |
| Normal commit | `git commit` | reference-transaction (update) | leave | leave [tested] |
| Amend | `git commit --amend` | post-rewrite `amend` | leave | leave [tested] |
| Create branch, no switch | `git branch foo [<start>]` | reference-transaction (create) | **init** `foo` = start | leave [tested] |
| Create + switch | `git switch -c foo` / `git checkout -b foo` / `git worktree add -b foo` | reference-transaction + post-checkout | **init** `foo` | **repoint** → `foo` [tested] |
| Switch branch | `git switch bar` / `git checkout bar` | post-checkout (flag 1) | leave | **repoint** → `bar`, or **clear** if `bar` has no base [tested] |
| Checkout files only | `git checkout -- <path>` / `git checkout <c> -- <path>` | post-checkout (flag 0) | leave | leave [tested] |
| Restore | `git restore <path>` | none | leave | leave |
| Delete branch | `git branch -d/-D foo` | reference-transaction (`new=0`) | **delete** `foo` | fix if dangling [tested] |
| Rename branch | `git branch -m old new` | reference-transaction (`new=0` for `old`) | **carry** `base(old)` → `new`, then **delete** `base(old)` | **repoint** → `new` if it's current [tested] |
| Merge (into current) | `git merge X` | reference-transaction (update) | leave | leave [tested] |
| Fast-forward / pull | `git pull` | reference-transaction (update) | leave | leave |
| Reset | `git reset [--hard] <c>` | reference-transaction (update) | leave | leave [tested] |
| Cherry-pick / revert | `git cherry-pick` / `git revert` | reference-transaction (update) | leave | leave |
| Stash | `git stash` | (uses `refs/stash`) | leave | leave |
| Fetch | `git fetch` | (updates `refs/remotes/*`) | leave | leave |
| Tag / note | `git tag` / `git notes` | (updates `refs/tags/*`, `refs/notes/*`) | leave | leave |
| Clone | `git clone` | reference-transaction + post-checkout | **init** default branch = clone tip | **repoint** |

Only `refs/heads/*` updates are considered; everything under `refs/remotes/*`,
`refs/tags/*`, `refs/stash`, `refs/base/*`, `HEAD`, `AUTO_MERGE`, etc. is ignored.

## Rebase family

A rebase replays commits and reports old→new pairs via `post-rewrite`. The base
moves **only when the onto-point changed** — computed as `parent(oldest-old)` vs
`parent(oldest-new)`. A rebase always detaches HEAD onto the target (which fires
`post-checkout` and clears `BASE`) and fires no checkout on re-attach, so
`post-rewrite` always **repoints** `BASE` afterward.

| Scenario | Command | Onto-point | `refs/base/<branch>` | `BASE` |
| --- | --- | --- | --- | --- |
| Rebase onto new upstream | `git rebase main` / `git pull --rebase` | changed | **move** → new onto | repoint [tested] |
| In-place interactive (reword/edit/squash/reorder/drop) | `git rebase -i HEAD~n` | same | leave | repoint [tested] |
| Interactive with new target | `git rebase -i --onto X A..B` | changed | **move** → `X` | repoint [tested] |
| Up to date / no-op | `git rebase main` (nothing to do) | — (no rewrite) | leave | leave [tested] |
| Root rebase | `git rebase --root` | undeterminable | leave (logged) | repoint |

## HEAD and worktree states

| Scenario | Command | `refs/base/<branch>` | `BASE` |
| --- | --- | --- | --- |
| Detach HEAD | `git checkout <sha>` / `git switch --detach` | leave | **clear** [tested] |
| Re-attach to a branch | `git switch <branch>` | leave | **repoint** (or clear) [tested] |
| Add worktree on existing branch | `git worktree add <path> <branch>` | leave | **repoint** in the new worktree [tested] |
| Two worktrees, different branches | — | leave | independent per worktree [tested] |

`BASE` lives in each worktree's own git dir (like `HEAD`), so every worktree
tracks the base of *its* current branch independently.

## Manual `git set-base`

| Command | `refs/base/<branch>` | `BASE` |
| --- | --- | --- |
| `git set-base` | current = HEAD | repoint [tested] |
| `git set-base <ref>` | current = `<ref>` | repoint [tested] |
| `git set-base <branch> <ref>` | `<branch>` = `<ref>` | repoint **iff** `<branch>` is current [tested] |
| `git set-base -d <branch>` | **delete** `<branch>` | clear iff `<branch>` is current |
| `git set-base --unset` | **delete** current | clear [tested] |
| `git set-base -l` / `--list` | — (lists all) | leave |

## Branch rename

`git branch -m old new` is handled specially. git reports it as a *deletion* of
`old` (with `old=<its tip>`) and silently creates `new` at that same tip with
**no creation event**. So when the delete worker fires, it:

1. reads `base(old)` (still present — only this worker removes it);
2. finds every branch now sitting at `old`'s tip that has **no base of its own**
   — the renamed `new` among them — and gives each `base(old)`;
3. deletes `base(old)`;
4. if the renamed branch is the current one, repoints `BASE` to it.

So a rename preserves the base and keeps `BASE` valid, with no manual step.
[tested, incl. renaming both the current and a non-current branch]

A plain `git branch -D` reports `old=0` (no tip), so this carry never fires for
a real deletion.

## Known limitations

| Case | Behavior | Recovery |
| --- | --- | --- |
| **`git branch -c old new` (copy)** | like rename the copy fires no creation event, but unlike rename there is no deletion either, so nothing triggers a base for the copy | `git set-base <copy> <ref>` |
| **`rebase --root`** | onto-point can't be derived (oldest commit has no parent); base left unchanged and a note is logged | `git set-base` if needed |
| **Non-rebase history rewrites** (`filter-branch`, `git-filter-repo`, BFG) | no `post-rewrite` event fires, so bases become stale | `git set-base` per branch |
| **Reset below the base** | base is left as-is and can end up *ahead* of HEAD (`git log BASE..HEAD` empty); intentional — reset does not move the base | `git set-base` if you want it moved |
| **Pre-existing branches at install time** | not fabricated; they have no base until re-checked-out or set manually | `git set-base`, or `git base install --seed` for the current branch |

## Safety

The `reference-transaction` hook runs on **every** ref write and, if it exited
non-zero in the prepared phase, would abort the whole transaction — blocking
commits, branches, everything. To make that impossible:

- the hook only acts in the **committed** phase and **always exits 0**;
- all ref writing happens in a **detached background worker** (`setsid`, stdin
  and output closed) that cannot stall or fail the triggering git command —
  verified: with the worker binary removed entirely, `git commit` still succeeds;
- worker errors go to the **systemd journal** (`logger -t git-base`), falling
  back to `$GIT_DIR/base.log`;
- when a base can't be determined or its ref is gone, `BASE` is **cleared**
  rather than left pointing at an unexpected ref.
