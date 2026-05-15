# Changelog

Dated events in this protocol's lifecycle. Newest first.

## 2026-05-15

Restructured the Strict Gate and Reminder Gate (in `CLAUDE.md`'s
Pre-Push Review Protocol) from a single flat list into a universal
core plus per-ecosystem extensions:

- **Strict Gate — Universal:** payment processing, auth/session/JWT,
  env vars/secrets, API endpoints accepting user input. Items every
  project gets regardless of platform.
- **Strict Gate — Web-specific:** RLS policies, CORS, OAuth callbacks,
  Next.js middleware, third-party scripts (the items previously
  treated as universal but actually web-flavored).
- **Strict Gate — Android-specific (new):** capture code paths
  (camera/audio/image bytes via `BitmapFactory` etc.), JNI / native
  boundaries, `allowBackup` / `dataExtractionRules`, component
  `exported="true"` changes, WebView / JS↔Kotlin bridges
  (`addJavascriptInterface`), external text becoming a system prompt,
  Network Security Config / cleartext traffic, cryptographic operations
  / `KeyStore` usage.
- **Reminder Gate — Android-specific (new):** `targetSdkVersion` bumps,
  release signing / ProGuard or R8 config changes, sensitive data
  stored in plain `SharedPreferences`.

The previous flat list was implicitly web-flavored. As active work
expanded into Android, that calibration left real risk surfaces
without coverage. The restructure scales to new ecosystems (iOS,
Solana mobile, etc.) without further reorganization.

No items were removed from the existing gate. The web-specific items
that used to be in the universal list are now categorized but still
fire on web projects.

## 2026-05-13

Updated `CLAUDE.md`, `install.sh`, `docs/CUSTOMIZE.md`, and `README.md`:

- Reframed lockfile drift detection (Dependency Installation Gate, section 6) as forensic rather than preventive. The drift check runs after `npm install` completes, by which point any malicious `postinstall` script has already executed. The original framing overstated what it prevents.
- Added section 7: `npm config set ignore-scripts true`. The install-time execution defense. Set by `install.sh` on all npm versions.
- Added section 8: `npm config set min-release-age 2d`. Forward protection for future supply chain attacks. Requires npm 11+; `install.sh` skips it gracefully on older npm.
- `docs/CUSTOMIZE.md` gained a section on tuning the release-age buffer, the script-allowance workflow for packages needing build steps (`sharp`, `esbuild`, `puppeteer`, `cypress`, `husky`, `node-gyp`, native modules), and equivalents for pnpm/yarn/bun.
- `README.md` surfaces both npm configs in the "What's in here" section.

## 2026-05-11

TanStack / Mini Shai-Hulud npm supply chain attack made public. 84 packages across the `@tanstack/` namespace shipped malicious versions, including `@tanstack/react-router` (12M+ weekly downloads). The campaign expanded over the following two days to OpenSearch, Mistral AI, Guardrails AI, UiPath, and Squawk — across both npm and PyPI.

The attack specifically targeted AI developer tooling, injecting persistence into `.claude/settings.json` and `.vscode/tasks.json`. `npm uninstall` did not remove the persistence.

This event exposed the install-time execution gap in the original protocol and triggered the 2026-05-13 update above.

## 2026-05-01

Companion article published on Substack: ["You Can Just Do Things." But Maybe, Be Safe About It?](https://atmr.substack.com/p/you-can-just-do-things-but-maybe)

Repo state at publication: five-layer baseline (Global `CLAUDE.md`, PreToolUse hook, global git pre-push hook, slash command references, Socket.dev). Lockfile drift detection was framed as preventive. No `ignore-scripts` or `min-release-age` configs in `install.sh`.
