# Third-party and exception licenses

OLLMchat source is **LGPL-3.0** (see the top-level [`LICENSE`](../LICENSE)),
**except** for the files listed below. Those files are under the license named
in their row (usually because they are copied or derived from another project).

This file is the inventory (bill of materials). There is no separate CycloneDX
SBOM for these exceptions.

## Files not under LGPL-3.0

| Path | License | Upstream |
|------|---------|----------|
| [`resources/pi-prompts/initial.md`](../resources/pi-prompts/initial.md) | MIT | [earendil-works/pi](https://github.com/earendil-works/pi) `packages/coding-agent/src/core/system-prompt.ts` (+ tool `promptSnippet` strings). See [`resources/pi-prompts/NOTICE`](../resources/pi-prompts/NOTICE). |
| [`resources/pi-prompts/compact.md`](../resources/pi-prompts/compact.md) | MIT | [earendil-works/pi](https://github.com/earendil-works/pi) compaction section shape; hash-link / `session_fetch` rules are OLLMchat. See [`resources/pi-prompts/NOTICE`](../resources/pi-prompts/NOTICE). |

When a derived file is added, put it in this table and keep the matching
upstream license text under `licenses/<component>/`.

## Components

### pi-coding-agent (MIT)

- **Upstream:** [earendil-works/pi](https://github.com/earendil-works/pi)
  (coding-agent package; default system prompt from
  `packages/coding-agent/src/core/system-prompt.ts`)
- **License text:** [`pi-coding-agent/LICENSE`](pi-coding-agent/LICENSE)
- **Copyright:** Copyright (c) 2025 Mario Zechner
- **Snapshot used for attribution setup:** commit `c820aa26`
  (`c820aa26fe0907e053e881a957722693fc094c9c`), dated from local clone
  2026-07-29

Agent Pi in OLLMchat copies or derives prompt wording from that source under
MIT. Listed paths above are the in-tree derived files.
