# base-common.sh -- shared helpers for the BASE ref extension.
# Sourced by git-set-base and git-base. POSIX sh.
#
# Concept: every branch has a "base" -- the commit it forks from. It is stored
# as a real ref refs/base/<branch> (mirrors refs/heads/<branch>). A per-worktree
# symbolic pseudoref BASE points at refs/base/<current-branch>, so `git rev-parse
# BASE`, `git log BASE..HEAD`, etc. resolve to the current branch's base.

BASE_VERSION=1

# Absolute path of the bin/ directory of the script that sourced us, with
# symlinks resolved. Lets us locate sibling tools (git-base) without PATH.
BASE_BIN=$(CDPATH= cd -- "$(dirname -- "$(readlink -f -- "$0" 2>/dev/null || printf '%s' "$0")")" && pwd)
BASE_WORKER="$BASE_BIN/git-base"

# --- logging -----------------------------------------------------------------
# Hook background jobs are detached, so their only channel to the user is the
# journal. Fall back to a repo-local logfile when logger is unavailable.
base_log() {
	_lvl=$1
	shift
	if command -v logger >/dev/null 2>&1; then
		logger -t git-base -p "user.$_lvl" -- "$*"
	else
		_lf=$(git rev-parse --git-path base.log 2>/dev/null) || _lf=/dev/null
		printf '%s [%s] %s\n' "$(date '+%F %T' 2>/dev/null)" "$_lvl" "$*" >>"$_lf" 2>/dev/null || true
	fi
}

base_die() {
	printf 'git-base: %s\n' "$*" >&2
	exit 1
}

# --- repo / ref primitives ---------------------------------------------------
base_require_repo() {
	git rev-parse --git-dir >/dev/null 2>&1 || base_die "not a git repository"
}

# Short name of the current branch; empty string when HEAD is detached.
base_current_branch() {
	git symbolic-ref --quiet --short HEAD 2>/dev/null || true
}

# True when $1 is a non-empty all-zero object id (sha1 or sha256) -- i.e. the
# "null" side of a ref creation (old) or deletion (new).
base_is_zero_oid() {
	case "$1" in
	'' | *[!0]*) return 1 ;;
	*) return 0 ;;
	esac
}

# Resolve a committish to a full commit oid, or return non-zero.
base_resolve_commit() {
	git rev-parse --verify --quiet "$1^{commit}" 2>/dev/null
}

# Write refs/base/<branch> = <oid>. Honors base.reflog for per-ref history.
base_write_ref() {
	if [ "$(git config --bool base.reflog 2>/dev/null)" = true ]; then
		git update-ref --create-reflog "refs/base/$1" "$2"
	else
		git update-ref "refs/base/$1" "$2"
	fi
}

base_del_ref() {
	git rev-parse --verify --quiet "refs/base/$1" >/dev/null 2>&1 || return 0
	git update-ref -d "refs/base/$1"
}

# Delete the per-worktree BASE pseudoref. Used whenever we can't confidently
# point it at a valid base, so BASE never resolves to an unexpected ref.
base_clear() {
	git symbolic-ref -d BASE 2>/dev/null ||
		git update-ref -d BASE 2>/dev/null || true
}

# Point the per-worktree BASE at refs/base/<branch> if that ref exists,
# otherwise clear BASE. Defaults to the current branch.
base_repoint() {
	_br=${1:-$(base_current_branch)}
	if [ -n "$_br" ] && git rev-parse --verify --quiet "refs/base/$_br" >/dev/null 2>&1; then
		git symbolic-ref BASE "refs/base/$_br"
	else
		base_clear
	fi
}

# Clear BASE if it is symbolic but its target ref no longer resolves. Covers
# e.g. `git branch -m`, which deletes refs/base/<old> but fires no checkout.
base_fix_dangling() {
	_t=$(git symbolic-ref --quiet BASE 2>/dev/null) || return 0
	git rev-parse --verify --quiet "$_t" >/dev/null 2>&1 || base_clear
}

# --- background offload ------------------------------------------------------
# Run a worker action fully detached (new session, fds closed) so a slow or
# failing job can never stall or abort the git command that triggered the hook.
# GIT_DIR is pinned to this worktree's gitdir so BASE lands in the right place.
base_spawn() {
	_gd=$(git rev-parse --absolute-git-dir 2>/dev/null) || return 0
	if command -v setsid >/dev/null 2>&1; then
		GIT_DIR=$_gd setsid "$BASE_WORKER" _worker "$@" </dev/null >/dev/null 2>&1 &
	else
		GIT_DIR=$_gd "$BASE_WORKER" _worker "$@" </dev/null >/dev/null 2>&1 &
	fi
}
