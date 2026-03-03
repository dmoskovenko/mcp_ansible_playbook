# Repository Guidelines

## Project Structure & Module Organization
This repository is an installer wrapper for external skill repositories.

- `install-skills.sh`: main script that clones linked repositories and links discovered skills.
- `uninstall-skills.sh`: safe remover for installer-managed symlinks and managed cloned repositories.
- `AGENTS.md`: contributor instructions for this repository.
- Cloned repositories are cached outside git in `${XDG_DATA_HOME:-$HOME/.local/share}/agent-skills/repos`.
- Installed skill links are created in `~/.claude/skills` and `~/.codex/skills`.

## Build, Test, and Development Commands
There is no build system at repo root. Use these commands:

- `bash -n install-skills.sh` validates shell syntax.
- `bash -n uninstall-skills.sh` validates shell syntax.
- `./install-skills.sh` clones/updates repositories and refreshes symlinks.
- `./install-skills.sh --help` shows environment overrides.
- `./uninstall-skills.sh --dry-run` previews removals without deleting anything.
- `./uninstall-skills.sh --yes` removes installer-managed artifacts non-interactively.
- `./uninstall-skills.sh --help` shows safety rules and environment overrides.
- `git status --short` verifies only intended tracked files changed.

## Coding Style & Naming Conventions
- Bash should be POSIX-friendly where possible, with `set -euo pipefail` for safety.
- Prefer explicit variable names (`SKILL_CLONE_ROOT`, `CLAUDE_SKILLS_DIR`, `CODEX_SKILLS_DIR`).
- Keep installer behavior deterministic: stable ordering, fail-fast on conflicts, and clear error output.
- Keep uninstall behavior conservative: only remove installer-managed symlinks and repositories with expected origin remotes.
- Documentation should stay concise and operational, with copy-paste-ready commands.

## Testing Guidelines
- No centralized automated test suite exists at repo root.
- Required checks before a PR:
  - `bash -n install-skills.sh`
  - `bash -n uninstall-skills.sh`
  - Run installer once in a safe environment and verify links in both target directories.
  - Re-run installer to confirm idempotent update behavior.
  - Run `./uninstall-skills.sh --dry-run` and confirm only installer-managed paths are selected.
  - Run `./uninstall-skills.sh --yes`, verify managed links/repos are removed, and re-run dry-run to confirm idempotent cleanup.
- Include manual validation notes in the PR description.

## Commit & Pull Request Guidelines
- Use imperative commit subjects with scope, e.g. `installer: add duplicate skill name detection`.
- Keep commits focused on one concern (installer logic, docs, or cleanup).
- PRs should include:
  - What changed and why.
  - Validation performed (commands run and outcomes).
  - Any behavior changes for existing users (especially conflict handling).
