---
name: Replace Config with Connection and migrate to config.2.json
overview: Replace OLLMchat.Config usage with OLLMchat.Settings.Connection throughout the codebase, update config loading to check for config.2.json first (converting config.json if needed), and add model property to Client to replace config.model. title_model is stored in Config2 but not on Client.
todos:
  - id: fix-config1-bug
    content: "Fix Config1.toV2() bug: change connection.default to connection.is_default"
    status: completed
  - id: update-client-class
    content: Replace Client.config with Client.connection, add model property (title_model removed from Client, stored in Config2 only)
    status: completed
  - id: update-config-loading
    content: Update Window.load_config_and_initialize() to check config.2.json first, convert config.json if needed
    status: completed
    dependencies:
      - fix-config1-bug
  - id: update-call-classes
    content: Update Call/Base.vala, Call/Chat.vala, Call/Embed.vala, Call/Generate.vala to use connection instead of config
    status: completed
    dependencies:
      - update-client-class
  - id: update-history-classes
    content: Update History classes (Manager, TitleGenerator, EmptySession, SessionBase) to use connection and model properties
    status: completed
    dependencies:
      - update-client-class
  - id: update-gtk-classes
    content: Update GTK classes (ChatInput, ChatWidget) to use connection and model properties
    status: completed
    dependencies:
      - update-client-class
  - id: update-bootstrap-dialog
    content: Update BootstrapDialog to create Connection and Config2, save as config.2.json
    status: completed
    dependencies:
      - update-client-class
  - id: update-settings-dialogs
    content: Update Settings dialogs (ConnectionAdd, ConnectionsPage) to use Connection instead of Config
    status: completed
    dependencies:
      - update-client-class
  - id: update-examples
    content: Update example files to use Connection instead of Config
    status: pending
    dependencies:
      - update-client-class
  - id: preserve-model-data
    content: Update Config1.toV2() to preserve model and title_model as ModelUsage objects in Config2's usage map (title_model stored in Config2, not on Client)
    status: completed
    dependencies:
      - fix-config1-bug
---

# Replace Config with Connection and migrate to config.2.json

## Overview

This plan replaces `OLLMchat.Config` with `OLLMchat.Settings.Connection` in the Client class and throughout the codebase. It also updates the configuration loading logic to check for `config.2.json` first, and if it doesn't exist, load `config.json`, convert it to Config2 format, and save it as `config.2.json`.**Important**: This is a refactoring and migration task only. We are NOT adding new features or functionality. We are:

- Moving existing properties from Config to Client/Connection (refactoring)
- Migrating config file format (migration)
- Fixing a bug (is_default property name)
- Preserving all existing functionality

## Changes Required

### 1. Update Client class ([libollmchat/Client.vala](libollmchat/Client.vala))

**Refactoring only**: Replacing Config with Connection. Caller sets model after constructor. title_model is NOT on Client (stored in Config2 only).

- Replace `public Config config { get; set; }` with `public Settings.Connection connection { get; set; }`
- Add direct property (caller sets this after constructor):
- `public string model { get; set; default = ""; }` - Direct property, caller sets from Config2's usage map if needed
- Do NOT add title_model property - it's stored in Config2 only, not on Client
- Update constructor to take `Settings.Connection` only (no Config2 access)
- Update all internal references from `this.config.url` to `this.connection.url`, `this.config.api_key` to `this.connection.api_key`, etc.
- Remove `set_model_from_ps()` method - caller can fetch ps and set model if they want

**Note**: `think` property remains on Client (it's a runtime property, not stored in config)

### 2. Fix Config1.toV2() bug and update migration ([libollmchat/Settings/Config1.vala](libollmchat/Settings/Config1.vala))

- Fix line 196: change `connection.default = true;` to `connection.is_default = true;`
- Preserve `model` and `title_model` from Config1 when converting (do NOT preserve `think`):
- Store as `ModelUsage` objects in Config2's `usage` map (see [1.3.1-configuration-classes.md](docs/plans/1.3.1-configuration-classes.md))
- Create `ModelUsage` for "default_model" key with: connection (URL), model, empty options
- Create `ModelUsage` for "title_model" key with: connection (URL), title_model, empty options
- The `connection` property in ModelUsage should reference the connection URL (key in connections map)
- Do NOT set `think` in ModelUsage - it's not stored in config
- **Default values** (see [1.3.3-config-bugs.md](docs/plans/1.3.3-config-bugs.md)):
- `model` and `title_model` can be empty strings (code should handle empty strings gracefully)

### 3. Update config loading logic ([ollmchat/Window.vala](ollmchat/Window.vala))

- Modify `load_config_and_initialize()` to:
- Check if `config.2.json` exists first
- If it exists, load it as `Config2` using `Config2.from_file()` (store in variable `config`)
- Register ModelUsage type for "default_model" and "title_model" keys: `config.register_type("default_model", typeof(Settings.ModelUsage))` and `config.register_type("title_model", typeof(Settings.ModelUsage))`
- Extract the default connection from `config.connections` (find connection where `is_default == true`)
- Create Client with the default connection
- Extract model from `config.usage` map and set on Client:
    - Get "default_model" ModelUsage from `config.usage.get("default_model")`, set `client.model = model_usage.model`
    - title_model is stored in Config2 but NOT set on Client (TitleGenerator accesses it from Config2 directly)
- If it doesn't exist, check for `config.json`
- If `config.json` exists, load it as `Config1`, convert to `Config2` using `toV2()` (store in variable `config`), save as `config.2.json`, and delete or rename `config.json`
- Create Client with the default connection
- Extract model from `config.usage` map and set on Client (same as above)

### 4. Update all Client.config references throughout codebase

Search and replace:

- `client.config.url` → `client.connection.url`
- `client.config.api_key` → `client.connection.api_key`
- `client.config.model` → `client.model` (direct property, set by caller from Config2's usage map)
- `client.config.title_model` → Access from Config2's usage map directly (title_model is NOT on Client)
- `client.config.think` → `client.think` (think remains on Client as runtime property, not stored in config)
- `client.config.clone()` → create new Connection and copy properties

Files to update:

- [libollmchat/Call/Base.vala](libollmchat/Call/Base.vala) - uses `client.config.url` and `client.config.api_key`
- [libollmchat/Call/Chat.vala](libollmchat/Call/Chat.vala) - uses `client.config.model`
- [libollmchat/Call/Embed.vala](libollmchat/Call/Embed.vala) - uses `client.config.model`
- [libollmchat/Call/Generate.vala](libollmchat/Call/Generate.vala) - uses `client.config.model`
- [libollmchat/History/Manager.vala](libollmchat/History/Manager.vala) - uses `client.config.clone()` and `client.config.model`
- [libollmchat/History/TitleGenerator.vala](libollmchat/History/TitleGenerator.vala) - takes Config, needs to take Connection and Config2 (to access title_model from usage map)
- [libollmchat/History/EmptySession.vala](libollmchat/History/EmptySession.vala) - uses `client.config.model`
- [libollmchat/History/SessionBase.vala](libollmchat/History/SessionBase.vala) - uses `client.config.model`
- [libollmchatgtk/ChatInput.vala](libollmchatgtk/ChatInput.vala) - uses `client.config.model`
- [libollmchatgtk/ChatWidget.vala](libollmchatgtk/ChatWidget.vala) - uses `client.config.model` and `client.config.url`
- [ollmchat/BootstrapDialog.vala](ollmchat/BootstrapDialog.vala) - creates Config, needs to create Connection and Config2
- [ollmchat/Settings/ConnectionAdd.vala](ollmchat/Settings/ConnectionAdd.vala) - creates Config for testing
- [ollmchat/Settings/ConnectionsPage.vala](ollmchat/Settings/ConnectionsPage.vala) - may use Config
- Examples and other files that create Client instances

### 5. Update BootstrapDialog ([ollmchat/BootstrapDialog.vala](ollmchat/BootstrapDialog.vala))

- Change to create `Connection` and `Config2` instead of `Config`
- Save as `config.2.json` instead of `config.json`
- Emit `config_saved` signal with Connection instead of Config

### 6. Update Config1.toV2() to preserve model/title_model using ModelUsage

**Preservation only**: We are preserving existing data during migration using the Config2 design (see [1.3.1-configuration-classes.md](docs/plans/1.3.1-configuration-classes.md)).

- Store `model` and `title_model` from Config1 as `ModelUsage` objects in Config2's `usage` map (do NOT store `think`):
- Create `ModelUsage` for "default_model" key:
    - `connection` = this.url (references connection in connections map)
    - `model` = this.model (can be empty string)
    - `options` = new empty Call.Options()
    - Do NOT set `think` - it's not stored in config
- Create `ModelUsage` for "title_model" key:
    - `connection` = this.url (references connection in connections map)
    - `model` = this.title_model (can be empty string)
    - `options` = new empty Call.Options()
    - Do NOT set `think` - it's not stored in config
- When loading Config2, extract model from usage map and set on Client (title_model remains in Config2, accessed directly when needed)
- **Important**: See [1.3.3-config-bugs.md](docs/plans/1.3.3-config-bugs.md) for default value handling:
- `model` and `title_model` can be empty strings (no default values needed)

### 7. Update Window.initialize_client() ([ollmchat/Window.vala](ollmchat/Window.vala))

- Change parameter from `OLLMchat.Config` to `OLLMchat.Settings.Connection` only
- After creating Client with default connection, extract model from Config2's usage map and set on Client:
- Get "default_model" ModelUsage from `config.usage.get("default_model")`, set `client.model = model_usage.model`
- title_model is stored in Config2 but NOT set on Client
- Update TitleGenerator constructor to take Connection and Config2, access title_model from Config2's usage map ("title_model" ModelUsage)

## Migration Strategy

1. Load `config.2.json` if it exists
2. If not, load `config.json` as Config1
3. Convert Config1 to Config2 using `toV2()`
4. Save as `config.2.json` in the same directory (`~/.config/ollmchat/`)
5. Optionally backup or remove old `config.json`

## Related Plans

- **1.3.1** - Configuration Classes ([docs/plans/1.3.1-configuration-classes.md](docs/plans/1.3.1-configuration-classes.md)) - Updated Config2 design with usage map and ModelUsage
- **1.3.3** - Configuration Migration Bugs and Defaults ([docs/plans/1.3.3-config-bugs.md](docs/plans/1.3.3-config-bugs.md))

## Testing Considerations

- Test loading existing `config.json` and conversion to `config.2.json`
- Test loading `config.2.json` directly
- Test creating new config when neither file exists
- Verify all Client instances work with Connection instead of Config