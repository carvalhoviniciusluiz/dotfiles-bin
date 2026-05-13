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

**Origem dos fixes**:
- 2026-05-12 v1: tmpfile branch pra payloads longos OU UTF-8 (resolveu spawn travando em "PS2 hanging" por escape inline insuficiente)
- 2026-05-12 v2 (audit security+reliability):
  - C1: shell injection via DIR (CRITICAL)
  - H1: precheck osascript + iTerm
  - M1: trap cleanup multi-signal
  - Defensive: chmod 600 explícito tmpfile

---

### `iterm-tab` — abre nova aba em janela iTerm ativa

```bash
~/bin/iterm-tab <DIR> [COMMAND...]
```

**Argumentos**:
- `DIR` (default `$PWD`): diretório de trabalho
- `COMMAND...` (opcional): comando(s) a executar após `cd $DIR`

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

# Abre aba + claude TL persona
~/bin/iterm-tab \
  "~/Developments/Workspaces/my-project" \
  "claude --agent tech-lead --model opus 'Onboarding TL fresh'"
```

---

### `iterm-win` — abre nova janela iTerm

```bash
~/bin/iterm-win <DIR> [COMMAND...]
```

Mesma assinatura do `iterm-tab`, mas cria **nova janela** em vez de aba. Útil pra workflows que precisam visibilidade lado-a-lado (ex: monitorar build em uma janela + editar em outra).

**Exemplos**:

```bash
# Nova janela monitorando logs
~/bin/iterm-win ~/Workspaces/my-app "tail -f logs/dev.log"

# Nova janela em projeto + Claude Code
~/bin/iterm-win ~/projects/some-project "claude"
```

---

### `claude-win` — nova janela com Claude Code + prompt longo via arquivo

```bash
~/bin/claude-win <DIR> <PROMPT_FILE>
```

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
```

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
2. **`claude-win` race condition**: `delay 0.35` hardcoded entre `cd && claude` e prompt — máquina muito lenta OR primeira execução pode race (T3-DEBT-TOOL-01.2 backlog)
3. **Sem `--label`**: múltiplas abas paralelas viram "Last login..." sem distinção visual (T3-DEBT-TOOL-01.3 backlog)
4. **Sem `--help`**: descobrir args requer ler source (T3-DEBT-TOOL-01.4 backlog)
5. **Sem audit log**: histórico de spawns não persistido (T3-DEBT-TOOL-01.5 backlog)

---

## Testing manual

```bash
# Test C1 shell injection guard (deve FALHAR com erro de pasta inexistente)
~/bin/iterm-tab '"; echo HACKED; #'
# Esperado: ❌ Pasta não existe: "; echo HACKED; #

# Test syntax válido em todos scripts
for f in ~/bin/iterm-tab ~/bin/iterm-win ~/bin/claude-win ~/bin/_iterm-lib.sh; do
  bash -n "$f" && echo "✓ $f"
done
```

---

## Cross-references

- Padrão de TL handoff específico do projeto (modo consultor após spawn) — adaptar por repo
- Backlog de tooling (ex: `--label`, `--help`, audit log) — trackear no roadmap do seu projeto
- Slash commands companheiros `/wrap-session-handoff` + `/spawn-tl-fresh` — implementar no `.claude/commands/` do seu projeto
