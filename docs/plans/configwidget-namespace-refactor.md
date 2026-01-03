# ConfigWidget Namespace Refactoring Plan

## Current State

### Structure
- **ConfigWidget classes** are in `ollmchat/Settings/ConfigWidget/` directory
  - All in `OLLMchat.Settings` namespace
  - `ConfigItemWidget`, `ConfigBool`, `ConfigString`, `ConfigConnection`, `ConfigModel`, `ConfigModelUsage`, `ConfigOptions`
  
- **OptionsWidget classes** are in `ollmchat/Settings/OptionWidget.vala`
  - In `OLLMchat.Settings` namespace
  - `OptionsWidget`, `OptionRow`, `OptionFloatWidget`, `OptionIntWidget`

### Usage
- `OptionsWidget` is used in `ModelRow` for model configuration (dynamically reparented)
- `ConfigOptions` wraps `OptionsWidget` and adds property binding for tool configuration
- `ConfigOptions` is used in `ToolsPage` and `ConfigModelUsage`

## Goal

1. **Create `OLLMchat.Settings.ConfigWidget` namespace** for all config widget classes
2. **Move OptionsWidget classes** into the ConfigWidget namespace
3. **Merge ConfigOptions with OptionsWidget** - make OptionsWidget work both ways:
   - Standalone mode (for ModelRow - dynamic reparenting)
   - ConfigItemWidget mode (for ToolsPage - property binding)

## Plan

### Phase 1: Move to ConfigWidget Namespace

1. **Update all ConfigWidget classes** to use `OLLMchat.Settings.ConfigWidget` namespace:
   - `ConfigItemWidget.vala`
   - `ConfigBool.vala`
   - `ConfigString.vala`
   - `ConfigConnection.vala`
   - `ConfigModel.vala`
   - `ConfigModelUsage.vala`
   - `ConfigOptions.vala`

2. **Move OptionWidget.vala** to `ConfigWidget/OptionWidget.vala` and update namespace:
   - `OptionsWidget` → `OLLMchat.Settings.ConfigWidget.OptionsWidget`
   - `OptionRow` → `OLLMchat.Settings.ConfigWidget.OptionRow`
   - `OptionFloatWidget` → `OLLMchat.Settings.ConfigWidget.OptionFloatWidget`
   - `OptionIntWidget` → `OLLMchat.Settings.ConfigWidget.OptionIntWidget`

3. **Update all references**:
   - `ToolsPage.vala` - update `ConfigOptions`, `ConfigBool`, etc. references
   - `ConfigModelUsage.vala` - update `ConfigOptions` reference
   - `ModelRow.vala` - update `OptionsWidget` reference
   - `meson.build` - update file paths

### Phase 2: Merge ConfigOptions with OptionsWidget

**Option A: Make OptionsWidget extend ConfigItemWidget (Recommended)**

Make `OptionsWidget` extend `ConfigItemWidget` when used for property binding, but keep it usable standalone:

```vala
namespace OLLMchat.Settings.ConfigWidget
{
    public class OptionsWidget : ConfigItemWidget
    {
        // Existing fields and methods
        
        // Constructor for standalone use (ModelRow)
        public OptionsWidget()
        {
            // Initialize rows
        }
        
        // Constructor for property binding (ConfigItemWidget mode)
        public OptionsWidget.for_property(ParamSpec pspec, Object config)
        {
            base(pspec, config);
            // Initialize rows
            // Set up property binding
        }
        
        // Override create_widget() for ConfigItemWidget mode
        protected override Gtk.Widget create_widget()
        {
            // Return container with rows
        }
    }
}
```

**Option B: Keep ConfigOptions as thin wrapper (Simpler)**

Keep `ConfigOptions` as a thin wrapper around `OptionsWidget`, but both in same namespace:

```vala
namespace OLLMchat.Settings.ConfigWidget
{
    // OptionsWidget stays as GLib.Object (for ModelRow)
    public class OptionsWidget : GLib.Object { ... }
    
    // ConfigOptions extends ConfigItemWidget (for ToolsPage)
    public class ConfigOptions : ConfigItemWidget
    {
        private OptionsWidget options_widget;
        // Thin wrapper that adds property binding
    }
}
```

**Recommendation: Option B** - Simpler, less refactoring, clearer separation of concerns.

### Phase 3: Update Documentation

1. Update `docs/meson.build` with new file paths
2. Update any documentation references

## Implementation Steps

1. ✅ Create plan document
2. Move `OptionWidget.vala` to `ConfigWidget/OptionWidget.vala`
3. Update all ConfigWidget classes to `OLLMchat.Settings.ConfigWidget` namespace
4. Update all references in consuming code
5. Update `meson.build` files
6. Test compilation
7. Update documentation

## Files to Modify

### Move/Rename
- `ollmchat/Settings/OptionWidget.vala` → `ollmchat/Settings/ConfigWidget/OptionWidget.vala`

### Update Namespace
- `ollmchat/Settings/ConfigWidget/ConfigItemWidget.vala`
- `ollmchat/Settings/ConfigWidget/ConfigBool.vala`
- `ollmchat/Settings/ConfigWidget/ConfigString.vala`
- `ollmchat/Settings/ConfigWidget/ConfigConnection.vala`
- `ollmchat/Settings/ConfigWidget/ConfigModel.vala`
- `ollmchat/Settings/ConfigWidget/ConfigModelUsage.vala`
- `ollmchat/Settings/ConfigWidget/ConfigOptions.vala`

### Update References
- `ollmchat/Settings/ToolsPage.vala`
- `ollmchat/Settings/ModelRow.vala`
- `ollmchat/meson.build`
- `docs/meson.build`

## Benefits

1. **Better organization** - All config widget classes in one namespace
2. **Clearer structure** - ConfigWidget namespace makes purpose clear
3. **Easier maintenance** - Related classes grouped together
4. **Consistent naming** - All config widgets follow same pattern

