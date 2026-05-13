# ~/bin — iTerm helpers pessoais

Coleção de helpers shell pra spawn de abas/janelas iTerm2 no macOS, com integração ao [Claude Code CLI](https://claude.com/claude-code). Compartilham lib `_iterm-lib.sh` (single source of truth pra escape + validação).

---

## Arquivos

### `_iterm-lib.sh` — lib compartilhada

Não-executável diretamente — fornece helpers usados pelos 3 scripts abaixo:

| Função | Propósito |
|--------|-----------|
| `iterm_escape_inline <str>` | Escapa `\` e `"` pra interpolar em AppleScript `"..."` inline (payloads curtos ASCII) |
| `iterm_needs_tmpfile <cmd>` | Decide se payload precisa de tmpfile branch (>500 chars OU contém byte UTF-8 multi-byte) |
| `iterm_write_tmpfile <cmd>` | Escreve payload em `mktemp` com perms 0600 + ecoa path |
| `iterm_safe_dir <dir>` | Valida que diretório existe + shell-quote via `printf %q` (previne injection) |
| `iterm_precheck` | Valida osascript disponível + tenta `open -ga iTerm` se inactive |
| `iterm_cleanup_trap <tmpfile>` | Registra trap multi-signal (EXIT, HUP, INT, TERM) pra remover tmpfile |
| `iterm_show_help <script> <summary> [extra]` | Helper de usage padronizado (impresso pela flag `--help`) |
| `iterm_audit_log <script> <dir> <cmd>` | Log de auditoria opt-in (no-op sem `SPAWN_LOG=1`); append em `~/.claude/spawn-log.txt` |
| `iterm_label_snippet` | Gera snippet AppleScript pra renomear sessão (vazio se `ITERM_LABEL` não setado) |
| `iterm_parse_flags <script> <summary> "$@"` | Parser compartilhado pra `--help` / `--label` / `--prompt-file`; exporta `ITERM_LABEL` + `ITERM_PROMPT_FILE`; ecoa args posicionais restantes |

**Origem dos fixes**:
- 2026-05-12 v1: tmpfile branch pra payloads longos OU UTF-8 (resolveu spawn travando em "PS2 hanging" por escape inline insuficiente)
- 2026-05-12 v2 (audit security+reliability):
  - C1: shell injection via DIR (CRITICAL)
  - H1: precheck osascript + iTerm
  - M1: trap cleanup multi-signal
  - Defensive: chmod 600 explícito tmpfile
- 2026-05-13 v3 (UX additive — 5 novas features opt-in nos 3 scripts):
  - Flag `--help` em todos 3 (usage padronizado via `iterm_show_help`)
  - Flag `--prompt-file <arquivo>` em `iterm-tab` / `iterm-win` (lê comando de arquivo — bypassa cap de typing do AppleScript pra prompts longos)
  - Flag `--label <nome>` em todos 3 (renomeia sessão iTerm via "set name of session")
  - Log de auditoria opt-in via env var `SPAWN_LOG=1`
  - NOVO wrapper `spawn-tl` (auto-detecta último handoff num projeto + delega)
  - Backward-compat 100%: sem flags, comportamento idêntico ao v2

---

### `iterm-tab` — abre nova aba em janela iTerm ativa

```bash
~/bin/iterm-tab [OPTIONS] <DIR> [COMMAND...]
```

**Argumentos**:
- `DIR` (default `$PWD`): diretório de trabalho
- `COMMAND...` (opcional): comando(s) a executar após `cd $DIR`

**Opções** (v3, todas opcionais — sem flags = comportamento idêntico ao v2):
- `--help` — imprime usage e sai
- `--label <nome>` — define o nome da sessão iTerm na nova aba (útil pra distinguir abas paralelas)
- `--prompt-file <arquivo>` — lê o comando/prompt de arquivo; mais seguro pra conteúdo longo do que passar inline (evita cap do AppleScript)

**Comportamento**:
- Abre nova **aba** na janela iTerm atual (não cria janela nova)
- Auto-detecta se precisa tmpfile branch
- Falha gracioso se DIR não existe OU iTerm inacessível

**Exemplos**:

```bash
# Abre aba em ~/Documents (sem comando)
~/bin/iterm-tab ~/Documents

# Abre aba em projeto + roda dev server
~/bin/iterm-tab ~/Workspaces/my-app "npm run dev"

# Aba com nome (ajuda a distinguir sessões paralelas)
~/bin/iterm-tab --label "dev-server" ~/Workspaces/my-app "npm run dev"

# Comando longo lido de arquivo (evita escape inline complicado)
echo 'claude --agent reviewer "$(cat huge-prompt.md)"' > /tmp/cmd.sh
~/bin/iterm-tab --prompt-file /tmp/cmd.sh ~/Workspaces/my-app

# Com audit log ligado
SPAWN_LOG=1 ~/bin/iterm-tab ~/Workspaces/my-app "npm test"
```

---

### `iterm-win` — abre nova janela iTerm

```bash
~/bin/iterm-win [OPTIONS] <DIR> [COMMAND...]
```

Mesma assinatura do `iterm-tab` (inclui `--help` / `--label` / `--prompt-file`), mas cria **nova janela** em vez de aba. Útil pra workflows que precisam visibilidade lado-a-lado (ex: monitorar build em uma janela + editar em outra).

**Exemplos**:

```bash
# Nova janela monitorando logs
~/bin/iterm-win ~/Workspaces/my-app "tail -f logs/dev.log"

# Janela nomeada pra streaming de logs
~/bin/iterm-win --label "logs-prod" ~/Workspaces/my-app "tail -f logs/prod.log"

# Nova janela em projeto + Claude Code
~/bin/iterm-win ~/projects/some-project "claude"
```

---

### `claude-win` — nova janela com Claude Code + prompt longo via arquivo

```bash
~/bin/claude-win [OPTIONS] <DIR> <PROMPT_FILE>
```

**Opções** (v3): `--help`, `--label`. (Nota: `PROMPT_FILE` já é arg posicional aqui — a flag `--prompt-file` não se aplica.)

**Argumentos**:
- `DIR`: diretório do projeto (obrigatório, validado)
- `PROMPT_FILE`: arquivo `.md`/`.txt` com prompt longo pro Claude (obrigatório, validado)

**Diferença vs `iterm-tab + claude '<prompt>'`**:
- Aceita prompts grandes (>500 chars) OU com UTF-8/acentos via tmpfile (sem corrupção AppleScript)
- Útil pra spawn de TL fresh com onboarding extenso, system briefings, etc

**Exemplos**:

```bash
# Cria prompt file + spawn Claude com contexto
echo "Você é PR reviewer. Analise os últimos 3 commits..." > /tmp/review-prompt.md
~/bin/claude-win ~/projects/some-project /tmp/review-prompt.md

# Onboarding TL completo
~/bin/claude-win \
  ~/Workspaces/my-plugin \
  ~/Workspaces/my-plugin/plans/handoffs/HANDOFF_SESSION_LATEST.md

# Janela nomeada pra sessões de review paralelas
~/bin/claude-win --label "review-PR-42" ~/projects/repo /tmp/pr42-prompt.md
```

---

### `spawn-tl` — wrapper conveniente pra spawn de Tech Lead (v3, novo)

```bash
~/bin/spawn-tl [OPTIONS]
```

Spawn one-command de uma sessão Tech Lead fresca num projeto escolhido. Auto-detecta o último `HANDOFF_SESSION_*.md` em `plans/handoffs/` pra usar como onboarding. Delega pra `iterm-tab` (prompt curto de onboarding) OR `claude-win` (via `--prompt-file` quando um arquivo de handoff é passado explicitamente).

**Opções**:
- `--help` — imprime usage e sai
- `--label <nome>` — define o nome da sessão iTerm (encaminhado pro helper subjacente)
- `--prompt-file <path>` — usa `claude-win` com esse arquivo (seguro pra prompts de qualquer tamanho)

**Env vars** (overrides dos defaults):
- `SPAWN_TL_PROJECT_DIR` — diretório do projeto (default: `$PWD`)
- `SPAWN_TL_AGENT` — nome do agent Claude (default: `tech-lead`)
- `SPAWN_TL_MODEL` — modelo Claude (default: `opus`)
- `SPAWN_TL_HANDOFF_DIR` — dir de handoffs relativo ao projeto (default: `plans/handoffs`)
- `SPAWN_TL_HANDOFF_GLOB` — glob dos arquivos de handoff (default: `HANDOFF_SESSION_*.md`)
- `SPAWN_LOG=1` — append registro de spawn em `~/.claude/spawn-log.txt`

**Exemplos**:

```bash
# Mais comum: spawn fresh no projeto atual
cd ~/projects/foo && ~/bin/spawn-tl

# Sessão nomeada (útil rodando 2 em paralelo)
~/bin/spawn-tl --label "feature-X"

# Força um arquivo de handoff específico (qualquer tamanho — usa claude-win internamente)
~/bin/spawn-tl --prompt-file ~/projects/foo/plans/handoffs/handoff.md

# Projeto diferente (override via env)
SPAWN_TL_PROJECT_DIR=~/projects/another-app ~/bin/spawn-tl

# Convenção de handoff customizada por projeto
SPAWN_TL_HANDOFF_DIR=docs/handoffs SPAWN_TL_HANDOFF_GLOB='HANDOFF_*.md' \
  ~/bin/spawn-tl
```

> 💡 **Defaults específicos do projeto**: exporte as env vars do seu `.zshrc` / `.bashrc` pra definir defaults por-projeto. O script em si permanece genérico.

---

## Patterns de uso comuns

### Spawn paralelo de N tabs

```bash
for dir in ~/projects/*/; do
  ~/bin/iterm-tab "$dir" "git status"
done
```

### TL handoff workflow (padrão do projeto pra handoff TL)

```bash
# Sessão atual TL prepara handoff persistido
git commit -m "docs(handoff): ..." plans/handoffs/HANDOFF_SESSION_<date>.md

# Spawn nova TL fresh em aba — onboarding via handoff (não inline)
~/bin/iterm-tab "$PWD" \
  "claude --agent tech-lead --model opus \
   'Onboarding TL fresh: read plans/handoffs/HANDOFF_SESSION_<date>.md'"
```

---

## Limitações conhecidas

1. **macOS-only**: depende de `osascript` + iTerm2 instalado
2. **`claude-win` race condition**: `delay 0.35` hardcoded entre `cd && claude` e prompt — máquina muito lenta OR primeira execução pode race
3. **Compatibilidade bash 3.2**: scripts evitam `mapfile` e outros idioms bash-4+ (macOS vem com bash 3.2.57 por default). Portabilidade verificada.
4. **Sem suite de testes `bats` / `shellcheck` ainda**: validação é manual (syntax check + smoke tests)
5. **Escape via `sed`**: funciona pra ASCII + UTF-8 multi-byte via tmpfile branch, mas casos exóticos podem ter corner cases

---

## Testing manual

```bash
# Test C1 shell injection guard (deve FALHAR com erro de pasta inexistente)
~/bin/iterm-tab '"; echo HACKED; #'
# Esperado: ❌ Pasta não existe: "; echo HACKED; #

# Test syntax válido em todos scripts
for f in ~/bin/iterm-tab ~/bin/iterm-win ~/bin/claude-win ~/bin/spawn-tl ~/bin/_iterm-lib.sh; do
  bash -n "$f" && echo "✓ $f"
done

# Smoke test das features v3
~/bin/iterm-tab --help                    # deve imprimir usage e sair com 0
~/bin/spawn-tl --help                     # deve imprimir usage e sair com 0
echo "echo hello" > /tmp/test-cmd.sh
~/bin/iterm-tab --label "smoke" --prompt-file /tmp/test-cmd.sh ~/Documents
SPAWN_LOG=1 ~/bin/iterm-tab ~/Documents "pwd"
cat ~/.claude/spawn-log.txt              # deve mostrar a entry acima
```

---

## Cross-references

- Padrão de TL handoff específico do projeto (modo consultor após spawn) — adaptar por repo
- Backlog de tooling (ex: `--label`, `--help`, audit log) — trackear no roadmap do seu projeto
- Slash commands companheiros `/wrap-session-handoff` + `/spawn-tl-fresh` — implementar no `.claude/commands/` do seu projeto
