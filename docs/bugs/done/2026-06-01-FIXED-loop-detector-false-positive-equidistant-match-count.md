# Loop detector: false stop after two phrase repeats (needs twelve)

**Status:** FIXED — applied 2026-06-01.

**Verified:**
- `/tmp/loop-exec-35.txt` (session msg 34) → **Loop detection: NO**
- `tests/data/twelve-equidistant-loop.txt` → **YES** at delta 72 (meson `check-back-token-test`)
- `tests/data/thinking-loop-transcript.txt` → **NO** (many repeats, not twelve equidistant — expected)

**Started:** 2026-06-01

**Related:** `~/.local/share/ollmchat/history/2026/06/01/08-55-43.json`; `examples/oc-test-loop.vala`; `tests/data/thinking-loop-transcript.txt`; `tests/meson.build` (`check-back-token-test`).

**Pointer:** `.cursor/rules/CODING_STANDARDS.md` (**Checklist for all plans**); `docs/bug-fix-process.md`; `docs/guide-to-writing-plans.md`.

---

## Purpose

- **🔷** Stop declaring a streaming loop until **twelve** equidistant copies of the same five-word window exist — not after two.
- **🔷** Fix **`index_of`** misuse (HEAD re-scanned from the start each pass) and **check-after-prepend** ordering.
- **⏳** Session `08-55-43` skill executor stream must not stop on two similar `## Result summary` paragraphs.

---

## Scope

| In scope | Out of scope |
|----------|----------------|
| **`check_back_token(string token)`** (before prepend) + **`detect_looping()`** order + cap | Skill prompts / model tuning |
| **`examples/oc-test-loop.vala`** — match check-before-prepend | New helper methods |
| Re-run `oc-test-loop` on session extract + thinking fixture | Disabling loop detection per call type |

---

## Acceptance criteria

- **🔷** `./build/examples/oc-test-loop /tmp/loop-exec-35.txt` → **Loop detection: NO** (session msg 34 content-stream).
- **🔷** `check_back_token()` only returns **`false`** (loop) when all **twelve** equidistant word slots and **twelve** five-word phrases match.
- **⏳** True runaway stream still detected — agree test fixture / meson test if `thinking-loop-transcript.txt` no longer qualifies (see **🚫** / **💩** below).
- **⏳** Discard current uncommitted diff on `Chat.vala` before apply (WIP is incomplete).

**Repro extract:**

```bash
python3 -c "import json; print(json.load(open('$HOME/.local/share/ollmchat/history/2026/06/01/08-55-43.json'))['messages'][34]['content'])" > /tmp/loop-exec-35.txt
./build/examples/oc-test-loop /tmp/loop-exec-35.txt
./build/examples/oc-test-loop tests/data/thinking-loop-transcript.txt
```

| Tree | Session exec | thinking-loop fixture |
|------|--------------|------------------------|
| **HEAD** | YES — delta 52 | YES — delta 35 |
| **Uncommitted WIP** | YES — delta 80 | YES — delta 89 |

---

## Root cause

- **🔷** Session stopped after **two** copies of **`asks or requests system the`** — not twelve headings.
- **🔷** Detector uses the **newest word** and five-word windows in **`back_tokens`** (newest-first, cap 100) — not markdown structure.
- **🔷** **`index_of(t0)`** on each pass found the **first** older hit again → **`matches`** could be **`[0, 41, 41, 41]`** (two real positions).
- **🔷** After the fixed **`for (int i = 0; i < 4; i++)`** finished, code still **`return false`** when **`matches.length == 2`**.
- **🚫** Raising the loop bound to **`i < 11`** only adds search passes — it does **not** require twelve hits (proven: WIP still stops the session stream).

---

## `back_tokens` sizing (twelve matches)

Twelve equidistant hits with spacing **`dist > 5`** (minimum **`dist == 6`**) need index **`11 × 6 = 66`** for the twelfth slot, plus **five** words for the phrase window → **`71`** words **after** the incoming token is prepended.

| Setting | HEAD | **🔷** Proposed | Why |
|---------|------|-----------------|-----|
| Early exit in **`check_back_token(token)`** | **`size < 10`** (after prepend) | **`size < 71`** (**before** prepend) | Window after prepend must hold twelve slots at minimum spacing |
| **`detect_looping()`** order | insert → check | **check → insert** | Head word is the **incoming** token; search current buffer with **`index_of`** |
| Sliding cap in **`detect_looping()`** | **`> 100`** trim | **`> 200`** trim | At cap 100, twelve hits only fit spacing **≤ ~8** words |
| Session false positive (spacing ~31) | Stops at two hits | Stays **NO** | Slot 3 at **`2 × 41`** already fails the word check |

**💩** Cap **200** is a round number that allows twelve hits up to spacing **~17**; tune after **`oc-test-loop`** on **`thinking-loop-transcript.txt`**.

---

## Concrete code proposals

**Vala style (`.cursor/rules/CODING_STANDARDS.md`):** no **`const`**; locals use **`var`**; inline literals; line comments at each phase.

**Design:** **`check_back_token(string token)`** runs **before** the token is prepended. The incoming word is the head (index 0 after insert). **`back_tokens.index_of(token)`** finds the next hit in the **current** buffer; **`dist = hit + 1`** is the spacing in the after-prepend window. Then two **`for (i = 0; i < 12; i++)`** loops: same word at **`i * dist`**, then same five-word phrase.

### 1. `libollmchat/Response/Chat.vala` — `check_back_token(string token)`: replace whole method

**Why:** Check **before** prepend; one **`index_of`** for spacing; twelve equidistant word slots, then twelve phrase compares. No blanking slot 0, no **`matches[]`**, no re-scan bug.

**Algorithm (comments in code mirror this):**

| Step | What |
|------|------|
| **1** | **`token`** — word about to be prepended; will be index **0**. |
| **2** | **`hit = back_tokens.index_of(token)`** — first same word in the **current** buffer. **`dist = hit + 1`**. No hit or **`dist ≤ 5`** → not a loop. |
| **3** | **Phase 1 — same word × 12** — on **`back_tokens`** only: **`index_of`**, **`get(pos - 1)`**, **`size`** range checks. No **`to_array()`**. |
| **4** | **Phase 2 — same five-word phrase × 12** — **`words = back_tokens.to_array()`** once; head = **`token` + `joinv(words[0:4])`**; at slot **`pos > 0`**, **`joinv(words[pos - 1:pos + 4])`**. |

**Where:** **`check_back_token()`** signature and body. Revert uncommitted WIP first.

**Depends on:** §2 **`detect_looping()`** (check before insert).

#### Remove

```vala
		public bool check_back_token()
		{
			if (this.back_tokens.size < 10) {
				return true;
			}

			var t0 = this.back_tokens.get(0);
			this.back_tokens.set(0, "");

			int[] matches = { 0 };

			for (int i = 0; i < 4; i++) {
				int pos = this.back_tokens.index_of(t0);

				if (pos < 0 || pos + 5 > this.back_tokens.size) {
					foreach (int m in matches) {
						this.back_tokens.set(m, t0);
					}
					return true;
				}

				matches += pos;

				if (matches.length > 2) {
					int n = matches.length;
					int dist = matches[n - 1] - matches[n - 2];
					if (dist != matches[n - 2] - matches[n - 3] || dist <= 5) {
						matches.resize(matches.length - 1);
						continue;
					}
				}
			}

			foreach (int m in matches) {
				this.back_tokens.set(m, t0);
			}

			var str = this.back_tokens.to_array();

			foreach (int match in matches) {
				if (match == 0) {
					continue;
				}
				if (string.joinv(" ", str[match:match + 5]) != string.joinv(" ", str[0:5])) {
					return true;
				}
			}

			return false;
		}
```

#### Replace with

```vala
		public bool check_back_token(string token)
		{
			// After prepend, window must hold twelve equidistant slots plus a five-word phrase.
			if (this.back_tokens.size < 71) {
				return true;
			}

			// Step 1: incoming token will be the head (index 0) once prepended.
			// Step 2: next occurrence in the current buffer — spacing in the after-prepend window.
			var hit = this.back_tokens.index_of(token);
			if (hit < 0) {
				return true;
			}
			var dist = hit + 1;

			// Spacing too tight for a real loop — not repeating yet.
			if (dist <= 5) {
				return true;
			}

			// Phase 1: twelve equidistant slots — same word at each (back_tokens only).
			for (var i = 0; i < 12; i++) {
				var pos = i * dist;
				// Need five words from this slot once the token is prepended.
				if (pos + 5 > this.back_tokens.size + 1) {
					return true;
				}
				// Slot 0 is the incoming token; older slots are back_tokens.get(pos - 1).
				if (i > 0 && this.back_tokens.get(pos - 1) != token) {
					return true;
				}
			}

			// Phase 2: five-word phrase at each slot — one array snapshot for slice + join.
			var words = this.back_tokens.to_array();
			var head_phrase = token + " " + string.joinv(" ", words[0:4]);

			// Same twelve slots — slice range and join.
			for (var i = 0; i < 12; i++) {
				var pos = i * dist;
				var phrase = (pos == 0)
					? head_phrase
					: string.joinv(" ", words[pos - 1:pos + 4]);
				if (phrase != head_phrase) {
					return true;
				}
			}

			// Twelve equidistant word hits and twelve matching phrases — loop.
			return false;
		}
```

---

### 2. `libollmchat/Response/Chat.vala` — `detect_looping()`: check before insert, larger cap

**Why:** Loop test uses the **incoming** token as head **before** it enters **`back_tokens`**. Cap **200** for twelve equidistant hits at moderate spacing.

**Where:** Replace whole **`detect_looping()`** method.

**Depends on:** §1.

#### Remove

```vala
		public bool detect_looping(string token)
		{
			foreach (string w in Regex.split_simple("\\s+", token)) {
				if (w.length == 0) {
					continue;
				}
				this.back_tokens.insert(0, w);
				if (this.back_tokens.size > 100) {
					this.back_tokens.remove_at(this.back_tokens.size - 1);
				}
				if (!this.check_back_token()) {
					return false;
				}
			}
			return true;
		}
```

#### Replace with

```vala
		public bool detect_looping(string token)
		{
			foreach (string w in Regex.split_simple("\\s+", token)) {
				if (w.length == 0) {
					continue;
				}
				// Check before prepend — incoming word is the head for check_back_token.
				if (!this.check_back_token(w)) {
					return false;
				}
				this.back_tokens.insert(0, w);
				if (this.back_tokens.size > 200) {
					this.back_tokens.remove_at(this.back_tokens.size - 1);
				}
			}
			return true;
		}
```

---

### 3. `examples/oc-test-loop.vala` — use `detect_looping` (check before insert)

**Why:** Test harness must match production order; drop **`push_delta` + `check_back_token()`**.

#### Remove

```vala
static void push_delta(OLLMchat.Response.Chat r, string token)
{
	if (token.length == 0) {
		return;
	}
	r.back_tokens.insert(0, token);
	if (r.back_tokens.size > 100) {
		r.back_tokens.remove_at(r.back_tokens.size - 1);
	}
}
```

And in **`main`**, replace the loop body:

```vala
		for (int i = 0; i < chunks.length; i++) {
			push_delta(r, chunks[i]);
			if (!r.check_back_token()) {
```

#### Replace with

```vala
		for (int i = 0; i < chunks.length; i++) {
			if (!r.detect_looping(chunks[i])) {
```

---

## Test follow-up (after apply — agree before merge)

- **🔷** Session extract **`/tmp/loop-exec-35.txt`** → **NO** (primary fix).
- **🔷** Re-run **`thinking-loop-transcript.txt`** after cap **200** — if still **NO**, agree new fixture (see **💩** below).
- **💩** Replace **`thinking-loop-transcript.txt`** if cap **200** is still too short for twelve equidistant hits in that fixture.
- **🚫** Do not merge with a failing meson test without explicit agreement.

---

## After the fix

- Move to **`docs/bugs/done/`** with **`FIXED`** in the filename when verified.
- No temporary **`GLib.debug()`** unless manual replay still disagrees with **`oc-test-loop`**.
