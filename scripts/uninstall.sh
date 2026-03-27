#!/bin/bash
set -euo pipefail

BINARY="wsl-screenshot-cli"
INSTALL_PATH="${HOME}/.local/bin/${BINARY}"
BASHRC="${HOME}/.bashrc"
CLAUDE_SETTINGS="${HOME}/.claude/settings.json"

info() {
    printf "\033[1;34m==>\033[0m %s\n" "$*"
}

warn() {
    printf "\033[1;33mwarning:\033[0m %s\n" "$*" >&2
}

success() {
    printf "\033[1;32mdone:\033[0m %s\n" "$*"
}

remove_bashrc_block() {
    if [ ! -f "$BASHRC" ]; then
        return
    fi

    python3 - "$BASHRC" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
blocks = [
    '\n# Added by wsl-screenshot-cli installer\nif [ -d "$HOME/.local/bin" ] && [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then\n    export PATH="$HOME/.local/bin:$PATH"\nfi\n',
    '\n# Auto-start wsl-screenshot-cli (added by installer)\nwsl-screenshot-cli start --daemon 2>/dev/null\n',
]
for block in blocks:
    text = text.replace(block, "\n")
path.write_text(text)
PY
}

remove_claude_hooks() {
    if [ ! -f "$CLAUDE_SETTINGS" ]; then
        return
    fi

    if ! command -v jq >/dev/null 2>&1; then
        warn "jq not found; leaving ${CLAUDE_SETTINGS} unchanged"
        return
    fi

    tmpfile=$(mktemp "${CLAUDE_SETTINGS}.XXXXXX")
    jq '
      if .hooks then
        .hooks.SessionStart = ((.hooks.SessionStart // []) | map(select((.hooks // []) | map(.command // "") | any(contains("wsl-screenshot-cli")) | not)))
        | .hooks.SessionEnd = ((.hooks.SessionEnd // []) | map(select((.hooks // []) | map(.command // "") | any(contains("wsl-screenshot-cli")) | not)))
      else . end
    ' "$CLAUDE_SETTINGS" > "$tmpfile"
    mv "$tmpfile" "$CLAUDE_SETTINGS"
}

if command -v "$BINARY" >/dev/null 2>&1; then
    "$BINARY" stop >/dev/null 2>&1 || true
fi

if [ -f "$INSTALL_PATH" ]; then
    rm -f "$INSTALL_PATH"
    success "Removed ${INSTALL_PATH}"
fi

remove_bashrc_block
success "Removed installer-managed ~/.bashrc additions"

remove_claude_hooks
success "Removed installer-managed Claude Code hooks where possible"

info "Uninstall finished. Open a new shell or run 'hash -r' if needed."
