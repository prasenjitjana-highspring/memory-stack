# memory-stack

Versioned definition of the local AI-agent memory stack for pi + omp (2026-10).
Four layers, all local, no server, no paid API:

| Layer | Store | Tool surface |
|---|---|---|
| Facts — omp native | mnemopi banks `~/.omp/agent/memories/mnemopi/` | auto recall/retain, `recall/retain/reflect/learn` |
| Facts — pi native | markdown `~/.pi/agent/memory/` + qmd index | `memory_write/memory_search/scratchpad` |
| Facts — **shared pi⇄omp** | mnemopi **global bank** (same SQLite file) | pi: `shared_retain/shared_recall/shared_forget` bridge |
| Episodic (all agents) | deja-vu local index | auto hooks + MCP recall |
| Structural code memory | codebase-memory-mcp graph | MCP tools in omp/pi |

## Layout

```
docs/
  MEMORY_STACK_RUNBOOK.md       # daily operating procedure (per-session habits)
  MEMORY_STACK_SETUP_GUIDE.md   # full manual build-from-scratch + gates + pitfalls
pi/extensions/
  shared-mnemopi.ts             # the pi⇄omp bridge (source of truth; node:sqlite, zero deps)
omp/
  config.yml                    # mnemopi/autolearn/browser settings block (merge, don't clobber)
  mcp.json                      # servers block: deja + codebase-memory (paths are placeholders)
agent-instructions/
  AGENTS.md                     # global user-level agent instructions (browser/nav rules)
scripts/
  install-stack.sh              # installs + wires everything idempotently
  verify-stack.sh               # runs all verification gates, prints PASS/FAIL table
```

## New machine, fastest path

```sh
git clone <this-repo-url> ~/memory-stack && cd ~/memory-stack
./scripts/install-stack.sh      # curl-installs omp/pi, npm qmd+pi-memory, deja,
                                # codebase-memory; merges configs; installs bridge
./scripts/verify-stack.sh       # gates: backends, tools list, round-trip bridge test
```

Then finish the two manual bits the scripts can't know:
1. **model roles/auth** — `omp` interactive `/models`+`/settings`, `pi` provider auth
   (memory LLM extraction needs a resolvable `tiny`/`smol` role; stack is useless without it).
2. **seed global facts** — follow SETUP_GUIDE Step 8 (verify env facts on the new box first;
   don't blindly copy this machine's).

`scripts/install-stack.sh` is safe to re-run (idempotent): it only appends missing config
keys/packages and never overwrites files it didn't create.

## Conventions

- The bridge file here is canonical. `~/.pi/agent/extensions/shared-mnemopi.ts` is a copy;
  edit here, re-run install, commit.
- `omp/config.yml` and `mcp.json` hold the memory-relevant keys only; machine-secret values
  (tokens) live in provider auth files, never here.
- Paths in `mcp.json` use `$HOME` placeholders resolved by the installer.
- Bank DBs, sessions, qmd index are runtime data — deliberately NOT versioned.
- Hindsight (self-hosted) remains the only sanctioned upgrade path; see SETUP_GUIDE
  "What intentionally NOT to install".
