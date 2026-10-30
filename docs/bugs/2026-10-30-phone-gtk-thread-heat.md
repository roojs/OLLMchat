# Phone GTK thread heats the handset

**Status:** ⏳ one core was pegged on the GTK thread; the loop is not named — no code yet

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
- ℹ️ `simpleperf record --app` returned 0 samples. `debuggerd -b 13599` needs root. There is no native stack for the hot interval.
- ℹ️ RSS was 214 MB while hot and 116 MB once the thread had gone idle.

## Root cause

- 💩 Not confirmed. The only thread that ran was the GTK thread, and it ran for the minutes the screen was off while this activity was still the top app. It stopped once the activity was cached. That shape is a frame or main-loop source that keeps the thread runnable while the surface still exists, including with the display off.
- 🚫 The cached-process limit. 1026 is the standard cap on this phone. It was not forcing the app to run.
- 🚫 The partial wake lock and the streaming foreground service, for this sample. Neither was held.
- 🚫 The fog icon timeout (`GLib.Timeout.add(400)` while `session.is_running`). Four hundred milliseconds cannot fill a core, and the agent-running wake lock was not held.
- 🚫 The two-second connect timeouts as the source of the 289 s. Those log lines are from after `sum_exec_runtime` had stopped climbing. They are a separate battery cost, below.

## Proposed fix

- 🔷 Cut GTK-thread CPU while the screen is off or the activity is not visible, and stop failed desktop probes from keeping the radio awake after the user has left.
- 💩 Pause the GDK frame clock when the display turns off or the activity stops, and start it again on resume. The hot interval matches “screen off, activity still resumed,” and the idle matches “activity cached.” The clock lives in the GTK Android backend, not in `ollmapp`. Do not patch product widgets until a stack or an A/B shows a widget `queue_draw`.
- 💩 Stop `reconnect` / `probe_addresses` when the activity is stopped. `reconnect` runs three passes over every stored `host:port` with `SocketClient.timeout` of 2 seconds (`ollmapp/android/OllmchatWindow.vala`). On this phone those addresses were unreachable (`192.168.122.1`, `10.9.188.9`, `172.17.0.1`). One pass after the screen is off is enough to keep the GTK thread and the radio waking. Resume may try again.
- 💩 While `session.is_running` is true, keep the existing `ollmchat:stream` lock and foreground service only for a live reply. Release both when the activity stops if no token is in flight. Not this sample’s cause. It is the path that would block Android from freezing the process on a later run.
- 🚫 Do not lower `mProcessLimit` or the app `RLIMIT_NPROC`. That does not throttle a runnable thread.
- 🚫 Do not add a sleep, a yield, or a timer inside the GTK thread to “use less CPU” without naming the source. That hides the loop.
- ⏳ No Vala fence until the next hot sample says which of the two 💩 items is the loop.

## Attempts / changelog

- ℹ️ 2026-10-30 — adb only. No product change. `simpleperf` and `debuggerd` could not name a symbol.

## Next

- ⏳ While the handset is hot again, before it is backgrounded: note `sum_exec_runtime` and `sum_sleep_runtime` for tid of `GTK Thread`, turn the screen off for ten seconds, read the counters, turn the screen on, leave the app, read them again. Exec time climbing only while the screen is off and the activity is still resumed confirms the frame-clock item.
- ⏳ If exec time climbs with the screen on and the chat idle, the source is a widget invalidate. Then A/B by leaving the file view and the startup probe out of that run, and only then add a fence.
