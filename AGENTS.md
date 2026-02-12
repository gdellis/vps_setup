# VPS Setup - Agent Guidelines

This document provides guidelines for agentic coding assistants working on the VPS Setup project.

## Build / Lint / Test Commands

### Running Scripts (Testing)

```bash
# Run a specific module directly (requires sudo)
sudo ./01_initial_hardening.sh
sudo ./02_docker_setup.sh
sudo ./03_wireguard_setup.sh
sudo ./04_monitoring_setup.sh
sudo ./05_alerting_setup.sh

# Run the full installation pipeline
sudo ./install_all.sh
```

### Linting

```bash
# Shell script linting with ShellCheck
shellcheck 01_initial_hardening.sh
shellcheck 02_docker_setup.sh
shellcheck 03_wireguard_setup.sh
shellcheck 04_monitoring_setup.sh
shellcheck 05_alerting_setup.sh
shellcheck lib/*.sh

# Check all bash scripts recursively
find . -name "*.sh" -exec shellcheck {} \;

# Markdown documentation linting with markdownlint
markdownlint *.md
markdownlint README.md Design.md AGENTS.md
find . -name "*.md" -exec markdownlint {} \;
```

### Dry Run / Validation (without root)

```bash
# Syntax check only
bash -n 01_initial_hardening.sh

# Source library functions for testing (if not running as root)
source ./lib/common.sh
source ./lib/logger.sh
```

## Code Style Guidelines

### Bash Scripting

#### Shebang and Interpreter

- Always use `#!/bin/bash` at the top of scripts
- Target Bash 4.0+ features for compatibility with Ubuntu 20.04+

#### Imports and Source Order

```bash template
#!/bin/bash
# 1. Source shared libraries first
source ./lib/common.sh
source ./lib/logger.sh

# 2. Then script-specific variables (sourced from .env if available)
[ -f .env ] && source .env

# 3. Then define script constants
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
```

#### Naming Conventions

- **Functions**: snake_case, descriptive: `install_docker()`, `configure_wireguard()`
- **Variables**: UPPER_CASE for constants, lower_case for locals: `SSH_PORT`, `username`
- **Readonly values**: Mark with `readonly`: `readonly CONFIG_PATH="/etc/wireguard/wg0.conf"`
- **Private functions**: Prefix with `_`: `_validate_config()`

#### Error Handling

- Always check return codes for critical operations: `command || exit 1`
- Use `set -euo pipefail` at script start for strict error handling
- Provide meaningful error messages: `log_error "Failed to create user: $username"`
- Use `trap` for cleanup on error: `trap cleanup ERR EXIT`

#### Formatting

- Use 4-space indentation (not tabs)
- Long commands: break into logical lines with backslashes
- Comments: `#` prefix, describe **why** not **what** (obvious code needs no comment)
- Separate functions with blank lines

#### Logging

- Use library logging functions: `log_info`, `log_success`, `log_warning`, `log_error`
- Log user-facing actions with numbered steps: `[1/5] Installing Docker...`
- Log to file with `log_to_file "INFO" "message"`

#### Conditionals

```bash
# Use [[ ]] for string/variable comparisons
if [[ -z "$variable" ]]; then
  log_error "Variable is empty"
fi

# Use (( )) for arithmetic
if (( count > 5 )); then
  log_info "Count is $count"
fi

# Use -eq for numeric equality in [ ]
if [ "$exit_code" -eq 0 ]; then
  log_success "Complete"
fi
```

#### Command Substitution

- Use `$()` syntax instead of backticks: `result=$(command)`
- Quote variables: `"$result"` to prevent word splitting

#### User Input

- When prompts are needed, use `read` with clear instructions
- Validate input before proceeding
- Provide sensible defaults via .env file instead of interactive input

### Markdown Documentation

#### Formatting Standards

- Use `markdownlint` to validate documentation before committing
- Headers should start at level 1 (`#`) for the document title, increment logically
- Use fenced code blocks for code examples: use \`\`\`bash for scripts, \`\`\`mermaid for diagrams
- Name code blocks with expected filenames after the language when the code represents a specific file
- Example: Use \`\`\`bash common.sh for a library function file
- Use descriptive names for generic examples: \`\`\`bash example
- Mermaid diagrams: filename not required
- Include mermaid diagrams where visual representation adds clarity
- Keep line length under 100-120 characters for readability
- Use lists with consistent spacing and indentation

#### mermaid Diagram Guidelines

- Use `mermaid` syntax for system architecture and flow diagrams
- Include `flowchart TB` (top-bottom) for vertical layouts
- Label subgraphs clearly: `subgraph Name["Display Name"]`
- Use color styling for better visualization: `style NODE fill:#hex`
- Avoid parentheses `()` in node labels - use colons `:` instead (parser limitation)

#### Documentation Structure

- Overview/Introduction at the top
- Sections ordered logically: Setup -> Configuration -> Reference
- Include code examples in code blocks with syntax highlighting
- Link related sections using Markdown reference-style links when possible
- Keep tables for comparison data or configuration options

## Security Guidelines

- Never hardcode passwords, keys, or tokens
- Always source `.env` for configuration values
- Validate all user input before using in commands
- Use `readonly` for immutable paths and configuration variables
- Backup files before editing: `backup_file /etc/file.conf`
- Sensitive files must be excluded by .gitignore (check before committing)

## File Organization

### Script Header Template

```bash
#!/bin/bash
# Script Name: 01_initial_hardening.sh
# Purpose:     Baseline security hardening setup
# Prerequisites: Root access, Ubuntu/Debian
# Usage:       sudo ./01_initial_hardening.sh
# Dependencies: ./lib/common.sh, ./lib/logger.sh
```

### Script Structure

1. Shebang
2. Header comments
3. Source libraries
4. Global constants/readonly variables
5. Main function
6. Helper functions
7. Call main() at end

## Testing Practices

- Test scripts in a VM or container before production use
- Verify dependencies are checked before attempting operations
- Validate configuration files created have correct syntax
- Test rollback scenarios (service failures, network issues)
- Verify idempotency (scripts can be run multiple times safely)

## When Working on This Codebase

1. Always read `Design.md` first to understand architecture
2. Check `install_all.sh` for expected execution order
3. Ensure library functions in `lib/` are used consistently
4. Maintain compatibility with Ubuntu 20.04+ and Debian 11+
5. Update this AGENTS.md if introducing new tooling or standards

## Commit Message Style

Follow the existing pattern:

- Capitalize the first letter of the subject line
- Use present tense: "Add" not "Added", "Fix" not "Fixed"
- Keep subject line under 72 characters
- Separate body with blank line if needed
- Reference related Design.md sections when relevant

## Git Workflow and PR Best Practices

### Branch Naming

- Use descriptive branch names: `feature/monitoring-setup`, `bugfix/ssh-port-config`
- Use `fix/` for bug fixes, `feature/` for new features, `docs/` for documentation
- Keep branch names lowercase with hyphens: `alertmanager-smtp-config`, not `AlertManager_SMTP_Config`

### Commit Strategy

- Make small, focused commits that do one thing
- Commits should be atomic and able to be reverted independently
- Run linters before committing: `shellcheck` and `markdownlint`
- Never commit:
  - `.env` files (contains sensitive data)
  - SSH keys, WireGuard private keys
  - Generated client configs
  - Any files listed in `.gitignore`

### Pull Request Guidelines

- PR titles should follow commit message style (present tense, capitalized)
- Include PR description with:
  - Summary of changes
  - What problem this solves
  - How to test/verify
  - Any breaking changes
- Link related issues or Design.md sections
- Keep PRs focused on a single feature or fix
- Update documentation (README.md, AGENTS.md) alongside code changes

### Pre-Merge Checklist

Before merging a PR:

- All linting passes: `shellcheck` and `markdownlint`
- Code follows AGENTS.md style guidelines
- Documentation is updated
- Sensitive files are not included (check `.gitignore`)
- Breaking changes are documented
- Related tests pass (if applicable)
- Revert capability: ensure changes can be cleanly reverted if needed

### Updating Code in Main Branch

When asked to commit changes:

- Review the diff to understand what will be committed
- Create descriptive commit following the style guide
- Do not push to remote unless explicitly requested
- Do not force push to protected branches (main, master, dev)

### Working with Feature Branches

1. Create feature branch from main: `git checkout -b feature/branch-name`
2. Make changes and commit frequently
3. Push to remote: `git push -u origin feature/branch-name`
4. Create PR with clear description
5. Address review feedback
6. Update branch and resolve conflicts if needed: `git rebase main`
7. Merge after approval

### Git Safety Rules

- NEVER update `git config` (user.email, user.name)
- NEVER run destructive git commands (push --force, hard reset) without explicit user request
- NEVER skip hooks (--no-verify, --no-gpg-sign) unless user explicitly requests
- NEVER force push to main/master (warn the user if requested)
- Avoid git commit --amend. Only use when ALL conditions are met:
  - User explicitly requested amend
  - OR commit succeeded but pre-commit hook auto-modified files that need including
  - AND HEAD commit was created by you in this conversation (verify: `git log -1 --format='%an %ae'`)
  - AND commit has NOT been pushed to remote (verify: `git status` shows "Your branch is ahead")
- CRITICAL: If commit FAILED or was REJECTED by hook, NEVER amend - fix the issue and create a NEW commit
- CRITICAL: If you already pushed to remote, NEVER amend unless user explicitly requests it (requires force push)
- NEVER commit changes unless the user explicitly asks you to. It is VERY IMPORTANT to only commit when explicitly asked,
  otherwise the user will feel that you are being too proactive.
