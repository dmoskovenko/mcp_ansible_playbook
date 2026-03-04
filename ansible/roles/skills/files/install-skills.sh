#!/usr/bin/env bash
set -euo pipefail

readonly SKILL_CLONE_ROOT="${SKILL_CLONE_ROOT:-${XDG_DATA_HOME:-$HOME/.local/share}/agent-skills/repos}"
readonly CLAUDE_SKILLS_DIR="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"
readonly CODEX_SKILLS_DIR="${CODEX_SKILLS_DIR:-$HOME/.codex/skills}"

[[ -n "${SKILL_REPOS:-}" ]] || { printf '[install-skills] ERROR: SKILL_REPOS env var is required\n' >&2; exit 1; }

REPOS=()
while IFS= read -r _repo; do
  [[ -n "$_repo" ]] && REPOS+=("$_repo")
done <<< "$SKILL_REPOS"
readonly REPOS

[[ ${#REPOS[@]} -gt 0 ]] || { printf '[install-skills] ERROR: SKILL_REPOS is empty\n' >&2; exit 1; }

log() {
  printf '[install-skills] %s\n' "$*"
}

die() {
  printf '[install-skills] ERROR: %s\n' "$*" >&2
  exit 1
}

count_lines() {
  wc -l < "$1" | tr -d '[:space:]'
}

usage() {
  cat <<'USAGE'
Usage: ./install-skills.sh [--dry-run]

Clones/updates linked skill repositories, discovers all parent directories containing
SKILL.md, and creates symlinks into:
  - ~/.claude/skills
  - ~/.codex/skills

Options:
  --dry-run   Print what would be done without making changes.
  -h, --help  Show this help.

Environment overrides:
  SKILL_CLONE_ROOT   (default: ${XDG_DATA_HOME:-$HOME/.local/share}/agent-skills/repos)
  CLAUDE_SKILLS_DIR  (default: $HOME/.claude/skills)
  CODEX_SKILLS_DIR   (default: $HOME/.codex/skills)
USAGE
}

repo_dir_name() {
  local repo_url="$1"
  basename "${repo_url%.git}"
}

check_requirements() {
  local required_cmd
  for required_cmd in git ssh find sort ln awk cut uniq mktemp wc sed dirname basename tr; do
    command -v "$required_cmd" >/dev/null 2>&1 || die "Missing required command: $required_cmd"
  done
}

init_workspace() {
  mkdir -p "$SKILL_CLONE_ROOT" "$CLAUDE_SKILLS_DIR" "$CODEX_SKILLS_DIR"

  tmp_dir="$(mktemp -d)"
  skills_tsv="$tmp_dir/skills.tsv"
  skills_unique_tsv="$tmp_dir/skills_unique.tsv"
  skill_names_txt="$tmp_dir/skill_names.txt"
  conflicts_txt="$tmp_dir/conflicts.txt"
}

cleanup_workspace() {
  [[ -n "${tmp_dir:-}" ]] && rm -rf "$tmp_dir"
}

normalize_github_url() {
  local url="$1"
  url="${url%.git}"
  url="${url#https://github.com/}"
  url="${url#git@github.com:}"
  printf '%s' "$url"
}

clone_or_update_repo() {
  local repo_url="$1"
  local repo_name
  local repo_path
  local current_origin

  repo_name="$(repo_dir_name "$repo_url")"
  repo_path="$SKILL_CLONE_ROOT/$repo_name"

  if [[ -d "$repo_path/.git" ]]; then
    current_origin="$(git -C "$repo_path" remote get-url origin 2>/dev/null || true)"
    [[ -n "$current_origin" ]] || die "Repository at '$repo_path' has no origin remote"

    if [[ "$current_origin" != "$repo_url" ]]; then
      if [[ "$(normalize_github_url "$current_origin")" == "$(normalize_github_url "$repo_url")" ]]; then
        log "Migrating remote origin for '$repo_name': $current_origin -> $repo_url"
        [[ "$DRY_RUN" == "1" ]] || git -C "$repo_path" remote set-url origin "$repo_url"
      else
        die "Origin mismatch for '$repo_path': expected '$repo_url', got '$current_origin'"
      fi
    fi

    if [[ "$DRY_RUN" == "1" ]]; then
      log "DRY-RUN update: $repo_url"
    else
      log "Updating $repo_url"
      git -C "$repo_path" fetch --prune origin
      local branch
      branch="$(git -C "$repo_path" rev-parse --abbrev-ref HEAD)"
      if ! git -C "$repo_path" pull --ff-only 2>/dev/null; then
        log "Fast-forward failed for '$repo_name' — resetting to origin/$branch"
        git -C "$repo_path" reset --hard "origin/$branch"
      fi
    fi
    updated_repo_count=$((updated_repo_count + 1))
    return
  fi

  [[ ! -e "$repo_path" ]] || die "Path '$repo_path' exists but is not a git repository"

  if [[ "$DRY_RUN" == "1" ]]; then
    log "DRY-RUN clone: $repo_url"
  else
    log "Cloning $repo_url"
    git clone "$repo_url" "$repo_path"
  fi
  cloned_count=$((cloned_count + 1))
}

clone_or_update_all_repos() {
  local repo_url
  for repo_url in "${REPOS[@]}"; do
    clone_or_update_repo "$repo_url"
    printf '\n'
  done
}

collect_skill_map() {
  local repo_url
  local repo_name
  local repo_path
  local skill_md
  local skill_dir
  local skill_name

  : > "$skills_tsv"
  skills_discovered=0

  for repo_url in "${REPOS[@]}"; do
    repo_name="$(repo_dir_name "$repo_url")"
    repo_path="$SKILL_CLONE_ROOT/$repo_name"

    while IFS= read -r -d '' skill_md; do
      skill_dir="$(dirname "$skill_md")"
      skill_name="$(basename "$skill_dir")"
      printf '%s\t%s\n' "$skill_name" "$skill_dir" >> "$skills_tsv"
      skills_discovered=$((skills_discovered + 1))
    done < <(find "$repo_path" -type f -name SKILL.md -print0)
  done

  [[ -s "$skills_tsv" ]] || die "No SKILL.md files discovered"
}

validate_no_duplicate_skill_names() {
  local duplicates
  local skill_name

  duplicates="$(cut -f1 "$skills_tsv" | sort | uniq -d || true)"
  [[ -z "$duplicates" ]] && return

  log "Duplicate skill directory names detected. Resolve conflicts before linking:"
  while IFS= read -r skill_name; do
    [[ -n "$skill_name" ]] || continue
    printf '  - %s\n' "$skill_name"
    awk -F '\t' -v name="$skill_name" '$1 == name { printf "      %s\n", $2 }' "$skills_tsv"
  done <<< "$duplicates"
  die "Duplicate skill names found — aborting"
}

build_unique_skill_files() {
  sort -t $'\t' -k1,1 "$skills_tsv" | awk -F '\t' '!seen[$1]++' > "$skills_unique_tsv"
  cut -f1 "$skills_unique_tsv" > "$skill_names_txt"
  unique_skill_count="$(count_lines "$skill_names_txt")"
}

validate_destination_conflicts() {
  local target_dir
  local skill_name
  local dest

  : > "$conflicts_txt"

  for target_dir in "$CLAUDE_SKILLS_DIR" "$CODEX_SKILLS_DIR"; do
    while IFS= read -r skill_name; do
      [[ -n "$skill_name" ]] || continue
      dest="$target_dir/$skill_name"
      [[ ! -L "$dest" ]] || continue
      if [[ -e "$dest" ]]; then
        printf '%s\n' "$dest" >> "$conflicts_txt"
      fi
    done < "$skill_names_txt"
  done

  [[ ! -s "$conflicts_txt" ]] && return

  log "Non-symlink paths already exist at destinations:"
  sed 's#^#  - #' "$conflicts_txt"
  die "Destination conflicts found — aborting"
}

link_skills_for_target() {
  local target_dir="$1"
  local created=0
  local updated=0
  local skill_name
  local source_dir
  local dest

  while IFS=$'\t' read -r skill_name source_dir; do
    [[ -n "$skill_name" ]] || continue
    [[ -n "$source_dir" ]] || die "Internal error: missing source for skill '$skill_name'"

    dest="$target_dir/$skill_name"
    if [[ -L "$dest" ]]; then
      if [[ "$(readlink "$dest")" == "$source_dir" ]]; then
        continue
      fi
      if [[ "$DRY_RUN" == "1" ]]; then
        log "DRY-RUN update link: $dest -> $source_dir"
      else
        rm -f "$dest"
        ln -s "$source_dir" "$dest"
      fi
      updated=$((updated + 1))
    else
      if [[ "$DRY_RUN" == "1" ]]; then
        log "DRY-RUN create link: $dest -> $source_dir"
      else
        ln -s "$source_dir" "$dest"
      fi
      created=$((created + 1))
    fi
  done < "$skills_unique_tsv"

  printf '%s %s\n' "$created" "$updated"
}

print_summary() {
  if [[ "$DRY_RUN" == "1" ]]; then
    log "Dry-run complete"
  else
    log "Done"
  fi
  log "Repositories: cloned=$cloned_count updated=$updated_repo_count total=${#REPOS[@]}"
  log "Skills discovered: total_SKILL_md=$skills_discovered unique_skill_dirs=$unique_skill_count"
  log "Links ($CLAUDE_SKILLS_DIR): created=$links_created_claude updated=$links_updated_claude"
  log "Links ($CODEX_SKILLS_DIR): created=$links_created_codex updated=$links_updated_codex"
}

DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
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
init_workspace
trap cleanup_workspace EXIT

cloned_count=0
updated_repo_count=0
skills_discovered=0
unique_skill_count=0
links_created_claude=0
links_updated_claude=0
links_created_codex=0
links_updated_codex=0

clone_or_update_all_repos
collect_skill_map
validate_no_duplicate_skill_names
build_unique_skill_files
validate_destination_conflicts

read -r links_created_claude links_updated_claude < <(link_skills_for_target "$CLAUDE_SKILLS_DIR")
read -r links_created_codex links_updated_codex < <(link_skills_for_target "$CODEX_SKILLS_DIR")

print_summary
