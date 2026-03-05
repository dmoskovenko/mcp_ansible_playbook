# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Ansible playbook for bootstrapping AI-assisted development environments on macOS:

- **Skills role** — clones external skill repositories, discovers directories containing `SKILL.md` files, and symlinks them into `~/.claude/skills` and `~/.codex/skills`. Bash scripts live in `ansible/roles/skills/files/`. Repo list is configured in `group_vars/all/skills.yml` and passed via the `SKILL_REPOS` env var.
- **MCP role** — a single parameterized role that installs and registers all MCP servers (Exa, Firecrawl, Figma, Context7, Cupertino, SwiftLens, XcodeBuildMCP) with the Claude Code and Codex CLIs. Server definitions live in `mcp_servers` dict in `group_vars/all/mcp_servers.yml`.

## Commands

```bash
# Syntax check
cd ansible && ansible-playbook playbook.yml --syntax-check

# Dry run
ansible-playbook -i inventory/localhost.yml playbook.yml --check -e @vars/vault.yml --ask-vault-pass

# Full run
ansible-playbook -i inventory/localhost.yml playbook.yml -e @vars/vault.yml --ask-vault-pass

# Single server (no secrets needed)
ansible-playbook -i inventory/localhost.yml playbook.yml --tags cupertino

# Single server (secrets needed)
ansible-playbook -i inventory/localhost.yml playbook.yml --tags exa -e @vars/vault.yml --ask-vault-pass

# All MCP servers (skip skills)
ansible-playbook -i inventory/localhost.yml playbook.yml --tags mcp -e @vars/vault.yml --ask-vault-pass

# Skills only (no vault pass needed)
ansible-playbook -i inventory/localhost.yml playbook.yml --tags skills

# Uninstall skills
ansible-playbook -i inventory/localhost.yml playbook.yml --tags skills -e skills_state=absent
```

## Architecture

**`ansible/playbook.yml`** — Bootstraps AI development environments on macOS:
- **Roles:** `prerequisites`, `skills`, `mcp` (parameterized, invoked once per server)
- **MCP role:** A single role with tasks for Homebrew install, Claude/Codex registration, and verification. Server config is passed via the `mcp_server` variable from the structured `mcp_servers` dict.
- **Skills role:** Delegates to `install-skills.sh` / `uninstall-skills.sh` in `roles/skills/files/`. Uninstall (`-e skills_state=absent`) removes only managed symlinks and repos.
- **Config:** `group_vars/all/mcp_servers.yml` (server definitions, toggles, CLI casks), `group_vars/all/skills.yml` (skill repos and toggle); `vars/vault.yml` stores API keys (loaded explicitly via `-e @vars/vault.yml`)
- **Prerequisites:** Node.js and uv installs are derived from `mcp_servers` runner types — no hardcoded server lists
- macOS-only, idempotent, supports tag-based selective runs and `--check` dry-run mode

See `ansible/README.md` for full playbook usage documentation.

## Conventions

- Deterministic behavior: stable ordering, fail-fast on conflicts
- Idempotent: all playbooks and roles are safe to re-run
- Commit subjects use imperative mood with scope prefix (e.g., `ansible: add Exa role`, `skills: add duplicate detection`)
- PRs require manual validation notes (install, re-install for idempotency, dry-run, uninstall)
