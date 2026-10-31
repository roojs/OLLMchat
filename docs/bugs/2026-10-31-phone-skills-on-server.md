# Phone Agent Pi prompt keeps skill and summary placeholders

**Status:** ⏳ open. The bundled skill pack is in the phone binary. Literal `{skills_md}` / `{conversation_summary}` in the sent prompt is still unexplained.

## Problem

- 🔷 An Agent Pi turn on the phone sent a system message that still contained the `{skills_md}` and `{conversation_summary}` placeholder text.
- 🔷 Expected: `{skills_md}` is the skill catalog. `{conversation_summary}` is the conversation checkpoint, or nothing when there is no checkpoint yet.
- 🔷 The base skills are in the phone resources. Confirm that before treating the phone as having no skill set.

## Evidence

- ✔️ `resources/pi-prompts/initial.md` leaves both tokens in the system template: `{agents_md}{skills_md}` then `{conversation_summary}`.
- ✔️ `liboccoder/AgentPi/PendingMessage.vala` `run` fills those tokens on the process that sends the chat. The phone runs Agent Pi itself (`ollmapp/android/OllmchatWindow.vala` registers `agent-pi`).
- ✔️ `{skills_md}` comes from `SkillSet.scan` then `to_prompt`. Scan order in `liboccoder/AgentPi/SkillSet.vala`:
  - bundled `/pi-skills` gresource
  - `~/.local/share/ollmchat/pi-skills/` via `get_user_data_dir()`
  - `{project}/.pi/skills/` and `{project}/.agents/skills/` via `GLib.FileUtils.test` and `GLib.File.new_for_path`
- ✔️ The installed phone package is `org.roojs.ollmchat.androidpoc`, `lastUpdateTime=2026-10-31 09:13:10`, `primaryCpuAbi=arm64-v8a`, native libs `run-from-apk`. Its `libollmchat.so` matches the debug APK built at 09:12 (2047104 bytes, sha256 `5f1a7010…bcbc5e76`).
- ✔️ That library contains the `/pi-skills` resource. Each directory is present once, and each `SKILL.md` body has its `name:` line:
  - `writing-plans`
  - `executing-plans`
  - `brainstorming`
  - `senior-solution-architect`
  - `agent-skill-orchestrator`
  - `prompt-engineer`
  - `deep-research`
  - `webpage-reader`
  - `research-codebase`
  - `debug-review`
- ✔️ The same library contains `pi-prompts/` and the template text `{agents_md}{skills_md}`.
- 🚫 The phone is not missing the bundled skill set. A pull from the server is not required for these ten skills.
- ✔️ User and project skill roots are still local paths. `FileUtils.test` does not go through the file connection, so desktop `~/.local/share/ollmchat/pi-skills` and the project `.pi/skills` / `.agents/skills` are not in this scan.
- ✔️ `to_prompt` returns `""` when nothing is offered. `Prompt.Template.system_fill` then deletes the token. A literal `{skills_md}` left in the sent text means the fill did not apply that pair. An empty catalog alone does not leave the token.
- ℹ️ `{conversation_summary}` is the local session checkpoint in `PendingMessage.run`. It is not a skill file.
- ℹ️ A failed `resources_enumerate_children("/pi-skills")` is caught and ignored in `SkillSet.scan`. The bytes are in the library. This check did not call enumerate inside the running process.

## Root cause

- ⏳ Leftover `{skills_md}` in a completed send is still unconfirmed. The tablet send died before `system_fill` logged.
- ✔️ The tablet crash is a missing `agent-pi` config entry. Android creates the factory and never calls `register_config`, so `config.agents` has no `agent-pi`. `PendingMessage.run` then reads `.skills` on null.

### Crash fix

Android must seed the agent the way desktop `Window.vala` does. `register_config` seeds the forbid list and skill names. It must not `GLib.error`. That aborts the process during startup, before the agent list is shown. Agent Pi is already omitted unless the desktop connection is live. Bash is always enabled and runs on the desktop daemon, so Android registers it beside read and write.

#### Remove — `liboccoder/AgentPi/Factory.vala` `register_config`, the write, read, and bash asserts.

```vala
if (!tools.has_key("write")) {
    GLib.error("agent %s: required tool missing: write", this.name);
}
if (!tools.has_key("read")) {
    GLib.error("agent %s: required tool missing: read", this.name);
}
if (this.form == OLLMcoder.Form.DESKTOP && !tools.has_key("bash")) {
    GLib.error("agent %s: required tool missing: bash", this.name);
}
```

#### Add — `ollmapp/android/OllmchatWindow.vala` `initialize_client`, immediately after the read tool and before the `agent-pi` factory. Same shape as read and write.

```vala
if (!this.history_manager.tools.has_key("bash")) {
    this.history_manager.register_tool(
        new OLLMtools.Bash.Tool(this.project_manager));
}
```

## Proposed fix

- 🚫 Do not pull the base pack from the server. It is already in `libollmchat.so` on the phone.
- 💩 ⏳ If a later capture shows `<available_skills>` empty while the resource is present, the failure is `SkillSet.scan` on the phone (enumerate, or the offered-name filter), not a missing file.
- 💩 ⏳ Desktop-only skill directories still need a file-connection read if those extras must appear on the phone. That is not this base pack.
- 🚫 Do not change `system_fill` until the sent string is captured and still contains `{skills_md}`.

## Attempts / changelog

- ℹ️ 2026-10-31 — debug in `liboccoder/AgentPi/SkillSet.vala` `scan` / `to_prompt` and `PendingMessage.vala` `run`. Logs resource children, load failures, scanned names, listed/offered counts, and whether the filled system text still contains `{skills_md}`, `{conversation_summary}`, or `<available_skills>`.
- ℹ️ Android `main` only sees argv `android-gtk`, so `--debug` never arrives.
- 🚫 `externalFilesDir/touch-debug` turns `GLib.debug` onto stderr (`TouchDebug.try_enable_from_storage`, then the window replaces the log handler). Those lines did not show in logcat. With the file removed, `GLib.debug` shows in logcat under `org.roojs.ollmchat.androidpoc`.
- ✔️ Phone emulator `emulator-5554` has 308MB free. `adb install` refuses (`Requested internal only, but not enough space`). The debug APK was not installed there.
- ✔️ Tablet emulator `emulator-5556` (`Medium_Tablet`) took the debug APK. Host Ollama is reachable as `127.0.0.1:11434` after `adb reverse tcp:11434 tcp:11434`. Startup logged `initialize_model ok model=deepseek-r1:1.5b`.
- ✔️ Agent Pi is omitted from the menu unless `filesd-client.state` is live. With state `3`, logcat showed `agent list store n=3` and `agent-pi list state=…LIVE show=true`.
- ✔️ Choosing Agent Pi logged `invalid cast from 'GtkTextBuffer' to 'GtkSourceBuffer'`, then `Factory.vala:259` `initialize Agent Pi widget:` with an empty message. There is no paired filesd on this emulator, so `rpc_load_projects_from_db` is the call in that try.
- 🚫 The chat `Gtk.TextView` did not take `adb input text`, `input keyboard text`, or keyevents.
- ✔️ 2026-10-31 11:11:16 — user sent “what can you tell me about building ollmchat” on the tablet. Process 3806 died with SIGSEGV, fault addr 0x0, in `oll_mcoder_agent_pi_pending_message_run` at `PendingMessage.vala:94` (`.skills` on the agent config). Logcat immediately before:
  - `SkillSet.vala:46` resource children include all ten skill dirs
  - `SkillSet.vala:116` `scan project=/home/alan/gitlive/OLLMchat items=10` and the ten names
  - `oll_mchat_settings_agent_config_get_skills: assertion 'self != NULL' failed`
  - `oll_mcoder_agent_pi_skill_set_to_prompt: assertion 'offered != NULL' failed`
- ✔️ Saved tablet `config.2.json` agents were only `just-ask` and `chatter`. Desktop `Window.vala` calls `agent_pi.register_config`. Android `OllmchatWindow.initialize_client` did not.
- ✔️ Applied the crash fix: `initialize_client` now calls `register_config`.
- ✔️ 2026-10-31 — Removed the `register_config` `GLib.error` asserts. They abort startup. Android registers `bash` beside `read` and `write`. Bash still runs on the desktop daemon.

## Next

- ✔️ Rebuilt and installed the debug APK on `emulator-5556`. Startup reached `initialize_model ok model=deepseek-r1:1.5b`, `agent list store n=3` with `agent-pi` first, and the process stayed up. No `required tool missing` abort.
- ⏳ 💩 Send one Agent Pi turn on the tablet (the chat field does not take `adb` text). Record the `filled skills` line (`skills_token`, `catalog`, `from_file`).
