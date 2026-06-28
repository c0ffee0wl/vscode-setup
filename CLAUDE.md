# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`vscode-setup` is a Debian installer that (1) installs Visual Studio Code from Microsoft's apt repo, (2) applies "local-LLM" VS Code settings via a vendored `configure-vscode`, and (3) optionally installs a GitHub Copilot `.vsix` and writes a profile export. It runs as a regular user (uses `sudo` for apt) and is idempotent (safe to re-run).

There is no build system and no test suite — it is shell + one vendored Python script. "Tests" are syntax checks and smoke runs.

## Commands

```bash
# Run the installer (interactive)
./linux/setup.sh
./linux/setup.sh --yes                              # non-interactive (answer Yes)
./linux/setup.sh --yes --copilot-vsix <path|dir>    # also install a Copilot vsix + profile export

# Syntax check (do this after editing any script)
bash -n linux/setup.sh && bash -n linux/common.sh

# Lint (style warnings SC1091/SC2034/SC2162 are expected — see "Lifted code" below)
shellcheck linux/setup.sh linux/common.sh

# Run the vendored configure-vscode directly (uv resolves json-five via PEP 723)
uv run linux/scripts/configure_vscode.py --dry-run   # preview
uv run linux/scripts/configure_vscode.py --list      # show the settings it manages
uv run linux/scripts/configure_vscode.py             # apply (default scope = user settings)
```

Scripts have a `#!/bin/bash` shebang and rely on bashisms (`mapfile`, `[[ ]]`, negative array indices). The interactive/dev shell here is zsh, so test snippets with `bash -c '...'`, not by pasting into the shell.

## Architecture

`linux/setup.sh` is the entry point. It sources `linux/common.sh`, parses flags, guards (root warning, Debian-family check), then runs three steps in order:

1. `install_vscode` — adds the MS GPG key + the apt source (`linux/configs/vscode.sources` → `/etc/apt/sources.list.d/`), then `apt-get install code`. Runs **unconditionally** (the `has_desktop_environment` check only warns); no-ops if `code` is already present.
2. `configure_vscode_settings` — runs the vendored `configure_vscode.py` via `uv`.
3. `install_copilot` — only when `--copilot-vsix` resolves to a real `.vsix`. A directory arg is globbed (`-iname '*copilot*.vsix'`, highest version via `sort -V`). When (and only when) a vsix is installed, it also writes `VSCODE_SKIP_BUILTIN_EXTENSIONS="GitHub.copilot-chat"` to `~/.profile` — these two actions are deliberately gated together.

Layout mirrors the sibling installers (`llm-setup`, `claude-litellm`, `ct-dfir-llm`): `linux/{common.sh, configs/, scripts/, setup.sh}`. There is no `windows/` yet, but the `linux/` skeleton leaves room for one.

## Conventions you must preserve

- **`linux/common.sh` is lifted near-verbatim from `/opt/linux-setup/linux-setup.sh`.** Keep its helpers (`log`/`warn`/`error`, `prompt_yes_no`, `update_profile_export`, `ensure_zprofile_sources_profile`, `has_desktop_environment`, `is_kali_linux`) faithful to upstream rather than refactoring them. `update_profile_export` is the only sanctioned way to edit `~/.profile` (idempotent). The unused `BLUE`/`FORCE_MODE`/`NO_MODE` shellcheck warnings come from this lift and are accepted.
- **`linux/scripts/configure_vscode.py` is vendored from `/opt/llm-server`.** Keep it in sync with upstream; it is Apache-2.0 like the rest of the repo (relicensed by the author) — see its header. It is run through `uv` using its PEP 723 block (`dependencies = ["json-five"]`), so `uv` is a hard requirement (no python3 fallback).
- **`configure_vscode.py` has no `--user` flag.** Its default scope already *is* user settings (`~/.config/Code/User/settings.json`). Do not pass `--user` — it will error.

## Integration with ct-dfir-llm

`ct-dfir-llm` consumes this repo as a phase: it clones to `/opt/vscode-setup` and invokes `/opt/vscode-setup/linux/setup.sh --yes --copilot-vsix <dir>` as the deploy user. Keep `setup.sh`'s CLI (`--yes`, `--copilot-vsix <path|dir>`) and the `linux/setup.sh` path stable, and keep the Copilot step a clean no-op when no vsix is present (so the phase works whether or not a vsix was baked in).
