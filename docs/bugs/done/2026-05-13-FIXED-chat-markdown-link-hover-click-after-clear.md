# Bug: Chat markdown link hover/click after `RenderBox` swap

**Status:** FIXED (2026-05-11)

ℹ️ **`docs/guide-to-writing-plans.md`** · **`docs/bug-fix-process.md`** · **`.cursor/rules/CODING_STANDARDS.md`** (full *Checklist for all plans* before implement).

## Design (signals)

- **`MarkdownGtk.RenderBox`**: parameterless ctor; **`Gtk.GestureClick`** + **`EventControllerMotion`** on **`this`**; callbacks **`emit`** **`on_link_click_released`**, **`on_link_motion`**, **`on_link_leave`**. No reference to **`Render`**.
- **`MarkdownGtk.Render`**: **`Render(MarkdownGtk.RenderBox box)`** — after **`this.box = box`**, three **`this.box.on_link_* .connect(this.on_link_* )`**. **`public void disconnect_box()`** — three **`this.box.on_link_* .disconnect(this.on_link_* )`** on the current **`box`** (no **`construct`** / **`notify`**).
- **`ChatView.clear()`**: after **`append(this.render_box)`**, **`this.renderer.disconnect_box()`**, then **`this.renderer.box = this.render_box`**, then the same three **`connect`** lines on **`this.renderer.box`**.
- **`RenderSourceView`**, **`oc-test-gtkmd`**: **unchanged** vs tree (nested **`Render`** is created once with its **`rendered_box`**).

## Implications

| Where | Effect |
| ----- | ------ |
| **`RenderBox.vala`** | **`signal`**s + gesture **`emit`** in ctor. |
| **`Render.vala`** | Ctor: **`connect`** only (no **`add_controller`**). **`public void disconnect_box()`** with three **`disconnect`** calls. **`on_link_*`** **`public`** so **`ChatView`** can **`connect`** after **`clear()`**. |
| **`ChatView.vala`** | **`clear()`**: **`disconnect_box()`**, then **`renderer.box = …`**, then three **`connect`** lines. |
| **`RenderSourceView.vala`**, **`examples/oc-test-gtkmd.vala`**, **`Table.vala`** | **No diff** vs tree. |

## Acceptance criteria

- After **`clear()`**, link hover + click work.
- **`meson compile -C build`**.

## Concrete code proposals

Verbatim **Remove** / **Replace with** / **Keep** / **Add** from tree unless noted.

### 1. `libocmarkdowngtk/RenderBox.vala`

**Part 1 — Class doc + signals**

#### Keep

```vala
namespace MarkdownGtk
{
```

#### Remove

```vala
	/**
	 * Vertical Gtk.Box used as the live markdown target for {@link Render}.
	 *
	 * Each logical row is one content widget listed in {@link by_id}. The owning
	 * {@link Render} passes this box at construction; each row uses {@link appender}
	 * on this class so indices stay aligned without relying on Gtk.Box.append dispatch.
	 */
	public class RenderBox : Gtk.Box
	{
```

#### Replace with

Replace with — Doc + three **`signal`**s.

```vala
	/**
	 * Vertical Gtk.Box used as the live markdown row target for {@link Render}.
	 *
	 * Link gestures run here; forward pointer/motion/leave via signals so each
	 * new box instance works without holding a reference to {@link Render}.
	 *
	 * @see Render
	 */
	public class RenderBox : Gtk.Box
	{
		public signal void on_link_click_released(double x, double y);
		public signal void on_link_motion(double x, double y);
		public signal void on_link_leave();
```

**Part 2 — `by_id` / `first_id` / `last_id`**

#### Keep

```vala
		/** Append order for scroll / id queries; updated only from {@link appender}. */
		public Gee.ArrayList<Gtk.Widget> by_id { get; private set; default = new Gee.ArrayList<Gtk.Widget>(); }

		/** Start index of the current span; set by {@link mark}. */
		public int first_id { get; private set; default = 0; }

		/** Last assigned id, or 0 when {@link by_id} is empty. */
		public int last_id {
			get {
				return this.by_id.size > 0 ? this.by_id.size - 1 : 0;
			}
		}

```

**Part 3 — Constructor**

#### Remove

```vala
		public RenderBox()
		{
			Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0);
		}

```

#### Replace with

Replace with — Controllers **`emit`** the three signals.

```vala
		public RenderBox()
		{
			Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0);
			var click_gesture = new Gtk.GestureClick();
			click_gesture.released.connect((n_press, x, y) => {
				this.on_link_click_released(x, y);
			});
			this.add_controller(click_gesture);
			var motion = new Gtk.EventControllerMotion();
			motion.motion.connect((x, y) => {
				this.on_link_motion(x, y);
			});
			motion.leave.connect(() => {
				this.on_link_leave();
			});
			this.add_controller(motion);
		}

```

#### Keep

```vala
		/**
		 * Append one content row: child, registered in {@link by_id}.
		 *
		 * @param child widget to append as the indexed row body
		 */
		public void appender(Gtk.Widget child)
```

### 2. `libocmarkdowngtk/Render.vala`

**Part 1 — Ctor: replace controllers with signal `connect`**

#### Remove

```vala
		/**
		 * Creates a renderer that appends content to the given box.
		 *
		 * @param box markdown row target; {@link MarkdownGtk.RenderBox.appender} is used for each row
		 */
		public Render(MarkdownGtk.RenderBox box)
		{
			base();
			this.box = box;
			var click_gesture = new Gtk.GestureClick();
			click_gesture.released.connect((n_press, x, y) => {
				this.on_link_click_released(x, y);
			});
			this.box.add_controller(click_gesture);
			var motion = new Gtk.EventControllerMotion();
			motion.motion.connect((x, y) => {
				this.on_link_motion(x, y);
			});
			motion.leave.connect(() => {
				this.on_link_leave();
			});
			this.box.add_controller(motion);
		}

```

#### Replace with

Replace with — **`this.box = box`** then three **`this.box.on_link_* .connect(this.on_link_* )`**.

```vala
		/**
		 * Creates a renderer that appends content to the given box.
		 *
		 * @param box markdown row target; {@link MarkdownGtk.RenderBox.appender} is used for each row
		 */
		public Render(MarkdownGtk.RenderBox box)
		{
			base();
			this.box = box;
			this.box.on_link_click_released.connect(this.on_link_click_released);
			this.box.on_link_motion.connect(this.on_link_motion);
			this.box.on_link_leave.connect(this.on_link_leave);
		}

```

**Part 1b — `disconnect_box()` (after ctor, before `on_link_click_released`)**

#### Keep

```vala
			this.box.on_link_leave.connect(this.on_link_leave);
		}

```

#### Add

Add — **`public`** so **`ChatView`** can call before swapping **`renderer.box`**.

```vala
		public void disconnect_box()
		{
			this.box.on_link_click_released.disconnect(this.on_link_click_released);
			this.box.on_link_motion.disconnect(this.on_link_motion);
			this.box.on_link_leave.disconnect(this.on_link_leave);
		}

```

**Part 2 — `on_link_*` visibility (`Render.vala` only)**

Flip **`private`** → **`public`** on the declaration line of **`on_link_click_released`**, **`on_link_motion`**, **`on_link_leave`** (tree lines **119**, **131**, **170** at time of plan; re-verify after **Part 1**).

### 3. `libollmchatgtk/ChatView.vala` — `clear()`

#### Keep

```vala
			this.text_view_box.append(this.render_box);

```

#### Remove

```vala
			this.renderer.box = this.render_box;

```

#### Add

Add — Drop link **`signal`** handlers on the old **`box`**, assign the new **`render_box`**, attach to the new box.

```vala
			this.renderer.disconnect_box();
			this.renderer.box = this.render_box;
			this.renderer.box.on_link_click_released.connect(this.renderer.on_link_click_released);
			this.renderer.box.on_link_motion.connect(this.renderer.on_link_motion);
			this.renderer.box.on_link_leave.connect(this.renderer.on_link_leave);

```

#### Keep

```vala
			// Reset state (indicator already cleared above)
```

### 4. Verification

#### Commands

```bash
cd /home/alan/gitlive/OLLMchat
meson compile -C build
```

## Changelog

- **2026-05-13** — Opened.
- **2026-05-11** — **Signals** on **`RenderBox`**; **`Render`** ctor **`connect`** only (no **`construct`** / **`notify["box"]`**).
- **2026-05-11** — **`disconnect_box()`** on **`Render`**; **`ChatView.clear()`** calls it before **`renderer.box = …`**.
- **2026-05-11** — Applied to tree; **`meson compile -C build`** OK.
