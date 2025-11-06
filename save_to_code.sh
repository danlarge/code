#!/usr/bin/env bash
# ======================================================================
# save_to_code.sh
#
# Upload any local script/file into your GitHub "code" repo, commit, push.
# Compatible with Bash and Zsh. macOS-friendly.
#
# DEFAULTS:
#   Remote URL:   https://github.com/danlarge/code.git
#   Clone dir:    ~/Applications_Uncontained/GitHubRepos/code
#   Branch:       main
#
# REQUIRED:
#   -s <source-file>
#
# OPTIONAL:
#   -n <dest-filename>       # defaults to basename of source
#   -p <dest-subdir>         # path inside repo, e.g. "scripts/tools"
#   -m <commit-message>      # default auto message with timestamp
#   -b <branch>              # default main; created if missing
#   -u <remote-url>          # override remote
#   -r <clone-dir>           # override local clone path
#   -G                       # set repo-local identity to Dan Large <gitpublic@danlarge.net>
#   -N                       # dry run (show steps, no changes)
#
# USAGE EXAMPLES:
#   ./save_to_code.sh -s ~/Applications_Uncontained/GitHubRepos/github_multiupdate.sh \
#     -p scripts/infra -m "Add multi-repo updater"
#
#   ./save_to_code.sh -s ./build_output1.sh -n github_allreposupdate.sh -G
# ======================================================================

set -u
set -o pipefail
IFS=$'\n\t'

REMOTE_URL="https://github.com/danlarge/code.git"
CLONE_DIR="~/Applications_Uncontained/GitHubRepos/code"
BRANCH="main"
SRC=""
DEST_NAME=""
DEST_SUBDIR=""
COMMIT_MSG=""
SET_LOCAL_ID=0
DRY_RUN=0

# --- functions ---
die() { echo "Error: $*" >&2; exit 2; }
info(){ echo "$@"; }

timestamp_utc() { date -u +'%Y-%m-%dT%H:%M:%SZ'; }

realpath_approx() {
  # works for absolute or relative paths
  # no readlink -f on macOS: use python fallback if present, else manual
  if command -v python3 >/dev/null 2>&1; then
    python3 - <<'PY' "$1"
import os,sys
print(os.path.abspath(sys.argv[1]))
PY
  else
    # best-effort
    case "$1" in
      /*) printf "%s\n" "$1" ;;
      *)  printf "%s/%s\n" "$(pwd)" "$1" ;;
    esac
  fi
}

ensure_clone() {
  local _remote="$1" _dir="$2"
  # expand ~ if present
  case "$_dir" in "~"*) _dir="${_dir/#\~/$HOME}";; esac
  if [[ -d "$_dir/.git" ]]; then
    info "Repo exists at $_dir"
    return 0
  fi
  if [[ -e "$_dir" && ! -d "$_dir" ]]; then
    die "Path $_dir exists and is not a directory"
  fi
  if [[ "$DRY_RUN" -eq 1 ]]; then
    info "DRY-RUN: git clone $_remote $_dir"
    return 0
  fi
  mkdir -p "$_dir/.." >/dev/null 2>&1 || true
  git clone "$_remote" "$_dir"
}

ensure_branch() {
  local _dir="$1" _branch="$2"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    info "DRY-RUN: (cd $_dir && git fetch --prune && git rev-parse --verify $_branch || git checkout -B $_branch origin/$_branch || git checkout -b $_branch)"
    return 0
  fi
  ( cd "$_dir" \
    && git fetch --prune \
    && { git rev-parse --verify "$_branch" >/dev/null 2>&1 \
         || git checkout -B "$_branch" "origin/$_branch" >/dev/null 2>&1 \
         || git checkout -b "$_branch"; } \
    && git checkout "$_branch" >/dev/null )
}

ensure_remote_url() {
  local _dir="$1" _remote="$2"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    info "DRY-RUN: (cd $_dir && git remote set-url origin $_remote)"
    return 0
  fi
  ( cd "$_dir" \
    && git remote get-url origin >/dev/null 2>&1 \
    && git remote set-url origin "$_remote" )
}

set_local_identity() {
  local _dir="$1"
  if [[ "$SET_LOCAL_ID" -eq 1 ]]; then
    if [[ "$DRY_RUN" -eq 1 ]]; then
      info "DRY-RUN: set local identity in $_dir -> Dan Large <gitpublic@danlarge.net>"
      return 0
    fi
    ( cd "$_dir" \
      && git config user.name  "Dan Large" \
      && git config user.email "gitpublic@danlarge.net" )
  fi
}

stage_commit_push() {
  local _dir="$1" _relpath="$2" _msg="$3" _branch="$4"
  if [[ -z "$_msg" ]]; then
    _msg="Save $_relpath ($(timestamp_utc))"
  fi
  if [[ "$DRY_RUN" -eq 1 ]]; then
    info "DRY-RUN: (cd $_dir && git add -- $_relpath && git commit -m \"$_msg\" && git push -u origin $_branch)"
    return 0
  fi
  ( cd "$_dir" \
    && git add -- "$_relpath" \
    && git commit -m "$_msg" \
    && git push -u origin "$_branch" )
}

# --- args ---
while getopts ":s:n:p:m:b:u:r:GN" opt; do
  case "$opt" in
    s) SRC="$OPTARG" ;;
    n) DEST_NAME="$OPTARG" ;;
    p) DEST_SUBDIR="$OPTARG" ;;
    m) COMMIT_MSG="$OPTARG" ;;
    b) BRANCH="$OPTARG" ;;
    u) REMOTE_URL="$OPTARG" ;;
    r) CLONE_DIR="$OPTARG" ;;
    G) SET_LOCAL_ID=1 ;;
    N) DRY_RUN=1 ;;
    \?) die "Unknown option -$OPTARG" ;;
    :)  die "Missing argument for -$OPTARG" ;;
  esac
done

[[ -z "$SRC" ]] && die "Source file required (-s)."

# normalize paths
SRC="$(realpath_approx "$SRC")"
[[ -f "$SRC" ]] || die "Source file not found: $SRC"
case "$CLONE_DIR" in "~"*) CLONE_DIR="${CLONE_DIR/#\~/$HOME}";; esac

# derive destination name
if [[ -z "$DEST_NAME" ]]; then
  DEST_NAME="$(basename "$SRC")"
fi

# ensure clone present and branch selected
ensure_clone "$REMOTE_URL" "$CLONE_DIR"
ensure_remote_url "$CLONE_DIR" "$REMOTE_URL"
ensure_branch "$CLONE_DIR" "$BRANCH"
set_local_identity "$CLONE_DIR"

# destination path in repo
REL_DST="$DEST_NAME"
if [[ -n "$DEST_SUBDIR" ]]; then
  # strip leading ./ or /
  REL_DST="${DEST_SUBDIR#/}"
  REL_DST="${REL_DST#./}"
  REL_DST="$REL_DST/$DEST_NAME"
fi
ABS_DST="$CLONE_DIR/$REL_DST"

# copy file
if [[ "$DRY_RUN" -eq 1 ]]; then
  info "DRY-RUN: mkdir -p $(dirname "$ABS_DST")"
  info "DRY-RUN: cp -p \"$SRC\" \"$ABS_DST\""
else
  mkdir -p "$(dirname "$ABS_DST")"
  cp -p "$SRC" "$ABS_DST"
fi

# commit and push
stage_commit_push "$CLONE_DIR" "$REL_DST" "$COMMIT_MSG" "$BRANCH"

info "Done."
info "Saved: $REL_DST"
info "Repo:  $CLONE_DIR"
info "Branch: $BRANCH"
