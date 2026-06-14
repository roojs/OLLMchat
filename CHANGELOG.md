# Changelog

All notable changes to OLLMchat are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html)
for git tags (`v1.2.4-alpha`, etc.).

`CHANGELOG.md` is the **single source of truth**. `debian/changelog` is generated
from it — do not edit `debian/changelog` by hand. Regenerate with:

```bash
./scripts/release/sync-debian-changelog.sh
```

## [Unreleased]

### Added

- **Coding Assistant**: Chatter-style summarized conversation history — background
  summarizer after each turn, `summary` transcript role, and follow-up rounds that
  send only messages since the latest summary plus a `coder_followup.md` system
  tail (with `session_fetch` hash links)
- **Agents**: shared `OLLMchat.Agent.Summarizer` and `Agent.Base.create_summary()`
  used by both Chatter and the Coding Assistant
- **run_command**: `run_as_root` parameter runs commands via `sudo` after in-app password prompt
  after explicit high-risk ChatPermission approval (Linux GTK app; no Allow Always
  shortcut)
- **Android**: chat shell under `ollmapp/android/` — `AndroidApplication` (app-private
  Config2 storage), `AndroidMainWindow`, `AndroidStartup`, and
  `AndroidSettingsDialog` (connections + default model); bootstrap via
  `ConnectionAdd`; replaces the inline-form `AndroidPoc.vala` target
- **Android**: Pixiewood shell APK scaffold and remote-only chat POC target
  (`ollmchat-android-poc`)
- **CI**: manual Android APK artifact workflow; Android validation workflows are
  manual-only
- **Release tooling**: changelog sync/finalize scripts; GitHub Release notes rendered
  from `CHANGELOG.md`
- **Docs**: Android feasibility notes, remote-only CI documentation, and
  `docs/creating-releases.md` changelog workflow

### Removed

- **Config**: Config1 and legacy `config.json` migration — applications load Config2
  from `config.2.json` only (desktop and Android)

### Changed

- **Coding Assistant**: system prompt is outbound-only — no longer persisted as
  `system` rows in the session transcript each turn
- **Chatter**: summarizer moved from `Chatter.Summarizer` to the shared agent class
- **CI**: PR checks limited to stable offline tests (Android builds run manually)
- **Android**: build caching for SDK, Pixiewood prefix, and Gradle; newer Meson
  scoped to Android APK builds only

### Fixed

- **Tool calling**: OpenAI-compatible request/response field names for `tool_calls`
  and `tool_call_id` (fixes broken tool rounds on some backends)
- **run_command**: tool execution path works reliably again after the tool-calling fix
- **Add Model dialog**: changing the server connection no longer breaks model search;
  connection labels no longer duplicate the URL when name and URL match
- **Android cross-build**: libgee wrap (`vala_gir: disabler()` disabled the whole
  library on Android); wrap patch re-apply when CI restores cached `subprojects/`;
  CI cache no longer saved before the APK build finishes

## [1.2.4-alpha] - 2026-06-13

### Fixed

- Packaging: add missing release files
