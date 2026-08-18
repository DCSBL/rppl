#!/usr/bin/env bash
# Move the current rppl feature worktree into the main checkout.
#
# Usage (from any worktree):
#   tools/worktree-to-main.sh
#   RPPL_MAIN_DIR=~/Development/rppl tools/worktree-to-main.sh
#   tools/worktree-to-main.sh --dry-run
#   tools/worktree-to-main.sh --keep-worktree
#
# Dirty main → stashed as "worktree-to-main:main-backup" (not auto-restored).
# Dirty worktree → stashed, then popped onto the branch in main.

set -euo pipefail

MAIN_DIR="${RPPL_MAIN_DIR:-/Users/ducosebel/Development/rppl}"
KEEP_WORKTREE=false
DRY_RUN=false

WORKTREE_STASH_MSG="worktree-to-main:from-worktree"
MAIN_STASH_MSG="worktree-to-main:main-backup"

usage() {
  cat <<'EOF'
Usage: worktree-to-main.sh [options]

Move the current feature worktree branch and working tree into the main rppl
checkout (default: ~/Development/rppl).

Options:
  --main-dir PATH     Main checkout path (default: RPPL_MAIN_DIR or ~/Development/rppl)
  --keep-worktree     Leave the worktree directory; detach HEAD instead of removing
  --dry-run           Print actions without changing anything
  -h, --help          Show this help

Environment:
  RPPL_MAIN_DIR       Override main checkout path

Examples:
  cd ~/Development/rppl-map-fit && tools/worktree-to-main.sh
  ~/Development/rppl/tools/worktree-to-main.sh --dry-run
EOF
}

log() {
  printf 'worktree-to-main: %s\n' "$*" >&2
}

die() {
  printf 'worktree-to-main: error: %s\n' "$*" >&2
  exit 1
}

# Git porcelain stdout goes to stderr so callers can capture status words
# (e.g. stash_if_dirty) without ingesting "Saved working directory..." lines.
run_git() {
  local dir="$1"
  shift
  if [[ "$DRY_RUN" == true ]]; then
    log "[dry-run] git -C '$dir' $*"
  else
    log "git -C '$dir' $*"
    git -C "$dir" "$@" >&2
  fi
}

run_git_global() {
  if [[ "$DRY_RUN" == true ]]; then
    log "[dry-run] git $*"
  else
    log "git $*"
    git "$@" >&2
  fi
}

git_in() {
  git -C "$1" "${@:2}"
}

repo_common_dir() {
  git_in "$1" rev-parse --path-format=absolute --git-common-dir
}

resolve_main_dir() {
  local common="$1"
  local line path branch

  while IFS= read -r line; do
    case "$line" in
      worktree*)
        path="${line#worktree }"
        branch=""
        ;;
      branch*)
        branch="${line#branch refs/heads/}"
        if [[ "$branch" == "main" && -n "${path:-}" ]]; then
          printf '%s\n' "$path"
          return 0
        fi
        ;;
    esac
  done < <(git --git-dir="$common" worktree list --porcelain)

  printf '%s\n' "$MAIN_DIR"
}

tree_dirty() {
  local dir="$1"
  ! git_in "$dir" diff --quiet \
    || ! git_in "$dir" diff --cached --quiet \
    || [[ -n "$(git_in "$dir" ls-files --others --exclude-standard)" ]]
}

stash_if_dirty() {
  local dir="$1" msg="$2"
  if tree_dirty "$dir"; then
    run_git "$dir" stash push -u -m "$msg"
    printf 'stashed\n'
  else
    printf 'clean\n'
  fi
}

pop_stash_by_message() {
  local dir="$1" msg="$2"
  local ref

  ref="$(git_in "$dir" stash list | grep -F "$msg" | head -1 | cut -d: -f1 || true)"
  if [[ -z "$ref" ]]; then
    return 0
  fi
  run_git "$dir" stash pop "$ref"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --main-dir)
      [[ $# -ge 2 ]] || die "--main-dir requires a path"
      MAIN_DIR="$2"
      shift 2
      ;;
    --keep-worktree)
      KEEP_WORKTREE=true
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      die "unknown option: $1 (try --help)"
      ;;
  esac
done

SOURCE_DIR="$(git rev-parse --show-toplevel 2>/dev/null)" || die "not inside a git repository"
SOURCE_DIR="$(cd "$SOURCE_DIR" && pwd)"
MAIN_DIR="$(cd "$MAIN_DIR" 2>/dev/null && pwd)" || die "main dir not found: $MAIN_DIR"

SOURCE_COMMON="$(cd "$(repo_common_dir "$SOURCE_DIR")" && pwd)"
MAIN_COMMON="$(cd "$(repo_common_dir "$MAIN_DIR")" && pwd)"
[[ "$SOURCE_COMMON" == "$MAIN_COMMON" ]] || die "source and main are not the same git repository"

RESOLVED_MAIN="$(resolve_main_dir "$SOURCE_COMMON")"
if [[ -d "$RESOLVED_MAIN" ]]; then
  MAIN_DIR="$(cd "$RESOLVED_MAIN" && pwd)"
fi

if [[ "$SOURCE_DIR" == "$MAIN_DIR" ]]; then
  die "already on main checkout ($MAIN_DIR); run from a feature worktree"
fi

BRANCH="$(git_in "$SOURCE_DIR" branch --show-current)"
[[ -n "$BRANCH" ]] || die "detached HEAD in worktree; checkout a branch first"
[[ "$BRANCH" != "main" ]] || die "worktree is on main; nothing to move"

log "source:  $SOURCE_DIR ($BRANCH)"
log "main:    $MAIN_DIR"
log "keep:    $KEEP_WORKTREE"

MAIN_DIRTY="$(stash_if_dirty "$MAIN_DIR" "$MAIN_STASH_MSG")"
WORKTREE_DIRTY="$(stash_if_dirty "$SOURCE_DIR" "$WORKTREE_STASH_MSG")"

if [[ "$KEEP_WORKTREE" == true ]]; then
  run_git "$SOURCE_DIR" checkout --detach
  log "detached HEAD in $SOURCE_DIR (directory kept)"
else
  run_git_global worktree remove "$SOURCE_DIR" --force
  log "removed worktree $SOURCE_DIR"
fi

run_git "$MAIN_DIR" checkout "$BRANCH"

if [[ "$WORKTREE_DIRTY" == stashed ]]; then
  pop_stash_by_message "$MAIN_DIR" "$WORKTREE_STASH_MSG"
fi

log "done — main is on branch $BRANCH at $MAIN_DIR"
if [[ "$MAIN_DIRTY" == stashed ]]; then
  log "main had uncommitted changes; stashed as '$MAIN_STASH_MSG'"
  log "restore with: git -C '$MAIN_DIR' stash list && git -C '$MAIN_DIR' stash pop"
fi
if [[ "$KEEP_WORKTREE" == true ]]; then
  log "old worktree dir still present (detached): $SOURCE_DIR — remove manually when done"
fi
