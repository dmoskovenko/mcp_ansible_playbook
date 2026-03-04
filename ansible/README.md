# MCP Server Ansible Playbook

Ansible playbook that installs and registers MCP servers (Cupertino, Exa, XcodeBuildMCP, Context7, SwiftLens, Figma) with Claude Code and Codex CLIs on macOS.

## Prerequisites

- macOS (Homebrew is installed automatically if missing)
- Ansible (`brew install ansible`)
- `community.general` collection:
  ```bash
  ansible-galaxy collection install community.general
  ```

The playbook installs Homebrew, Node.js, Claude Code, and Codex automatically — on a fresh Mac only Ansible itself is needed. uv is installed automatically when SwiftLens is enabled.

## Vault Setup

1. Add your API keys to the vault file:
   ```bash
   cd ansible
   # Edit the plaintext template
   vi group_vars/all/vault.yml
   # Replace REPLACE_ME_THEN_ENCRYPT with your actual keys:
   #   vault_exa_api_key       — Exa search API key
   #   vault_context7_api_key  — Context7 API key

   # Encrypt the file
   ansible-vault encrypt group_vars/all/vault.yml
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
ansible-playbook -i inventory/localhost.yml playbook.yml --check --ask-vault-pass
```

**Full run:**
```bash
ansible-playbook -i inventory/localhost.yml playbook.yml --ask-vault-pass
```

**With vault password file:**
```bash
ansible-playbook -i inventory/localhost.yml playbook.yml --vault-password-file .vault_pass
```

**Run a single role via tags:**
```bash
ansible-playbook -i inventory/localhost.yml playbook.yml --tags cupertino --ask-vault-pass
ansible-playbook -i inventory/localhost.yml playbook.yml --tags exa --ask-vault-pass
ansible-playbook -i inventory/localhost.yml playbook.yml --tags xcodebuildmcp --ask-vault-pass
ansible-playbook -i inventory/localhost.yml playbook.yml --tags context7 --ask-vault-pass
ansible-playbook -i inventory/localhost.yml playbook.yml --tags swiftlens --ask-vault-pass
ansible-playbook -i inventory/localhost.yml playbook.yml --tags figma
```

## Toggling Servers

Edit `group_vars/all/mcp_servers.yml` and adjust `mcp_servers_enabled`:

```yaml
mcp_servers_enabled:
  - cupertino
  # - exa            # commented out = skipped
  - xcodebuildmcp
  - context7
  - swiftlens
  - figma
```

## Skills

The `skills` role is a thin wrapper that delegates to the root-level `install-skills.sh` and `uninstall-skills.sh` bash scripts, which clone external skill repositories, discover directories containing `SKILL.md` files, and create symlinks into `~/.claude/skills/` and `~/.codex/skills/`.

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

Set `skills_enabled: false` in `group_vars/all/mcp_servers.yml`.

## Verification

After a successful run, confirm registration:

```bash
claude mcp get cupertino
claude mcp get exa
claude mcp get xcodebuildmcp
claude mcp get context7
claude mcp get swiftlens
claude mcp get figma
codex mcp get cupertino
codex mcp get exa
codex mcp get xcodebuildmcp
codex mcp get context7
codex mcp get swiftlens
```

## Idempotency

Both `claude mcp add` and `codex mcp add` overwrite existing entries with the same name, so re-running the playbook is safe.
