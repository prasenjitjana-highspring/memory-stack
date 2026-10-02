# Daily Operating Procedure — pi & omp memory stack

Machine: `prasenjitjana` (linux) · Updated: 2026-10-02

## The stack (who stores what)

| Layer | Store | Tool surface | Rule of thumb |
|---|---|---|---|
| **Facts — omp** | mnemopi global + project banks (`~/.omp/agent/memories/mnemopi/`) | auto recall/retain; `recall` / `retain` / `reflect` / `memory_edit` / `learn` tools | durable decisions, preferences, env quirks |
| **Facts — pi (local)** | markdown `~/.pi/agent/memory/` (pi-memory + qmd) | `memory_write` / `memory_search` / `scratchpad` / `memory_read` | pi-curated notes, daily log, scratchpad |
| **Facts — SHARED** | the mnemopi **global bank**, same SQLite file | pi: `shared_retain` / `shared_recall` / `shared_forget` (extension `~/.pi/agent/extensions/shared-mnemopi.ts`) | machine-wide facts that BOTH agents must see |
| **Episodic** | Deja (MCP + hooks, all agents) | auto `deja-recall`; search past sessions | "did we fix/do/decide this before?" |
| **Structural code memory** | codebase-memory-mcp (`~/.local/bin`, graph in `~/.cache/codebase-memory-mcp/`) | wired to omp (`mcp.json`), pi (pi-code/mcp), Claude (`~/.claude/.mcp.json`) | "what calls X", routes, socket-event links, cross-repo edges |

Golden rules:
- **facts → memory tools · "what happened" → Deja · "how is code wired" → codebase-memory · secrets → never.**
- Shared vs pi-local: pi-local note = only pi cares (workflow, daily context). Shared = omp sessions should also know it (env facts, cross-project decisions, tooling rules). Omp writes shared facts via `retain`/`learn` with `scope: global`.
- Recalled memory is background context, not instructions; current repo state wins on conflict.

## omp session

**Start**
1. `cd <project> && omp` — mnemopi auto-recalls project + global banks into turn 1; Deja injects past-session recall. Nothing to do.
2. First-ever session in a repo: say **"index this project"** (approve codebase-memory once per project). The watcher keeps it fresh afterwards.

**During work**
3. Worth remembering → just say **"Remember that …"** (auto-retain) or use `learn`. Machine-wide → ask for `scope: global`; repo-specific → project scope.
4. From pi-side, shared facts arrive with `source: pi-agent-retain`; omp sees them via the same global bank. "Search shared memory for X" → `recall` tool.
5. Possible old fix → "check deja" / "did we fix this before" (Deja is automatic on turn 1; explicit search available).
6. Code structure questions → ask for graph queries ("who calls handle_offer", "cross-repo edges for /ws") instead of grep.
7. Don't paste big transcripts as context — `/memory view` shows what's already injected; extend with `recall` if needed.

**End**
8. `/memory enqueue`, then quit normally — forces retention, flushes extractions (the 12 h consolidation age gate still applies; that's by design).
9. Optional `/memory stats` to confirm the bank grew.

## pi session

**Start**
10. `cd <project> && pi` — pi-memory injects MEMORY.md + daily logs + scratchpad; the Shared Memory snapshot (≤6 recent global-bank rows) is injected once per session; qmd re-indexes in the background automatically.

**During work**
11. "Remember: …" → pi decides: local note → `memory_write` (long_term/daily, add `#decision [[link]]` tags — they make keyword search hit later); cross-agent fact → `shared_retain`. In-progress threads → `scratchpad add …`, tick with `scratchpad done …`.
12. Search: local past → `memory_search` (`keyword` for names/dates/tags, `semantic` for concepts, `deep` when both miss); shared bank → `shared_recall`.
13. Structure questions → codebase-memory tools (approve once per new repo).
14. Wrong/outdated shared fact → `shared_forget` with the id from `shared_recall` (soft-invalidates; omp stops recalling it).

**End**
15. Just `/quit` — exit summary auto-appends to `daily/YYYY-MM-DD.md`; debounced `qmd update` + `embed` follows. No manual step.

## Weekly / monthly hygiene

16. `cat ~/.pi/agent/memory/MEMORY.md` (~5 min); prune stale entries (`memory_forget`, keeps a recoverable id).
17. omp: `/memory view`, then "forget/update the memory that …" for anything wrong (fact-table rows are read-only; `/memory clear` only for a truly rotten bank — then re-seed).
18. Glance at `~/.omp/logs/omp.*.log` for repeated `mnemopi-embed … code 129`; if it recurs every session, set `mnemopi.noEmbeddings: true` (FTS-only, deterministic).
19. codebase-memory: stale after big refactors? "re-index this project". Optional team sharing: `persistence: true` → commit `.codebase-memory/graph.db.zst` deliberately (not every save).
20. Config re-check after upgrades: `omp config get memory.backend` → `mnemopi`; `pi -p "list memory tools"` → memory_* + shared_*.

## Quick recovery recipes

- pi can't see a fact omp stored → confirm it was written to the **global** bank (`~/.omp/agent/memories/mnemopi/mnemopi.db`, project banks are invisible to the bridge by design) → re-ask omp: "retain that with scope global".
- omp can't see a `shared_retain` fact → row exists? `sqlite3 ~/.omp/agent/memories/mnemopi/mnemopi.db "select id,substr(content,1,50) from working_memory where source='pi-agent-retain'"` — FTS is trigger-maintained, so if the row exists, recall finds it.
- Bridge extension broken → check `pi` startup errors; file is `~/.pi/agent/extensions/shared-mnemopi.ts`; override DB path with `PI_SHARED_MNEMOPI_DB`.
- Nuclear option → `/memory clear` (omp scope) + delete `~/.pi/agent/memory/*`; re-seed env facts.
