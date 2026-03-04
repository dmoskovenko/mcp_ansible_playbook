# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Ansible playbook for bootstrapping AI-assisted development environments on macOS:

- **Bash scripts** (`install-skills.sh`, `uninstall-skills.sh`) — clone external skill repositories, discover directories containing `SKILL.md` files, and symlink them into `~/.claude/skills` and `~/.codex/skills`.
- **Skills role** — thin Ansible wrapper that delegates to the bash scripts above.
- **MCP server roles** — installs and registers MCP servers (Exa, Firecrawl, Perplexity, Figma, Context7, Cupertino, SwiftLens, XcodeBuildMCP) with the Claude Code and Codex CLIs.

## Commands

```bash
# Syntax check
cd ansible && ansible-playbook playbook.yml --syntax-check

# Dry run
ansible-playbook -i inventory/localhost.yml playbook.yml --check --ask-vault-pass

# Full run
ansible-playbook -i inventory/localhost.yml playbook.yml --ask-vault-pass

# Single role
ansible-playbook -i inventory/localhost.yml playbook.yml --tags cupertino --ask-vault-pass

# Skills only (no vault pass needed)
ansible-playbook -i inventory/localhost.yml playbook.yml --tags skills

# Uninstall skills
ansible-playbook -i inventory/localhost.yml playbook.yml --tags skills -e skills_state=absent
```

## Architecture

**`ansible/playbook.yml`** — Bootstraps AI development environments on macOS:
- **Roles:** `prerequisites`, `skills`, `exa`, `firecrawl`, `perplexity`, `figma`, `context7`, `cupertino`, `swiftlens`,`xcodebuildmcp`
- **Skills role:** Thin wrapper that delegates to root-level `install-skills.sh` / `uninstall-skills.sh` bash scripts. Uninstall (`-e skills_state=absent`) removes only managed symlinks and repos.
- **Config:** `group_vars/all/mcp_servers.yml` toggles which servers and skills are enabled; `vault.yml` stores API keys
- macOS-only, idempotent, supports tag-based selective runs and `--check` dry-run mode

See `ansible/README.md` for full playbook usage documentation.

## Conventions

- Deterministic behavior: stable ordering, fail-fast on conflicts
- Idempotent: all playbooks and roles are safe to re-run
- Commit subjects use imperative mood with scope prefix (e.g., `ansible: add Exa role`, `skills: add duplicate detection`)
- PRs require manual validation notes (install, re-install for idempotency, dry-run, uninstall)
