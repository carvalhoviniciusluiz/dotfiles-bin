# ~/bin — Personal iTerm helpers

> 🇧🇷 Versão em português: [README.pt-BR.md](./README.pt-BR.md)

Collection of shell helpers for spawning iTerm2 tabs/windows on macOS, with [Claude Code CLI](https://claude.com/claude-code) integration. Share `_iterm-lib.sh` as a single source of truth for escaping and validation.

---

## Files

### `_iterm-lib.sh` — shared library

Not directly executable — provides helpers used by the 3 scripts below:

| Function | Purpose |
|----------|---------|
| `iterm_escape_inline <str>` | Escapes `\` and `"` for interpolation in AppleScript `"..."` inline (short ASCII payloads) |
| `iterm_needs_tmpfile <cmd>` | Decides whether the payload needs the tmpfile branch (>500 chars OR contains multi-byte UTF-8) |
| `iterm_write_tmpfile <cmd>` | Writes payload to `mktemp` with 0600 perms and echoes the path |
| `iterm_safe_dir <dir>` | Validates directory existence + shell-quotes via `printf %q` (prevents injection) |
| `iterm_precheck` | Validates `osascript` availability + attempts `open -ga iTerm` if inactive |
| `iterm_cleanup_trap <tmpfile>` | Registers multi-signal trap (EXIT, HUP, INT, TERM) to remove tmpfile |

**Origin of fixes**:
- 2026-05-12 v1: tmpfile branch for long OR UTF-8 payloads (resolved "PS2 hanging" spawn caused by insufficient inline escape)
- 2026-05-12 v2 (security + reliability audit):
  - C1: shell injection via DIR (CRITICAL)
  - H1: `osascript` + iTerm precheck
  - M1: multi-signal cleanup trap
  - Defensive: explicit `chmod 600` on tmpfile

---

### `iterm-tab` — opens a new tab in the active iTerm window

```bash
~/bin/iterm-tab <DIR> [COMMAND...]
```

**Arguments**:
- `DIR` (default `$PWD`): working directory
- `COMMAND...` (optional): command(s) to run after `cd $DIR`

**Behavior**:
- Opens a new **tab** in the current iTerm window (does not create a new window)
- Auto-detects whether tmpfile branch is needed
- Fails gracefully if DIR is missing OR iTerm is unreachable

**Examples**:

```bash
# Open tab in ~/Documents (no command)
~/bin/iterm-tab ~/Documents

# Open tab in a project and run dev server
~/bin/iterm-tab ~/Workspaces/my-app "npm run dev"

# Open tab + Claude TL persona
~/bin/iterm-tab \
  "~/Developments/Workspaces/my-project" \
  "claude --agent tech-lead --model opus 'Onboarding TL fresh'"
```

---

### `iterm-win` — opens a new iTerm window

```bash
~/bin/iterm-win <DIR> [COMMAND...]
```

Same signature as `iterm-tab`, but creates a **new window** instead of a tab. Useful for workflows that need side-by-side visibility (e.g. monitoring a build in one window while editing in another).

**Examples**:

```bash
# New window tailing logs
~/bin/iterm-win ~/Workspaces/my-app "tail -f logs/dev.log"

# New window in project + Claude Code
~/bin/iterm-win ~/projects/some-project "claude"
```

---

### `claude-win` — new window with Claude Code + long prompt loaded from a file

```bash
~/bin/claude-win <DIR> <PROMPT_FILE>
```

**Arguments**:
- `DIR`: project directory (required, validated)
- `PROMPT_FILE`: `.md`/`.txt` file with the long prompt (required, validated)

**Difference vs `iterm-tab + claude '<prompt>'`**:
- Accepts large prompts (>500 chars) OR UTF-8/accent-heavy content via tmpfile (avoids AppleScript corruption)
- Useful for spawning a fresh TL with extensive onboarding, system briefings, etc.

**Examples**:

```bash
# Create a prompt file and spawn Claude with context
echo "You are a PR reviewer. Analyze the last 3 commits..." > /tmp/review-prompt.md
~/bin/claude-win ~/projects/some-project /tmp/review-prompt.md

# Complete TL onboarding
~/bin/claude-win \
  ~/Workspaces/my-plugin \
  ~/Workspaces/my-plugin/plans/handoffs/HANDOFF_SESSION_LATEST.md
```

---

## Common usage patterns

### Parallel spawn of N tabs

```bash
for dir in ~/projects/*/; do
  ~/bin/iterm-tab "$dir" "git status"
done
```

### TL handoff workflow (project-specific TL handoff pattern)

```bash
# Current TL session prepares the persisted handoff
git commit -m "docs(handoff): ..." plans/handoffs/HANDOFF_SESSION_<date>.md

# Spawn a fresh TL in a tab — onboarding via handoff (not inline)
~/bin/iterm-tab "$PWD" \
  "claude --agent tech-lead --model opus \
   'Onboarding TL fresh: read plans/handoffs/HANDOFF_SESSION_<date>.md'"
```

---

## Known limitations

1. **macOS-only**: depends on `osascript` + iTerm2 installed
2. **`claude-win` race condition**: hardcoded `delay 0.35` between `cd && claude` and the prompt — very slow machines OR first execution may race (T3-DEBT-TOOL-01.2 backlog)
3. **No `--label`**: parallel tabs all show "Last login..." without visual distinction (T3-DEBT-TOOL-01.3 backlog)
4. **No `--help`**: discovering args requires reading source (T3-DEBT-TOOL-01.4 backlog)
5. **No audit log**: spawn history is not persisted (T3-DEBT-TOOL-01.5 backlog)

---

## Manual testing

```bash
# C1 shell injection guard test (must FAIL with non-existent folder error)
~/bin/iterm-tab '"; echo HACKED; #'
# Expected: ❌ Pasta não existe: "; echo HACKED; #

# Syntax check across all scripts
for f in ~/bin/iterm-tab ~/bin/iterm-win ~/bin/claude-win ~/bin/_iterm-lib.sh; do
  bash -n "$f" && echo "✓ $f"
done
```

---

## Cross-references

- Project-specific TL handoff pattern (consultant mode after spawn) — adopt per repo
- Tooling backlog (e.g. `--label`, `--help`, audit log) — track in your project roadmap
- Companion slash commands `/wrap-session-handoff` + `/spawn-tl-fresh` — implement in your project's `.claude/commands/`
