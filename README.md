Personal git extensions — custom commands, refs, and hooks.

Each top-level directory is a self-contained, independently installable
extension named for what it does.

## Extensions

- [**base**](base/) — a `BASE` ref for git: tracks the commit each branch forks
  from as `refs/base/<branch>`, with a per-worktree `BASE` pointer (like `HEAD`)
  and hooks that keep it current. See [base/README.md](base/README.md).

## Install

Put the commands on your `PATH`, then enable per repo:

```sh
./install.sh                   # symlink git-* commands into ~/.local/bin
cd /path/to/repo && git base install
```

Or set it up once for every repo (per user or machine-wide) with
`git base install --global` / `--system`; see [base/README.md](base/README.md).
