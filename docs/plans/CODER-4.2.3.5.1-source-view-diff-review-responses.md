# 4.2.3.5.1 — ReviewBar programmable review responses

**Status:** implemented

> **Do not update `docs/plans/CODER-1.0-summary.md` for this sub-plan.**

**Parent:** [`CODER-4.2.3.5-source-view-diff-approval.md`](CODER-4.2.3.5-source-view-diff-approval.md) (Phase A)

**Pointer:** `docs/guide-to-writing-plans.md` — Checklist for plans; proposed Vala follows **`docs/coding-standards.md`**

---

## Purpose

- 🔷 Programmable **review responses** — quick feedback **to the LLM** (first samples: **Coding standards**, **Helper methods**).
- 🔷 **Does not** accept, reject, revert, or change hunk/file review state — user flags a problem; **LLM decides** what to do next.
- 🔷 Each item: **`ReviewResponse`** with **`label`**, **`tooltip`**, **`prompt`**, **`is_bulk`** (`get; set; default =`).
- 🔷 **`is_bulk == false`** → per-hunk overlay button (active hunk context); click **emits then advances** to the next pending change block (**no** decision change).
- 🔷 **`is_bulk == true`** → whole-file overlay button at the **far left** of **`review_overlay`** (**`hunk_index = -1`** on emit; **no** navigation).
- 🔷 Signal carries **what was flagged**:
  - **`review_response(ReviewResponse response, int file_index, int hunk_index)`**
  - **`hunk_index >= 0`** — per-hunk button (**`is_bulk == false`**, active hunk)
  - **`hunk_index == -1`** — bulk button (**`is_bulk == true`**, whole current file)
- 🔷 Owner supplies the list — harness only, not hard-coded in **`ReviewBar`**.
- 🔷 Two overlay zones on **`review_overlay`** (left → right):
  - **`review_bulk_response_zone`** — **`is_bulk`** buttons at the **very left**; visible whenever review map is active (**not** tied to pending/unapprove).
  - **`review_response_zone`** — **`!is_bulk`** buttons **right of Reject**; same visibility as Accept/Reject (**hidden with Unapprove**).
- 🔷 **Not** in the footer bulk dropdown menu.
- 🔷 **One entry point:** **`responses(Gee.ArrayList<ReviewResponse> items)`** — owner calls **once** after construction.
- 🔷 Constructor exposes both zones on **`review_overlay`**.
- ⏳ Implement after user approves this doc.
- ⏳ User smoke **✅** on harness with two samples.
- ℹ️ First attempt reverted — do not hook response UI into **`update_diff()`**.

---

## How it works

1. Owner constructs **`ReviewBar`**, calls **`responses(list)`** once, then **`update_diff`** as today.
2. **`responses()`** only: store list, rebuild **`review_bulk_response_zone`** (**`is_bulk`**) and **`review_response_zone`** (**`!is_bulk`**). **No** bulk-menu / **`bulk_menu_popover`** changes.
3. Per-hunk button (**`is_bulk == false`**): require valid pending **`active`** hunk, emit with **`hunk_index = active`**, then **`next()`** (same advance as accept/reject, no decision change).
4. Bulk button (**`is_bulk == true`**): emit with **`hunk_index = -1`** only — no navigation, no state change.
5. **`review_response_zone.visible`** mirrors **`accept_btn.visible`** at existing toggle sites (§5 patterns A–E).
6. **`review_bulk_response_zone.visible`** — mock-inactive off + zone has children (§5 patterns F–G); **not** hidden on unapprove / grey hunk.

---

## Named methods (approved)

- 🔷 **`ReviewResponse`** — data object in **`OLLMcoder.Diff`** (same file as **`ReviewBar`**).
- 🔷 **`next()`** — advance to next pending hunk from **`active`** (source scroll, overlay visibility, map scroll); used by accept, reject, per-hunk response.
- 🔷 **`responses(Gee.ArrayList<ReviewResponse> items)`** — sole method that touches response UI.

---

Edits are **Remove** / **Replace with** / **Add** from the tree; verify surrounding context before applying.

### 1. `liboccoder/Diff/ReviewBar.vala` — `ReviewResponse` type

**Why:** owner-configurable label / tooltip / prompt; **`is_bulk`** picks left bulk zone vs per-hunk zone.

**Where:** after **`HunkDecision`** enum, before **`HunkBand`**.

**Depends on:** none.

#### Keep

```vala
	public enum HunkDecision {
		PENDING,
		ACCEPTED,
		REJECTED
	}

```

#### Add — `ReviewResponse` class before `HunkBand`.

```vala
	/**
	 * Programmable quick-review feedback to the LLM (label, tooltip, prompt text).
	 * Does not change hunk or file review state — consumer sends prompt to the LLM.
	 */
	public class ReviewResponse : Object
	{
		public string label { get; set; default = ""; }
		public string tooltip { get; set; default = ""; }
		public string prompt { get; set; default = ""; }
		public bool is_bulk { get; set; default = false; }
	}

```

#### Keep

```vala
	public class HunkBand : Object
```

---

### 2. `liboccoder/Diff/ReviewBar.vala` — fields + signal

**Why:** zone hooks, stored list, signal with feedback context.

**Where:** **`ReviewBar`** class body.

**Depends on:** §1.

#### Keep

```vala
	public class ReviewBar : Gtk.Box
	{
		public Gtk.Box review_overlay;

		public signal void file_index_changed(int index);
		public signal void accept_all_files();
		public signal void reject_all_files();

		private OLLMcoder.SourceView source_view;
```

#### Add — public zones + signal after existing signals.

```vala
		public Gtk.Box review_bulk_response_zone;
		public Gtk.Box review_response_zone;

		public signal void review_response(ReviewResponse response, int file_index, int hunk_index);
```

#### Keep

```vala
		private Gtk.Button accept_btn;
		private Gtk.Button reject_btn;
		private Gtk.Button unapprove_btn;

		public ReviewBar(
```

#### Add — private field after `unapprove_btn` (use `get; set; default =`).

```vala
		private Gee.ArrayList<ReviewResponse> review_responses {
			get; set; default = new Gee.ArrayList<ReviewResponse>();
		}

```

---

### 3. `liboccoder/Diff/ReviewBar.vala` — constructor: overlay zones

**Why:** left bulk zone + per-hunk zone between Reject and Unapprove.

**Where:** constructor — **`review_overlay`** block before **`update_diff()`**.

**Depends on:** §2.

#### Keep

```vala
			this.review_overlay = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8) {
				halign = Gtk.Align.CENTER,
				valign = Gtk.Align.END,
				vexpand = true,
				hexpand = true,
				spacing = 8,
				css_classes = { "oc-diff-review-overlay" },
			};
```

#### Add — empty zones after `review_overlay` box, before `accept_btn`.

```vala
			this.review_bulk_response_zone = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 4) {
				visible = false,
			};
			this.review_response_zone = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 4) {
				visible = false,
			};
```

#### Keep

```vala
				this.hunks.get(this.active).decision = HunkDecision.PENDING;
				this.accept_btn.visible = true;
				this.reject_btn.visible = true;
```

#### Add — in **`unapprove_btn.clicked`**, after `reject_btn.visible = true`.

```vala
				this.review_response_zone.visible = true;
```

#### Remove — existing three append lines.

```vala
			this.review_overlay.append(this.accept_btn);
			this.review_overlay.append(this.reject_btn);
			this.review_overlay.append(this.unapprove_btn);
```

#### Replace with — bulk zone left, per-hunk zone between Reject and Unapprove.

```vala
			this.review_overlay.append(this.review_bulk_response_zone);
			this.review_overlay.append(this.accept_btn);
			this.review_overlay.append(this.reject_btn);
			this.review_overlay.append(this.review_response_zone);
			this.review_overlay.append(this.unapprove_btn);
```

#### Keep

```vala
		}

		/**
		 * Owner calls after {@link OLLMcoder.SourceView.show_diff} when the differ changes.
```

---

### 3.5. `liboccoder/Diff/ReviewBar.vala` — `next()` (user-approved)

**Why:** pending-advance + map-scroll tail duplicated in accept/reject; per-hunk response reuses it.

**Where:** private method before **`on_map_clicked()`**; refactor **`on_accept_clicked()`** / **`on_reject_clicked()`** only.

**Depends on:** §3 (**`review_response_zone`** in **`next()`**).

#### Add — before **`on_map_clicked()`**.

```vala
		private void next()
		{
			this.active = this.hunks.pending_after(this.active);
			if (this.active >= 0) {
				this.source_view.navigate_to_line(this.hunks.get(this.active).scroll_line);
			}
			var pending = this.active >= 0;
			this.accept_btn.visible = pending;
			this.reject_btn.visible = pending;
			this.review_response_zone.visible = pending;
			this.unapprove_btn.visible = false;
			if (!this.map_scroll_mode || this.active < 0) {
				this.map_area.queue_draw();
				return;
			}
			var ah = this.hunks.get(this.active);
			var vw = (double) this.map_area.get_allocated_width();
			var max_scroll = this.map_content_width - vw;
			if (max_scroll < 0) {
				max_scroll = 0;
			}
			this.map_scroll_x = ah.map_start + ah.map_width * 0.5 - vw * 0.5;
			if (this.map_scroll_x < 0) {
				this.map_scroll_x = 0;
			}
			if (this.map_scroll_x > max_scroll) {
				this.map_scroll_x = max_scroll;
			}
			this.map_scroll_left.sensitive = this.map_scroll_x > 0.5;
			this.map_scroll_right.sensitive = this.map_scroll_x < max_scroll - 0.5;
			this.map_area.queue_draw();
		}

```

#### Refactor — **`on_accept_clicked()`** / **`on_reject_clicked()`**: after setting decision, replace advance tail with **`this.next();`**.

#### Remove — tail of **`on_accept_clicked()`** (after **`HunkDecision.ACCEPTED`** assignment).

```vala
			this.active = this.hunks.pending_after(decided);
			if (this.active >= 0) {
				this.source_view.navigate_to_line(this.hunks.get(this.active).scroll_line);
			}
			var pending = this.active >= 0;
			this.accept_btn.visible = pending;
			this.reject_btn.visible = pending;
			this.unapprove_btn.visible = false;
			if (this.map_scroll_mode && this.active >= 0) {
				var ah = this.hunks.get(this.active);
				var vw = (double) this.map_area.get_allocated_width();
				var max_scroll = this.map_content_width - vw;
				if (max_scroll < 0) {
					max_scroll = 0;
				}
				this.map_scroll_x = ah.map_start + ah.map_width * 0.5 - vw * 0.5;
				if (this.map_scroll_x < 0) {
					this.map_scroll_x = 0;
				}
				if (this.map_scroll_x > max_scroll) {
					this.map_scroll_x = max_scroll;
				}
				this.map_scroll_left.sensitive = this.map_scroll_x > 0.5;
				this.map_scroll_right.sensitive = this.map_scroll_x < max_scroll - 0.5;
			}
			this.map_area.queue_draw();
```

#### Replace with

```vala
			this.next();
```

#### Remove — same tail from **`on_reject_clicked()`** (after **`HunkDecision.REJECTED`** assignment); **Replace with** **`this.next();`**.

---

### 4. `liboccoder/Diff/ReviewBar.vala` — `responses()` method

**Why:** sole entry point for **review-response UI only** — not accept/reject chrome.

**Where:** after constructor `}`, before **`update_diff()`** docblock.

**Depends on:** §1–§3.5.

**Does not:** change **`HunkDecision`**, call accept/reject handlers, or use closure-capture index temps (**`pick`**, **`ri`**) — attach **`ReviewResponse`** on each widget/action via **`set_data`** / **`get_data`** (same pattern as **`FileDropdown.vala`**).

#### Keep

```vala
			this.review_overlay.append(this.unapprove_btn);
		}

```

#### Add — new method before `update_diff()`.

```vala
		/**
		 * Programmable review-response buttons (left bulk zone + per-hunk zone).
		 * Emits {@link review_response} only — does not accept/reject/revert.
		 *
		 * @param items quick-review actions supplied by the owner
		 */
		public void responses(Gee.ArrayList<ReviewResponse> items)
		{
			this.review_responses.clear();
			for (var ri = 0; ri < items.size; ri++) {
				this.review_responses.add(items.get(ri));
			}
			var child = this.review_bulk_response_zone.get_first_child();
			while (child != null) {
				var next = child.get_next_sibling();
				this.review_bulk_response_zone.remove(child);
				child = next;
			}
			child = this.review_response_zone.get_first_child();
			while (child != null) {
				var next = child.get_next_sibling();
				this.review_response_zone.remove(child);
				child = next;
			}
			for (var ri = 0; ri < this.review_responses.size; ri++) {
				if (this.review_responses.get(ri).is_bulk) {
					var bulk_btn = new Gtk.Button.with_label(this.review_responses.get(ri).label) {
						tooltip_text = this.review_responses.get(ri).tooltip,
					};
					bulk_btn.set_data<ReviewResponse>("review-response", this.review_responses.get(ri));
					bulk_btn.clicked.connect(() => {
						this.review_response(bulk_btn.get_data<ReviewResponse>("review-response"), this.file_index, -1);
					});
					this.review_bulk_response_zone.append(bulk_btn);
					continue;
				}
				var btn = new Gtk.Button.with_label(this.review_responses.get(ri).label) {
					tooltip_text = this.review_responses.get(ri).tooltip,
				};
				btn.set_data<ReviewResponse>("review-response", this.review_responses.get(ri));
				btn.clicked.connect(() => {
					if (this.active < 0 || this.active >= this.hunks.size) {
						return;
					}
					if (this.hunks.get(this.active).decision != HunkDecision.PENDING) {
						return;
					}
					this.review_response(btn.get_data<ReviewResponse>("review-response"), this.file_index, this.active);
					this.next();
				});
				this.review_response_zone.append(btn);
			}
		}

```

#### Keep

```vala
		/**
		 * Owner calls after {@link OLLMcoder.SourceView.show_diff} when the differ changes.
```

---

### 5. `liboccoder/Diff/ReviewBar.vala` — zone visibility (one-line inserts)

**Why:** per-hunk zone shares Accept/Reject visibility; bulk zone stays up during review.

**Where:** grep **`reject_btn.visible`** for patterns A–E; **`update_diff()`** for F–G.

**Depends on:** §3.

#### Per-hunk zone — patterns A–E (same as before)

**Pattern A** — literal `true` (2×: **`map_scroll_left`**, **`map_scroll_right`** pending branch)

#### Remove

```vala
						this.reject_btn.visible = true;
						this.unapprove_btn.visible = false;
```

#### Replace with

```vala
						this.reject_btn.visible = true;
						this.review_response_zone.visible = true;
						this.unapprove_btn.visible = false;
```

#### Pattern B — literal `false` then **`unapprove_btn.visible = true`** (2×: scroll prev/next default branch)

#### Remove

```vala
						this.reject_btn.visible = false;
						this.unapprove_btn.visible = true;
```

#### Replace with

```vala
						this.reject_btn.visible = false;
						this.review_response_zone.visible = false;
						this.unapprove_btn.visible = true;
```

#### Pattern C — literal `false` then **`unapprove_btn.visible = false`** (5×: bulk accept/reject file, accept/reject all-files, **`update_diff`** mock-inactive)

#### Remove

```vala
				this.reject_btn.visible = false;
				this.unapprove_btn.visible = false;
```

#### Replace with

```vala
				this.reject_btn.visible = false;
				this.review_response_zone.visible = false;
				this.unapprove_btn.visible = false;
```

#### Pattern D — `pending` variable (6×: bulk reset, pending-label click, **`update_diff`** pending tail, **`on_map_clicked`** pending, **`on_accept_clicked`**, **`on_reject_clicked`**)

#### Remove

```vala
				this.reject_btn.visible = pending;
				this.unapprove_btn.visible = false;
```

#### Replace with

```vala
				this.reject_btn.visible = pending;
				this.review_response_zone.visible = pending;
				this.unapprove_btn.visible = false;
```

#### Pattern E — **`on_map_clicked()`** default branch only (1×; tabs differ from pattern B)

#### Remove

```vala
					this.reject_btn.visible = false;
					this.unapprove_btn.visible = true;
```

#### Replace with

```vala
					this.reject_btn.visible = false;
					this.review_response_zone.visible = false;
					this.unapprove_btn.visible = true;
```

#### Bulk zone — pattern F — **`update_diff()`** mock-inactive (1×)

#### Remove

```vala
				this.accept_btn.visible = false;
				this.reject_btn.visible = false;
				this.unapprove_btn.visible = false;
				return;
```

#### Replace with

```vala
				this.accept_btn.visible = false;
				this.reject_btn.visible = false;
				this.review_bulk_response_zone.visible = false;
				this.unapprove_btn.visible = false;
				return;
```

#### Bulk zone — pattern G — **`update_diff()`** pending tail (1×; apply **after** pattern D on same block)

#### Remove

```vala
			this.reject_btn.visible = pending;
			this.review_response_zone.visible = pending;
			this.unapprove_btn.visible = false;
```

#### Replace with

```vala
			this.reject_btn.visible = pending;
			this.review_bulk_response_zone.visible =
				this.review_bulk_response_zone.get_first_child() != null;
			this.review_response_zone.visible = pending;
			this.unapprove_btn.visible = false;
```

---

### 6. `examples/oc-test-source-diff.vala` — harness wiring

**Why:** Phase A mock; samples and signal handler in harness only.

**Where:** **`TestDiffWindow` constructor**.

**Depends on:** §4.

#### Keep

```vala
		this.review_bar = new OLLMcoder.Diff.ReviewBar(
			this.source_view, pair_count, opt_mock_inactive, 0, this.pair_titles);
```

#### Add — call **`responses()`** before **`file_index_changed`** connect.

```vala
		var review_responses = new Gee.ArrayList<OLLMcoder.Diff.ReviewResponse>();
		review_responses.add(new OLLMcoder.Diff.ReviewResponse() {
			label = "Coding standards",
			prompt = "This section of code does not follow coding standards. "
				+ "Please refer to docs/coding-standards-router.md and the mapped "
				+ "sections in docs/coding-standards.md.",
			tooltip = "Report coding standards issue for this hunk",
			is_bulk = false,
		});
		review_responses.add(new OLLMcoder.Diff.ReviewResponse() {
			label = "Helper methods (whole file)",
			prompt = "This file contains helper methods that were not requested. "
				+ "Do not add helper methods unless the user or plan names them.",
			tooltip = "Report unauthorized helper methods for the whole file",
			is_bulk = true,
		});
		this.review_bar.responses(review_responses);
```

#### Keep

```vala
		this.review_bar.update_diff(differ, 0);
		var loop = new GLib.MainLoop();
```

#### Add — signal mock after first **`update_diff`**.

```vala
		this.review_bar.review_response.connect((response, file_index, hunk_index) => {
			GLib.print("Review response [%s] file=%d hunk=%d:\n%s\n\n".printf(
				response.label, file_index, hunk_index, response.prompt));
		});
```

#### Keep

```vala
		this.window.close_request.connect(() => {
```

---

## Test (Phase A)

```bash
meson compile -C build occoder examples/oc-test-source-diff
./build/examples/oc-test-source-diff \
  tests/source-diff/review-smoke-baseline.txt \
  tests/source-diff/review-smoke-current.txt
```

- Pending hunk: **Helper methods (whole file)** on the **left**; **Accept**, **Reject**, **Coding standards** visible.
- Click **Coding standards** → terminal prints **`hunk=N`**; view **jumps to next pending hunk**; bands unchanged.
- Click **Helper methods (whole file)** → terminal prints **`hunk=-1`**; no navigation; bands unchanged.
- Click grey hunk → **Unapprove** only; **Helper methods** still visible; **Coding standards** hidden.

---

## LLM notes

- 🚫 Hook response **rebuild** into **`update_diff()`** — §5 F–G visibility one-liners only.
- 🚫 **`response_ui_dirty`**, **`sync_*`**, **`ensure_*`**, **`pending_review_box`**.
- 🚫 Sample **`ReviewResponse`** objects inside **`ReviewBar`**.
- 🚫 Put **`is_bulk`** items in **`bulk_menu_popover`** — left **`review_bulk_response_zone`** only.
- 🚫 **`bulk_response_actions`**, **`bulk-resp`** action group, or menu append in **`responses()`**.
- 🚫 Reassign action groups with **`new …`** — N/A (no bulk actions).
- 🚫 Closure-capture index temps (**`pick`**, **`ri`**) to reach **`ReviewResponse`** — use **`set_data<ReviewResponse>("review-response", …)`** on the button, **`get_data`** in the handler (ℹ️ **`FileDropdown.vala`**).
- 🚫 Trivial alias locals (**`var resp = …get(ri)`**) — inline **`this.review_responses.get(ri)`** at build sites; handler reads **`get_data`** only.
- 🚫 Change review state from **`responses()`** — no accept/reject/revert; per-hunk click calls **`next()`** only.
- 🚫 Call **`responses()`** more than once.
- ✅ **`next()`** — user-approved; use for pending advance (accept, reject, per-hunk response).
- 🚫 Gratuitous one-arg-per-line wraps on short calls — match **`ReviewBar.vala`** / **`line-length-breaking`** (group args; **`set_data`**, **`review_response`**, **`navigate_to_line`** on one line when they fit).
