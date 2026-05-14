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

# -----------------------------------------------------------------------------
# v3 additive helpers (2026-05-13). All opt-in via flag/env — without flags,
# scripts behave identically to v2.
# -----------------------------------------------------------------------------

# Standardized usage helper (--help flag across iterm-tab/win/claude-win).
# Caller passes: script_name + usage_summary + extra_flags_block (optional).
iterm_show_help() {
    local script="$1"
    local summary="$2"
    local extra="${3:-}"
    cat <<HELP
Usage: $script [OPTIONS] <dir> [<cmd-or-prompt-file>]

$summary

Options:
  --help                   Show this help and exit
  --label <name>           Custom iTerm tab/window name (set name of session)
  --prompt-file <file>     Read command/prompt from file (robust escape, bypasses AppleScript cap)$extra

Env:
  SPAWN_LOG=1              Append record to ~/.claude/spawn-log.txt (script + dir + cmd + timestamp)

Examples:
  $script /path/to/project "echo hello"
  $script --label "build-watch" --prompt-file /tmp/cmd.sh /path/to/project

See: ~/bin/README.md
HELP
}

# Opt-in audit log via SPAWN_LOG=1 env var.
# Idempotent — without SPAWN_LOG set, full no-op. Appends to ~/.claude/spawn-log.txt.
iterm_audit_log() {
    [[ "${SPAWN_LOG:-0}" != "1" ]] && return 0
    local script="$1"
    local dir="$2"
    local cmd_or_prompt="$3"
    local log="${SPAWN_LOG_PATH:-$HOME/.claude/spawn-log.txt}"
    mkdir -p "$(dirname "$log")" 2>/dev/null || true
    {
        printf '[%s] script=%s dir=%s cmd_len=%d label=%s\n' \
            "$(date '+%Y-%m-%d %H:%M:%S')" \
            "$script" \
            "$dir" \
            "${#cmd_or_prompt}" \
            "${ITERM_LABEL:-<none>}"
    } >> "$log" 2>/dev/null || true
    return 0
}

# AppleScript snippet to rename session (--label flag).
# Echoes empty string if ITERM_LABEL not set — caller embeds unconditionally.
iterm_label_snippet() {
    [[ -z "${ITERM_LABEL:-}" ]] && return 0
    local label="$ITERM_LABEL"
    # escape quotes for AppleScript safety
    label="${label//\"/\\\"}"
    printf '      set name to "%s"' "$label"
}

# Shared parser for additive flags (--help / --label / --prompt-file).
# IMPORTANT: must be called directly (NOT via process substitution / subshell) so
# that ITERM_LABEL, ITERM_PROMPT_FILE, and POSITIONAL global vars are set in the
# caller's shell. With set -u, callers must initialize the 3 globals BEFORE the call.
#
# Caller pattern (required):
#   ITERM_LABEL=""
#   ITERM_PROMPT_FILE=""
#   POSITIONAL=()
#   iterm_parse_flags "script-name" "summary" "$@"
#   # POSITIONAL, ITERM_LABEL, ITERM_PROMPT_FILE are now populated
iterm_parse_flags() {
    local script_name="$1"
    local summary="$2"
    shift 2
    # POSITIONAL is a global array — reset it here
    POSITIONAL=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help|-h)
                iterm_show_help "$script_name" "$summary" >&2
                exit 0
                ;;
            --label)
                ITERM_LABEL="${2:-}"
                if [[ -z "$ITERM_LABEL" ]]; then
                    echo "ERR: --label requires a value" >&2
                    exit 1
                fi
                shift 2
                ;;
            --prompt-file)
                ITERM_PROMPT_FILE="${2:-}"
                if [[ -z "$ITERM_PROMPT_FILE" ]] || [[ ! -f "$ITERM_PROMPT_FILE" ]]; then
                    echo "ERR: --prompt-file requires an existing file: ${2:-<missing>}" >&2
                    exit 1
                fi
                shift 2
                ;;
            --)
                shift
                POSITIONAL+=("$@")
                break
                ;;
            *)
                POSITIONAL+=("$1")
                shift
                ;;
        esac
    done
}
