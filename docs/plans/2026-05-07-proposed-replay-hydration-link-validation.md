# 2026-05-07 Replay / restore: hydrate without link validation

**Status:** implemented (**2026-05-07**) after **`/tmp/log.txt`** proved GTK restore had **`in_replay=false`** (**bug doc** Evidence). Original gate was **`docs/bug-fix-process.md`** approval.

**Pointer:** **`.cursor/rules/CODING_STANDARDS.md`** — checklist for plans; smallest change.

## Logging (convention for this work)

- **In code:** Put each **`GLib.debug()`** at a **fixed, meaningful site** in the real control flow — e.g. right after the **`can_replay`** guard, immediately before **`exec_post_extract`** / **`exec_extract`**, at a **phase**/**outcome** boundary — not scattered through the function. Do **not** put class names, method names, or file/line text inside the message (the runtime already logs file and line). Follow **“Debug and Warning Statements”** in **`.cursor/rules/CODING_STANDARDS.md`** (no throttling or debug-only flags whose only job is to reduce log volume).
- **For verification / bug evidence:** Always capture the same way to a **single path** so everyone can grep the same file — e.g. run with debug enabled and save to **`/tmp/log.txt`** (or one team path). That keeps repro logs comparable and avoids “which file was that run?”

## Purpose

- GTK **`restore_messages`** → **`on_replay`** and ReplayChat **`Runner.replay`** both parse transcript through **`ResultParser`** / **`ValidateLink`**.
- Link checks use **current disk** → restore fails (**`post_issues_len>0`**) though transcript was valid live.

## Scope

| In scope | Out of scope |
|----------|----------------|
| **`Runner.on_replay`** + **`ValidateLink.validate_all`** | New **`SessionBase`** flags (**🚫** user veto **`restoring_history`**) |
| Skip **`ValidateLink`** only while hydrating (**`in_replay`**) | **`ProgressList`** / iteration rewrite (**unless** still broken after this) |
| Fences below | Relaxing validation on **live** sends |

## Acceptance criteria

- **`ninja -C build`**
- GTK restore: **`REPLAY POST EXEC outcome`** **`issues_empty=true`** when prior failure was link/env only (same repro as bug log).
- Live continuation after restore still validates new output (**`in_replay`** false).

## Current behaviour (bullets)

- **`in_replay`** set **`true`** only in **`Runner.replay()`** (ReplayChat).
- **`Session.restore_messages`** never enters **`Runner.replay()`** → **`in_replay`** stays **`false`** during GTK restore.

## Proposed behaviour (bullets)

- Every **`on_replay`** message runs with **`in_replay`** true (**save/restore** old value).
- **`ValidateLink.validate_all`** no-op when **`details.runner.in_replay`**.

## Concrete code proposals

Intro: hunks are **Keep** / **Remove** / **Replace with** / **Add** from tree — verify context before apply (**`docs/guide-to-writing-plans.md`**).

🔷 **Implement in order:** **### 1** then **### 2** (GTK restore needs **`### 1`** before **`ValidateLink`** sees **`in_replay`**).

### 1. `liboccoder/Skill/Runner.vala` — `on_replay`

ℹ️ After the **`can_replay`** guard: save **`was_in_replay`**, set **`this.in_replay = true`**, run the existing method body unchanged, then **`this.in_replay = was_in_replay`** as the **last** statement before the method closes. **No `try` / `finally`**: the body has **no** early **`return`** after the guard (only **`switch`** / **`break`**). If **`GLib.error`** aborts from inside a **`catch`**, the process exits — same as elsewhere.

##### Part 1 — Guard unchanged

#### Keep

```vala
		public override void on_replay(OLLMchat.Message m)
		{
			if (!this.session.can_replay) {
				return;
			}

```

#### Add — After guard (before existing debug / **`switch`**).

```vala
			var was_in_replay = this.in_replay;
			this.in_replay = true;

```

##### Part 2 — Body unchanged

ℹ️ Leave **`GLib.debug`** · **`switch (this.replay_phase)`** · … as-is (**no** extra indent from a wrapper).

##### Part 3 — Restore at end

#### Add — Immediately after the outer **`switch (this.replay_phase)`** closes.

```vala
			this.in_replay = was_in_replay;
```

💩 Do **not** add session-level flags (**🚫** **`restoring_history`**).

### 2. `liboccoder/Task/ValidateLink.vala` — `validate_all`

Pair with **### 1**.

#### Remove

```vala
	/**
	 * Validate every link in ''links''; appends to [[issues]] (same shape as task reference errors).
	 */
	public void validate_all (Gee.Iterable<Markdown.Document.Format> links)
	{
		foreach (var link in links) {
			this.validate (link);
		}
	}
```

#### Replace with — Skip links during hydration only.

```vala
	/**
	 * Validate every link in ''links''; appends to [[issues]] (same shape as task reference errors).
	 * Skipped when [[Skill.Runner.in_replay]] (ReplayChat or GTK restore after §1).
	 */
	public void validate_all (Gee.Iterable<Markdown.Document.Format> links)
	{
		if (this.details.runner.in_replay) {
			return;
		}
		foreach (var link in links) {
			this.validate (link);
		}
	}
```

### 3. Rejected

🚫 **`SessionBase.restoring_history`** — user veto.

## Verify

- **`ninja -C build`**
- Open saved session → grep **`REPLAY POST EXEC outcome`**
- Optional: bug doc **`REPLAY HYDRATE FLAGS`** (**`docs/bugs/2026-05-03-OPEN-task-progress-orphan-clear-pending-replay.md`** § Debug gaps)

## Changelog

- 2026-05-07 — First draft (**Observation**, Options).
- 2026-05-07 — **Guide shape:** Purpose / Scope / Acceptance / bullets / **Concrete code proposals** with **Part** chunks + **ValidateLink** Remove/Replace; dropped duplicate prose section.
- 2026-05-07 — **Logging** convention: fixed **`GLib.debug`** sites per **CODING_STANDARDS**; verification logs to a single path (e.g. **`/tmp/log.txt`**).
- 2026-05-07 — **`### 1`**: **`in_replay`** restore without **`try`/`finally`** (single exit path after guard).
