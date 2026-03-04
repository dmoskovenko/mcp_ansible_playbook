# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Bash-based installer that manages external AI agent skill repositories for Claude and Codex editors. It clones skill repos, discovers skills (directories containing `SKILL.md` files), and symlinks them into `~/.claude/skills` and `~/.codex/skills`.

## Commands

```bash
# Validate shell syntax (the only available "test" step)
bash -n install-skills.sh
bash -n uninstall-skills.sh

# Run installer (clones/updates repos, creates symlinks)
./install-skills.sh

# Preview or execute uninstall
./uninstall-skills.sh --dry-run
./uninstall-skills.sh --yes
```

## Architecture

**`install-skills.sh`** — Sequential pipeline:
1. Clone or update a hardcoded list of git repos into `${XDG_DATA_HOME:-$HOME/.local/share}/agent-skills/repos`
2. Discover all `SKILL.md` files across cloned repos
3. Build a TSV skill-name → directory mapping, validate for duplicates and destination conflicts
4. Create/update symlinks in both `~/.claude/skills` and `~/.codex/skills`

**`uninstall-skills.sh`** — Conservative removal:
- Only removes symlinks whose targets resolve to managed repo paths
- Only removes repos whose git origin URL matches the expected list
- Supports `--dry-run` and `--yes` flags; prompts for confirmation by default

Both scripts use `set -euo pipefail`, readonly config variables, and trap-based temp file cleanup.

## Conventions

- POSIX-friendly bash with explicit variable names
- Deterministic behavior: stable ordering, fail-fast on conflicts
- Idempotent: both scripts are safe to re-run
- Commit subjects use imperative mood with scope prefix (e.g., `installer: add duplicate detection`)
- PRs require manual validation notes (install, re-install for idempotency, dry-run, uninstall)
