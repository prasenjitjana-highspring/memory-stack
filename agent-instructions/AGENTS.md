# Global agent instructions

## Repository navigation (user directive, 2026)

At the start of work in any repository, follow the `codebase-map` skill
(`~/.agents/skills/codebase-map/SKILL.md` — load it with the read tool or
`/skill:codebase-map`). Core rules:

- Never read a code file over ~300 lines wholesale. First touch = structural
  view (bare `read <file>` → declaration summary) or symbol search; then open
  only the needed line windows.
- On this machine: LSP via `xd://lsp` (omp); universal-ctags installed;
  rg installed.
- Build/refresh `<repo>/CODEBASE_MAP.md` once per repo; retrieve at symbol
  level; `retain` durable discoveries to memory (omp mnemopi backend).

## Headless browser preference (user directive, 2026)

Never use Chrome headless (google-chrome --headless, chrome/chromium via
Playwright/Puppeteer/Selenium launch, chromedriver, etc.).

Use **Lightpanda** instead: https://github.com/lightpanda-io/browser

- Lightpanda is CDP-compatible: start it with `lightpanda serve --host 127.0.0.1 --port 9222`,
  then connect Playwright/Puppeteer over CDP
  (`chromium.connectOverCDP('http://127.0.0.1:9222')`) — no code rewrite needed,
  only the launch/connect step changes. Selenium/Bidi: `--protocol webdriver`.
- If Lightpanda is not installed: `brew install lightpanda-io/browser/lightpanda`
  (or download the nightly binary from GitHub releases), never fall back to
  Chrome headless silently — ask the user first.

This applies everywhere (screenshots, scraping, browser tests, PDF rendering).
