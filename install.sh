#!/bin/sh
# install.sh -- symlink the git-* commands onto your PATH.
#
#   ./install.sh [BIN_DIR]     # default BIN_DIR = ~/.local/bin
#
# After this, `git set-base` / `git base` work globally. Then run
# `git base install` inside any repo to wire up its hooks.
set -eu

here=$(CDPATH= cd -- "$(dirname -- "$(readlink -f -- "$0" 2>/dev/null || printf '%s' "$0")")" && pwd)
dest=${1:-$HOME/.local/bin}
src="$here/base/bin"

mkdir -p "$dest"
for f in git-set-base git-base git-base-install; do
	ln -sf "$src/$f" "$dest/$f"
	printf 'linked %s -> %s\n' "$dest/$f" "$src/$f"
done

case ":$PATH:" in
*":$dest:"*) ;;
*) printf '\nNOTE: %s is not on your PATH; add it so git can find the commands.\n' "$dest" ;;
esac
printf '\nNext: cd into a repo and run `git base install` to wire up its hooks.\n'
