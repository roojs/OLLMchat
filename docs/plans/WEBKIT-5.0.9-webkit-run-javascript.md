# 5.0.9 — WebKit running JavaScript

> **Do not update `docs/plans/WEBKIT-1.0-summary.md` for this plan.**

**Status:** **proposed** — design lock from chat; not implemented.

**Pointer:** `docs/guide-to-writing-plans.md` — **Checklist for plans**; proposed Vala follows **`docs/coding-standards.md`**

**Parent:** [`WEBKIT-5.0-webkit-control.md`](WEBKIT-5.0-webkit-control.md)

**Related:**

- ℹ️ Parent veto: no page-JS for **a11y dump / fill / press** — this plan is a **separate**, permissioned **`run_js`** path (not that veto)
- ℹ️ Permission UX precedent: `ChatPermission` Allow / Deny / Always (`libollmchat/ChatPermission/`); press uses standard chat bar ([`5.0.3`](WEBKIT-5.0.3-DEFERRED-webkit-press-permission-overlay.md) overlay still deferred)
- ℹ️ Script authoring: existing **`write_file`** tool (`liboctools/WriteFile/`)
- ℹ️ Host already has `evaluate_javascript` for settle `document.readyState` only (`libocwebkit/Browser.vala`) — not a model-facing action today

---

## Purpose

- **🔷** Add a browser tool action that **runs LLM-authored JavaScript** in the current page.
- **🔷** Script body lives in a **file** (not inline in the tool call). Model uses **`write_file`** into a known temp / cache dir, then the browser action points at that path.
- **🔷** Permission is **per site** (not per script fragment): user accepts that the agent may run generated JS **on this site**.
- **🔷** Tool call must include a **reason / description** of what the script is for.
- **🔷** Permission UI offers **Allow** (once), **Describe** (show short description of the script), and **Allow always** (trust this site for generated JS).
- **🔷** After **Allow always** for a site, do **not** require a fresh script description / summarizer pass every time.
- **⏳** Lock wire name, temp-dir contract, permission key, and summarizer call — then implement.
- **ℹ️** Parent **5.0** stays parked; this is an additive child.

---

## Why a file (not inline script)

- **🔷** Model writes the script with **`write_file`** (same as other generated artefacts).
- **🔷** Browser tool takes a **path** to that file and executes its contents in the page.
- **🔷** Keeps the tool call small and reviewable; big scripts stay on disk.
- **💩** Exact temp root (e.g. under app cache / session tmp) — lock at implement; must be a path **`write_file`** is allowed to write and the browser action is allowed to read.
- **💩** Whether the path arg is absolute only, or relative to that temp root — lock at implement.

---

## Wire shape (proposed)

- **🔷** New **`browser`** action to run the file in the current WebView session.
- **💩** Action name: **`run_js`** (confirm; alternatives `javascript` / `eval` rejected unless user prefers).
- **🔷** Args:
  - **`path`** (or equivalent) — filesystem path to the `.js` file the model wrote
  - **`reason`** (or **`description`**) — short human/model reason for running it (required on the tool call)
- **💩** Optional return: script result / `toString` of evaluate return value / console capture — confirm; minimum is success/fail + settle + normal page dump if useful.
- **🚫** Do **not** put the full script source in the tool JSON when a file path is the contract.
- **🚫** Do **not** use this action to replace a11y dump / fill / press (parent veto stays).

---

## Permission model

### Identity

- **🔷** Scope: **site** the WebView is on when the run is requested (origin / host — not a one-off script hash).
- **💩** Exact key string: e.g. `browser_run_js#https://example.com` (origin) vs full URI — prefer **origin**; confirm at implement.
- **🔷** Operation: **EXECUTE** (same family as `press`).
- **🔷** Stored **Allow always** means: agent may run generated JS on that site without asking again (and without forcing Describe / summarizer).

### Prompt copy

- **🔷** Default question tone: **run generated JavaScript on this site** (site name / host visible).
- **🔷** Do **not** paste the full script into the default permission question.
- **🔷** The tool’s **`reason`** is available for the UI; full script stays on disk until Describe (or always-allow skip).

### Buttons

- **🔷** **Allow** — run this script **once** on this site; does not persist always-trust.
- **🔷** **Describe** — show a **short description** of what the script does (see Summarizer). Does not by itself grant always-trust. User can then Allow or Allow always.
- **🔷** **Allow always** — allow this run **and** remember for this site; later matching runs skip the prompt (and skip Describe / summarizer).
- **💩** **Deny** / **Deny always** — assume standard `ChatPermission` deny family unless UI already omits them; do not invent a fifth custom button without need.
- **ℹ️** Today’s chat permission row is Allow / Deny / Always — **Describe** is **new** affordance for this action (may need ChatPermission UI extension or a one-shot expand on the question).

### Trust vs review

- **🔷** **Allow always** = user is saying they trust the agent on that site for generated JS (insane but intentional).
- **🔷** Without always-trust: each (or each session) prompt can surface **Describe** so the user is not forced to read raw JS unless they want to.

---

## Summarizer (Describe)

- **🔷** When the user chooses **Describe** (or when building the short blurb to show), present a **short natural-language summary** of the script — not the raw source by default.
- **🔷** Preferred source for that blurb: a **lightweight chat-completion** call (no thinking / no tool loop) over the script file + the tool **`reason`**, asking for a brief user-facing description.
- **🔷** If the site already has **Allow always**, **skip** the summarizer (no need to describe every script).
- **💩** Which connection / model usage key (e.g. title-model-class cheap model) — confirm at implement; TitleGenerator-style one-shot is the precedent family.
- **💩** Fallback if the summarizer call fails: show the tool **`reason`** only, or offer “show file path / open script” — confirm; do not block Allow on summarizer failure.
- **💩** Whether **Allow** (once) always shows the short blurb inline vs only after **Describe** — user wording leans: options are Allow + Describe + Allow always; Describe reveals the summary.

---

## Execution flow

1. **⏳** **🔷** Model writes JS via **`write_file`** into the agreed temp / cache directory.
2. **⏳** **🔷** Model calls **`browser`** with **`action: run_js`**, **`path`**, **`reason`**.
3. **⏳** **🔷** Request builds permission (`permission_target_path` site-scoped, question “run generated JS on …”).
4. **⏳** **🔷** If not always-allowed: show Allow / Describe / Allow always (and Deny as usual).
5. **⏳** **🔷** On Describe: run summarizer (or show cached summary for this call); keep permission UI open.
6. **⏳** **🔷** On Allow / Allow always: read file contents, `evaluate_javascript` (or platform equivalent) in the current page, then settle / return result per locked return shape.
7. **⏳** **🔷** On Deny: refuse; no page JS run.

---

## Platforms

- **🔷** Linux WebKitGTK first (same as parent spike path).
- **💩** Windows (`webview2-gtk`) / Android parity when host evaluate APIs exist — follow **5.0.1** / **5.0.2** patterns; not a blocker for Linux design lock.

---

## Suggested order

1. **⏳** **🔷** Lock wire: action name, `path`, `reason`, return payload.
2. **⏳** **🔷** Lock temp-dir contract with **`write_file`** (writable path the tool docs advertise).
3. **⏳** **🔷** Permission key + Allow / Describe / Allow always behaviour (ChatPermission UI gap for Describe).
4. **⏳** **🔷** Summarizer one-shot completion (cheap model, no thinking).
5. **⏳** **🔷** Implement `run_js` execute path (`read file` → evaluate → settle / reply).
6. **⏳** **🔷** Tool description text so the model knows: write file first, then run with reason.
7. **⏳** **💩** Spike in `oc-test-webkit` if useful before chat wiring.

---

## LLM notes

- Parent forbids JS for **dump / fill / press**. This plan is explicit **opt-in agent JS** with site permission — different product surface.
- Do not update **`-README.md`** until this plan is done and archived.
- Do not add Vala helpers unless the user names them when implementing.
- Mark any new ChatPermission button / expand UX carefully — reuse Provider persistence for always-allow; only extend UI for **Describe**.
