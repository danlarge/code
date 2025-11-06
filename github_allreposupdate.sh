#!/usr/bin/env bash
# ======================================================================
# Git multi-repo updater with auto-discovery, safe FF-only updates,
# and permission self-repair for macOS. Compatible with Bash and Zsh.
#
# Execution assumptions:
# - macOS or BSD userland (supports chflags).
# - You have read/write access to the base directory.
# - Repos use an 'origin' remote.
# ======================================================================

# ----------------------------------------------------------------------
# GLOBAL SETTINGS
# ----------------------------------------------------------------------
# Purpose: safer shell defaults without aborting whole run on one failure.
# -u: error on unset variables
# pipefail: fail pipeline on first failing command
set -u
set -o pipefail
IFS=$'\n\t'

# ----------------------------------------------------------------------
# CONSTANTS / INPUTS
# ----------------------------------------------------------------------
# INPUT: BASE_DIR
# Meaning: absolute path containing your Git repositories as subfolders.
BASE_DIR="/Users/daniellarge/Applications_Uncontained/GitHubRepos"

# OUTPUT FILES: change and skip logs, truncated at start of run.
CHANGED_LOG="$BASE_DIR/changed_repos.log"
SKIPPED_LOG="$BASE_DIR/skipped_repos.log"

# ----------------------------------------------------------------------
# PRE-RUN: privilege warm-up for future sudo use (permission repair).
# INPUT: none. Prompts once if needed.
# EFFECT: caches sudo credentials; no action if not required later.
# ----------------------------------------------------------------------
echo "Requesting sudo (for permission repair only, if needed)..."
sudo -v || true

# ----------------------------------------------------------------------
# LOG INITIALIZATION
# INPUTS: $CHANGED_LOG, $SKIPPED_LOG
# EFFECT: truncate logs and add run header.
# ----------------------------------------------------------------------
: > "$CHANGED_LOG"
: > "$SKIPPED_LOG"
{
  printf "Run: %s\n" "$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
} >> "$CHANGED_LOG"
{
  printf "Run: %s\n" "$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
} >> "$SKIPPED_LOG"

# ======================================================================
# FUNCTIONS
# ======================================================================

# ----------------------------------------------------------------------
# fn: note_skip
# INPUTS:
#   $1 = repo_name (string)
#   $2 = reason     (string)
# EFFECT:
#   - prints a human message
#   - appends a structured line to $SKIPPED_LOG
# RETURNS: 0
# ----------------------------------------------------------------------
note_skip() {
  local _name="$1"; local _reason="$2"
  echo "  Skip: ${_reason}."
  printf "%s\t%s\t%s\n" "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$_name" "$_reason" >> "$SKIPPED_LOG"
}

# ----------------------------------------------------------------------
# fn: note_change
# INPUTS:
#   $1 = repo_name (string)
#   $2 = branch    (string)
#   $3 = commit    (full SHA or short SHA)
# EFFECT:
#   - prints a human message
#   - appends a structured line to $CHANGED_LOG
# RETURNS: 0
# ----------------------------------------------------------------------
note_change() {
  local _name="$1"; local _branch="$2"; local _sha="$3"
  echo "  Updated to ${_branch} (${_sha:0:7})."
  printf "%s\t%s\t%s\t%s\n" "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$_name" "$_branch" "$_sha" >> "$CHANGED_LOG"
}

# ----------------------------------------------------------------------
# fn: is_git_repo
# INPUTS:
#   $1 = repo_path (absolute path)
# EFFECT: none
# RETURNS:
#   0 if repo_path contains a .git directory
#   1 otherwise
# ----------------------------------------------------------------------
is_git_repo() {
  [[ -d "$1/.git" ]]
}

# ----------------------------------------------------------------------
# fn: ensure_origin_exists
# INPUTS:
#   none (uses current directory's git context)
# EFFECT: none
# RETURNS:
#   0 if 'origin' remote is configured
#   1 otherwise
# ----------------------------------------------------------------------
ensure_origin_exists() {
  git remote get-url origin >/dev/null 2>&1
}

# ----------------------------------------------------------------------
# fn: detect_target_branch
# INPUTS:
#   none (uses current directory's git context)
# EFFECT:
#   echoes the chosen target branch to stdout:
#     - current branch if it exists on origin
#     - else origin's default branch
#     - else 'main'
# RETURNS:
#   0 always; consumer reads stdout
# ----------------------------------------------------------------------
detect_target_branch() {
  # current branch, empty if detached
  local _current
  _current="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
  if [[ -n "${_current}" ]] && git show-ref --verify --quiet "refs/remotes/origin/${_current}"; then
    echo "$_current"; return 0
  fi
  # origin/HEAD -> origin/<default>, strip 'origin/'
  local _default
  _default="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##' || true)"
  if [[ -n "${_default}" ]]; then
    echo "$_default"; return 0
  fi
  echo "main"
}

# ----------------------------------------------------------------------
# fn: has_local_config_changes
# INPUTS:
#   none (uses current directory's git context)
# EFFECT: none
# RETURNS:
#   0 if working tree shows modified paths matching 'config' (case-insensitive)
#   1 otherwise
# NOTES:
#   Adjust grep if you need stricter patterns.
# ----------------------------------------------------------------------
has_local_config_changes() {
  git status --porcelain | awk '{print $2}' | grep -qi 'config'
}

# ----------------------------------------------------------------------
# fn: fetch_target
# INPUTS:
#   $1 = branch name to fetch from origin
# EFFECT:
#   git fetch --prune origin <branch>
# RETURNS:
#   pass-through git fetch exit code
# ----------------------------------------------------------------------
fetch_target() {
  local _branch="$1"
  git fetch --prune origin "${_branch}"
}

# ----------------------------------------------------------------------
# fn: ff_to_origin
# INPUTS:
#   $1 = target branch name
# EFFECT:
#   - If HEAD is ancestor of origin/<branch>:
#       * if behind: hard reset to origin/<branch> (discard local changes/commits)
#       * if equal: no-op
#   - If diverged or ahead: do nothing
# RETURNS:
#   0 on success or no-op
#   10 if diverged/ahead
#   20 if reset failed
# ----------------------------------------------------------------------
ff_to_origin() {
  local _branch="$1"
  local _local
  _local="$(git rev-parse HEAD)"
  local _remote
  _remote="$(git rev-parse "origin/${_branch}")"

  # HEAD is ancestor of remote => behind or equal; safe to fast-forward
  if git merge-base --is-ancestor "${_local}" "${_remote}"; then
    if [[ "${_local}" == "${_remote}" ]]; then
      echo "  Up to date."
      return 0
    fi
    # behind: force working tree to remote state
    if git reset --hard "origin/${_branch}" >/dev/null 2>&1; then
      note_change "$(basename "$(pwd)")" "${_branch}" "${_remote}"
      return 0
    else
      # permissions or file flags likely blocked reset
      return 20
    fi
  else
    # diverged or ahead; do not auto-merge
    return 10
  fi
}

# ----------------------------------------------------------------------
# fn: repair_permissions
# INPUTS:
#   $1 = repo_path (absolute path)
# EFFECT:
#   - Clears macOS 'uchg' flags recursively
#   - Resets ownership to current user:staff
#   - Ensures u+rwX everywhere
# RETURNS:
#   0 always (best-effort)
# ----------------------------------------------------------------------
repair_permissions() {
  local _path="$1"
  # Clear immutable flags; ignore errors if not set
  chflags -R nouchg "$_path" 2>/dev/null || true
  # Fix ownership; may prompt for sudo if cached creds expired
  sudo chown -R "$USER":staff "$_path" 2>/dev/null || true
  # Ensure write and search permissions for user
  chmod -R u+rwX "$_path" 2>/dev/null || true
}

# ----------------------------------------------------------------------
# fn: update_repo
# INPUTS:
#   $1 = repo_path (absolute path)
# EFFECT:
#   - Validates repo
#   - Determines target branch
#   - Skips if local config changes present
#   - Fetches target
#   - Fast-forward updates or logs skip
#   - On permission failure, performs repair and retries once
# RETURNS:
#   0 on success or no-op
#   non-zero on skip conditions (informational)
# ----------------------------------------------------------------------
update_repo() {
  local repo_path="$1"
  local repo_name; repo_name="$(basename "$repo_path")"
  echo "Processing: $repo_name"

  # Ensure repository structure
  if ! is_git_repo "$repo_path"; then
    note_skip "$repo_name" "not a git repo"
    return 1
  fi

  # Enter repo directory for all git operations
  if ! pushd "$repo_path" > /dev/null 2>&1; then
    note_skip "$repo_name" "cannot enter directory"
    return 1
  fi

  # Ensure an 'origin' remote exists
  if ! ensure_origin_exists; then
    note_skip "$repo_name" "no origin remote"
    popd > /dev/null; return 1
  fi

  # Resolve the correct update branch
  local target_branch
  target_branch="$(detect_target_branch)"

  # Protect local config edits
  if has_local_config_changes; then
    note_skip "$repo_name" "local config changes detected"
    popd > /dev/null; return 1
  fi

  # Fetch latest remote state for the target branch
  if ! fetch_target "$target_branch" >/dev/null 2>&1; then
    note_skip "$repo_name" "fetch failed for origin/${target_branch}"
    popd > /dev/null; return 1
  fi

  # Attempt fast-forward update
  if ff_to_origin "$target_branch"; then
    :
  else
    case "$?" in
      10)
        note_skip "$repo_name" "diverged/ahead of origin/${target_branch}"
        ;;
      20)
        echo "  Reset failed due to permissions. Attempting repair..."
        popd > /dev/null
        repair_permissions "$repo_path"
        # Retry inside repo
        if pushd "$repo_path" > /dev/null 2>&1 && ff_to_origin "$target_branch"; then
          :
        else
          note_skip "$repo_name" "reset failed after repair"
        fi
        ;;
      *)
        note_skip "$repo_name" "unexpected update error"
        ;;
    esac
  fi

  # Leave repo directory
  popd > /dev/null || true
}

# ======================================================================
# MAIN
# ======================================================================

echo "Scanning for repositories in: $BASE_DIR"

# Iterate immediate subdirectories. Compatible with Bash and Zsh.
# Uses newline splitting; handles spaces in names.
find "$BASE_DIR" -mindepth 1 -maxdepth 1 -type d | while IFS=$'\n' read -r dir; do
  update_repo "$dir"
done

# SUMMARY OUTPUT
echo
echo "Changed repos log: $CHANGED_LOG"
echo "Skipped  repos log: $SKIPPED_LOG"
