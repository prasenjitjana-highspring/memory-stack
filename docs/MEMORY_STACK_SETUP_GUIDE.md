# Replicating the pi + omp AI-agent memory stack on a new machine

Companion to `MEMORY_STACK_RUNBOOK.md` (daily use). This doc is the build-from-scratch
instruction set: what to install, in what order, exact config, and verification gates.
Written against this machine on 2026-10-02; pins are "verified version at time of writing".

## Architecture being replicated

Four layers, all local, no server, no paid API:

| Layer | Answers | Store | Agents that read/write it |
|---|---|---|---|
| **Facts (native)** | "what conventions/preferences does this agent have" | omp: mnemopi SQLite banks · pi: markdown + qmd index | each agent natively |
| **Facts (shared)** | machine-wide facts both agents must know | `~/.omp/agent/memories/mnemopi/mnemopi.db` (global bank) | omp natively (`retain scope:global`); pi via the `shared-mnemopi` bridge extension |
| **Episodic** | "did we fix/decide this in a past session?" | deja-vu local index (single Go binary, no LLM/embeddings) | all wired agents (omp MCP + hooks, pi, …) |
| **Structural code memory** | "what calls X / routes / socket links / cross-repo" | codebase-memory-mcp SQLite graph | omp (mcp.json), pi (pi-code import), others |

Key design decisions (don't silently deviate):
- mnemopi is the shared *spine* — the bridge writes omp-native rows, so sharing needs no daemon.
- deja is the *single* episodic layer. Do **not** add MemPalace/Memori/etc. alongside it.
- No Mem0/OpenMemory/Zep/Letta/Cognee: server or external-LLM-key requirements conflict with the free-tier/local posture.
- Hindsight (self-hosted Docker) is the only sanctioned *upgrade path* if you later want server-side synthesis; the stack migrates to it without stranding data.

## Prerequisites

- OS: Linux or macOS. 2+ GB free RAM beyond agent use; ~5 GB disk for models/caches (4 vCPU / 14 GB is plenty).
- **Node ≥ ~22** with npm — required: pi runs on node, and the shared bridge uses built-in `node:sqlite`. (Verified: node 25.6.1. On older nodes without `node:sqlite`, the bridge won't load.)
- `git`, `curl`, and ideally `sqlite3` CLI (verification + deja's opencode indexing use it).
- `uv` (`curl -LsSf https://astral.sh/uv/install.sh | sh`) if you'll ever need isolated Python test envs — unrelated to memory but part of this machine's conventions.

## Step 1 — install the agents

```sh
# oh-my-pi (omp) — memory engine + agent
curl -fsSL https://omp.sh/install | sh
omp --version                     # verified: 18.4.8

# pi coding agent (badlogic/earendil build)
npm install -g @earendil-works/pi-coding-agent
pi --version                      # verified: 1.0.0
```

Skip Claude/Codex wiring unless requested — the stack is pi + omp by design.

## Step 2 — provider/model roles (prerequisite for memory LLM work)

mnemopi's default `llmMode: smol` performs fact extraction/consolidation through the
agent's configured `tiny`/`smol` model roles — memory is useless with no resolvable model.

```sh
omp          # interactive: /models (auth), /settings → Providers + Model roles
```
This machine used free/open tiers: `tiny: opencode-zen/mimo-v2.5-free`,
`smol: opencode-zen/north-mini-code-free`, advisor/vision on the antigravity gemini role.
pi: configure provider auth per its docs (`b-ai` provider here). **Verify before continuing:**
run one trivial prompt in each agent.

## Step 3 — omp memory backend (mnemopi)

Edit `~/.omp/agent/config.yml` (create if absent; `omp config set k=v` also works):

```yaml
memory:
  backend: mnemopi
mnemopi:
  scoping: per-project-tagged    # project writes + global recall visibility
  polyphonicRecall: true         # fuse vector/graph/fact voices on recall
  proactiveLinking: true         # new memories link into episodic graph
autolearn:
  enabled: true                  # `learn` tool + managed-skill capture
```

Gate: `omp config get memory.backend` → `mnemopi`; the two recall flags → `true`.

## Step 4 — pi local memory (pi-memory + qmd)

```sh
pi install npm:pi-memory
npm install -g @tobilu/qmd        # verified: 2.8.3
```

pi-memory auto-creates the qmd `pi-memory` collection at first session; embeddings build in
the background. Memory lives in `~/.pi/agent/memory/` (MEMORY.md, daily/, scratchpad).

Gate: `pi -p "List the memory-related tool names you have available"` → must include
`memory_write, memory_search, memory_status, scratchpad` (+ `memory`, `memory_forget`, `memory_restore`).

## Step 5 — the shared bridge (pi ⇄ omp global bank)

Install `pi/extensions/shared-mnemopi.ts` from this repo (canonical source; the repo's
`scripts/install-stack.sh` copies it into `~/.pi/agent/extensions/`). No npm deps:
it uses built-in `node:sqlite` and
`node:crypto` only. What it must contain (contract, if you re-implement):

1. Target DB: `${HOME}/.omp/agent/memories/mnemopi/mnemopi.db` (override env:
   `PI_SHARED_MNEMOPI_DB`). Open with `PRAGMA busy_timeout=5000`.
2. **retain** = plain `INSERT INTO working_memory` mirroring omp's row shape:
   `id = 16 hex chars`, `source='pi-agent-retain'`, ISO-8601 `timestamp`,
   `session_id='default'`, `importance=0.75`,
   `metadata_json={cwd, agent:'pi', context?}`, `veracity='tool'`,
   `memory_type='fact'`, `scope='bank'`, `author_id='pi-agent'`,
   `author_type='agent'`, `trust_tier='STATED'`.
   Do **not** touch `fts_working` — omp's schema has AFTER INSERT triggers that
   maintain it (that's why a raw row is instantly recallable everywhere).
3. **recall** = FTS5 BM25 `MATCH` over `fts_working⋈working_memory` and
   `fts_episodes⋈episodic_memory` (query = OR of ≥3-char sanitized tokens with
   prefix form), excluding `valid_until IS NOT NULL` / `superseded_by IS NOT NULL`
   rows, plus a LIKE fallback. Embeddings are filled later by omp consolidation —
   lexical recall works immediately.
4. **forget** = soft-invalidate: `SET valid_until = now`, reason into
   `metadata_json.$.retired_reason`. Never DELETE rows.
5. Tools registered: `shared_retain`, `shared_recall`, `shared_forget`;
   one-shot `before_agent_start` snapshot injection (≤6 recent rows, stable for
   the session → keeps pi's prompt cache intact).

Gate (full round-trip, do it exactly):
```sh
cd /tmp
pi  -p "Call shared_retain with content 'BRIDGE-TEST <date>'. Report the id."   # -> id P
omp -p "Use the recall tool with query 'BRIDGE-TEST'. Reply with matching ids."  # must show P
pi  -p "Call shared_recall with query 'BRIDGE-TEST'."                             # must show P
```
Then retire the test row with `shared_forget`. If step 2 fails on a fresh machine, the
usual cause is the global bank DB not existing yet — start an omp session once first
(mnemopi creates `mnemopi.db` at startup).

## Step 6 — episodic layer (deja-vu)

```sh
curl -fsSL https://raw.githubusercontent.com/vshulcz/deja-vu/main/install.sh | sh
deja install --auto        # wires MCP + hooks into every agent found (omp, pi, …)
# or explicit: deja install omp-auto pi-auto
```
Binary lands in `~/.local/bin/deja` (verified 0.20.2). No LLM, no embeddings, secrets
redacted at index time. It indexes pre-existing agent session dirs, so run it *after*
the agents have been used at least once if you want day-one history.

Optional cross-machine continuity: `deja sync ssh <other-host>` (pulls/pushes the index;
this is how machines converge on episodic memory — the fact store itself is not synced).

Gate: `deja doctor` clean; new sessions show deja-recall blocks / `deja` MCP tools.

## Step 7 — structural code memory (codebase-memory-mcp)

```sh
curl -fsSL https://raw.githubusercontent.com/DeusData/codebase-memory-mcp/main/install.sh | bash
# installs ~/.local/bin/codebase-memory-mcp and auto-wires detected agents (verified v0.9.0)
codebase-memory-mcp config set auto_index true      # optional: index on session start
```
It writes MCP entries for detected clients itself (this machine: Claude got it via
`~/.claude/.mcp.json`, pi via pi-code's import). **omp is NOT in its auto-wire set —
add it by hand** to `~/.omp/agent/mcp.json` beside deja:

```json
{
  "$schema": "https://raw.githubusercontent.com/can1357/oh-my-pi/main/packages/coding-agent/src/config/mcp-schema.json",
  "mcpServers": {
    "deja":             { "command": "/ABS/HOME/.local/bin/deja", "args": ["mcp"] },
    "codebase-memory":  { "command": "/ABS/HOME/.local/bin/codebase-memory-mcp" }
  }
}
```

Gate: in a repo, tell omp "index this project" (first-time per-project approval prompt),
then "what calls <known symbol>?" → graph answer instead of grep.

## Step 8 — seed the global bank (fresh machine = empty global bank)

Start `omp` in any dir and have it retain the machine's durable conventions as
**global** scope, e.g. the four seeds here:
1. package-manager/runtime rules for the box (e.g. "no system pytest → `uv run --with pytest pytest`"; "only `docker compose` v2 exists, not `docker-compose`") — verify each fact on the new machine first, don't blindly copy;
2. browser-automation directive if you use Lightpanda (see Step 10);
3. the memory-stack map itself ("facts→memory tools, history→deja, structure→codebase-memory; shared=mnemopi global bank via bridge");
4. anything the old machine's `~/.omp/agent/learned.md` / MEMORY.md carries that's machine-agnostic.
Or copy the whole bank file (`~/.omp/agent/memories/mnemopi/mnemopi.db` + banks dir)
from the old machine — stop omp first, copy `mnemopi/` into the same path; FTS/embeddings
are inside.

## Step 9 — user-level agent instructions

Both agents read `~/.omp/agent/AGENTS.md` and `~/.pi/agent/AGENTS.md` (pi also picks up
CLAUDE.md-style imports via pi-code). Copy the global AGENTS.md from the source machine
(browser directives, repo-navigation rules) — it's the non-memory half of the behavior.

## Step 10 — machine-specific extras (only if the old machine had them)

- **Lightpanda** CDP browser (user directive; never Chrome headless):
  `brew install lightpanda-io/browser/lightpanda` or nightly binary from GitHub releases →
  run `lightpanda serve --host 127.0.0.1 --port 9222` as a user service → omp
  `browser.cdpUrl: http://127.0.0.1:9222`.
- Other pi packages on this machine (providers, telegram, subagents, advisor-flow, ponytail…):
  see `~/.pi/agent/settings.json` `packages` — replicate only what's wanted; the memory
  stack needs **none** of them beyond pi-code for the codebase-memory import path.

## Known pitfalls (observed on this machine)

- **Embed subprocess crashes**: `mnemopi-embed: worker exited with code 129` in
  `~/.omp/logs/omp.*.log` is intermittent (on-demand fastembed install path); FTS carries
  recall regardless. If it recurs every session on the new box → `mnemopi.noEmbeddings: true`
  (deterministic FTS-only), or point `mnemopi.embeddingApiUrl` at any OpenAI-compatible
  local endpoint.
- **Global bank stays empty until asked**: omp writes project banks automatically but
  `scope: global` only when you (or the bridge) ask. Check with
  `sqlite3 ~/.omp/agent/memories/mnemopi/mnemopi.db "select count(*) from working_memory;"`.
- **New config = new process**: omp config.yml/mcp.json changes apply to processes started
  after the edit; restart open sessions.
- **Don't double-store episodic memory**: Deja already covers transcripts; adding
  MemPalace/agentmemory-style transcript tools splits recall.
- **Bridge row shape matters**: wrong `source`/`veracity` values still work, but skipping
  the `working_memory` table (writing FTS directly) breaks omp consolidation.
- **Node version**: pi extensions need `node:sqlite` (≥22ish). On an old node, upgrade
  node rather than rewriting the bridge.
- **`/memory clear` deletes the shared bank too**: it is the same DB — the pi bridge then
  errors on open until an omp session recreates it; recreation is automatic on omp start.

## Verification checklist (fresh machine, all green = done)

- [ ] `omp config get memory.backend` → `mnemopi`; polyphonic/linking → `true`
- [ ] omp session recalls a seeded global fact on turn 1 (`<memories>` block)
- [ ] pi lists `memory_*` + `scratchpad` tools; `~/.pi/agent/memory/` created; `qmd collection list` shows `pi-memory`
- [ ] Round-trip test (Step 5 gate) passes both directions
- [ ] `deja doctor` OK; deja recall appears in both agents
- [ ] omp: project indexed via codebase-memory; graph query answers a real symbol question
- [ ] This repo cloned/committed; docs also at `~/.memory-stack/` (installer copies them)
- [ ] After a day of real use: banks grew (`/memory stats`), pi daily log has entries

## What intentionally NOT to install

Mem0/OpenMemory (needs external keys/server), Zep/Graphiti, Letta, Cognee, MemPalace
(duplicates Deja), marm-memory (immature), memory-mcp family (strictly weaker than the
mnemopi native loop), Hindsight **yet** — add it only if you later want one synthesis-backed
bank shared identically across more agents (`docker run … vectorize-io/hindsight`,
`memory.backend: hindsight`, `npx @vectorize-io/hindsight-coding-agents install pi`);
it subsumes this stack's shared layer and the migration is reversible (mnemopi store kept).
