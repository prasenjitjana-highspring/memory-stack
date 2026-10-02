#!/usr/bin/env bash
# memory-stack verifier — PASS/FAIL table for every automatable gate.
# Default: deterministic checks only (no LLM calls).
# --roundtrip: additionally runs the pi<->omp bridge LLM test (~4-5 min, model calls).
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$HOME/.local/bin:$HOME/bin:$PATH"
DB="$HOME/.omp/agent/memories/mnemopi/mnemopi.db"
declare -a RES=()
pass() { RES+=("PASS|$1|${2:-}"); }
run() { # run <name> <cmd...>  -> PASS if exit 0, prints trimmed output
  local name="$1"; shift
  local raw rc
  raw="$("$@" 2>&1)"; rc=$?
  local out; out="$(printf '%s' "$raw" | tr '\n' ' ' | sed 's/  */ /g; s/^ //; s/ $//')"
  if [ "$rc" -eq 0 ]; then pass "$name" "${out:0:80}"; else fail "$name" "rc=$rc ${out:0:80}"; fi
}

# ---------- layer: omp facts ----------
run "omp binary" omp --version
[ "$(omp config get memory.backend 2>/dev/null)" = "mnemopi" ] \
  && pass "omp backend=mnemopi" || fail "omp backend=mnemopi" "got: $(omp config get memory.backend 2>/dev/null)"
for k in mnemopi.polyphonicRecall mnemopi.proactiveLinking autolearn.enabled; do
  [ "$(omp config get "$k" 2>/dev/null)" = "true" ] \
    && pass "omp $k=true" || fail "omp $k=true" "got: $(omp config get "$k" 2>/dev/null)"
done
[ "$(omp config get mnemopi.scoping 2>/dev/null)" = "per-project-tagged" ] \
  && pass "omp scoping=per-project-tagged" || fail "omp scoping=per-project-tagged"

# ---------- layer: shared global bank ----------
if [ -f "$DB" ]; then
  pass "global bank exists" "$DB"
  if command -v sqlite3 >/dev/null; then
    N="$(sqlite3 "$DB" 'select count(*) from working_memory;' 2>/dev/null)"
    NP="$(sqlite3 "$DB" 'select count(*) from working_memory where source='"'"'pi-agent-retain'"'"' and valid_until is null;' 2>/dev/null)"
    [ "${N:-0}" -ge 1 ] && pass "global bank populated" "rows=$N pi-rows=$NP" || warn "global bank populated" "rows=0 — seed facts (guide Step 8)"
  else
    warn "sqlite3 CLI missing" "cannot count bank rows; bridge still works via node:sqlite"
  fi
else
  warn "global bank exists" "$DB missing — start one omp session to create it, then re-verify"
fi

# ---------- layer: pi local facts ----------
run "pi binary" pi --version
grep -q '"npm:pi-memory"' "$HOME/.pi/agent/settings.json" 2>/dev/null \
  && pass "pi-memory registered" || fail "pi-memory registered"
[ -d "$HOME/.pi/agent/memory" ] && pass "pi memory dir" || warn "pi memory dir" "~/.pi/agent/memory not created yet (appears after first session)"
if command -v qmd >/dev/null; then
  qmd collection list 2>/dev/null | grep -q "pi-memory" \
    && pass "qmd pi-memory collection" || warn "qmd pi-memory collection" "auto-creates on first pi session with writes"
else
  fail "qmd installed"
fi

# ---------- layer: bridge ----------
if diff -q "$REPO/pi/extensions/shared-mnemopi.ts" "$HOME/.pi/agent/extensions/shared-mnemopi.ts" >/dev/null 2>&1; then
  pass "bridge installed & matches repo"
else
  fail "bridge installed & matches repo" "run scripts/install-stack.sh"
fi
node --experimental-sqlite -e 'require("node:sqlite"); console.log("node:sqlite ok")' >/dev/null 2>&1 \
  || node -e 'require("node:sqlite")' 2>/dev/null \
  && pass "node:sqlite available" || fail "node:sqlite available" "node $(node -p process.versions.node)"

# ---------- layer: episodic ----------
if command -v deja >/dev/null; then
  run "deja binary" deja --version
  deja doctor >/dev/null 2>&1 && pass "deja doctor" || warn "deja doctor" "inspect: deja doctor --json"
  grep -q '"deja"' "$HOME/.omp/agent/mcp.json" 2>/dev/null && pass "deja wired in omp mcp.json" || fail "deja wired in omp mcp.json"
else
  fail "deja installed" "install: curl -fsSL https://raw.githubusercontent.com/vshulcz/deja-vu/main/install.sh | sh"
fi

# ---------- layer: structural ----------
CBM="$(command -v codebase-memory-mcp || echo "$HOME/.local/bin/codebase-memory-mcp")"
[ -x "$CBM" ] && pass "codebase-memory binary" "$CBM" || fail "codebase-memory binary" "$CBM not executable"
grep -q 'codebase-memory' "$HOME/.omp/agent/mcp.json" 2>/dev/null \
  && pass "codebase-memory wired in omp mcp.json" || fail "codebase-memory wired in omp mcp.json"

# ---------- agent instructions ----------
for f in "$HOME/.omp/agent/AGENTS.md" "$HOME/.pi/agent/AGENTS.md"; do
  [ -f "$f" ] && pass "AGENTS.md present" "$f" || warn "AGENTS.md present" "$f missing (optional)"
done

# ---------- optional: LLM round-trip ----------
if [ "${1:-}" = "--roundtrip" ]; then
  TS="BRIDGE-VERIFY-$(date +%s)"
  id="$(cd /tmp && timeout 240 pi -p "Call shared_retain with content '$TS'. Reply ONLY the stored id." 2>/dev/null | grep -oE '[0-9a-f]{16}' | head -1)"
  if [ -n "$id" ]; then
    pass "roundtrip pi->bank" "id=$id"
    if cd /tmp && timeout 240 omp -p "Use the recall tool with query '$TS'. Reply ONLY matching memory ids, one per line." 2>/dev/null | grep -q "$id"; then
      pass "roundtrip bank->omp recall"
    else
      fail "roundtrip bank->omp recall" "omp -p did not surface $id"
    fi
    cd /tmp && timeout 120 pi -p "Call shared_forget with id '$id' and reason 'verify-stack cleanup'." >/dev/null 2>&1 \
      && pass "roundtrip cleanup (row invalidated)" || warn "roundtrip cleanup" "retire manually: shared_forget $id"
  else
    fail "roundtrip pi->bank" "shared_retain produced no id"
  fi
fi

# ---------- report ----------
printf '\n\033[1m=== memory-stack verification ===\033[0m\n'
P=F=W=0
for r in "${RES[@]}"; do
  IFS='|' read -r s n d <<< "$r"
  case "$s" in
    PASS) P=$((P+1)); printf '\033[32m  PASS\033[0m %-38s %s\n' "$n" "$d";;
    FAIL) F=$((F+1)); printf '\033[31m  FAIL\033[0m %-38s %s\n' "$n" "$d";;
    WARN) W=$((W+1)); printf '\033[33m  WARN\033[0m %-38s %s\n' "$n" "$d";;
  esac
done
printf '%s\n' "total: $P pass, $W warn, $F fail"
[ "$F" -eq 0 ] || exit 1
