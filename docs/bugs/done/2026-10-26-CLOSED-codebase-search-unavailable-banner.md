# Codebase search banner does not name the model

**Status:** 🚫 CLOSED 2026-10-31. Parked. The `SearchFault` banner text is in the tree. It was not checked on a running app. A new log if that banner shows up again.

## Problem

- 🔷 Opening a project shows a banner: "Codebase search model is unavailable. Update the tool model in Settings."
- 🔷 Expected: the banner names the Settings row (Embedding Model or Analysis Model), the model, and the connection, so that row can be changed.
- 🔷 Startup can also show "Required tool model not available: <model>. Update the tool model in Settings." That names the model and still not the row.

## Evidence

- ✔️ The project banner is `Banner.show` in `ollmfilesd/ProjectManager.vala` when `vector_db.dimension` stays 0 after `open_vector_db`.
- ✔️ `BackgroundScan.open_vector_db` logs the real error (`vector index: …`) and does not put it on the banner.
- ✔️ `Database.check_required_models_available` returns false for a missing config, a disabled tool, a failed embed check, or a failed analysis check, with no distinction.
- ✔️ `ModelUsage.verify_model` returns false for an empty connection, an empty model, a missing connection, a list-models error, or a model that is not listed, and discards which one.
- ℹ️ Settings → Tools shows the tool as "Semantic Codebase Search Tool". The rows are the property nicks "Embedding Model" and "Analysis Model".

## Root cause

- ✔️ The banner is a fixed sentence. The check that decides to show it throws away the setting, the model name, and the failure.

## Proposed fix

- 🔷 `verify_model` stores a {@link OLLMchat.Settings.SearchFault}, not a sentence. {@link OLLMchat.Settings.SearchSlot} says Embedding Model or Analysis Model.
- 🔷 {@link OLLMchat.Settings.SearchFault.text} in `libollmchat/Settings/SearchFault.vala` turns that into text, when the banner is shown.

### `libollmchat/Settings/ModelUsage.vala` — `SearchFault` and `verify_model`

**Why:** The failure is a condition. The model name and connection stay on the usage and the config.

#### Replace with

`verify_model` sets `fault`. `detail` is only the raw list-models error. `SearchFault.text` builds the banner sentence.

### `libocvector2/Database.vala` — `check_required_models_available`

**Why:** Callers need the fault codes, not a sentence.

#### Replace with

Return the tool-level {@link OLLMchat.Settings.SearchFault}. NONE means both models were checked. Their faults stay on the model usages.

### `ollmfilesd/Vector/BackgroundScan.vala` — `open_vector_db`

**Why:** An embed or analysis call can still fail after the models are listed.

#### Replace with

Store `tool_fault`, `embed_fault`, and `analysis_fault`. A later failure is `CALL_FAILED` on that model, with `e.message` in the detail string.

### `ollmfilesd/ProjectManager.vala` and `ollmapp/Initialize.vala`

#### Replace with

`Banner.show` carries `object_type = "SearchFault"` and args `(fault, slot, detail)`. Desktop and Android banners call `SearchFault.text`.

## Next

- 🚫 2026-10-31. Closed. The banner has not shown up. Leave it.
