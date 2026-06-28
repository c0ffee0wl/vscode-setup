# vscode-setup

Standalone installer for Visual Studio Code on Debian-based systems, laid out
to mirror the sibling installers (`linux/{common.sh,configs,scripts,setup.sh}`).
It:

1. Installs VS Code from Microsoft's apt repository.
2. Applies local-LLM VS Code settings via a vendored `configure-vscode`
   (`linux/scripts/configure_vscode.py`, run with [uv](https://docs.astral.sh/uv/)
   — only dependency is `json-five`, resolved from PEP 723 metadata).
3. Optionally installs/updates a GitHub Copilot `.vsix` extension and writes
   `export VSCODE_SKIP_BUILTIN_EXTENSIONS="GitHub.copilot-chat"` to `~/.profile`.

Helpers and the VS Code install logic are lifted from
[`linux-setup`](https://github.com/c0ffee0wl/linux-setup).

## Requirements

- A Debian-based distribution (Debian/Ubuntu/Kali).
- `uv` on `PATH` (used to run `configure-vscode`).
- `sudo` privileges (for the apt install). Run as a regular user, not root.

## Usage

```bash
./linux/setup.sh                 # interactive
./linux/setup.sh --yes           # non-interactive
./linux/setup.sh --yes --copilot-vsix /path/to/dir-with-copilot-vsix
```

| Flag | Purpose |
|------|---------|
| `--copilot-vsix <path\|dir>` | Install/update a Copilot extension from a `.vsix` file, or the highest-versioned `copilot*.vsix` in a directory. Also writes the `VSCODE_SKIP_BUILTIN_EXTENSIONS` profile export. Skipped cleanly if no vsix is found. |
| `--force`, `-f`, `--yes`, `-y` | Non-interactive; answer "Yes" to prompts. |
| `--no`, `-n` | Non-interactive; answer "No" to prompts. |
| `--help`, `-h` | Show help. |

Re-runs are idempotent: VS Code install no-ops when `code` is present, the
extension is reinstalled with `--force`, the profile export is updated in place,
and `configure-vscode` backs up and diffs before writing.

## Layout

```
linux/setup.sh    main installer
linux/common.sh   shared helpers (lifted from linux-setup)
linux/configs/    vscode.sources (Microsoft apt repo file)
linux/scripts/    configure_vscode.py (vendored configure-vscode)
```

## License

This repository is Apache-2.0. `linux/scripts/configure_vscode.py` is vendored
from the `llm-server` project and retains its origin license
(GPL-3.0-or-later); see the header in that file.
