#!/usr/bin/env bash
# _iterm-lib.sh — shared helpers pra iterm-tab, iterm-win, claude-win
# Origem: fix 2026-05-12 — payloads longos OR UTF-8 multi-byte quebravam
# transporte shell→AppleScript→iTerm. Single source of truth.
#
# Update 2026-05-12 v2 (audit security+reliability):
#   - C1: shell injection guard via printf %q em DIR
#   - H1: validação iTerm instalado + osascript disponível
#   - H2: claude REPL ready-check em vez de delay hardcoded
#   - M1: trap cleanup pra EXIT+HUP+INT+TERM

# Escapa string pra usar dentro de "..." em AppleScript heredoc (inline path)
iterm_escape_inline() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

# Decide se payload precisa de tmpfile (>500 chars OR contém byte não-print/non-space)
iterm_needs_tmpfile() {
    local cmd="$1"
    if [[ ${#cmd} -gt 500 ]]; then return 0; fi
    if LC_ALL=C printf '%s' "$cmd" | LC_ALL=C grep -q '[^[:print:][:space:]]'; then return 0; fi
    return 1
}

# Cria tmpfile com payload + ecoa o path (caller deve usar iterm_cleanup_trap)
iterm_write_tmpfile() {
    local cmd="$1"
    local tmpfile
    tmpfile="$(mktemp -t iterm-payload.XXXXXX)"
    chmod 600 "$tmpfile"  # defensive: explicit owner-only perms
    printf '%s' "$cmd" > "$tmpfile"
    printf '%s' "$tmpfile"
}

# C1 fix: shell-quote DIR pra prevent injection via paths com chars especiais.
# Returns shell-quoted DIR (use em `cd $(iterm_safe_dir "$DIR") && ...`).
iterm_safe_dir() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        echo "❌ Pasta não existe: $dir" >&2
        return 1
    fi
    printf '%q' "$dir"
}

# H1 fix: precheck environment — osascript existe + iTerm instalado.
iterm_precheck() {
    if ! command -v osascript >/dev/null 2>&1; then
        echo "❌ osascript não encontrado (macOS only)" >&2
        return 1
    fi
    if ! osascript -e 'tell application "System Events" to exists application process "iTerm2"' >/dev/null 2>&1; then
        # iTerm não está rodando — tenta abrir
        if ! open -ga iTerm 2>/dev/null; then
            echo "❌ iTerm2 não instalado ou inacessível" >&2
            return 1
        fi
        sleep 0.5  # give iTerm time to launch
    fi
    return 0
}

# M1 fix: trap cleanup pra múltiplos sinais (não só EXIT).
# Usage: iterm_cleanup_trap "$TMPFILE"
iterm_cleanup_trap() {
    local tmpfile="$1"
    # shellcheck disable=SC2064  # we WANT immediate expansion of $tmpfile
    trap "rm -f '$tmpfile'" EXIT HUP INT TERM
}
