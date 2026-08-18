# vscode-setup

Installs Visual Studio Code on Debian-based systems. It uses the same
`linux/{common.sh,configs,scripts,setup.sh}` layout as the sibling installers,
and it:

1. Installs VS Code from Microsoft's apt repository.
2. Applies local-LLM VS Code settings with a vendored `configure-vscode`
   (`linux/scripts/configure_vscode.py`), run via [uv](https://docs.astral.sh/uv/).
   Its one dependency, `json-five`, comes from the script's PEP 723 metadata.
3. Optionally installs or updates a GitHub Copilot `.vsix` and writes
   `export VSCODE_SKIP_BUILTIN_EXTENSIONS="GitHub.copilot-chat"` to `~/.profile`.
4. Optionally writes `export VSCODE_AGENT_HOST_CAPI_URL_OVERRIDE="<url>"` to
   `~/.profile`, pointing the VS Code agent host (VS Code core, 1.129+) at an
   OpenAI-compatible endpoint such as a local LiteLLM proxy.

Helpers and the VS Code install steps are lifted from
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
./linux/setup.sh --yes --copilot-vsix /path/to/dir --capi-url http://127.0.0.1:4000
```

| Flag | Purpose |
|------|---------|
| `--copilot-vsix <path\|dir>` | Install/update a Copilot extension from a `.vsix` file, or the highest-versioned `copilot*.vsix` in a directory. Also writes the `VSCODE_SKIP_BUILTIN_EXTENSIONS` profile export. Exports that variable **before** installing and force-removes any prior `GitHub.copilot-chat` copy, so the override is written with clean metadata and loads on first launch. Skipped cleanly if no vsix is found. |
| `--capi-url <url>` | Write the `VSCODE_AGENT_HOST_CAPI_URL_OVERRIDE` profile export, pointing the VS Code agent host at an OpenAI-compatible endpoint. Must be an `http(s)://` URL; rejected at parse time otherwise. Unlike the Copilot export, this is gated only on the flag (the agent host is a VS Code core process that exists with or without the extension). |
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

Apache-2.0. `linux/scripts/configure_vscode.py` is vendored from the
`llm-server` project and relicensed under Apache-2.0 for this repository.
