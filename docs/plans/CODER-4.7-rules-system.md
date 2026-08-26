# 4.7. Rules System

## Overview

Rules system for coding rules and other rules that need to be injected into the prompting system. This enables users to define project-specific or global coding standards, conventions, and guidelines that the code assistant should follow.

## Status

⏳ **TODO** - To be implemented.

## Related Plans

- **4.5** - Coding Agent Missing Bits (parent plan)
- **4.5.1** - Rules Support for Code Assistant (merged into this plan)

## Goals

- Allow users to define coding rules (project-specific or global)
- Inject rules into Code Assistant system prompts
- Support multiple rule sources (project config, global config, user-defined)
- Rules should be context-aware (language-specific, project-specific)
- Rule management UI
- Rule templates/presets

## Implementation Details

### Features
- Define coding rules
- Define project-specific rules
- Inject rules into prompting system
- Rule management UI
- Rule templates/presets

### Use Cases
- Enforce coding standards
- Project-specific guidelines
- Style guides
- Best practices

### Rule Sources

1. **Project-specific rules** - Stored in project configuration
2. **Global rules** - Stored in user configuration
3. **Language-specific rules** - Rules that apply only to specific programming languages

### Integration with Code Assistant

- Rules should be injected into the system prompt
- Rules should be formatted clearly in the prompt
- Rules should be updated when project changes or rules are modified

### Files to Create/Modify

- Rules storage system
- Rules injection into prompts
- Rules management UI
- Rule templates
- `liboccoder/Prompt/CodeAssistant.vala` - Add rules injection into system prompt
- `libollmchat/Settings/Config2.vala` - Add rules storage (if needed)
- `libocfiles/ProjectManager.vala` - Add project-specific rules support (if needed)

### Implementation Notes
- Design rules format/storage
- Integrate with prompt system
- Create UI for managing rules
- Support rule inheritance/merging
- Allow per-chat or per-project rules

## Future Enhancements

- Rule validation
- Rule templates
- Rule sharing between projects
- Rule versioning
