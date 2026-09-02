# 6.1.10 Agent Pi — skills configuration (initial offer)


> **DONE** — archived. Parent: [`CODER-6.1-agent-pi.md`](../CODER-6.1-agent-pi.md).

Status: ✔️ agent-done (Phases 1–4; awaiting user ✅)

> **`docs/plans/CODER-1.0-summary.md` is not updated** for this sub-plan until it is done and archived.

ℹ️ Checklist: `docs/guide-to-writing-plans.md` — Checklist for plans (emoji provenance: **🔷** = user said it; **💩** = LLM suggestion).  
ℹ️ Parent: [6.1](CODER-6.1-agent-pi.md) / [6.1.2](done/6.1.2-DONE-pi-like-agent.md) Phase 2.  
ℹ️ Pack content / vendoring: [done/6.1.3](done/6.1.3-DONE-base-skills.md); extended: [6.1.11](CODER-6.1.11-extended-base-skills.md). Spec: [agentskills.io](https://agentskills.io/).

## Purpose

- 🔷 `✔️` Skills UI lives under **Settings dialog → Skills** page.
- 🔷 Settings for this live in **config** (settings), independent of the Agent itself; the agent can **read** config.
- 🔷 Store under the **agents** config subtree (like tools / agents maps) — Agent Pi’s own config, `skills` for now.
- 🔷 Toggle controls **initially offered**.
- ℹ️ **Offered** (Agent Pi only): names that go into the system-prompt skill catalog.
  - Template placeholder `{skills_md}` ← `AgentPi.SkillSet.to_prompt()` → `<available_skills>` XML.
  - 🚫 Not the old Runner / `OLLMcoder.Skill` system.
- 🔷 Available skills can be a **larger** set than the initial offer (not a dump of everything into the prompt).
- 🔷 By default skills **run from the resource system** (gresource / packaged `resources/pi-skills/`) — **no** need to copy them onto the filesystem for normal use.
- 🔷 Config can **export** a skill resource → user filesystem; user-edited copy **overrides** the resource skill.
- ℹ️ Loader / scan roots partly exist (`SkillSet.scan`); extend for offer filter + export UI.

---

## Two layers (Agent Pi catalog — not old Skills)

- 🔷 **Available** — listed on the Settings Skills page (resource pack + user/project filesystem Pi skills).
- 🔷 **Initially offered** — subset toggled on; those entries are what Agent Pi puts in the prompt catalog (`<available_skills>` via `{skills_md}`).
- 🔷 Configuration dialog edits **initially offered**.
- ℹ️ Model still `read`s full `SKILL.md` only when it chooses a catalog entry (progressive disclosure unchanged).
- 🚫 Do not confuse with `OLLMcoder.Skill` / Runner / refine–execute — different product.

---

## Resource vs filesystem (source + export)

- 🔷 **Default source:** packaged / gresource (`resources/pi-skills/` from [done/03](done/6.1.3-DONE-base-skills.md)). Catalog `location` can be a resource path the `read` tool can open — **no** silent copy-on-first-use of the whole pack.
- 🔷 **User source:** filesystem under existing scan roots (especially `~/.local/share/ollmchat/pi-skills/`). Same name as a resource skill → **user wins** (override), matching today’s later-scan-wins / by-name replace idea.
- 🔷 **Export:** built-in skill → filesystem (user said click-to-export on the built-in subtext).
- 🔷 **Subtext:** built-in click-to-export wording, **or** the filesystem **path** when it lives on disk.
  - 🔷 Path / folder name **is** the indicator (resource skills have no file path — no separate “exported” badge).
- 🔷 🚫 Config does **not** delete the exported filesystem skill.
  - Removing the override is out of band (e.g. ask the LLM / delete the folder yourself).
- 🔷 `⏳` v1 export target = **user** skill set only (e.g. `~/.local/share/ollmchat/pi-skills/`); project export later if wanted.
- 🔷 On-disk / override = match by skill **name** (folder / file under scan roots) — not a persisted “exported” flag.
- ℹ️ Ties acquisition in [done/03](done/6.1.3-DONE-base-skills.md): ship in resources; export-on-demand via this dialog — not blanket A→C for every skill.

---

## Do skills declare other skills they need?

- ℹ️ **Agent Skills frontmatter has no skill→skill dependency field.**
  - Required: `name`, `description`.
  - Optional: `license`, `compatibility` (environment / packages / network — **not** other skills), `metadata`, `allowed-tools`.
- ℹ️ Soft skills often **name companions in the markdown body** (prose), e.g. superskills `writing-plans` says hand off / **REQUIRED SUB-SKILL** → `executing-plans`.
- ℹ️ That is advice for the **model after it has read the skill**, not a host contract.
- 🔷 Host must **not** assume machine-readable “requires skill X” today.
- 🔷 When choosing the **default initial offer**, include companions that the recommended skills routinely hand off to (e.g. if `writing-plans` is offered, also offer `executing-plans`).
- 🔷 `⏳` **Later:** review how a skill **writes** another skill (body prose / naming) before any UI or parser for companions — see then; not v1.
- 🚫 Do not invent a private frontmatter `depends:` unless we deliberately extend the format later.
- 🚫 No “mentioned companions” settings hint until that later look.

---

## Configuration UI — Settings → Skills page

- 🔷 `✔️` **Settings dialog → Skills** page.
- 🔷 Settings stored in **config** (settings), independent of the Agent; agent reads config.
- 🔷 One **row per skill**; **not** collapsible.
- 🔷 Like tools enable — a **toggle** for **initially offered**.
- 🔷 Needs a **header** (e.g. these are the skills / offered).
- 🔷 Row: skill **name** + **subtext**:
  - built-in: click here to export to the filesystem
  - otherwise: path where it is on disk
- 🔷 🚫 No right-click popup (export is the built-in subtext click).
- 🔷 🚫 No **Delete** (or uninstall) of the exported copy from this UI.
- 🔷 Fresh install defaults = a **recommended initial set** (not “everything vendored”).
- 🔷 Persist under **`Config2.agents`** (same subtree as tools/agents maps) — Agent Pi’s **`AgentConfig.skills`**.
  - ℹ️ JSON: `"agents": { "agent-pi": { "forbidden": […], "skills": [ "writing-plans", … ] } }`.
  - ℹ️ Only thing in `skills` is **offered** names. Path / on-disk / export are **not** in config — scan + name match.
  - ℹ️ Name in the array ⇒ offered; absent ⇒ available but not offered.
  - 🔷 Missing `skills` key ⇒ seed default offer list; empty array in file ⇒ none offered (valid).
  - 🚫 Not a top-level `agent-pi-skills` key on Config2.
  - 🚫 Not an array of objects.
- 🔷 `⏳` **Later:** project-specific offer list / separate project config file — not v1.
- 🔷 `✔️` `SkillSet.scan` — resource + user/project roots (done/03).
- 🔷 `✔️` After scan, filter prompt catalog to `agents["agent-pi"].skills` only (soft — LLM not blocked from using others).
- 🔷 `✔️` Export materializes resource skill into **user** Pi-skills dir; subtext becomes path.

---

## Recommended initial set (defaults)

🔷 Defaults = which Agent Pi **offers** on a fresh install (Settings toggles start on).  
ℹ️ Vendored pack still owned by [done/03](done/6.1.3-DONE-base-skills.md) (+ [11](CODER-6.1.11-extended-base-skills.md) later).

Default **offered** (on) — seed these names:

- 🔷 `writing-plans`, `executing-plans`, `brainstorming`
- 🔷 `research-codebase`, `debug-review`
- 🔷 `⏳` `writing-agents-md` — [6.1.12](CODER-6.1.12-write-agents-md-skill.md) (on by default; missing `AGENTS.md` is a start-work path)
- 🔷 `senior-solution-architect`, `prompt-engineer`
- 🔷 `deep-research`, `webpage-reader`

Available but **not** default-offered:

- 🔷 `agent-skill-orchestrator` — listed in Settings; not in the seed array
- 🔷 🚫 Skills 03 marked skip (grill-me, discovery, document-converter, …)

---

## Phase 1 — `AgentConfig.skills` under `Config2.agents`

- 🔷 `✔️` Offered names live on the Agent Pi entry in **`Config2.agents`** — property **`skills`** on {@link OLLMchat.Settings.AgentConfig} (peer of `forbidden`).
- 🔷 `✔️` Missing `skills` key seeds defaults above; empty array means none offered.
- ℹ️ Same serialize pattern as `forbidden` (string array). Seed in `AgentPi.Factory.register_config` (already creates `agents["agent-pi"]`).
- ℹ️ Edits are **Remove** / **Replace with** / **Add** from the tree; verify surrounding context before applying.

### 1. `libollmchat/Settings/AgentConfig.vala` — `skills` property

**Why:** Agent Pi offered-skill list as part of the agents config subtree (like tools under `Config2.tools`).

**Where:** class body after `forbidden` property.

**Depends on:** none.

#### Add — After the `forbidden` property block (before `forbid`).

```vala
		/**
		 * Offered Agent Pi skill names (JSON ''skills'' string array).
		 *
		 * Name present ⇒ included in the prompt catalog. Missing key on load
		 * seeds the product default offer; empty array means none offered.
		 */
		[Description(nick = "Skills", blurb = "Offered Agent Pi skills")]
		public Gee.ArrayList<string> skills {
			get;
			set;
			default = new Gee.ArrayList<string>();
		}

		/**
		 * True when ''skills'' was present in the loaded JSON for this agent.
		 * Not serialized.
		 */
		public bool skills_from_file = false;
```

### 2. `libollmchat/Settings/AgentConfig.vala` — `serialize_property` for `skills`

**Why:** Write the string array like `forbidden`.

**Where:** `serialize_property` switch — after `case "forbidden":` block.

**Depends on:** §1.

#### Add — After the `case "forbidden":` block (before `default:`).

```vala
				case "skills":
					var skills_arr = new Json.Array();
					var skills_list = (Gee.ArrayList<string>) value.get_object();
					if (skills_list != null) {
						foreach (var s in skills_list) {
							skills_arr.add_string_element(s);
						}
					}
					var skills_node = new Json.Node(Json.NodeType.ARRAY);
					skills_node.set_array(skills_arr);
					return skills_node;

```

### 3. `libollmchat/Settings/AgentConfig.vala` — `deserialize_property` for `skills`

**Why:** Read string array; set `skills_from_file` so missing key can seed defaults.

**Where:** `deserialize_property` switch — after `case "forbidden":` block.

**Depends on:** §1.

#### Add — After the `case "forbidden":` block (before `default:`).

```vala
				case "skills":
					this.skills_from_file = true;
					this.skills.clear();
					if (property_node.get_node_type() == Json.NodeType.ARRAY) {
						var skills_arr = property_node.get_array();
						for (var i = 0; i < skills_arr.get_length(); i++) {
							var elem = skills_arr.get_element(i);
							if (elem.get_node_type() != Json.NodeType.VALUE) {
								continue;
							}
							this.skills.add(elem.get_string());
						}
					}
					value = Value(typeof(Gee.ArrayList));
					value.set_object(this.skills);
					return true;

```

### 4. `liboccoder/AgentPi/Factory.vala` — `register_config` seed `skills`

**Why:** New agent-pi config and upgrades (agent present, no `skills` key) get the default offer.

**Where:** `register_config` body.

**Depends on:** §1, Recommended initial set.

#### Remove

```vala
			if (!config.agents.has_key(this.name)) {
				config.agents.set(this.name, new OLLMchat.Settings.AgentConfig() {
					forbid = "write_file,edit_mode,read_file,run_command"
				});
			}
```

#### Replace with — Ensure agent entry exists; seed `skills` via `add_all_array` when not loaded from file.

```vala
			if (!config.agents.has_key(this.name)) {
				config.agents.set(this.name, new OLLMchat.Settings.AgentConfig() {
					forbid = "write_file,edit_mode,read_file,run_command"
				});
			}
			var agent_cfg = config.agents.get(this.name);
			if (!agent_cfg.skills_from_file) {
				agent_cfg.skills.clear();
				agent_cfg.skills.add_all_array({
					"writing-plans",
					"executing-plans",
					"brainstorming",
					"research-codebase",
					"debug-review",
					"senior-solution-architect",
					"prompt-engineer",
					"deep-research",
					"webpage-reader",
				});
			}
```

ℹ️ Also update the `AgentConfig` class docblock JSON example to show `"skills": [ … ]` under `"agent-pi"` (doc-only; same file).

---

## Phase 2 — Filter Agent Pi prompt catalog

- 🔷 `✔️` `SkillSet.scan` still fills **all** available skills (Settings needs the full list).
- 🔷 `✔️` `to_prompt` only emits skills whose names are in `agents["agent-pi"].skills`.
- 🔷 Soft filter only — do not block `read` / tool use of other paths.
- ℹ️ Still skip `disable_model` skills in the catalog (existing behaviour).

### 5. `liboccoder/AgentPi/SkillSet.vala` — `to_prompt` filter

**Why:** Prompt catalog = offered names only.

**Where:** `to_prompt` method.

**Depends on:** Phase 1.

##### Part 1 — signature

#### Remove

```vala
		public string to_prompt()
```

#### Replace with — Accept offered name list from Config2.

```vala
		public string to_prompt(Gee.ArrayList<string> offered)
```

##### Part 2 — skip when not offered

#### Remove

```vala
			foreach (var skill in this.items) {
				if (skill.disable_model) {
					continue;
				}
```

#### Replace with — Keep `disable_model` skip; add offered check.

```vala
			foreach (var skill in this.items) {
				if (skill.disable_model) {
					continue;
				}
				if (!offered.contains(skill.name)) {
					continue;
				}
```

### 6. `liboccoder/AgentPi/PendingMessage.vala` — pass config list

**Why:** Wire Config2 into `{skills_md}` fill.

**Where:** `run` — `system_fill` call that passes `"skills_md"`.

**Depends on:** §5, Phase 1.

#### Remove

```vala
				"skills_md", skill_set.to_prompt(),
```

#### Replace with — Pass Agent Pi `AgentConfig.skills` from session config.

```vala
				"skills_md", skill_set.to_prompt(
					agent.session.manager.config.agents.get(
						agent.session.agent_name).skills),
```

---

## Phase 3 — Settings → Skills page

- 🔷 `✔️` New Settings tab; flat rows (not ExpanderRow); header; toggle = offered.
- 🔷 `✔️` Row title = skill name; subtext = built-in click-to-export **or** filesystem path.
- 🔷 🚫 No right-click; no Delete.
- 🔷 `✔️` `agent_skills` property = `AgentConfig` for ''agent-pi'' (set in ctor); offered list is `this.agent_skills.skills`.
- 🔷 `✔️` Separate **create widgets** (`add_skill`) from **load values** (`load_skills`).
- 🔷 `✔️` `load_skills`: scan; `add_skill` only for names not already in the map; then fill toggles / subtitles.
- 💩 `Gee.HashMap` name → row, toggle, and skill; export updates row via map.
- 💩 Default `row.subtitle = skill.path`, then override if `resource://`.
- 💩 Built-in: `row.activatable` + `activated` → export (no `activate_link` on ActionRow in our Adw).
- ℹ️ Landed: `ollmapp/SettingsDialog/SkillsPage.vala`, MainDialog, meson/valadoc.

### 7. `ollmapp/SettingsDialog/SkillsPage.vala` — new page

**Why:** Settings UI for available / offered Pi skills.

**Where:** new file (whole file).

**Depends on:** Phase 1; Phase 4 export body is connected here.

#### Add — Create `ollmapp/SettingsDialog/SkillsPage.vala` with this content.

```vala
/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this library; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 */

namespace OLLMapp.SettingsDialog
{
	/**
	 * Settings tab: Agent Pi skills available vs initially offered.
	 *
	 * Flat rows (not expanders). {@link add_skill} builds widgets once;
	 * {@link load_skills} adds only new names then fills values. Toggle edits
	 * {@link OLLMchat.Settings.AgentConfig.skills} on ''agents["agent-pi"]''.
	 */
	public class SkillsPage : SettingsPage
	{
		public MainDialog dialog { get; construct; }

		/**
		 * Agent Pi config entry this page edits (''agents["agent-pi"]'').
		 */
		public OLLMchat.Settings.AgentConfig agent_skills { get; private set; }

		private Gtk.ScrolledWindow scrolled_window;
		private Adw.PreferencesGroup group;
		private Gtk.Box boxed_list;
		private Gee.HashMap<string, Adw.ActionRow> skill_rows =
			new Gee.HashMap<string, Adw.ActionRow>();
		private Gee.HashMap<string, Gtk.Switch> skill_toggles =
			new Gee.HashMap<string, Gtk.Switch>();
		private Gee.HashMap<string, OLLMcoder.AgentPi.Skill> skills_by_name =
			new Gee.HashMap<string, OLLMcoder.AgentPi.Skill>();
		private bool filling_skills = false;

		public SkillsPage(MainDialog dialog)
		{
			Object(
				dialog: dialog,
				page_name: "skills",
				page_title: "Skills",
				page_icon: "application-x-addon-symbolic",
				orientation: Gtk.Orientation.VERTICAL,
				spacing: 0
			);

			this.agent_skills = this.dialog.app.config.agents.get("agent-pi");

			this.action_widget = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6) {
				hexpand = true,
				visible = false
			};

			this.group = new Adw.PreferencesGroup() {
				title = "Skills",
				description = "Toggle to include a skill in the Agent Pi initial offer (prompt catalog)."
			};
			this.boxed_list = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
			this.group.add(this.boxed_list);

			this.scrolled_window = new Gtk.ScrolledWindow() {
				vexpand = true,
				hexpand = true
			};
			this.scrolled_window.set_child(this.group);
			this.scrolled_window.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);
			this.append(this.scrolled_window);
		}

		/**
		 * Create row + toggle for one skill and connect signals (once).
		 *
		 * @param skill scanned Agent Pi skill
		 */
		private void add_skill(OLLMcoder.AgentPi.Skill skill)
		{
			var row = new Adw.ActionRow() {
				title = skill.name,
				subtitle = skill.path,
				activatable = false
			};
			var toggle = new Gtk.Switch() {
				valign = Gtk.Align.CENTER
			};
			if (skill.path.has_prefix("resource://")) {
				row.use_markup = true;
				row.subtitle = "<a href=\"export\">Built-in — click to export to the filesystem</a>";
				row.activate_link.connect((uri) => {
					this.export_skill(skill.name);
					return true;
				});
			}
			toggle.notify["active"].connect(() => {
				if (this.filling_skills) {
					return;
				}
				if (toggle.active) {
					if (!this.agent_skills.skills.contains(skill.name)) {
						this.agent_skills.skills.add(skill.name);
					}
					return;
				}
				this.agent_skills.skills.remove(skill.name);
			});
			row.add_suffix(toggle);
			this.boxed_list.append(row);
			this.skill_rows.set(skill.name, row);
			this.skill_toggles.set(skill.name, toggle);
		}

		/**
		 * Scan; add rows for new skill names only; fill toggles and subtitles.
		 */
		public void load_skills()
		{
			var project_path = "";
			var history_manager = (this.dialog.parent as OllmchatWindow).history_manager;
			if (history_manager != null) {
				project_path = history_manager.session.project_path;
			}
			var skill_set = new OLLMcoder.AgentPi.SkillSet();
			skill_set.scan(project_path);
			foreach (var skill in skill_set.items) {
				this.skills_by_name.set(skill.name, skill);
				if (!this.skill_rows.has_key(skill.name)) {
					this.add_skill(skill);
				}
			}
			var offered = this.agent_skills.skills;
			this.filling_skills = true;
			foreach (var entry in this.skills_by_name.entries) {
				var skill = entry.value;
				var row = this.skill_rows.get(skill.name);
				var toggle = this.skill_toggles.get(skill.name);
				toggle.active = offered.contains(skill.name);
				row.subtitle = skill.path;
				row.use_markup = false;
				if (skill.path.has_prefix("resource://")) {
					row.use_markup = true;
					row.subtitle = "<a href=\"export\">Built-in — click to export to the filesystem</a>";
				}
			}
			this.filling_skills = false;
		}

		/**
		 * Copy a resource skill into the user Pi-skills dir; update that row.
		 *
		 * @param skill_name name key in {@link skill_rows}
		 */
		private void export_skill(string skill_name)
		{
			var skill = this.skills_by_name.get(skill_name);
			var user_root = GLib.Path.build_filename(
				GLib.Environment.get_user_data_dir(), "ollmchat", "pi-skills");
			var dest_dir = GLib.Path.build_filename(user_root, skill.name);
			try {
				GLib.File.new_for_path(dest_dir).make_directory_with_parents(null);
			} catch (GLib.Error e) {
				if (!(e is GLib.IOError.EXISTS)) {
					GLib.warning("Failed to create %s: %s", dest_dir, e.message);
					return;
				}
			}
			var resource_dir = "/pi-skills/" + skill.name;
			var children = GLib.resources_enumerate_children(
				resource_dir, GLib.ResourceLookupFlags.NONE);
			foreach (var child in children) {
				if (child.has_suffix("/")) {
					continue;
				}
				var bytes = GLib.resources_lookup_data(
					resource_dir + "/" + child, GLib.ResourceLookupFlags.NONE);
				var dest = GLib.File.new_for_path(
					GLib.Path.build_filename(dest_dir, child));
				dest.replace_contents(
					bytes.get_data(), null, false,
					GLib.FileCreateFlags.REPLACE_DESTINATION, null, null);
			}
			var skill_md = GLib.Path.build_filename(dest_dir, "SKILL.md");
			skill.path = skill_md;
			var row = this.skill_rows.get(skill_name);
			row.use_markup = false;
			row.subtitle = skill_md;
		}
	}
}
```

ℹ️ Ctor sets `this.agent_skills` from `config.agents.get("agent-pi")`; toggles / fill use `this.agent_skills.skills`. `add_skill` = widgets + connects; `load_skills` = scan, add missing, fill. Subtitle defaults to path, then resource override.
- 🚫 Do not look up `agents.get("agent-pi")` on every toggle / fill — use `this.agent_skills`.
- 🚫 Do not tear down / rebuild all rows on every `load_skills`.
- 🚫 Do not call `load_skills()` after a single export — update that row via the map.
### 8. `ollmapp/SettingsDialog/MainDialog.vala` — mount Skills tab

**Why:** Show the page beside Tools.

**Where:** fields + constructor (after tools page) + `show_dialog`.

**Depends on:** §7.

##### Part 1 — field

#### Add — After `private ToolsPage tools_page;`.

```vala
		private SkillsPage skills_page;
```

##### Part 2 — construct page

#### Add — After tools page `action_widget.visible = false;` block (before `notify["visible-child"]`).

```vala
			this.skills_page = new SkillsPage(this);
			this.view_stack.add_titled(this.skills_page,
				this.skills_page.page_name,
				this.skills_page.page_title);
			this.view_stack.get_page(this.skills_page).icon_name = this.skills_page.page_icon;
			this.action_bar_area.append(this.skills_page.action_widget);
			this.skills_page.action_widget.visible = false;
```

##### Part 3 — load on show

#### Add — After `this.tools_page.load_configs();` in `show_dialog`.

```vala
			this.skills_page.load_skills();
```

### 9. `ollmapp/meson.build` — compile SkillsPage

**Why:** Include new source in app + valadoc lists.

**Where:** both `ollmapp` source arrays near `ToolsPage.vala`.

**Depends on:** §7.

#### Add — After each `'SettingsDialog/ToolsPage.vala',` line (app sources and any duplicate list that includes ToolsPage).

```meson
    'SettingsDialog/SkillsPage.vala',
```

### 10. `docs/meson.build` — valadoc input

**Why:** Keep docs build in sync.

**Where:** `valadoc_docs` `input:` list after ToolsPage.

**Depends on:** §7.

#### Add — After `'../ollmapp/SettingsDialog/ToolsPage.vala',`.

```meson
    '../ollmapp/SettingsDialog/SkillsPage.vala',
```

---

## Phase 4 — Export (user Pi-skills dir)

- 🔷 `✔️` Export copies the resource skill into `~/.local/share/ollmchat/pi-skills/<name>/`.
- 🔷 On-disk = scan finds that folder; same name replaces resource (existing scan order).
- 🔷 `✔️` Subtext becomes the filesystem path on that row after export (no separate badge).
- 🔷 🚫 No project-dir export in v1.
- ℹ️ Export implementation lives in Phase 3 §7 (`export_skill` + row `activated`) — no extra hunks here.
- 💩 Nested resource subdirs (e.g. `references/`) — v1 copies top-level files only; extend later if a shipped skill needs deep copy.

---

## Suggested order

1. 🔷 `✔️` Resource scan + override ([done/03](done/6.1.3-DONE-base-skills.md)).
2. 🔷 `✔️` **Phase 1** — `AgentConfig.skills` under `agents["agent-pi"]` + seed in `register_config`.
3. 🔷 `✔️` **Phase 2** — `to_prompt(offered)` + PendingMessage wire.
4. 🔷 `✔️` **Phase 3** — Skills page + MainDialog + meson.
5. 🔷 `✔️` **Phase 4** — export via Skills page (user dir); that row’s subtitle → path.
6. 🔷 Later — companion naming; project-specific config.

---

## Link back

- ℹ️ [02 § Skill](done/6.1.2-DONE-pi-like-agent.md#skill--separate-from-old-skills) + Phase 2 / 2.1.
- ℹ️ [done/03](done/6.1.3-DONE-base-skills.md) — what we vendor; not the same as what we initially offer.
- ℹ️ `liboccoder/AgentPi/Skill.vala`, `SkillSet.vala` — scan today; offer filter in Phase 2.
- ℹ️ `AgentConfig.forbidden` — same string-array serialize pattern as `skills`.

---

## LLM notes

- ℹ️ **🔷** = user requirement; **💩** = confirm before build; open work as `🔷 ⏳` or `💩 ⏳`.
- 🚫 Do not treat body prose “REQUIRED SUB-SKILL” as a parser contract.
- 🚫 Do not dump every available Pi skill into the Agent Pi prompt catalog once the pack grows.
- 🚫 Do not treat “not offered” as a hard ban — only omit from the prompt catalog (user: LLM can still use them).
- 🚫 Do not add project-specific / separate project config for offers in v1 — Config2 only; later.
- 🚫 Do not mix this with the old `OLLMcoder.Skill` / Runner system.
- 🚫 Do not copy-on-first-use the whole resource pack to the filesystem.
- 🚫 Do not export to the **project** skill dir in v1 — **user** Pi-skills dir only.
- 🚫 Do not add Delete/uninstall of exported skills in the config UI (user/LLM can remove files outside settings).
- 🚫 Do not make skill rows collapsible (user: not collapsible).
- 🚫 Do not use a right-click menu for export (user: no).
- 🚫 Do not store this on the Agent object — config/settings only; agent reads config (user).
- 🚫 Do not add a top-level Config2 `agent-pi-skills` key — use `agents["agent-pi"].skills` (user).
- 🚫 Do not add a separate “exported” badge — path/folder name is the indicator (user).
- 🚫 Do not default-offer `agent-skill-orchestrator` (available, toggle off).
- 🚫 Do not try/catch around the export link handler — `export_skill` then update that row’s subtitle. Mkdir only special-cases `EXISTS`.
- 🚫 Do not rebuild all skill rows on every tab show — `add_skill` once; `load_skills` adds new + fills.
- 🚫 Do not rebuild the whole skills list after exporting one skill.
- 🚫 Do not add helper methods beyond what Phase 3 names (`SkillsPage`, `add_skill`, `load_skills`, `export_skill`).
- 🚫 No product-docs skill as part of this config story ([done/03](done/6.1.3-DONE-base-skills.md) already drops that gap).
