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
./linux/setup.sh --yes --capi-url <url>             # also write the agent-host endpoint profile export

# Syntax check (do this after editing any script)
bash -n linux/setup.sh && bash -n linux/common.sh

# Regression tests (no VS Code needed for the capi one)
bash linux/scripts/selftest_capi_url.sh
bash linux/scripts/selftest_copilot_metadata.sh     # needs the apt 'code' build; SKIPs otherwise

# Lint (style warnings SC1091/SC2034/SC2162 are expected — see "Lifted code" below)
shellcheck linux/setup.sh linux/common.sh

# Run the vendored configure-vscode directly (uv resolves json-five via PEP 723)
uv run linux/scripts/configure_vscode.py --dry-run   # preview
uv run linux/scripts/configure_vscode.py --list      # show the settings it manages
uv run linux/scripts/configure_vscode.py             # apply (default scope = user settings)
```

Scripts have a `#!/bin/bash` shebang and rely on bashisms (`mapfile`, `[[ ]]`, negative array indices). The interactive/dev shell here is zsh, so test snippets with `bash -c '...'`, not by pasting into the shell.

## Architecture

`linux/setup.sh` is the entry point. It sources `linux/common.sh`, parses flags, guards (root warning, Debian-family check, `--capi-url` must match `^https?://` — callers pass a static literal, so a malformed value is a bug and is rejected before any install work), then runs four steps in order:

1. `install_vscode` — adds the MS GPG key + the apt source (`linux/configs/vscode.sources` → `/etc/apt/sources.list.d/`), then `apt-get install code`. Runs **unconditionally** (the `has_desktop_environment` check only warns); no-ops if `code` is already present.
2. `configure_vscode_settings` — runs the vendored `configure_vscode.py` via `uv`.
3. `install_copilot` — only when `--copilot-vsix` resolves to a real `.vsix`. A directory arg is globbed (`-iname '*copilot*.vsix'`, highest version via `sort -V`). When (and only when) a vsix is installed, it also writes `VSCODE_SKIP_BUILTIN_EXTENSIONS="GitHub.copilot-chat"` to `~/.profile` — these two actions are deliberately gated together. Before installing, it now also **exports** `VSCODE_SKIP_BUILTIN_EXTENSIONS="GitHub.copilot-chat"` so the bundled same-ID builtin is hidden from `code --install-extension` (otherwise the user vsix inherits the builtin's `isBuiltin`/`isApplicationScoped` metadata and is later dropped as an "obsolete builtin" once the env var hides the builtin at runtime), and **force-uninstalls** any prior `GitHub.copilot-chat` (a plain `--force` reinstall does not clear `isBuiltin`, so an explicit uninstall is required to repair an already-poisoned profile). It then persists the same export to `~/.profile`. Regression test: `linux/scripts/selftest_copilot_metadata.sh`.
4. `configure_agent_host_capi_url` — only when `--capi-url` is given. Writes `VSCODE_AGENT_HOST_CAPI_URL_OVERRIDE="<url>"` to `~/.profile`, pointing the agent host (a VS Code **core** process, 1.129+ — not part of the Copilot extension) at an OpenAI-compatible endpoint. Deliberately **not** gated on a vsix installing, unlike step 3's export: `VSCODE_SKIP_BUILTIN_EXTENSIONS` breaks Copilot when the replacement extension is absent, while the agent-host process exists either way and this override is opt-in by definition. Regression test: `linux/scripts/selftest_capi_url.sh`.

Layout mirrors the sibling installers (`llm-setup`, `claude-litellm`, `ct-dfir-llm`): `linux/{common.sh, configs/, scripts/, setup.sh}`. There is no `windows/` yet, but the `linux/` skeleton leaves room for one.

## Conventions you must preserve

- **`linux/common.sh` is lifted near-verbatim from `/opt/linux-setup/linux-setup.sh`.** Keep its helpers (`log`/`warn`/`error`, `prompt_yes_no`, `update_profile_export`, `ensure_zprofile_sources_profile`, `has_desktop_environment`, `is_kali_linux`) faithful to upstream rather than refactoring them. `update_profile_export` is the only sanctioned way to edit `~/.profile` (idempotent). The unused `BLUE`/`FORCE_MODE`/`NO_MODE` shellcheck warnings come from this lift and are accepted.
- **`linux/scripts/configure_vscode.py` is vendored from `/opt/llm-server`.** Keep it in sync with upstream; it is Apache-2.0 like the rest of the repo (relicensed by the author) — see its header. It is run through `uv` using its PEP 723 block (`dependencies = ["json-five"]`), so `uv` is a hard requirement (no python3 fallback).
- **`configure_vscode.py` has no `--user` flag.** Its default scope already *is* user settings (`~/.config/Code/User/settings.json`). Do not pass `--user` — it will error.

## Integration with ct-dfir-llm

`ct-dfir-llm` (and its `ct-kali-llm` sibling) consumes this repo as a phase: it clones to `/opt/vscode-setup` and invokes `/opt/vscode-setup/linux/setup.sh --yes --copilot-vsix <dir> --capi-url http://127.0.0.1:4000` as the deploy user (the URL is its local LiteLLM proxy). Keep `setup.sh`'s CLI (`--yes`, `--copilot-vsix <path|dir>`, `--capi-url <url>`) and the `linux/setup.sh` path stable, and keep the Copilot step a clean no-op when no vsix is present (so the phase works whether or not a vsix was baked in). Ordering note for CLI additions: the forks pull this repo at run time, so a new flag must be pushed here **before** a fork starts passing it — against a stale checkout the unknown option makes the whole invocation fail (the fork downgrades that to a warn and skips its VS Code phase for the run).
