#!/usr/bin/env bash
# memory-stack installer — idempotent; safe to re-run.
# Builds the pi+omp four-layer local memory stack defined in this repo.
# Manual follow-ups it cannot do: agent provider auth/model roles, global-fact seeding,
# Lightpanda service (see README / docs/MEMORY_STACK_SETUP_GUIDE.md).
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
step() { printf '\n\033[1;36m==> %s\033[0m\n' "$1"; }
ok()   { printf '    \033[32mok\033[0m %s\n' "$1"; }
warn() { printf '    \033[33mWARN\033[0m %s\n' "$1"; }
die()  { printf '    \033[31mFAIL\033[0m %s\n' "$1"; exit 1; }

step "prerequisites"
command -v node >/dev/null || die "node not found (need >=22 for node:sqlite)"
NODE_MAJ="$(node -p 'process.versions.node.split(".")[0]')"
[ "$NODE_MAJ" -ge 22 ] || die "node $NODE_MAJ < 22: pi bridge needs built-in node:sqlite"
for c in npm curl git; do command -v $c >/dev/null || die "$c missing"; done
ok "node $(node -p process.versions.node)"

step "omp (oh-my-pi)"
if command -v omp >/dev/null; then ok "omp present: $(omp --version 2>/dev/null)"
else
  curl -fsSL https://omp.sh/install | sh || die "omp install failed"
  export PATH="$HOME/.local/bin:$HOME/bin:$PATH"
  command -v omp >/dev/null || die "omp not on PATH after install"
  ok "omp installed: $(omp --version 2>/dev/null)"
fi

step "pi coding agent"
if command -v pi >/dev/null; then ok "pi present: $(pi --version 2>/dev/null)"
else
  npm install -g @earendil-works/pi-coding-agent || die "pi install failed"
  ok "pi installed"
fi

step "pi local memory (pi-memory + qmd)"
command -v qmd >/dev/null || npm install -g @tobilu/qmd || warn "qmd install failed (semantic search degraded; core tools still work)"
grep -q '"npm:pi-memory"' "$HOME/.pi/agent/settings.json" 2>/dev/null || pi install npm:pi-memory || die "pi-memory install failed"
ok "pi-memory + qmd"

step "mnemopi config (omp)"
# omp config set merges into ~/.omp/agent/config.yml without clobbering other keys.
while IFS='=' read -r k v; do
  cur="$(omp config get "$k" 2>/dev/null || true)"
  if [ "$cur" != "$v" ]; then omp config set "$k" "$v" || warn "set $k=$v failed"; fi
done <<'EOF'
memory.backend=mnemopi
mnemopi.scoping=per-project-tagged
mnemopi.polyphonicRecall=true
mnemopi.proactiveLinking=true
autolearn.enabled=true
EOF
ok "memory keys set"

step "deja-vu (episodic layer, all agents)"
if ! command -v deja >/dev/null && [ -x "$HOME/.local/bin/deja" ]; then export PATH="$HOME/.local/bin:$PATH"; fi
if ! command -v deja >/dev/null; then
  curl -fsSL https://raw.githubusercontent.com/vshulcz/deja-vu/main/install.sh | sh || warn "deja install failed"
  export PATH="$HOME/.local/bin:$PATH"
fi
if command -v deja >/dev/null; then
  deja install --auto || warn "deja install --auto failed; wire manually (see guide step 6)"
  ok "deja $(deja --version 2>/dev/null) wired"
else warn "deja unavailable — episodic layer missing"; fi

step "codebase-memory-mcp (structural layer)"
CBM="$HOME/.local/bin/codebase-memory-mcp"
command -v codebase-memory-mcp >/dev/null && CBM="$(command -v codebase-memory-mcp)"
if [ ! -x "$CBM" ]; then
  curl -fsSL https://raw.githubusercontent.com/DeusData/codebase-memory-mcp/main/install.sh | bash || warn "codebase-memory install failed"
  [ -x "$CBM" ] || CBM="$(command -v codebase-memory-mcp || true)"
  [ -n "$CBM" ] || warn "codebase-memory-mcp binary not found — skipping omp wiring"
fi
[ -x "$CBM" ] && ok "codebase-memory at $CBM"

step "omp mcp.json (deja + codebase-memory)"
node - "$HOME/.omp/agent/mcp.json" "$HOME/.local/bin/deja" "$CBM" <<'NODE'
const [path, deja, cbm] = process.argv.slice(2);
const fs = require("fs");
const cfg = fs.existsSync(path) ? JSON.parse(fs.readFileSync(path, "utf8")) : {};
cfg.mcpServers ??= {};
let changed = false;
if (!cfg.mcpServers.deja && fs.existsSync(deja)) {
  cfg.mcpServers.deja = { command: deja, args: ["mcp"] }; changed = true;
}
if (!cfg.mcpServers["codebase-memory"] && cbm && fs.existsSync(cbm)) {
  cfg.mcpServers["codebase-memory"] = { command: cbm }; changed = true;
}
if (!cfg.$schema) cfg.$schema = "https://raw.githubusercontent.com/can1357/oh-my-pi/main/packages/coding-agent/src/config/mcp-schema.json";
if (changed) fs.writeFileSync(path, JSON.stringify(cfg, null, 2) + "\n");
console.log(changed ? "added missing servers" : "servers already wired");
NODE
ok "mcp.json"

step "shared bridge (pi extension)"
mkdir -p "$HOME/.pi/agent/extensions"
if ! diff -q "$REPO/pi/extensions/shared-mnemopi.ts" "$HOME/.pi/agent/extensions/shared-mnemopi.ts" >/dev/null 2>&1; then
  cp "$REPO/pi/extensions/shared-mnemopi.ts" "$HOME/.pi/agent/extensions/shared-mnemopi.ts"
  ok "bridge installed"
else ok "bridge already current"; fi

step "global AGENTS.md"
[ -f "$HOME/.omp/agent/AGENTS.md" ] || { mkdir -p "$HOME/.omp/agent"; cp "$REPO/agent-instructions/AGENTS.md" "$HOME/.omp/agent/AGENTS.md"; ok "copied to ~/.omp/agent/"; }
[ -f "$HOME/.pi/agent/AGENTS.md" ]  || { cp "$REPO/agent-instructions/AGENTS.md" "$HOME/.pi/agent/AGENTS.md";  ok "copied to ~/.pi/agent/"; }
[ -f "$HOME/.omp/agent/AGENTS.md" ] && [ -f "$HOME/.pi/agent/AGENTS.md" ] && ok "AGENTS.md present in both"

step "docs into HOME"
mkdir -p "$HOME/.memory-stack"
cp "$REPO/docs/MEMORY_STACK_RUNBOOK.md" "$REPO/docs/MEMORY_STACK_SETUP_GUIDE.md" "$HOME/.memory-stack/" 2>/dev/null && ok "runbook+guide at ~/.memory-stack/"

printf '\n\033[1;32mInstall pass complete.\033[0m\n'
printf 'NEXT (manual, machine-specific):\n'
printf '  1. omp: /models + /settings auth & model roles (tiny/smol needed for memory LLM work); pi: provider auth.\n'
printf '  2. Start one omp session in any dir (creates mnemopi.db), then seed global facts — guide Step 8.\n'
printf '  3. Optional Lightpanda CDP service + omp browser.cdpUrl (guide Step 10).\n'
printf '  4. Verify: ./scripts/verify-stack.sh   (add --roundtrip for the full pi<->omp LLM test)\n'
