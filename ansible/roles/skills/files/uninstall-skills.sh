#!/usr/bin/env bash
set -euo pipefail

readonly SKILL_CLONE_ROOT="${SKILL_CLONE_ROOT:-${XDG_DATA_HOME:-$HOME/.local/share}/agent-skills/repos}"
readonly CLAUDE_SKILLS_DIR="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"
readonly CODEX_SKILLS_DIR="${CODEX_SKILLS_DIR:-$HOME/.codex/skills}"

[[ -n "${SKILL_REPOS:-}" ]] || { printf '[uninstall-skills] ERROR: SKILL_REPOS env var is required\n' >&2; exit 1; }

REPO_URLS=()
REPO_NAMES=()
while IFS= read -r _repo; do
  [[ -n "$_repo" ]] || continue
  REPO_URLS+=("$_repo")
  _name="${_repo##*/}"
  REPO_NAMES+=("${_name%.git}")
done <<< "$SKILL_REPOS"
readonly REPO_URLS
readonly REPO_NAMES

[[ ${#REPO_URLS[@]} -gt 0 ]] || { printf '[uninstall-skills] ERROR: SKILL_REPOS is empty\n' >&2; exit 1; }

log() {
  printf '[uninstall-skills] %s\n' "$*"
}

die() {
  printf '[uninstall-skills] ERROR: %s\n' "$*" >&2
  exit 1
}

count_lines() {
  wc -l < "$1" | tr -d '[:space:]'
}

usage() {
  cat <<'USAGE'
Usage: ./uninstall-skills.sh [--dry-run] [--yes]

Removes installer-managed skill symlinks from:
  - ~/.claude/skills
  - ~/.codex/skills

And removes installer-managed cloned repositories under:
  - ${XDG_DATA_HOME:-$HOME/.local/share}/agent-skills/repos

Safety behavior:
  - Removes only symlinks that point into one of the six managed repositories.
  - Removes only repositories that are git repos with expected origin URL.
  - Preserves unrelated entries (for example ~/.codex/skills/.system).

Options:
  --dry-run   Print what would be removed without making changes.
  --yes       Skip confirmation prompt.
  -h, --help  Show this help.

Environment overrides:
  SKILL_CLONE_ROOT   (default: ${XDG_DATA_HOME:-$HOME/.local/share}/agent-skills/repos)
  CLAUDE_SKILLS_DIR  (default: $HOME/.claude/skills)
  CODEX_SKILLS_DIR   (default: $HOME/.codex/skills)
USAGE
}

check_requirements() {
  local required_cmd
  for required_cmd in find readlink git rm mktemp wc sed dirname; do
    command -v "$required_cmd" >/dev/null 2>&1 || die "Missing required command: $required_cmd"
  done
}

normalize_github_url() {
  local url="$1"
  url="${url%.git}"
  url="${url#https://github.com/}"
  url="${url#git@github.com:}"
  printf '%s' "$url"
}

is_repo_managed_target() {
  local target="$1"
  local normalized="${target%/}"
  local repo_name
  local repo_root

  for repo_name in "${REPO_NAMES[@]}"; do
    repo_root="${SKILL_CLONE_ROOT%/}/$repo_name"
    if [[ "$normalized" == "$repo_root" || "$normalized" == "$repo_root/"* ]]; then
      return 0
    fi
  done
  return 1
}

resolve_link_target_guess() {
  local link_path="$1"
  local raw_target="$2"

  if [[ "$raw_target" == /* ]]; then
    printf '%s\n' "${raw_target%/}"
    return
  fi

  printf '%s/%s\n' "$(dirname "$link_path")" "$raw_target"
}

collect_symlink_removals_for_dir() {
  local target_dir="$1"
  local out_file="$2"
  local link_path
  local raw_target
  local guessed_target

  [[ -d "$target_dir" ]] || return 0

  while IFS= read -r -d '' link_path; do
    raw_target="$(readlink "$link_path" || true)"
    [[ -n "$raw_target" ]] || continue
    guessed_target="$(resolve_link_target_guess "$link_path" "$raw_target")"

    if is_repo_managed_target "$guessed_target"; then
      printf '%s\t%s\n' "$link_path" "$raw_target" >> "$out_file"
    fi
  done < <(find "$target_dir" -mindepth 1 -maxdepth 1 -type l -print0)
}

collect_repo_removals() {
  local out_file="$1"
  local i
  local repo_name
  local repo_path
  local expected_origin
  local current_origin

  i=0
  while [[ $i -lt ${#REPO_NAMES[@]} ]]; do
    repo_name="${REPO_NAMES[$i]}"
    expected_origin="${REPO_URLS[$i]}"
    repo_path="${SKILL_CLONE_ROOT%/}/$repo_name"

    if [[ ! -e "$repo_path" ]]; then
      i=$((i + 1))
      continue
    fi

    if [[ ! -d "$repo_path/.git" ]]; then
      log "Skipping non-git path (left untouched): $repo_path"
      i=$((i + 1))
      continue
    fi

    current_origin="$(git -C "$repo_path" remote get-url origin 2>/dev/null || true)"
    if [[ -z "$current_origin" ]]; then
      log "Skipping repo without origin remote (left untouched): $repo_path"
      i=$((i + 1))
      continue
    fi

    if [[ "$current_origin" != "$expected_origin" ]] && \
       [[ "$(normalize_github_url "$current_origin")" != "$(normalize_github_url "$expected_origin")" ]]; then
      log "Skipping repo with origin mismatch (left untouched): $repo_path"
      log "  expected: $expected_origin"
      log "  actual:   $current_origin"
      i=$((i + 1))
      continue
    fi

    printf '%s\n' "$repo_path" >> "$out_file"
    i=$((i + 1))
  done
}

print_manifest() {
  local manifest_dir="$1"
  local symlink_file="$2"
  local repo_file="$3"
  local symlink_count
  local repo_count

  symlink_count=0
  repo_count=0
  [[ -s "$symlink_file" ]] && symlink_count="$(count_lines "$symlink_file")"
  [[ -s "$repo_file" ]] && repo_count="$(count_lines "$repo_file")"

  log "Manifest directory: $manifest_dir"
  log "Symlinks selected: $symlink_count"
  log "Repos selected: $repo_count"
}

remove_selected_symlinks() {
  local symlink_file="$1"
  local dry_run="$2"
  local line
  local link_path
  local raw_target
  local removed=0

  [[ -s "$symlink_file" ]] || {
    SYMLINKS_REMOVED=0
    return 0
  }

  while IFS= read -r line; do
    link_path="$(printf '%s' "$line" | cut -f1)"
    raw_target="$(printf '%s' "$line" | cut -f2-)"

    if [[ "$dry_run" == "1" ]]; then
      log "DRY-RUN unlink: $link_path -> $raw_target"
    else
      rm -f "$link_path"
      log "Unlinked: $link_path"
    fi
    removed=$((removed + 1))
  done < "$symlink_file"

  SYMLINKS_REMOVED="$removed"
}

remove_selected_repos() {
  local repo_file="$1"
  local dry_run="$2"
  local repo_path
  local removed=0

  [[ -s "$repo_file" ]] || {
    REPOS_REMOVED=0
    return 0
  }

  while IFS= read -r repo_path; do
    [[ -n "$repo_path" ]] || continue
    if [[ "$dry_run" == "1" ]]; then
      log "DRY-RUN rm -rf: $repo_path"
    else
      rm -rf "$repo_path"
      log "Removed repo: $repo_path"
    fi
    removed=$((removed + 1))
  done < "$repo_file"

  REPOS_REMOVED="$removed"
}

confirm_or_abort() {
  local symlink_count="$1"
  local repo_count="$2"

  if [[ "$AUTO_YES" == "1" || "$DRY_RUN" == "1" ]]; then
    return 0
  fi

  printf '[uninstall-skills] About to remove %s symlink(s) and %s repo(s). Proceed? [y/N] ' "$symlink_count" "$repo_count"
  read -r response
  case "$response" in
    y|Y|yes|YES) ;;
    *) die "Aborted by user" ;;
  esac
}

DRY_RUN=0
AUTO_YES=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --yes) AUTO_YES=1 ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown argument: $1 (use --help)"
      ;;
  esac
  shift
done

check_requirements

manifest_dir="$(mktemp -d)"
trap 'rm -rf "$manifest_dir"' EXIT

selected_symlinks_tsv="$manifest_dir/selected-symlinks.tsv"
selected_repos_txt="$manifest_dir/selected-repos.txt"
touch "$selected_symlinks_tsv" "$selected_repos_txt"

collect_symlink_removals_for_dir "$CLAUDE_SKILLS_DIR" "$selected_symlinks_tsv"
collect_symlink_removals_for_dir "$CODEX_SKILLS_DIR" "$selected_symlinks_tsv"
collect_repo_removals "$selected_repos_txt"

symlink_count=0
repo_count=0
[[ -s "$selected_symlinks_tsv" ]] && symlink_count="$(count_lines "$selected_symlinks_tsv")"
[[ -s "$selected_repos_txt" ]] && repo_count="$(count_lines "$selected_repos_txt")"

print_manifest "$manifest_dir" "$selected_symlinks_tsv" "$selected_repos_txt"

if [[ "$symlink_count" == "0" && "$repo_count" == "0" ]]; then
  log "Nothing to remove."
  exit 0
fi

confirm_or_abort "$symlink_count" "$repo_count"

SYMLINKS_REMOVED=0
REPOS_REMOVED=0
remove_selected_symlinks "$selected_symlinks_tsv" "$DRY_RUN"
remove_selected_repos "$selected_repos_txt" "$DRY_RUN"

if [[ "$DRY_RUN" == "1" ]]; then
  log "Dry-run complete: planned_unlinks=$SYMLINKS_REMOVED planned_repo_removals=$REPOS_REMOVED"
else
  log "Done: unlinked=$SYMLINKS_REMOVED repos_removed=$REPOS_REMOVED"
fi
