# Nested four-backtick fences (CommonMark) not supported

## Problem

Frame / agent code sometimes wraps markdown that contains literal triple-backtick lines using an **outer fence with more backticks** (often four) so inner triple-backtick runs are **content**, not delimiters. **CommonMark** requires opening and closing fence lines to use the **same** backtick-run length (≥ 3); a shorter run inside the block must not close the outer fence.

**`libocmarkdown` does not implement variable-length fences.** A line starting with four backticks is not parsed as a single four-tick fence: the marker map’s longest registered backtick key is three characters, so the fourth backtick is treated as part of the info string after the fence, and the rest of the document mis-parses.

## Reproduce

1. Fixture: [`tests/markdown/nested-backtick-fence.md`](../../tests/markdown/nested-backtick-fence.md)
2. Parser trace (DummyRenderer):

   ```bash
   ./build/examples/oc-markdown-test tests/markdown/nested-backtick-fence.md
   ```

   (From `tests/`: `./build/examples/oc-markdown-test markdown/nested-backtick-fence.md`.)

## Expected vs actual

**Expected (CommonMark-style):** One fenced code block whose body includes literal triple-backtick lines and ends with a closing line of four backticks.

**Actual:** Mixed paragraphs, inline code, and multiple code-block regions; inner triple-backtick lines close a **three**-backtick fence. Baseline trace: [`tests/markdown/nested-backtick-fence-expected-trace.txt`](../../tests/markdown/nested-backtick-fence-expected-trace.txt) (current parser output).

## Code analysis (why it breaks, and what must change)

### 1. Marker map only registers three backticks / three tildes

Fenced blocks are keyed only as three backticks and three tildes, not longer runs.

```104:110:libocmarkdown/BlockMap.vala
			// Fenced Code: ``` or ~~~ with optional language; indented case handled by skipping leading spaces before eat
			mp["`"] = FormatType.INVALID;
			mp["``"] = FormatType.INVALID;
			mp["```"] = FormatType.FENCED_CODE_QUOTE;
			mp["~"] = FormatType.INVALID;
			mp["~~"] = FormatType.INVALID;
			mp["~~~"] = FormatType.FENCED_CODE_TILD;
```

Adding **only** `mp["````"]` (and optionally `~~~~` for tildes) would let [`MarkerMap.eat()`](../../libocmarkdown/MarkerMap.vala) prefer a longer match when present (same idea as `*` → `**` → `***` — see the loop at lines 121–128). That does **not** cover **five or more** backticks: once the sequence is no longer in the map, `eat()` returns the previous `max_match_length` (see early return when `matched_type` is already `FENCED_CODE_QUOTE` at lines 139–142), so a line of five ticks would still open a **four**-tick fence if the map only adds one extra key (e.g. four ticks) and not five or more. Full CommonMark behavior needs a **run-length scan** (3+ ticks) or unbounded map keys (impractical).

**Proposed change (minimal — four ticks only):** extend the static map next to the existing fence keys:

```vala
			mp["````"] = FormatType.FENCED_CODE_QUOTE;
			mp["~~~~"] = FormatType.FENCED_CODE_TILD;
```

**Proposed change (CommonMark — arbitrary length ≥ 3):** stop relying on the map for the run length; before or instead of `eat()` for this line, scan from `chunk_pos + space_skip` while the char is `` ` `` or `~`, count ≥ 3, then set `matched_block` / `byte_length` from that scan (and keep `eat()` for other blocks unchanged). Sketch:

```vala
// After computing space_skip and stripped line start, if line starts with a run of ` or ~:
//   int run = count_fence_run(chunk, fence_start_pos, out char fence_char);
//   if (run >= 3) { matched_block = ...; byte_length = space_skip + run * fence_char_utf8_len; ... }
```

### 2. `fence_open` hard-codes width `3` after indent

Even when `eat()` matches the opening fence, `fence_open` is built with **`space_skip + 3`**, not the actual matched span. Closing-fence detection compares the full `fence_open` string in [`peekFencedEnd()`](../../libocmarkdown/BlockMap.vala) (see below), so this must equal **spaces + full backtick run**.

```232:235:libocmarkdown/BlockMap.vala
			// Fenced code: need newline and optional language; store whole match for matching closing fence
			if (matched_block == FormatType.FENCED_CODE_QUOTE 
				|| matched_block == FormatType.FENCED_CODE_TILD) {
				this.fence_open = chunk.substring(chunk_pos, space_skip + 3);
```

**Issue:** `byte_length` after the match (line 203: `byte_length = space_skip + byte_length`) already reflects the matched fence length from `eat()`; `fence_open` should align with that (e.g. substring from `chunk_pos` through the end of the backtick run), not assume three characters.

**Proposed change:** set `fence_open` from the same span `fence_end_pos` uses (here `byte_length` is still “from `chunk_pos` through end of fence” before line 246 overwrites it):

```vala
				this.fence_open = chunk.substring(chunk_pos, chunk_pos + byte_length);
```

(Equivalent: `var fence_end_pos = chunk_pos + byte_length;` first, then `this.fence_open = chunk.substring(chunk_pos, fence_end_pos);` — same substring.)

### 3. `fence_indent` uses `fence_open.length > 3` (wrong for 4 ticks, no spaces)

Indented fences inside lists use a longer `fence_open` (e.g. `"   ```"`), so the code infers list indent from length:

```404:408:libocmarkdown/BlockMap.vala
				case FormatType.FENCED_CODE_QUOTE:
				case FormatType.FENCED_CODE_TILD:
					this.parser.current_block = matched_block;
					var fence_indent = this.fence_open.length > 3 ? "   " : "";
					this.parser.do_block(true, matched_block, block_lang, fence_indent);
```

**Issue:** A plain opening fence of **four backticks** at column 0 also yields **length > 3**, so it would incorrectly get `fence_indent = "   "`. Any fix that lengthens `fence_open` must **not** rely on length alone; use **leading space** / `space_skip` (or “starts with three spaces”) to match the existing indented-fence behavior.

**Proposed change:** tie list indent to **`space_skip`**, which the fenced-line rules already constrain (lines 223–229: only 0 or 3 spaces before the fence):

```vala
					var fence_indent = (space_skip == 3) ? "   " : "";
```

If `peek()` / `handle_block_result` do not have `space_skip` in scope at this `switch`, **thread it through** the same way `block_lang` is passed, or set `fence_indent` from `fence_open.has_prefix("   ")` (three spaces only), not from `fence_open.length`.

### 4. Closing fence: `peekFencedEnd()` is consistent if `fence_open` is fixed

Closing logic already compares the **entire** `fence_open` string and consumes through the newline when the rest of the line is optional whitespace:

```487:531:libocmarkdown/BlockMap.vala
		public int peekFencedEnd(
			string chunk,
			ref int chunk_pos,
			FormatType fence_type,
			bool is_end_of_chunks)
		{
			...
			var at_marker = chunk.substring(chunk_pos, this.fence_open.length);
			if (at_marker != this.fence_open) {
				if (this.fence_open.length > 3 && at_marker.has_prefix("   ")) {
					chunk_pos += 3;
				}
				return 0;
			}
			...
			if (newline_pos != -1) {
				var between = chunk.substring(pos, newline_pos - pos);
				if (between.strip().length == 0) {
```

The special case at lines 506–508 (`fence_open.length > 3` and `"   "`) is tied to the same “indented fence” story; if `fence_open` can be a four-backtick run **without** leading spaces, those heuristics may need revisiting together with §3.

**Proposed change:** stop using `fence_open.length > 3` as a proxy for “list-indented fence”. Prefer matching the **same** three-space prefix the opening fence used, e.g. only skip three spaces when the **closing** line is comparing against a fence that was opened with list indent:

```vala
			if (at_marker != this.fence_open) {
				if (this.fence_open.has_prefix("   ") && at_marker.has_prefix("   ")) {
					chunk_pos += 3;
				}
				return 0;
			}
```

(If that is too loose, store a **bool** or **int** `fence_list_indent` on `BlockMap` when opening, set in the same place as §3, and use it here instead of `has_prefix`.)

[`Parser.vala`](../../libocmarkdown/Parser.vala) calls `peekFencedEnd` at line 282; comment at 283 notes sync when `fence_open` is longer than three characters:

```280:286:libocmarkdown/Parser.vala
					// At line start - check for closing fence
					var peek_fence_pos = chunk_pos;
					var fence_result = this.blockmap.peekFencedEnd(chunk, ref chunk_pos, this.current_block, is_end_of_chunks);
					// peekFencedEnd may advance chunk_pos past list-indent (fence_open longer than ```); keep TEXT slice in sync
					if (chunk_pos != peek_fence_pos) {
						text_start_pos = chunk_pos;
					}
```

No change strictly required in `Parser.vala` if `fence_open` is correct; optionally update the comment at 283 to say “longer than opening ```” instead of assuming three.

### 5. Document round-trip always emits three backticks

The document serializer does not preserve N-backtick fence length; it always uses three-backtick / three-tilde fences:

```161:178:libocmarkdown/document/Block.vala
				case FormatType.FENCED_CODE_QUOTE:
				case FormatType.FENCED_CODE_TILD:
					var fence = this.kind == FormatType.FENCED_CODE_QUOTE ? "```" : "~~~";
					var code = this.code_text;
					if (code.has_suffix("\n")) {
						code = code.substring(0, code.length - 1);
					}
					var indent = this.fence_indent;
					if (indent != "") {
						var ret = indent + fence + (this.lang != "" ? this.lang : "") + "\n";
						foreach (var line in code.split("\n")) {
							ret += indent + line + "\n";
						}
						ret += indent + fence;
						return ret;
					}
					return fence + (this.lang != "" ? this.lang : "") +
						"\n" + code + "\n" + fence;
```

**Impact:** Parsing / GTK rendering can be fixed without this, but **md → JSON → md** may collapse a four-tick fence to three ticks and break content that contains triple-backtick lines in the body. A full fix may store **fence length** (or opening line) on [`Block`](../../libocmarkdown/document/Block.vala) (`fence_indent` / `lang` exist; fence run length does not).

**Proposed change (superseded):** use **`this.kind.to_fence()`** in [`document/Block.vala`](../../libocmarkdown/document/Block.vala) — see **[Complete proposed fix](#complete-proposed-fix)** §1 and §5.

## Automated test

- [`tests/test-markdown-parser.sh`](../../tests/test-markdown-parser.sh) — **Test 8** (`test_nested_backtick_fence`) runs `oc-markdown-test` on [`tests/markdown/nested-backtick-fence.md`](../../tests/markdown/nested-backtick-fence.md) and compares to [`tests/markdown/nested-backtick-fence-expected-trace.txt`](../../tests/markdown/nested-backtick-fence-expected-trace.txt).

The expected file matches **today’s** output (regression baseline). **After** a correct N-backtick implementation, replace it with the trace for a **single** outer code block with inner lines as `CODE_TEXT`.

## Fix options (for approval)

| Approach | Notes |
|----------|--------|
| **Map + `fence_open` + `fence_indent` fixes** | Add longer map keys (e.g. four backticks / four tildes), set `fence_open` from the real matched length, fix `fence_indent` so it does not use `fence_open.length > 3` alone. Covers the common **four**-tick case; still wrong for **five+** ticks unless you add more keys or a scan. |
| **Run-length scan in `peek()` (or helper)** | Count consecutive `` ` `` / `~` on the fence line (≥ 3), set `fence_open` to indent + run; matches CommonMark; same for close. Preferable long-term. |
| **Document layer** | Optional: store fence run length for [`Block`](../../libocmarkdown/document/Block.vala) round-trip (§5). |

### Pragmatic scope: cap the map at five (no arbitrary-length scan)

Registering longer keys only — e.g. three through **five** backtick runs and three through **five** tilde runs — is a reasonable product choice: content with **six or more** tick runs in the wild is rare; if it appears later, extend the map again or add a scan.

**Still required alongside map extension:** fix `fence_open` to use the matched span (§2), not `space_skip + 3`, or the closing fence will not match.

### Product context (OLLMchat)

The bug shows up mainly in **our own framing** — fenced UI blocks we wrap around content that may already contain triple-backtick lines. That pattern is **uncommon in everyday Markdown** users paste from elsewhere. For implementation priority, optimizing for **column-0** outer fences (four–five ticks) matches real usage; exotic combinations are secondary.

### `fence_indent`: edge case or not?

If you only ever lengthen `fence_open` (four–five ticks) **and** leave `fence_indent = fence_open.length > 3`, a **plain** fence at column 0 (no list indent) wrongly gets `fence_indent = "   "`. That hits the usual “outer four-backtick wrapper” case — so a one-line fix (`space_skip == 3` or `fence_open.has_prefix("   ")`) is still worthwhile when you touch this code.

By contrast, **list indent plus a long fence** (three spaces before four+ backticks) is almost **never** seen in our product: we do not rely on that combo for the framed-content path above. CommonMark-correct behavior there can stay a lower priority than fixing the unindented wrapper case.

### New `FormatType`s (`FENCE_QUOTE_4`, …) vs one `FENCED_CODE_QUOTE`

**Update:** The chosen approach is the **[Complete proposed fix](#complete-proposed-fix)** section below. The analysis in this section still applies to **edit sites** and **Tier A vs B** cost.

Earlier alternative: a single `FENCED_CODE_QUOTE` / `FENCED_CODE_TILD` plus variable-length **`fence_open`** only (and stored run length on `Block` for round-trip). We are **not** taking that minimal-enum path for naming clarity.

Not every reference is equal cost: many are **bundled `case` labels** that fall through to one body — adding `case FENCED_CODE_QUOTE_4:` (etc.) next to the existing pair is mechanical, not a branching explosion. The painful spots are **predicates** and **equality chains** that must list every variant unless refactored.

#### Inventory: where `FENCED_CODE_QUOTE` / `FENCED_CODE_TILD` appear today (Vala)

Counted with repository search on implementation sources (`*.vala`, excluding docs). **38** total name references across **7** files (some lines count twice).

| File | References | Role (summary) |
|------|------------|----------------|
| [`libocmarkdown/Parser.vala`](../../libocmarkdown/Parser.vala) | 11 | enum; bundled `case` ×2; `current_block` checks ×2; `do_block`; doc comment |
| [`libocmarkdown/BlockMap.vala`](../../libocmarkdown/BlockMap.vala) | 8 | `mp[...]`; `matched_block` conditions ×2; bundled `case`; comment |
| [`libocmarkdown/document/Render.vala`](../../libocmarkdown/document/Render.vala) | 4 | bundled `on_block` `case`; **predicate** `pb.kind != …`; **`on_code` `kind = …`** |
| [`libocmarkdown/document/Block.vala`](../../libocmarkdown/document/Block.vala) | 3 | bundled `case`; body uses quote vs tilde for fence string |
| [`liboccoder/Task/ResultParser.vala`](../../liboccoder/Task/ResultParser.vala) | 6 | **three `if (kind != … && …)` predicates** |
| [`liboccoder/Task/WriteChange.vala`](../../liboccoder/Task/WriteChange.vala) | 4 | **two `if (kind != … && …)` predicates** |
| [`libocmarkdown/RenderBase.vala`](../../libocmarkdown/RenderBase.vala) | 2 | bundled `case` → `on_code_block` |

**GTK/HTML:** [`HtmlRender.vala`](../../libocmarkdown/HtmlRender.vala), [`PangoRender.vala`](../../libocmarkdown/PangoRender.vala), [`DummyRenderer.vala`](../../libocmarkdown/DummyRenderer.vala) use **`on_code` / `on_code_block`** and **`fence_char`**, not these `FormatType` names — per-length enum values **do not** add work there.

#### Tier A — Bundled `switch` cases (same body; add labels only)

These are **not** a real multiplier: each extra `FormatType` is another `case` line before the shared body (same as adding rows to a fall-through group). Examples:

- [`Parser.vala`](../../libocmarkdown/Parser.vala) — `block_starts_new_line` (`case` list including fenced kinds, ~lines 123–124).
- [`Parser.vala`](../../libocmarkdown/Parser.vala) — `do_block` / `on_node` dispatch (~963–964).
- [`BlockMap.vala`](../../libocmarkdown/BlockMap.vala) — `handle_block_result` (~404–405).
- [`RenderBase.vala`](../../libocmarkdown/RenderBase.vala) — `on_code_block` (~152–153).
- [`document/Render.vala`](../../libocmarkdown/document/Render.vala) — `on_block` (~202–203), e.g.:

```201:205:libocmarkdown/document/Render.vala
				case FormatType.FENCED_CODE_QUOTE:
				case FormatType.FENCED_CODE_TILD:
					this.on_block(is_start ? new Block(type) { lang = s1, fence_indent = s2 } : null);
```

**Rough count:** **5** such clusters (Parser counts as **2**). Adding four more enum values → **~20** extra `case` lines total if each cluster gets four new labels — tedious but **linear and obvious**.

**Exception in Tier A:** [`document/Block.vala`](../../libocmarkdown/document/Block.vala) (~161–163) bundles cases but the **body** picks `` ` `` vs `~` for serialization; per-length enums still need a **fence string** (length N), not just more `case` lines.

#### Tier B — Predicates and equality chains (where per-length enums hurt)

Without a helper such as **`is_fenced_kind(FormatType k)`**, each site must grow:

| Site | Count | Pattern |
|------|-------|---------|
| [`ResultParser.vala`](../../liboccoder/Task/ResultParser.vala) | 3 | `if (block.kind != QUOTE && != TILD) continue` |
| [`WriteChange.vala`](../../liboccoder/Task/WriteChange.vala) | 2 | same |
| [`document/Render.vala`](../../libocmarkdown/document/Render.vala) | 1 | `if (pb.kind != QUOTE && != TILD) return` |
| [`Parser.vala`](../../libocmarkdown/Parser.vala) | 2 | `current_block` is fenced (two `==` checks) |
| [`BlockMap.vala`](../../libocmarkdown/BlockMap.vala) | 2 | `matched_block` is fenced (two `==` checks) |

**Total: 10 predicate / equality sites** (four new variants each → **4** extra conjuncts or disjuncts per site, or **one** shared helper used everywhere).

**Tier B — Alternative: contiguous enum + range check**

If every fenced `FormatType` is **declared in one contiguous run** in the enum (e.g. all backtick lengths first, then all tilde lengths, with **no** other `FormatType` members inserted between the minimum and maximum fenced value), then underlying numeric order is consecutive and you can replace long `==` / `!=` chains with **two comparisons**:

```vala
if (this.current_block >= FormatType.FENCED_CODE_QUOTE /* first in fenced range */
    && this.current_block <= FormatType.FENCED_CODE_TILD_5 /* last in fenced range */) {
```

Same idea for `matched_block`, `block.kind`, etc., using the **same** first/last constants (or dedicated `FENCED_KIND_MIN` / `FENCED_KIND_MAX` aliases if you add them as extra enum members — often people use the first and last real variant as bounds).

**Requirements**

- **Declare order matters:** new variants must stay **adjacent** in [`Parser.vala`](../../libocmarkdown/Parser.vala) `enum FormatType` so nothing else sits between the smallest and largest fenced value (today `FENCED_CODE_QUOTE` / `FENCED_CODE_TILD` already sit as a pair between `INDENTED_CODE` and `BLOCKQUOTE`; expand that **block** in place rather than scattering new kinds elsewhere in the enum).
- **Negation:** e.g. `if (kind < FENCED_MIN || kind > FENCED_MAX) continue` instead of N inequality tests.

**Caveats**

- Changing enum declaration order or inserting members **shifts integer values** — risky if anything **persists** raw `FormatType` ordinals (e.g. document JSON); review before reshuffling.
- [`is_block()`](../../libocmarkdown/Parser.vala) and other **`switch (FormatType)`** lists still need **every** fenced variant in their `case` arms (or a `default` that handles the range deliberately) — range checks do not replace **Tier A** `case` lists for exhaustive switches.

This addresses **Tier B** predicate sites without a separate `is_fenced_kind()` function, **provided** the enum block is kept contiguous.

#### Tier C — Enum, map, and kind assignment

- **Enum** — [`Parser.vala`](../../libocmarkdown/Parser.vala): add **4** members.
- **Map** — [`BlockMap.init`](../../libocmarkdown/BlockMap.vala): **8** keys if four tick + four tilde lengths each map to a distinct `FormatType`.
- **`on_code`** — [`document/Render.vala`](../../libocmarkdown/document/Render.vala) ~414: `kind = fence_char == '~' ? TILD : QUOTE` becomes a mapping from **(fence_char, run length)** to one of **six** kinds unless you keep a single kind and store length on `Block`.

#### If we added four more variants — revised conclusion

- **Tier A** (~5 bundled switches): **not** the scary part; mostly duplicate `case` lines.
- **Tier B** (**10** sites): the friction — use **`is_fenced_kind`** (or equivalent), **or** keep all fenced values **contiguous** in the enum and use **min/max range checks** (see above); otherwise pay **O(variants × sites)** edits.
- **Tier C**: enum + map + `on_code` mapping still duplicate fence length in the type system; **Tier A** does not remove the need for **fence run length** on `Block` for round-trip.

Overall: **38** references split into **~12** in bundled `case` groups (plus Block body nuance), **~22** in predicates / conditions / map / enum / assignment / comments — the earlier “~6 switches × 4 labels” overstates the problem **where** the pattern is shared-body `case` fall-through (e.g. [`Render.vala`](../../libocmarkdown/document/Render.vala) 201–205).

## Complete proposed fix

Naming: **`FENCE_QUOTE_3` … `FENCE_QUOTE_5`**, **`FENCE_TILD_3` … `FENCE_TILD_5`** (contiguous enum block). Single design: **rename** existing kinds, **add** `_4`/`_5`, **contiguous enum** (min `FENCE_QUOTE_3`, max `FENCE_TILD_5`), **map** keys for three–five ticks/tildes, **`fence_open` / `fence_indent` / `peekFencedEnd`** fixes from §2–§4, **range checks** for Tier B (like `HEADING_1`…`HEADING_6`), **explicit Tier A** `case` lists, **`to_fence()`** with **string literals** (no `string.nfill`). `FormatType` is **internal** — no persisted ordinals for this path.

**Tier B predicate (repeat at each site, or wrap in a small `is_fence_kind(FormatType k)`):**

```vala
(k >= FormatType.FENCE_QUOTE_3 && k <= FormatType.FENCE_TILD_5)
```

Requires the six fenced members to be **contiguous** in the enum (nothing else between `FENCE_QUOTE_3` and `FENCE_TILD_5`).

---

### 1. [`libocmarkdown/Parser.vala`](../../libocmarkdown/Parser.vala) — `enum FormatType`

Replace `FENCED_CODE_QUOTE` / `FENCED_CODE_TILD` with a **contiguous block** (example order):

```vala
		INDENTED_CODE,
		FENCE_QUOTE_3,
		FENCE_QUOTE_4,
		FENCE_QUOTE_5,
		FENCE_TILD_3,
		FENCE_TILD_4,
		FENCE_TILD_5,
		BLOCKQUOTE,
```

Add **`to_fence()`** on the enum (literal fence lines — use real backtick/tilde runs in source, not `nfill`):

```vala
		public string to_fence() {
			switch (this) {
				case FENCE_QUOTE_3: return "```";
				case FENCE_QUOTE_4: return "````";
				case FENCE_QUOTE_5: return "`````";
				case FENCE_TILD_3: return "~~~";
				case FENCE_TILD_4: return "~~~~";
				case FENCE_TILD_5: return "~~~~~";
				default: assert_not_reached();
			}
		}
```

**Also in this file**

- **`is_block()`** — add six `case` labels for fenced kinds (same fall-through as other block cases).
- **`block_starts_new_line()`** — add six `case` labels (with existing fenced cases).
- **`do_block()`** — replace the two fenced `case`s with **six** `case`s, each `this.renderer.on_node(block_type, is_start, lang, fence_indent);` (same body).
- **`current_block` fenced handling** (~268, ~712) — use **`>= FormatType.FENCE_QUOTE_3 && <= FormatType.FENCE_TILD_5`** instead of two `==` checks.
- Comments that say `FENCED_CODE_*` → new names.

---

### 2. [`libocmarkdown/BlockMap.vala`](../../libocmarkdown/BlockMap.vala)

**`init` map** — map ` ``` ` … ````` and `~~~` … `~~~~~` to the matching `FENCE_*` enum (eight `mp[...]` lines).

**`peek()`**

- After `matched_block` is identified as fenced (use **range** `>= FENCE_QUOTE_3 && <= FENCE_TILD_5` instead of two `==` where appropriate).
- **`fence_open`:** `this.fence_open = chunk.substring(chunk_pos, chunk_pos + byte_length);` (not `space_skip + 3`).
- **`fence_indent` in `handle_block_result`:** `var fence_indent = (space_skip == 3) ? "   " : "";` and **six** `case` labels for fenced kinds.

**`peekFencedEnd()`** — replace `fence_open.length > 3` branch with **`fence_open.has_prefix("   ") && at_marker.has_prefix("   ")`** (see §4).

---

### 3. [`libocmarkdown/RenderBase.vala`](../../libocmarkdown/RenderBase.vala)

**`on_node` switch** — six `case` labels → `on_code_block(is_start, s1);` (shared body).

---

### 4. [`libocmarkdown/document/Render.vala`](../../libocmarkdown/document/Render.vala)

- **`on_node`** — six `case`s for fenced → `on_block(...)` (same as today’s two lines).
- **`CODE_TEXT` branch** (~229) — `if (pb.kind < FormatType.FENCE_QUOTE_3 || pb.kind > FormatType.FENCE_TILD_5) return;` (or the same range test negated with `&&` as appropriate).
- **`on_code`** (~412–415) — today only knows `fence_char`. If this path must emit multi-length fences, add **`fence_run_length`** to the callback **or** map **`~` → `FENCE_TILD_3`**, **`` ` `` → `FENCE_QUOTE_3`** as minimal fallback until callers pass length. **Primary** fenced path is **`on_node`** from `do_block` with full `FormatType` from the map.

---

### 5. [`libocmarkdown/document/Block.vala`](../../libocmarkdown/document/Block.vala)

**`to_md` fenced branch** — six `case` labels; body uses:

```vala
var fence = this.kind.to_fence();
```

(replaces `kind == … ? "```" : "~~~"`).

---

### 6. [`liboccoder/Task/ResultParser.vala`](../../liboccoder/Task/ResultParser.vala)

Three **`if (block.kind != … && …)`** sites → **range** negation:  
`if (block.kind < FormatType.FENCE_QUOTE_3 || block.kind > FormatType.FENCE_TILD_5) continue;` (or equivalent).

---

### 7. [`liboccoder/Task/WriteChange.vala`](../../liboccoder/Task/WriteChange.vala)

Two predicate sites — same range pattern as §6.

---

### 8. Project-wide rename

**Grep** `FENCED_CODE_QUOTE`, `FENCED_CODE_TILD` in `*.vala`, tests, and docs; update to `FENCE_*`. Any **generated** or **external** references to old names.

---

### 9. Tests

Regenerate [`tests/markdown/nested-backtick-fence-expected-trace.txt`](../../tests/markdown/nested-backtick-fence-expected-trace.txt) after fix; run [`tests/test-markdown-parser.sh`](../../tests/test-markdown-parser.sh) Test 8 and full markdown suite.

---

### 10. Optional follow-ups

- [`libocmarkdowngtk/Render.vala`](../../libocmarkdowngtk/Render.vala) / other renderers: only if they branch on old `FormatType` names.
- **Document JSON:** confirm no stored raw `FormatType` integers for blocks (stated internal-only).

---

### Supersedes

Earlier **Implementation plan** bullets and the **`string.nfill`** `to_fence` sketch — use **literals** as in §1. Tier A/B/C analysis above remains background; this section is the **action checklist**.

## Changelog

- 2026-04-08 — Initial report, fixture, Test 8, baseline trace.
- 2026-04-08 — Expanded with file/line references, `fence_open` / `fence_indent` / `eat()` / `peekFencedEnd` / document serializer analysis.
- 2026-04-08 — Added code citations, cross-links to sources and tests (paths relative to this file), fix-options table, and wording fixes so inline backticks do not break Markdown rendering.
- 2026-04-08 — After each code-analysis subsection (1–5), added **Proposed change** blocks with concrete Vala-style edits.
- 2026-04-08 — Added **Pragmatic scope**: capped map (five ticks/five tildes), `fence_indent` note, recommendation to avoid per-length `FormatType` variants.
- 2026-04-08 — **Product context:** primary use is our own wrapping / framed UI blocks; indent + long fence de-prioritized vs column-0 fences.
- 2026-04-08 — **Per-length `FormatType`:** documented grep-based inventory (**7** files, **38** name references) and rough edit impact (~6 switch clusters, 5 predicates, enum + map).
- 2026-04-08 — Split **bundled `case`** (low friction) vs **Tier B predicates** (**10** sites) vs **Tier C** enum/map/`on_code`; noted [`Render.vala`](../../libocmarkdown/document/Render.vala) 201–205 style is not the costly pattern.
- 2026-04-08 — **Tier B:** documented **contiguous enum + `>=` / `<=` range** pattern for `current_block` / `kind` checks; caveats (declaration order, persistence, `is_block` / switches).
- 2026-04-08 — **Implementation plan:** rename `FENCED_CODE_QUOTE`/`TILD` → `FENCE_QUOTE_3`/`FENCE_TILD_3`; add `_4`/`_5` variants; map cap five; Tier A explicit switches OK; Tier B ranges aligned with `HEADING_1`..`HEADING_6` style; internal enum only.
- 2026-04-08 — **Implementation plan:** `FormatType.to_fence()` for [`document/Block.vala`](../../libocmarkdown/document/Block.vala) serialization; supersedes extra `fence_run_length` on `Block` when kind encodes length.
- 2026-04-08 — Replaced overlapping **Implementation plan** / `to_fence` sections with one **[Complete proposed fix](#complete-proposed-fix)** checklist; **`to_fence()`** uses **string literals**, not `string.nfill`.
