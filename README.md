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
| `iterm_show_help <script> <summary> [extra]` | Standardized usage helper (printed by `--help` flag) |
| `iterm_audit_log <script> <dir> <cmd>` | Opt-in audit log (no-op unless `SPAWN_LOG=1`); appends to `~/.claude/spawn-log.txt` |
| `iterm_label_snippet` | Generates AppleScript snippet to rename session (empty if `ITERM_LABEL` unset) |
| `iterm_parse_flags <script> <summary> "$@"` | Shared parser for `--help` / `--label` / `--prompt-file`; exports `ITERM_LABEL` + `ITERM_PROMPT_FILE`; echoes remaining positional args |

**Origin of fixes**:
- 2026-05-12 v1: tmpfile branch for long OR UTF-8 payloads (resolved "PS2 hanging" spawn caused by insufficient inline escape)
- 2026-05-12 v2 (security + reliability audit):
  - C1: shell injection via DIR (CRITICAL)
  - H1: `osascript` + iTerm precheck
  - M1: multi-signal cleanup trap
  - Defensive: explicit `chmod 600` on tmpfile
- 2026-05-13 v3 (UX additive — 5 new opt-in features across the 3 scripts):
  - `--help` flag in all 3 (standardized usage via `iterm_show_help`)
  - `--prompt-file <file>` in `iterm-tab` / `iterm-win` (reads command from file — bypasses AppleScript typing cap for long prompts)
  - `--label <name>` in all 3 (renames iTerm session via "set name of session")
  - Opt-in audit log via `SPAWN_LOG=1` env var
  - NEW `spawn-tl` wrapper (auto-detects latest handoff in a project + delegates)
  - Backward-compat 100%: without flags, behavior is identical to v2

---

### `iterm-tab` — opens a new tab in the active iTerm window

```bash
~/bin/iterm-tab [OPTIONS] <DIR> [COMMAND...]
```

**Arguments**:
- `DIR` (default `$PWD`): working directory
- `COMMAND...` (optional): command(s) to run after `cd $DIR`

**Options** (v3, all optional — no flags = same behavior as v2):
- `--help` — prints usage and exits
- `--label <name>` — sets the new tab's iTerm session name (useful to distinguish parallel tabs)
- `--prompt-file <file>` — reads the command/prompt from a file; safer for long content than passing inline (avoids AppleScript typing cap)

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

# Named tab (helps distinguish parallel sessions)
~/bin/iterm-tab --label "dev-server" ~/Workspaces/my-app "npm run dev"

# Long command read from a file (avoids inline escaping pain)
echo 'claude --agent reviewer "$(cat huge-prompt.md)"' > /tmp/cmd.sh
~/bin/iterm-tab --prompt-file /tmp/cmd.sh ~/Workspaces/my-app

# With audit log on
SPAWN_LOG=1 ~/bin/iterm-tab ~/Workspaces/my-app "npm test"
```

---

### `iterm-win` — opens a new iTerm window

```bash
~/bin/iterm-win [OPTIONS] <DIR> [COMMAND...]
```

Same signature as `iterm-tab` (including `--help` / `--label` / `--prompt-file`), but creates a **new window** instead of a tab. Useful for workflows that need side-by-side visibility (e.g. monitoring a build in one window while editing in another).

**Examples**:

```bash
# New window tailing logs
~/bin/iterm-win ~/Workspaces/my-app "tail -f logs/dev.log"

# Named window for log streaming
~/bin/iterm-win --label "logs-prod" ~/Workspaces/my-app "tail -f logs/prod.log"

# New window in project + Claude Code
~/bin/iterm-win ~/projects/some-project "claude"
```

---

### `claude-win` — new window with Claude Code + long prompt loaded from a file

```bash
~/bin/claude-win [OPTIONS] <DIR> <PROMPT_FILE>
```

**Options** (v3): `--help`, `--label`. (Note: `PROMPT_FILE` is already a positional arg here — `--prompt-file` flag doesn't apply.)

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

# Named window for parallel review sessions
~/bin/claude-win --label "review-PR-42" ~/projects/repo /tmp/pr42-prompt.md
```

---

### `spawn-tl` — convenience wrapper for Tech Lead spawn (v3, new)

```bash
~/bin/spawn-tl [OPTIONS]
```

Single-command spawn of a fresh Tech Lead session in a chosen project. Auto-detects the latest `HANDOFF_SESSION_*.md` in `plans/handoffs/` and uses it for onboarding. Delegates to `iterm-tab` (short onboarding prompt) OR `claude-win` (via `--prompt-file` when a handoff file is explicitly chosen).

**Options**:
- `--help` — prints usage and exits
- `--label <name>` — sets the new iTerm session name (forwarded to underlying helper)
- `--prompt-file <path>` — uses `claude-win` with that file (safe for long prompts of any size)

**Env vars** (override defaults):
- `SPAWN_TL_PROJECT_DIR` — project directory (default: `$PWD`)
- `SPAWN_TL_AGENT` — Claude agent name (default: `tech-lead`)
- `SPAWN_TL_MODEL` — Claude model (default: `opus`)
- `SPAWN_TL_HANDOFF_DIR` — handoff dir relative to project (default: `plans/handoffs`)
- `SPAWN_TL_HANDOFF_GLOB` — glob for handoff files (default: `HANDOFF_SESSION_*.md`)
- `SPAWN_LOG=1` — append spawn record to `~/.claude/spawn-log.txt`

**Examples**:

```bash
# Most common: spawn fresh in current project
cd ~/projects/foo && ~/bin/spawn-tl

# Named session (useful when running 2 sessions in parallel)
~/bin/spawn-tl --label "feature-X"

# Force a specific handoff file (any size — uses claude-win under the hood)
~/bin/spawn-tl --prompt-file ~/projects/foo/plans/handoffs/handoff.md

# Different project (env override)
SPAWN_TL_PROJECT_DIR=~/projects/another-app ~/bin/spawn-tl

# Custom handoff convention per project
SPAWN_TL_HANDOFF_DIR=docs/handoffs SPAWN_TL_HANDOFF_GLOB='HANDOFF_*.md' \
  ~/bin/spawn-tl
```

> 💡 **Project-specific defaults**: export the env vars from your `.zshrc` / `.bashrc` to set per-project defaults. The script itself stays generic.

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
2. **`claude-win` race condition**: hardcoded `delay 0.35` between `cd && claude` and the prompt — very slow machines OR first execution may race
3. **Bash 3.2 compatibility**: scripts avoid `mapfile` and other bash-4+ idioms (macOS ships with bash 3.2.57 by default). Verified portable.
4. **No `bats` / `shellcheck` test suite yet**: validation is manual (syntax check + smoke tests)
5. **`sed`-based escape**: works for ASCII + multi-byte UTF-8 via tmpfile branch, but corner cases with exotic chars may exist

---

## Manual testing

```bash
# C1 shell injection guard test (must FAIL with non-existent folder error)
~/bin/iterm-tab '"; echo HACKED; #'
# Expected: ❌ Pasta não existe: "; echo HACKED; #

# Syntax check across all scripts
for f in ~/bin/iterm-tab ~/bin/iterm-win ~/bin/claude-win ~/bin/spawn-tl ~/bin/_iterm-lib.sh; do
  bash -n "$f" && echo "✓ $f"
done

# v3 features smoke test
~/bin/iterm-tab --help                    # should print usage and exit 0
~/bin/spawn-tl --help                     # should print usage and exit 0
echo "echo hello" > /tmp/test-cmd.sh
~/bin/iterm-tab --label "smoke" --prompt-file /tmp/test-cmd.sh ~/Documents
SPAWN_LOG=1 ~/bin/iterm-tab ~/Documents "pwd"
cat ~/.claude/spawn-log.txt              # should show the entry above
```

---

## Cross-references

- Project-specific TL handoff pattern (consultant mode after spawn) — adopt per repo
- Tooling backlog (e.g. `--label`, `--help`, audit log) — track in your project roadmap
- Companion slash commands `/wrap-session-handoff` + `/spawn-tl-fresh` — implement in your project's `.claude/commands/`
