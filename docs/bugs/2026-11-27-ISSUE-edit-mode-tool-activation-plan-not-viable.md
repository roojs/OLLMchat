# Edit-mode `write` activation + fence stream plan not viable for primary models

**Status:** ⏳

## User decisions required

- 💩 **Product direction** — ship **always-on** `<<write>>` parsing on Agent Pi vs keep the **`write`** tool gate (tag syntax in the continuing stream either way) — see [EDIT-2.16](../plans/EDIT-2.16-edit-output-format-strategy.md).
- 💩 **Outside-project writes** — session allow-list vs modal **per** `<<write>>`; inline **accept / reject / review** on streamed blocks vs end-of-turn only — **Proposed fix → Outside-project writes**.
- 💩 **Permission timing** — when to prompt for outside paths until session UI exists: end of message, mid-stream, or end + diff preview.
- 💩 **Multiple `<<write>>` blocks** in one assistant message — one permission check per path, or reject multiples.
- 💩 **Drop `write` tool** on Agent Pi when always-on ships, or run both temporarily.

Syntax shape, delimiter choice, and harness results are **not** blocked on you — see **Proposed fix → Recorded syntax** and **Testing phases**.

## User reported

- 🔷 `write` + fence streaming is not reliable for `ornith-1.5:35b`; always-on `<write>` POC worked without the tool.
- 🔷 This report should document **today’s EditMode**, especially **permissions** and **edit modes**, and the always-on replacement — not extra plan files.

## Success scenario

- Always-on `<write>` parser ships for Agent Pi.
- Outside-project WRITE rules match today’s `build_perm_question()` ([`Request.vala`](../../liboctools/EditMode/Request.vala)).
- Permissions and mode behaviour in this report stay accurate for shipping code and proposed tag parser.

## Current behavior

- Harness (phone + desktop gtktest1)
  - User asks for a mid-file edit.
  - Model calls `write` with `file_path` + `edit_mode`.
  - Harness replies with fence / tag instructions and “do not call `write` again in this message”.
  - Model often emits **think-only** or **empty** assistant content, then calls **`write` again** — see [CLOSED phone session](done/2026-11-23-CLOSED-phone-agent-pi-edit-file-test.md).
- Always-on CLI repro (no `write` tool registered)
  - `ollmchat-cli` with [`tests/data/always-on-edit-brace-poc/`](../../tests/data/always-on-edit-brace-poc/) and `ornith-1.5:35b`.
  - Single assistant turn with `<write file="…">…</write>` (POC used `edit_mode="complete_file"` — drop that attribute); no `tool_calls` — excerpt in [`last-run.txt`](../../tests/data/always-on-edit-brace-poc/last-run.txt).
- Gap
  - No full agent-loop probe: **`write` offered**, edit activated, model must emit **tag** syntax in the continuing stream.

## Permissions

The app **only prompts** when the write target is **outside** the active project. Paths inside the project do not ask ([`build_perm_question()`](../../liboctools/EditMode/Request.vala)).

Always-on `<<write>>` should keep the same inside/outside rule; **when** to ask is in **User decisions required** (**Permission timing**).

## Edit modes

**Shipping today** — `edit_mode` on **`write`** / **`edit_mode`** ([`Request.vala`](../../liboctools/EditMode/Request.vala), default **`ast_path`**). Always-on plan: **no `edit_mode` on `<write>`** — only `file="…"` and body shape (**Proposed fix**).

**Stream apply** — [`Stream.vala`](../../liboctools/EditMode/Stream.vala) parses assistant **fences** while edit mode is active; rejects hunks that do not match the activated mode.

**Agent-facing names**

- Pi / phone: **`write`** ([`Write.vala`](../../liboctools/EditMode/Write.vala)).
- Skills agent: **`edit_mode`** ([`Tool.vala`](../../liboctools/EditMode/Tool.vala)).

### `complete_file`

- New file or **whole-file** replace on an existing path.
- Body: **plain text** (full file contents). **Not** markdown ``` fences while the **`write`** gate is in use.
- With the tool gate, a bare `` ```lang `` fence in the stream matches this mode ([`Tool.vala`](../../liboctools/EditMode/Tool.vala)).

### `line_numbers`

- Partial edit by **1-based** line range; end line **exclusive** (e.g. `` ```vala:10:15 ``` ``).
- Still in the tool schema; **not recommended** in help text — LLMs are poor at stable line ranges → **drop for always-on** (**Proposed fix**).

### `ast_path`

- Partial edit by symbol path on an **existing** file (shipping tool gate only).
- Fences: `type:Namespace-Class-Method` and suffixes ([`Tool.vala`](../../liboctools/EditMode/Tool.vala)).
- Models rarely name symbols correctly → **not planned for always-on**; partial edits there use **content chunks** only (**Proposed fix**).

### `overwrite`

- **`complete_file`** only; default **`false`** → error if file exists; **`true`** replaces without review gate in tool validation.
- Post-approval diff flow may make this redundant for always-on → likely **drop** the attribute (**Recorded syntax**).

### Always-on gap (not shipping)

- Partial **`<<remove>>`** / **`<<add>>`** on **verbatim snippets** (+ optional weak **`lines`** hint) — **Proposed fix**. No AST, no **`after`**. Delimiter **`<<…>>`** (proposed).
- **XML / HTML targets** — if **`<<…>>`** holds in harness, normal `<` in file content should not clash with controls — **Testing phases** (phase 8).

## Codebase observed behavior

- [`Request.vala`](../../liboctools/EditMode/Request.vala) — validation of `edit_mode`, permission build, tool result instructs tag/fence shape for the **same** assistant message.
- [`Stream.vala`](../../liboctools/EditMode/Stream.vala) — fence streaming and apply; mode mismatch errors.
- [`Write.vala`](../../liboctools/EditMode/Write.vala) — Pi schema + short help for tag attributes.

## Debugging

### Current debug output

- Archived phone session — [done/2026-11-23-CLOSED-phone-agent-pi-edit-file-test.md](done/2026-11-23-CLOSED-phone-agent-pi-edit-file-test.md).
- Always-on POC — [`last-run.txt`](../../tests/data/always-on-edit-brace-poc/last-run.txt).

### Debug code added (remove when complete)

- None.

## Proposed fix

Always-on `<<write>>` in assistant text (no **`write`** tool on Agent Pi when always-on ships — **User decisions required**). **No product parser** until **Testing phases** pass on delimiter + models. Prefer the examples below over enum lists.

### Recorded syntax (authoritative for spec work)

- Partial edits: literal file context, **`<<remove>>`** / **`<<add>>`**, more context — **no `<<replace>>`**, **no `---`**, **no `after`**.
- **Swap in place**: context + **`<<remove>>`** + **`<<add>>`** + context. **Pure insert**: context + **`<<add>>`** + context.
- **`<<remove>>` body** = bytes to delete only. Anchor with **≥2 unchanged lines** each side when the cut is not unique.
- Several **`<<remove>>`** in one `<<write>>` OK in **file order** with context between cuts.
- Control tags **`<<remove>>`**, **`<<add>>`**, closers at **column 0**; file body keeps real indentation.
- **`<<write file="…">>`** — only **`file`** (no `edit_mode`, no `overwrite`, no AST on the tag).
- Weak optional **`lines="start:end"`** on partial tags — ship only if harness shows models respect it.
- **`<<block>>`** wrapper — sketch only; name and UI TBD during parser work (examples at bottom).
- **`<<…>>` delimiter** — working assumption so file HTML/XML keeps single `<`; revert only if **Testing phases** fail badly.

### Tag vocabulary (always-on, v0)

- **Control tags** use **`<<` … `>>`** — e.g. `<<write file="path">>`, `<</write>>`, `<<remove>>`, `<</remove>>`, `<<add>>`, `<</add>>`.
- **File bytes** between controls stay literal (real `.xml` may contain `<schema>`, `<key>`, etc.).
- POC [`last-run.txt`](../../tests/data/always-on-edit-brace-poc/last-run.txt) still uses **single** `<write>`; examples below use **`<<`** (target shape for harness).

- Go/no-go for a product parser follows **Testing phases** (after examples), not **User decisions required**.

### Examples — new or whole file

POC shape ([`last-run.txt`](../../tests/data/always-on-edit-brace-poc/last-run.txt)):

```xml
<<write file="sample-brace.txt">>
1
2
3 First line of content
4 Second line
…
<</write>>
```

Minimal new file:

```xml
<<write file="docs/quick-note.md">>
# Quick note

Body paragraph.
<</write>>
```

Replace entire existing file after review (no `overwrite` flag):

```xml
<<write file="src/Version.vala">>
namespace MyApp;

public const string VERSION = "2.0.0";
<</write>>
```

### Examples — `remove`

**Unique chunk** — `<<remove>>` alone is enough when the body appears once in the file:

```xml
<<write file="lib/Config.vala">>
<<remove>>
	// TEMP: remove before release
	if (debug) {
		stderr.printf ("verbose\n");
	}
<</remove>>
<</write>>
```

**With file context (recommended when unsure)** — copy unchanged lines from disk into `<<write>>` on both sides of `<<remove>>`; only the tag body is removed:

```xml
<<write file="meson.build">>
executable('app', …)
subdir('app')
<<remove>>
subdir('legacy')
<</remove>>
subdir('tests')
subdir('docs')
<</write>>
```

```xml
<<write file="lib/Panel.vala">>
	this.content = box;
	this.focusable = true;
<<remove>>
	// FIXME: temporary
	this.margin_top = 0;
<</remove>>
	this.margin_top = 6;
	this.margin_bottom = 0;
<</write>>
```

Several **`<<remove>>`** tags in one `<<write>>` are fine when the model streams **one patch in file order**: literal context lines between tags disambiguate each cut. Use whole-file **`<<write>>`** when the patch is not a simple in-order sequence.

### Examples — swap in place (context + `remove` + `add`)

Version field in a meson header (two lines of context each side):

```xml
<<write file="meson.build">>
project('gtktest1', 'vala',
  license : 'MIT',
<<remove>>
  version : '1.2.3',
<</remove>>
<<add>>
  version : '1.2.4',
<</add>>
  meson_version : '>= 1.2.0',
)
<</write>>
```

Multi-line method swap:

```xml
<<write file="lib/Widget.vala">>
	public class Widget : Gtk.Box {
	public void hide () {
		visible = false;
	}
<<remove>>
	public void show () {
		hide ();
		visible = true;
	}
<</remove>>
<<add>>
	public void show () {
		if (!visible) {
			visible = true;
			queue_resize ();
		}
	}
<</add>>
	public void toggle () {
		show ();
	}
<</write>>
```

Drop a `using` and swap a call in one file:

```xml
<<write file="src/main.vala">>
using Gtk;
<<remove>>
using Legacy;
<</remove>>
using Adw;

static int main (string[] args) {
<<remove>>
	int result = run_sync ();
<</remove>>
<<add>>
	int result = run_async ();
<</add>>
	return result;
}
<</write>>
```

Two paths in one assistant turn:

```xml
<<write file="data/app.gschema.xml">>
  <schema id="org.example.App" path="/org/example/App/">
    <key name="window-width" type="i">
<<remove>>
    <key name="old-flag" type="b">
<</remove>>
<<add>>
    <key name="new-flag" type="b">
<</add>>
    </key>
  </schema>
<</write>>

<<write file="src/Settings.vala">>
	var settings = new GLib.Settings ("org.example.App");
	if (settings.get_boolean ("other-flag")) {
<<remove>>
	settings.get_boolean ("old-flag");
<</remove>>
<<add>>
	settings.get_boolean ("new-flag");
<</add>>
	}
<</write>>
```

Same short string twice in file — wider literal context, then **remove** + **add**:

```xml
<<write file="lib/Config.vala">>
[paths]
data_dir=/var/lib
[ui]
window_height=600
<<remove>>
window_width=800
<</remove>>
<<add>>
window_width=1024
<</add>>
fullscreen=false
<</write>>
```

**remove** only (unique method body):

```xml
<<write file="lib/Legacy.vala">>
<<remove>>
	public void old_api () {
		stderr.printf ("deprecated\n");
	}
<</remove>>
<</write>>
```

### Examples — optional `lines` hint (weak)

Body still carries the chunk; lines only help scan:

```xml
<<write file="meson.build">>
executable('app', …)
subdir('app')
<<remove lines="14:15">>
subdir('legacy')
<</remove>>
subdir('tests')
<</write>>
```

```xml
<<write file="CHANGELOG.md">>
### Fixed
- Review bar loop
## 1.2.3
<<remove>>
## 1.2.3
<</remove>>
<<add>>
## 1.2.4
<</add>>
### Added
<</write>>
```

### Examples — pure insert (context + `add`)

Insert between existing lines (no **`remove`**):

```xml
<<write file="src/main.vala">>
int main (string[] args) {
<<add>>
	Application.init ();
<</add>>
	return 0;
}
<</write>>
```

Insert into a meson header:

```xml
<<write file="meson.build">>
project('gtktest1', 'vala',
<<add>>
  meson_version : '>= 1.2.0',
<</add>>
  version : '1.2.4',
)
<</write>>
```

Several insertions in file order (context between each **`add`**):

```xml
<<write file="lib/Service.vala">>
public class Service : Object {
<<add>>
	public signal void ready ();
<</add>>
	construct {
<<add>>
		notify["ready"] ();
<</add>>
	}
}
<</write>>
```

**Remove** then **add** on the next lines (no separate **`after`**):

```xml
<<write file="lib/Panel.vala">>
	this.content = box;
<<remove>>
	// FIXME: temporary
	this.margin_top = 0;
<</remove>>
	this.margin_top = 6;
<<add>>
	this.margin_bottom = 6;
<</add>>
	this.margin_start = 0;
<</write>>
```

### Examples — outside-project writes (later, not syntax)

Today’s rule unchanged: **inside project** → no prompt; **outside project** → ask ([**Permissions**](#permissions)). Open UX:

**Session — accept writes to these paths outside the project:**

```text
Allow Agent Pi to write outside this project for:

  [ ] /etc/app/config.conf
  [ ] ~/.config/foo/settings.ini

[ Remember for this session ]  [ Cancel ]
```

In-project paths stay implicit (no tick list). Session memory only affects **outside** paths.

**Per `<<write file="…">>` while streaming** (especially outside project — blocks are easy to scroll past):

```text
Write: /etc/app/config.conf
  [ Accept ]  [ Reject ]  [ Review ]  [ View on disk ]

```

- **Accept** applies when the block is complete (or on end-of-message — **Permission timing** in **User decisions required**).
- **Reject** drops the block; file untouched.
- **Review** / **View** need a **pre-apply snapshot** of that path if we are not already on the diff-review stack — otherwise **Accept** is **unguarded**: no undo unless we recorded bytes **before** apply outside normal file-monitor history (explore after core **Testing phases** if needed).

### Examples — `<<block>>` wrapper (sketch)

Several islands in one logical patch — name and UI TBD:

```xml
<<write file="lib/App.vala">>
<<block>>
using Gtk;
<<remove>>
using Legacy;
<</remove>>
using Adw;
<</block>>
<<block>>
namespace App {
<<remove>>
	public static int run () { return 0; }
<</remove>>
<<add>>
	public static int run () { return run_async () ? 0 : 1; }
<</add>>
}
<</block>>
<</write>>
```

### Testing phases

Ordered LLM harness work to see whether **Recorded syntax** + **`<<…>>`** delimiter is viable. **Not** user gates — agent runs and scores; results go in **LLM** and fixture `last-run.txt` siblings.

**Harness (all phases)**

- Runner: [`tests/run-always-on-edit-brace-poc.sh`](../../tests/run-always-on-edit-brace-poc.sh) + `ollmchat-cli` (`--system-file`, `--user-file`, no **`write`** tool).
- Workspace: small project tree (e.g. gtktest1) or temp dir under `tests/data/always-on-edit-brace-poc/fixtures/` (create as needed).
- Models (minimum): **`ornith-1.5:35b`** (existing POC), plus production Agent Pi model when known.
- Capture: full assistant text per run; optional grep scorer for `<<write`, `<write`, `<<remove>>`, literal file `<` inside `<<write>>`.
- System prompt: teach **`<<` … `>>`** controls and **Recorded syntax** (replace [`system.md`](../../tests/data/always-on-edit-brace-poc/system.md) per phase or one `system-double-angle.md`).

**Pass / fail (common)**

- **Pass** — response contains well-formed control tags for the phase, file bytes in examples match **Recorded syntax**, no `tool_calls` for **`write`**, file content inside `<<write>>` matches the ask (manual or diff after parser spike).
- **Fail** — single-angle `<write>` only, markdown fences instead of tags, `---` or `<<replace>>`, control tags indented inside file body, HTML/XML in the **target file** escaped or mangled, empty or think-only reply.

**Phase 1 — delimiter + `<<write>>` shell (no real path)**

- ⏳ **Goal** — model learns **`<<`** controls, not HTML `<write>`.
- **User ask** — “Reply with exactly one empty edit block: `<<write file="probe.txt">>` then a newline then `<</write>>` and nothing else.”
- **Pass** — `<<write` and `<</write>>` present; no bare `<write` without second `<`.

**Phase 2 — whole file create**

- ⏳ **Goal** — always-on create without tool (extends existing POC to **`<<`**).
- **User ask** — same as [`user.md`](../../tests/data/always-on-edit-brace-poc/user.md) (~50 lines) but system requires `<<write file="…">>`.
- **Pass** — one `<<write>>`, ~50 lines plain text inside, no `edit_mode` attribute.

**Phase 3 — whole file replace**

- ⏳ **Goal** — clobber body via always-on tags.
- **Setup** — seed `fixtures/sample-brace.txt` (or gtktest1 copy) in user message: “**File `sample-brace.txt` currently:**” + fenced contents.
- **User ask** — “Replace entire file with a short header and 10 numbered lines using always-on edit.”
- **Pass** — single `<<write>>` with full new contents; context lines from old file **not** required.

**Phase 4 — partial remove (unique chunk)**

- ⏳ **Goal** — `<<remove>>` only when chunk is unique.
- **Setup** — paste full file in user message (e.g. 20-line `fixtures/config-snippet.ini` with one `DEBUG=yes` line).
- **User ask** — “Edit mode is always on. Remove the debug flag line only.”
- **Pass** — one `<<write file="…">>`, `<<remove>>` body equals flag line; optional context lines; column-0 tags.

**Phase 5 — partial remove with context**

- ⏳ **Goal** — anchors with **≥2 lines** each side (see examples — meson or Panel).
- **Setup** — file with ambiguous repeated substring plus one removable `subdir('legacy')` (or Panel FIXME block).
- **User ask** — “Remove the legacy subdir / FIXME block; use surrounding file lines in the `<<write>>` as in the spec.”
- **Pass** — literal context before/after `<<remove>>`; no `---`; only removed bytes inside `<<remove>>`.

**Phase 6 — swap (`<<remove>>` + `<<add>>`)**

- ⏳ **Goal** — version bump or method body swap.
- **Setup** — paste `fixtures/Widget.vala` or `meson.build` excerpt in user message.
- **User ask** — concrete change (“set version to 1.2.4”, “replace `show` with the guarded version from the spec examples”).
- **Pass** — context + `<<remove>>` + `<<add>>` + context; new body matches ask.

**Phase 7 — pure insert (`<<add>>` only)**

- ⏳ **Goal** — context + `<<add>>` without `<<remove>>`.
- **Setup** — paste `main.vala` with `int main` but no init call.
- **User ask** — “Insert `Application.init ();` after the opening brace line.”
- **Pass** — anchor lines + `<<add>>` block only.

**Phase 8 — XML target file (delimiter vs content `<`)**

- ⏳ **Goal** — prove **`<<` controls** while file keeps `<schema>` / `<key>`.
- **Setup** — paste `fixtures/app.gschema.xml` fragment in user message.
- **User ask** — rename a key or swap one `<key>` block per spec examples.
- **Pass** — file markup inside `<<write>>` uses **single** `<`; controls use `<<`; no confused half-tags.

**Phase 9 — multi-edit one file**

- ⏳ **Goal** — file-order multiple `<<remove>>` / `<<add>>` islands (e.g. drop `using Legacy` and swap `run_sync` → `run_async`).
- **Setup** — paste `fixtures/main.vala`.
- **User ask** — both changes in one assistant message.
- **Pass** — one `<<write>>`, two islands with context between.

**Phase 10 — optional follow-ons (after 1–9 green)**

- ⏳ Parser apply on captured outputs (fixture corpus, not live LLM).
- ⏳ Same phases with **`write` tool registered but instructions say “use tags only”** — measure tool-call relapse.
- ⏳ `<<block>>` wrapper if phases 6–9 need clearer streaming boundaries.

**Fixture layout (to add under poc dir)**

```text
tests/data/always-on-edit-brace-poc/
  system.md              # legacy single-angle (keep for regression)
  system-double-angle.md # << syntax (phases 1+)
  user.md                # phase 2 create ask
  user-phase-N-….md      # one user template per phase
  fixtures/              # sample file bodies pasted into user prompts
  runs/                  # last-run-phase-N.txt captures
```

## LLM

- ℹ️ **2026-11-28** **Testing phases** (10-step harness plan) added after examples; extends [`always-on-edit-brace-poc`](../../tests/data/always-on-edit-brace-poc/).
- ℹ️ **2026-11-28** **User decisions required** trimmed — only product/permission direction; syntax + harness → **Recorded syntax** / **Testing phases**.
- ℹ️ **2026-11-28** Working delimiter **`<<…>>`**; partial edits **`<<remove>>`** / **`<<add>>`**, column 0; no **`after`**, **`---`**, **`<<replace>>`**.
- ℹ️ Related: [CLOSED phone](done/2026-11-23-CLOSED-phone-agent-pi-edit-file-test.md), [always-on POC](2026-11-27-FEATURE-always-on-edit-brace-syntax-poc.md), [EDIT-2.16](../plans/EDIT-2.16-edit-output-format-strategy.md).