# Phone GTK thread heats the handset

**Status:** 🚫 CLOSED 2026-10-30. Parked. The idle-timeout change is in the tree and in the 15:50 phone install. Exec time was not remeasured. Follow-up is a new log if the handset heats again.

**Device:** SM-S9380, Android 16, wireless `adb-R5CY134DA0W`. Package `org.roojs.ollmchat.androidpoc` 0.2.0, pid 13575, GTK thread tid 13599.

## Problem

- 🔷 The handset gets hot in the hand while this app is the recent process. Expected: an idle or backgrounded chat does not hold a core, so skin temperature and battery current stay near the rest of the phone.
- 🔷 Actual, 2026-10-30 about 10:29: the GTK thread had used one core for almost the whole life of the process. Skin was already in the moderate thermal band.

## Evidence

- ✔️ 10:29 `top`: process at 100% of one core (`800%cpu` on 8 cores). GTK thread tid 13599 at 100%, then 38% on the next snapshot. Every other thread in the process was at 0. Time on that thread was `4:28` after the process had been up about five minutes.
- ✔️ `/proc/13575/task/13599/sched` while it was hot: `sum_exec_runtime` 288907 ms, `sum_sleep_runtime` 7603 ms, `sum_block_runtime` 31 ms, `iowait_count` 37, `nr_migrations` 16448. The thread was running, not blocked on disk. `wchan` was `0`.
- ✔️ Same counter a minute later: `sum_exec_runtime` 289046.877 ms, then unchanged across a two-second sample and still unchanged at 10:34:06. `top -H` then showed 26 threads, all sleeping. The spin stopped. It did not keep going once the activity was cached.
- ✔️ Activity Manager at 10:29: `visible=false`, `lastInvisibleTime` 10:29:24, `curProcState=15` (cached), `oom adj` 700, `isFrozen=false`. `hasShownUi=true`. The activity is `org.gtk.android.ToplevelActivity`.
- ✔️ Power log: `10:24:09 OFF timeout` while `org.roojs.ollmchat.androidpoc` was the top app. The hot window is the minutes after the screen turned off, until the activity was no longer visible.
- ✔️ Thermals at 10:29: skin 41.5°C, status moderate (skin steps 38 / 40 / 42°C). App processor 49.9°C. Battery 39.5°C, level 82, status discharging. `dumpsys battery` shows the cell climb from 25.7°C at 09:04 (92%) through about 30°C at 10:12, then 32–39°C from 10:18 to 10:29, with `current_avg` about −0.8 A to −1.8 A.
- ✔️ `mProcessLimit` 1026, `mProcessLimitOverride` −1, `CUR_MAX_CACHED_PROCESSES` 1026. The app `RLIMIT_NPROC` is 38969 and CPU time is unlimited. Nothing in those caps was clipping this process.
- ✔️ `dumpsys power` at 10:34: no `ollmchat:stream` partial wake lock held. No foreground service for this package. Historical `ollmchat:stream` acquires are from 8 October, not this run.
- ✔️ Logcat on the GTK thread at 10:30:26–10:30:32, after exec time had already flattened: `GSocketClient` walking `192.168.122.1`, `10.9.188.9`, and `172.17.0.1`, each `Socket I/O timed out` at about two seconds. Warning is `OllmchatWindow.vala:678`. That is `probe_addresses` inside `reconnect` (three passes).
- ℹ️ Morning `simpleperf record --app` returned 0 samples because the thread was already asleep. `debuggerd -b 13599` needs root.
- ℹ️ RSS was 214 MB while hot and 116 MB once the thread had gone idle.
- ✔️ 14:50, same pid 13575, GTK tid 13599, activity still resumed and visible. Screen awake: `sum_exec_runtime` 505643 → 510801 ms in 5 s (about one core). `nr_voluntary_switches` stayed 3418. `wchan` was `0`.
- ✔️ Screen then Dozing for 10 s: exec 511986 → 519921 ms. The spin continued with the display off. Home did not cache the activity (`visible=true`, still the resumed activity) and exec kept climbing.
- ✔️ By 14:52:17 exec was frozen at 551085.315 ms and the thread was sleeping, while `ToplevelActivity` was still the resumed activity and the screen was Dozing. This burst ended without the process being cached.
- ✔️ Waking the screen at 14:55:33 restarted it. Logcat: a burst of `onDisplayChanged` with state 4 → 4, then 4 → 2, then the window unstopped and the surfaces were recreated. 14:55:36–14:55:44 exec 553289 → 561332 ms. Voluntary switches stayed 3815.
- ✔️ `simpleperf record --app org.roojs.ollmchat.androidpoc -t 13599 -g -f 500 --duration 12` during the next wake (14:56) recorded 5432 samples. Exec over a 5 s slice inside that window was 569737 → 573876 ms. Samples: `libglib-2.0.so` 52%, `libc` 16%, `libgobject-2.0.so` 16%, `libgtk-4.so` 11%, `libollmchatgtk.so` 4.6%. Call graph: `__start_thread` → `g_application_run` → `g_main_context_iteration`, and the dispatch child is `libollmchatgtk.so[+25674]`. Named GTK hits are `gtk_scrollbar_get_type`, `gtk_range_get_type`, `gtk_scrollbar_get_adjustment`, `gtk_scrolled_window_get_type`, `gtk_scrolled_window_get_vadjustment`, `gtk_adjustment_get_upper`. `__ppoll` is 6.4%. The `gsk_renderer_render` → `eglSwapBuffers` branch is a few percent of the dispatch.
- ℹ️ Phone `libollmchatgtk.so` build id `b267eb38962952a46a4a09646a1123382653a9db` (255984 bytes, stripped). The unstripped copy under `.pixiewood/bin-aarch64` is build id `c3b51803a727568ca3eb709cd488eef9c008d736`, dated 6 October. Offsets from this profile do not apply to that file.
- ✔️ At 14:48:27, when the window was unstopped, logcat recorded 1380 `onDisplayChanged` lines in that one second, all state 2 → 2. That burst is one second. The core stayed pegged for minutes around it.

## Root cause

- ✔️ The hot thread is the GTK thread, inside `g_main_context_iteration`, in a callback in `libollmchatgtk.so`. The callback stays ready: voluntary switches do not move while exec climbs by about one second per second. The GTK symbols in that sample are the scrollbar and the scrolled-window adjustment.
- 💩 The matching source is an idle that returns true while `vadjustment.upper < 100`. `ChatView.scroll_to_bottom` does that (`libollmchatgtk/ChatView.vala`, the idle added around the `upper < 100.0` check) and `ChatView.scroll_to_idx` returns true on the same check. `ScrolledView.buffer_change` and `ChatView.resize_widget_callback` also return true until the widget is mapped or realized. A ready idle never lets the main loop sleep. The phone binary's build id is not the one on disk, so this sample is not yet pinned to one of those functions.
- 🚫 The GDK frame clock as the thing filling the core. Exec climbed with the screen awake, and the render / `eglSwapBuffers` path is a small branch of the same profile.
- 🚫 The cached-process limit. 1026 is the standard cap on this phone. It was not forcing the app to run.
- 🚫 The partial wake lock and the streaming foreground service, for this sample. Neither was held.
- 🚫 The fog icon timeout (`GLib.Timeout.add(400)` while `session.is_running`). Four hundred milliseconds cannot fill a core, and the agent-running wake lock was not held.
- 🚫 The two-second connect timeouts as the source of the core. During the 5 s full-core window, voluntary switches did not increase, so the thread was not blocked in those connects. `__ppoll` is 6% of the profile. The timeouts are a separate radio cost.

## Proposed fix

- 🔷 Cut the GTK-thread spin while the chat is idle. The profile is a ready idle in `libollmchatgtk.so` that reads the scrolled-window adjustment.
- 🚫 Do not pause the GDK frame clock for this sample. The profile's time is in the app callback, and the spin happens with the screen on.
- 🚫 Do not lower `mProcessLimit` or the app `RLIMIT_NPROC`. That does not throttle a runnable thread.
- 🚫 Do not add a sleep inside the idle callback. Returning true from `GLib.Idle.add` is what keeps the main loop awake. A later `Timeout` is a separate source.

### 1. `libollmchatgtk/ChatView.vala` — `scroll_to_bottom`: wait with a timeout

**Why:** 💩 Source match only. This idle returns true while `vadjustment.upper < 100`, and the profile's GTK symbols are the scrolled-window adjustment. The phone build id was not symbolized to this function.

**Where:** Inside the `GLib.Idle.add` lambda, the `vadjustment.upper < 100.0` branch.

**Depends on:** none.

#### Remove

```vala
				if (vadjustment.upper < 100.0) {
					// Layout not ready yet, try again on next idle (but only if scrolling is still enabled)
					return this.scroll_enabled && !this.autoscroll_paused_by_user;
				}
```

#### Replace with

```vala
				if (vadjustment.upper < 100.0) {
					GLib.Timeout.add(100, () => {
						this.scroll_to_bottom();
						return false;
					});
					return false;
				}
```

### 2. `libollmchatgtk/ChatView.vala` — `scroll_to_idx`: wait with a timeout

**Why:** 💩 Same source match. `return true` while `vadj.upper < 100`. Not symbolized on the phone binary.

**Where:** Inside the `GLib.Idle.add` lambda, the `vadj.upper < 100.0` branch.

**Depends on:** none.

#### Remove

```vala
				if (vadj.upper < 100.0) {
					/* GLib.debug(
						"scroll_idx retry upper=%.0f idx=%d",
						vadj.upper,
						idx); */
					return true;
				}
```

#### Replace with

```vala
				if (vadj.upper < 100.0) {
					/* GLib.debug(
						"scroll_idx retry upper=%.0f idx=%d",
						vadj.upper,
						idx); */
					GLib.Timeout.add(100, () => {
						this.scroll_to_idx(idx);
						return false;
					});
					return false;
				}
```

### 3. `libollmchatgtk/ChatView.vala` — `resize_widget_callback`: wait with a timeout

**Why:** 💩 Same idle pattern, weaker match. The profile did not name a measure or realize path. `return true` until the widget is realized would still hold the core if this callback is the one that is ready.

**Where:** The unrealized check at the start of `resize_widget_callback`.

**Depends on:** none.

#### Remove

```vala
			if (widget == null || !widget.get_realized()) {
				return true; // Try again next time
			}
```

#### Replace with

```vala
			if (widget == null || !widget.get_realized()) {
				GLib.Timeout.add(100, () => {
					this.resize_widget_callback(widget, scrolled_window, mode, expand_button);
					return false;
				});
				return false;
			}
```

### 4. `libollmchatgtk/ScrolledView.vala` — `buffer_change`: wait with a timeout

**Why:** 💩 Same idle pattern, weaker match. The profile did not name line-yrange or map checks. `return true` from this idle would hold the core if this callback is the one that is ready.

**Where:** Three `return true` sites in `buffer_change`. The docblock return line matches the new wait.

**Depends on:** none.

#### Remove

```vala
		 * @return true to wait for map/width, false when done
```

#### Replace with

```vala
		 * @return false. A later timeout retries while the view is unmapped,
		 *   has no width, or has no line height.
```

#### Remove

```vala
			if (!this.text_view.get_mapped()) {
				return true;
			}
			if (this.get_width() <= 0) {
				return true;
			}
```

#### Replace with

```vala
			if (!this.text_view.get_mapped()) {
				GLib.Timeout.add(100, this.buffer_change);
				return false;
			}
			if (this.get_width() <= 0) {
				GLib.Timeout.add(100, this.buffer_change);
				return false;
			}
```

#### Remove

```vala
				if (peer_h > 0) {
					return false;
				}
				return true;
```

#### Replace with

```vala
				if (peer_h > 0) {
					return false;
				}
				GLib.Timeout.add(100, this.buffer_change);
				return false;
```

## Attempts / changelog

- ℹ️ 2026-10-30 morning — adb only. No product change. `simpleperf` caught the thread after it had gone to sleep, so that record had 0 samples.
- ℹ️ 2026-10-30 14:50–14:57 — adb only. Screen off, wake, and `simpleperf` as above. Record left on the phone at `/data/local/tmp/gtk-heat2.data`. No product change.
- ✔️ 2026-10-30 15:28 — applied the four idle-timeout fences in `libollmchatgtk/ChatView.vala` and `libollmchatgtk/ScrolledView.vala`. `PIXIEWOOD_PHASE=build scripts/android/build-chat-poc-apk.sh` wrote `app-arm64-v8a-debug.apk` at 15:31.
- ℹ️ 15:31 `adb install -r` of that APK failed: `INSTALL_FAILED_UPDATE_INCOMPATIBLE` (signatures do not match the package on the phone).
- ✔️ 15:50 uninstalled `org.roojs.ollmchat.androidpoc` and installed `app-arm64-v8a-debug.apk`. Launched `ToplevelActivity`. pid 17608, `versionName=0.2.0`, `lastUpdateTime=2026-10-30 15:50:52`. On-device pairing data went with the old package.

## Next

- 🚫 None. Closed.
