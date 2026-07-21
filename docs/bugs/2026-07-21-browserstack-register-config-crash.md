# 2026-07-21 — BrowserStack crash on app start (register_config)

**Status:** ✔️ agent fixed — await user ✅

## Problem

- **🔷** App segfaults on startup when registering the `browser` tool config.
- **🔷** Expected: config registration does not construct WebKit/GTK chrome.
- **🔷** Actual: crash inside libgtk while constructing `BrowserStack`.

## Evidence

- **ℹ️** gdb bt:
  - `BaseTool.register_config` → `Object.new(OLLMwebkit.Tool)`
  - `Tool` instance_init → property default `new BrowserStack()` (`Tool.vala:62`)
  - `BrowserStack` construct → crash in GTK `g_type_create_instance` / widget path
  - Called from `Registry.init_config` during `OllmchatApplication` construct

## Root cause

- **✔️** First crash: `stack` used `default = new BrowserStack()` → GObject `instance_init` during `register_config`’s `Object.new`.
- **✔️** Second crash (after removing default): `Tool()` still did `new BrowserStack()` → same GTK fault from `Registry.setup_config_defaults` → `(new OLLMwebkit.Tool()).setup_tool_config_default(...)` during `Application` construct, still before a display/window.
- **✔️** Any path that constructs `Tool` for config-only work must **not** touch WebKit/GTK.

## Proposed fix

- **🔷** Lazy-create `BrowserStack` on first `stack` / `view_widget` access (`has_stack` flag).
- **🔷** Wire CF → `show_view` when the stack is created (get or set).
- **🔷** `Tool()` stays empty aside from `base()` — config defaults can `new Tool()` safely.
- **🚫** Do not add null guards around stack; real tool use always goes through the getter.

### `libocwebkit/Tool.vala` — lazy stack (supersedes ctor create)

#### Remove

```vala
	public OLLMwebkit.BrowserStack stack { get; set; }

	public string icon_name { get { return "web-browser-symbolic"; } }

	public string tooltip_text { get { return "Browser"; } }

	public GLib.Object view_widget { get { return this.stack; } }

	public Tool()
	{
		base();
		this.stack = new OLLMwebkit.BrowserStack();
		this.stack.cloudflare_blocked.connect((browser) => {
			this.show_view();
		});
	}
```

#### Replace with

```vala
	/**
	 * Browser stack for this tool instance (one per chat when wired).
	 *
	 * Created on first access — not in the constructor — so
	 * {@code register_config} / {@code setup_config_defaults} can
	 * instantiate the tool without building WebKit/GTK chrome.
	 */
	private OLLMwebkit.BrowserStack owned_stack;
	private bool has_stack = false;

	public OLLMwebkit.BrowserStack stack {
		get {
			if (this.has_stack) {
				return this.owned_stack;
			}
			this.owned_stack = new OLLMwebkit.BrowserStack();
			this.owned_stack.cloudflare_blocked.connect((browser) => {
				this.show_view();
			});
			this.has_stack = true;
			return this.owned_stack;
		}
		set {
			this.owned_stack = value;
			this.has_stack = true;
			this.owned_stack.cloudflare_blocked.connect((browser) => {
				this.show_view();
			});
		}
	}

	public string icon_name { get { return "web-browser-symbolic"; } }

	public string tooltip_text { get { return "Browser"; } }

	public GLib.Object view_widget { get { return this.stack; } }

	public Tool()
	{
		base();
	}
```

## Attempts / changelog

- **✔️** Removed property `default = new BrowserStack()` — still crashed in `Tool()` via `setup_config_defaults`.
- **✔️** Lazy `stack` getter with `has_stack` — applied; app starts.
- **✔️** Tool toggles never appeared: wire loop ran after `fill_tools` while `chat_widget` was still null (`get_chat_bar: assertion 'self != NULL' failed`). Moved wire to after `setup_chat_widget` + `window_pane` create.

## Next

- **⏳** **🔷** Confirm globe toggle appears left of the model dropdown and opens the browser pane.
