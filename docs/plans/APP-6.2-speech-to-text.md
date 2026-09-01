# 6.2 Composer microphone (IBus Sherpa ONNX)

> **Do not update `docs/plans/APP-1.0-summary.md` for this plan until it is done and archived.**

**Status:** ⏳ proposed

**Pointer:** `docs/guide-to-writing-plans.md` — **Checklist for plans**; proposed Vala follows `docs/coding-standards.md`

**Related:**
- [`APP-1.30.1-DONE-chatinput-preedit-speech.md`](done/APP-1.30.1-DONE-chatinput-preedit-speech.md) — `✅` composer already grows on IME / Sherpa ONNX preedit
- [`APP-1.30-DONE-chat-input-composer.md`](done/APP-1.30-DONE-chat-input-composer.md) — compact play on the right; expanded play on `ChatBar`

**ℹ️** Product: **Sherpa ONNX**. Package/repo [`ibus-sherpa-onnx`](https://github.com/roojs/ibus-sherpa-onnx). Engine ids `sherpa-onnx` / `sherpa-onnx-*`. IBus longname `Sherpa ONNX`.

**ℹ️** Canonical host-widget start (already shipped): `ibus-sherpa-onnx` **`src/setup/RowMicText.vala`** (`57775267d529b2f87eb83fce7ec7742440932b86`). Voice-commands prefs: mic on each phrase row. Open that file; do not reinvent the sequence.

---

## Purpose

- **🔷** Speech-to-text in OLLMchat is **not** an in-app ASR stack.
- **🔷** Sherpa ONNX already does capture, decode, preedit, and commit into the focused field.
- **🔷** Add a **microphone button** on the chat composer (`ChatInput` text area).
- **🔷** Click **starts** the Sherpa ONNX listening / recording session into that `Gtk.TextView`.
- **⏳** Linux / IBus only. No mic on Windows or Android.
- **ℹ️** Committed text is normal composer buffer; send stays Ctrl+Enter / play. No new message pipeline.

---

## What this replaces

- **🔷** Drop the old 6.2 bake-off (Whisper / Vosk / PocketSphinx / cloud APIs / Speech Dispatcher).
- **🔷** Drop in-process mic capture, STT provider abstraction, and worker-process transcription.
- **ℹ️** Sherpa ONNX GTK PoC already cloned this composer: `ibus-sherpa-onnx` `src/gtk/ComposerInput.vala` (mic on the right). That PoC talks to the engine **in-process**. OLLMchat must **not** link sherpa — it only triggers the **already-running IBus engine**.

---

## How Sherpa ONNX starts listening today

- **ℹ️** Engine is idle until an explicit toggle. Selecting the IME does **not** open the mic.
- **ℹ️** Toggle: **Ctrl+Shift+Space** (pref `general/hotkey`) or the IBus panel **listening** property.
- **ℹ️** `process_key_event` / `property_activate("listening")` both **toggle**. They ignore the property checked state.
- **ℹ️** Keys only reach the engine when Sherpa ONNX is the **active IME** and a text field has **IBus focus**.
- **ℹ️** Partials are IME preedit; endpoints `commit_text`. `APP-1.30.1` already refits height on `preedit_changed`.

---

## Copy prefs `RowMicText` (do not simplify)

**ℹ️** Prefs already solved “mic button starts listen into **this** widget.” It was not a one-liner. `ibus-sherpa-onnx` `docs/plans/0.6.1-DONE-voice-commands.md`: IBus `property_activate` **did not reach this engine**. `0.6.4` records the focus mess. Working path is AT-SPI of the toggle hotkey after the target widget owns focus.

**ℹ️** File: `/home/alan/git/ibus-sherpa-onnx/src/setup/RowMicText.vala`. Hotkey parse: `src/Config.vala` `hotkey()`. Engine gate (same name check): `src/setup/Preferences.vala` `fill()` / `banner()`.

**🔷** ChatInput copies this **start** sequence (clicked → ARMING → delay → IBus checks → AT-SPI). Same constants (500 ms, LOCKMODIFIERS + SYM + UNLOCKMODIFIERS).

Start sequence in `RowMicText` (clicked, then `start_listening`, then `toggle_hotkey`):

- **ℹ️** If not `IDLE`, return (do not fire a second toggle while arming / listening).
- **ℹ️** Parse toggle via `Config.hotkey()` (`Ctrl+` → `Control+`, then `IBus.key_event_from_string` if `accelerator_parse` yields 0). Invalid → stop.
- **ℹ️** `grab_focus()` on the target field.
- **ℹ️** `GLib.Timeout.add(500, …)` — comment in tree: delay so the field owns focus before the hotkey.
- **ℹ️** Timeout: `grab_focus()` again. `IBus.Bus` connected. Global engine is `sherpa-onnx` or `sherpa-onnx-*`. Else abort.
- **ℹ️** AT-SPI: `Atspi.init` if needed. Map IBus mods → lock mask (SHIFT / CONTROL / ALT / META). `LOCKMODIFIERS` → `SYM` of `keyval` → `UNLOCKMODIFIERS`.

Prefs-only (do **not** copy):

- **ℹ️** Making the `Gtk.Entry` sensitive, clearing it, saving the phrase, 300 ms focus-leave stop. That is voice-command editing, not composer dictation.

ChatInput extras:

- **🔷** Target widget is `this.text_view`, not `this.entry`.
- **🔷** Mic `focus_on_click = false` (still `grab_focus` + 500 ms like prefs).
- **💩** Failures: `GLib.warning` (no prefs banner).

---

## UI

- **🔷** Mic sits on the **composer**, not `ChatBar`.
- **🔷** Icon `audio-input-microphone-symbolic`. Compact order: **TextView | mic | play**.
- **🔷** Expanded (play moved to footer): **mic stays** on the right of the field.
- **💩** CSS class `has-mic` on `ChatInput` when the button is packed, so expanded rounding joins TextView+mic without breaking Windows (no mic).
- **💩** Mic chrome is **white / flat** (matches the field), not the blue send button.
- **💩** Tooltip: `Start dictation`.
- **🔷** Click is **start** (same IDLE guard as `RowMicText`). Engine still stops via its own hotkey / typing / voice-command stop.
- **💩** After a successful AT-SPI send, drop ARMING (ChatInput has no focus-leave save). Extra clicks during the 500 ms window still no-op.
- **💩** No spinner, no hide-mic-while-listening (GTK PoC had those; not asked).
- **🔷** If IBus is down, or the global engine is not `sherpa-onnx` / `sherpa-onnx-*`: warn and return (same gate as prefs). Do **not** auto-switch IME.
- **💩** Confirm in review: auto-`set_global_engine` to a Sherpa ONNX id when installed but not active.

---

## Suggested order

1. **🔷** `⏳` Mic button + CSS on `ChatInput` (Linux `#if HAS_IBUS` only).
2. **🔷** `⏳` Click: same sequence as `RowMicText` (focus + 500 ms + IBus gate + AT-SPI toggle).
3. **💩** `⏳` Device check: click mic → preedit / commit in composer → play still sends.

---

## Phase 1 — Mic on `ChatInput`

Intro: edits are **Remove** / **Replace with** / **Add** from the tree;
verify surrounding context before applying.

### 1. `libollmchatgtk/meson.build` — Linux IBus + AT-SPI

**Why:** Same deps as prefs `RowMicText` (`ibus-1.0`, `atspi-2`).

**Where:** next to the existing `if host_machine.system() == 'linux'` `libsecret` / `Sudo.vala` block.

**Depends on:** none.

#### Add — inside the Linux `if`, after `dependency('libsecret-1')`

```meson
  ollmchatgtk_deps += dependency('ibus-1.0')
  ollmchatgtk_deps += dependency('atspi-2')
```

#### Add — `vala_args` for **both** `library('ollmchatgtk', …)` blocks (Linux host only)

**Where:** the non-Android `library()` `vala_args` (and the Android block only if that build is Linux — it is not; skip Android).

Use Meson’s usual pattern: append `'-D', 'HAS_IBUS'` to `vala_args` when `host_machine.system() == 'linux'` (same flag on the non-Android library). Implementer: do **not** add `HAS_IBUS` on Android/Windows.

---

### 2. `libollmchatgtk/ChatInput.vala` — fields `mic_button` / `mic_arming`

**Why:** Composer owns the mic. `mic_arming` is the prefs `Mic.ARMING` guard (ignore clicks during the 500 ms wait).

**Where:** class fields, after `private Gtk.Button inline_play;`.

**Depends on:** none.

#### Add — after `private Gtk.Button inline_play;`

```vala
		private Gtk.Button mic_button;
		private bool mic_arming = false;
```

---

### 3. `libollmchatgtk/ChatInput.vala` — `ChatInput()`: pack mic before play

**Why:** Compact strip is TextView | mic | play. Start-listen is the `RowMicText` sequence, inlined (no new methods).

**Where:** `ChatInput()` — after `this.append(overlay);`, before `this.inline_play = …`.

**Depends on:** §1, §2.

**ℹ️** Open `/home/alan/git/ibus-sherpa-onnx/src/setup/RowMicText.vala` and `src/Config.vala` `hotkey()` while applying. Hotkey parse below is that `hotkey()` body, inlined.

#### Add — after `this.append(overlay);`

```vala
#if HAS_IBUS
			IBus.init();
			this.mic_button = new Gtk.Button.from_icon_name("audio-input-microphone-symbolic") {
				tooltip_text = "Start dictation",
				valign = Gtk.Align.FILL,
				focus_on_click = false
			};
			this.mic_button.add_css_class("chat-composer-mic");
			this.add_css_class("has-mic");
			this.mic_button.clicked.connect(() => {
				if (this.mic_arming) {
					return;
				}
				var keyval = (uint) 0;
				var mods = (IBus.ModifierType) 0;
				var accel_path = GLib.Path.build_filename(
					GLib.Environment.get_user_config_dir(),
					"ibus-sherpa-onnx", "settings.ini");
				try {
					var kf = new GLib.KeyFile();
					kf.load_from_file(accel_path, GLib.KeyFileFlags.NONE);
					var hotkey = kf.get_string("general", "hotkey");
					IBus.accelerator_parse(hotkey, out keyval, out mods);
					if (keyval == 0) {
						var normalized = hotkey.replace("Ctrl+", "Control+").replace("ctrl+", "Control+");
						var plus = normalized.last_index_of_char('+');
						if (plus >= 0) {
							normalized = normalized.substring(0, plus + 1)
								+ normalized.substring(plus + 1).down();
						}
						var kv = (uint) 0;
						var md = (uint) 0;
						if (IBus.key_event_from_string(normalized, out kv, out md)) {
							keyval = kv;
							mods = (IBus.ModifierType) md;
						}
					}
				} catch (GLib.Error err) {
				}
				if (keyval == 0) {
					GLib.warning("Set a valid Sherpa ONNX toggle hotkey first");
					return;
				}
				this.mic_arming = true;
				this.text_view.grab_focus();
				GLib.Timeout.add(500, () => {
					this.text_view.grab_focus();
					var bus = new IBus.Bus();
					if (!bus.is_connected()) {
						this.mic_arming = false;
						GLib.warning("IBus is not running");
						return false;
					}
					var eng = bus.get_global_engine();
					var eng_name = eng != null ? eng.get_name() : "";
					if (eng_name != "sherpa-onnx" && !eng_name.has_prefix("sherpa-onnx-")) {
						this.mic_arming = false;
						GLib.warning("Active IBus engine is '%s', not Sherpa ONNX", eng_name);
						return false;
					}
					if (!Atspi.is_initialized()) {
						Atspi.init();
					}
					var lock = (long) 0;
					if ((mods & IBus.ModifierType.SHIFT_MASK) != 0) {
						lock |= (1 << Atspi.ModifierType.SHIFT);
					}
					if ((mods & IBus.ModifierType.CONTROL_MASK) != 0) {
						lock |= (1 << Atspi.ModifierType.CONTROL);
					}
					if ((mods & IBus.ModifierType.MOD1_MASK) != 0) {
						lock |= (1 << Atspi.ModifierType.ALT);
					}
					if ((mods & IBus.ModifierType.SUPER_MASK) != 0
							|| (mods & IBus.ModifierType.META_MASK) != 0
							|| (mods & IBus.ModifierType.HYPER_MASK) != 0) {
						lock |= (1 << Atspi.ModifierType.META);
					}
					try {
						if (lock != 0) {
							Atspi.generate_keyboard_event(lock, null, Atspi.KeySynthType.LOCKMODIFIERS);
						}
						Atspi.generate_keyboard_event((long) keyval, null, Atspi.KeySynthType.SYM);
						if (lock != 0) {
							Atspi.generate_keyboard_event(lock, null, Atspi.KeySynthType.UNLOCKMODIFIERS);
						}
					} catch (GLib.Error err) {
						GLib.warning("Could not send the toggle hotkey: %s", err.message);
					}
					this.mic_arming = false;
					return false;
				});
			});
			this.append(this.mic_button);
#endif
```

---

### 4. `resources/style.css` — mic join + white chrome

**Why:** Compact: TextView+mic+play one strip. Expanded: TextView+mic when `has-mic`.

**Where:** after the existing `.chat-composer:not(.is-expanded) button.chat-composer-send` rule.

**Depends on:** §3.

#### Add — after `button.chat-composer-send` compact join rule

```css
.chat-composer.has-mic:not(.is-expanded) button.chat-composer-mic {
	border-radius: 0;
}

.chat-composer.has-mic.is-expanded scrolledview.chat-composer-entry {
	border-top-right-radius: 0;
	border-bottom-right-radius: 0;
}

.chat-composer.has-mic.is-expanded button.chat-composer-mic {
	border-top-left-radius: 0;
	border-bottom-left-radius: 0;
	border-top-right-radius: 6px;
	border-bottom-right-radius: 6px;
}

button.chat-composer-mic {
	background-color: white;
	color: #3d3846;
	border: none;
	box-shadow: none;
	border-radius: 6px;
}

button.chat-composer-mic:hover {
	background-color: #f6f5f4;
}
```

---

## LLM notes

- **🚫** Whisper / Vosk / cloud STT / `whisper.cpp` / PulseAudio capture module / STT provider interface.
- **🚫** Link `ibus-sherpa-onnx` / sherpa-onnx / GStreamer ASR into OLLMchat.
- **🚫** New helper methods (`start_listening`, `toggle_hotkey`, `ensure_ibus`, …). Inline in the `clicked` / `Timeout.add` lambdas (prefs has those names in `RowMicText`; do not re-extract them here).
- **🚫** New `ChatInputIbus.vala` / `SpeechExtension` class.
- **🚫** Mic on `ChatBar`.
- **🚫** Skip the 500 ms focus delay or the second `grab_focus`.
- **🚫** `IBus.InputContext.process_key_event` / panel `property_activate` as a “nicer” first path. Prefs already found `property_activate` does not reach this engine.
- **🚫** Auto-switch IME unless review promotes that 💩.
- **🚫** D-Bus Start/Stop inside Sherpa ONNX (separate repo, deferred `0.6.4`).
- **🚫** AT-SPI into foreign windows.
- **🚫** Copy phrase-entry lock / focus-leave save from `RowMicText`.
- **🚫** Spinner / hide-mic-while-listening unless review promotes those 💩.
