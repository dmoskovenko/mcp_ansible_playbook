# MCP Server Ansible Playbook

Ansible playbook that installs and registers MCP servers (Cupertino, Exa, XcodeBuildMCP, Context7, SwiftLens, Figma, Firecrawl, Parallel) with Claude Code and Codex CLIs on macOS.

## Prerequisites

- macOS (Homebrew is installed automatically if missing)
- Ansible (`brew install ansible`)
- `community.general` collection:
  ```bash
  ansible-galaxy collection install community.general
  ```

The playbook installs Homebrew, Node.js, Claude Code, and Codex automatically — on a fresh Mac only Ansible itself is needed. uv is installed automatically when any uvx-based server is enabled.

## Architecture

All MCP servers are defined as structured entries in `group_vars/all/mcp_servers.yml`. A single parameterized `mcp` role handles installation, registration with both CLIs, and verification for every server type (npx, uvx, binary, http). Adding a new server requires only a new entry in the config dict and an entry in `playbook.yml` — no new role files.

Skill repositories are configured in `group_vars/all/skills.yml` and passed to the shell scripts via the `SKILL_REPOS` environment variable.

## Vault Setup

1. Add your API keys to the vault file:
   ```bash
   cd ansible
   # Edit the plaintext template
   vi vars/vault.yml
   # Replace REPLACE_ME_THEN_ENCRYPT with your actual keys:
   #   vault_exa_api_key       — Exa search API key
   #   vault_context7_api_key  — Context7 API key
   #   vault_firecrawl_api_key — Firecrawl API key
   #   vault_parallel_api_key  — Parallel Search API key
   # Encrypt the file
   ansible-vault encrypt vars/vault.yml
   ```

2. Optionally create a vault password file (gitignored):
   ```bash
   echo 'your-vault-password' > .vault_pass
   chmod 600 .vault_pass
   ```

## Usage

Run from the `ansible/` directory.

**Syntax check:**
```bash
ansible-playbook playbook.yml --syntax-check
```

**Dry run (check mode):**
```bash
ansible-playbook -i inventory/localhost.yml playbook.yml --check -e @vars/vault.yml --ask-vault-pass
```

**Full run:**
```bash
ansible-playbook -i inventory/localhost.yml playbook.yml -e @vars/vault.yml --ask-vault-pass
```

**With vault password file:**
```bash
ansible-playbook -i inventory/localhost.yml playbook.yml -e @vars/vault.yml --vault-password-file .vault_pass
```

**Run a single server via tags (no secrets needed):**
```bash
ansible-playbook -i inventory/localhost.yml playbook.yml --tags cupertino
ansible-playbook -i inventory/localhost.yml playbook.yml --tags swiftlens
```

**Run a single server via tags (secrets needed):**
```bash
ansible-playbook -i inventory/localhost.yml playbook.yml --tags exa -e @vars/vault.yml --ask-vault-pass
```

**Run all MCP servers (skip skills):**
```bash
ansible-playbook -i inventory/localhost.yml playbook.yml --tags mcp -e @vars/vault.yml --ask-vault-pass
```

## Toggling Servers

Edit `group_vars/all/mcp_servers.yml` and adjust `mcp_servers_enabled`:

```yaml
mcp_servers_enabled:
  - cupertino
  - exa
  - xcodebuildmcp
  - context7
  - swiftlens
  - figma
  - firecrawl
  - parallel
```

Node.js and uv prerequisites are installed automatically based on which server runners (npx/uvx) are enabled.

## Skills

The `skills` role delegates to `install-skills.sh` and `uninstall-skills.sh` in `roles/skills/files/`. Skill repositories are defined in `group_vars/all/skills.yml` under `skill_repos` and passed to the scripts via the `SKILL_REPOS` environment variable.

**Install skills only:**
```bash
ansible-playbook -i inventory/localhost.yml playbook.yml --tags skills
```

No `--ask-vault-pass` is needed for skills-only runs (no API keys required).

**Uninstall skills:**
```bash
ansible-playbook -i inventory/localhost.yml playbook.yml --tags skills -e skills_state=absent
```

This removes only managed symlinks (those pointing into the clone root) and cloned repos. Unrelated entries like `~/.codex/skills/.system` are preserved.

**Disable skills in full runs:**

Set `skills_enabled: false` in `group_vars/all/skills.yml`.

## Verification

After a successful run, confirm registration:

```bash
claude mcp get cupertino
claude mcp get exa
claude mcp get xcodebuildmcp
claude mcp get context7
claude mcp get swiftlens
claude mcp get figma
claude mcp get firecrawl
claude mcp get parallel
codex mcp get cupertino
codex mcp get exa
codex mcp get xcodebuildmcp
codex mcp get context7
codex mcp get swiftlens
codex mcp get firecrawl
codex mcp get parallel
```

## Idempotency

Both `claude mcp add` and `codex mcp add` overwrite existing entries with the same name, so re-running the playbook is safe. Registration tasks report `ok` (not `changed`) since they are idempotent.
