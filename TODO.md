# TODO

## Plans

See [docs/plans/](docs/plans/) for detailed implementation plans:
- [needed_tools.md](docs/plans/needed_tools.md) - Tools implementation plan

## DONE

Completed plans (for reference):
- [outline_plan.md](docs/plans/outline_plan.md) - Overall implementation plan
- [prompting_plan.md](docs/plans/prompting_plan.md) - Prompting system plan

---

## Current Other TODO Items

* replace markdown with md4c library?

 * need a copy paste feature for sourceview
   * fix the text selection stuff for sourceview?


* Chat logs (so we can restored the?)

* test the Prompt
  * have a Prompt for 'planning'?
  
* Context usage? 
  * there is an options thinkg that includes setting context size
  * in theory the returned number shows how much is used
  * we have to send that number and get it back in theory

* I guess we also need to consider that if the user has denied it before we currently show a message I think, but just that the request was blocked, we might need to enhance that with a clear button? that just clears the 


* annoying bug that the tool icon shows up on a thinking model pulldown during first load - tried to debug but could not find any solution - the pulldonw list is fine, tis' just the button.

## Code Editor Bugs/TODO

* **Clipboard file reference feature needs proper design**
  * Current implementation was commented out - needs architectural review
  * Requirements:
    - When user copies text from SourceView, store file path and line range metadata
    - When user pastes into ChatInput, replace pasted text with file reference (e.g., "file:path:123" or "file:path:123-456")
  * Issues with current approach:
    - Clipboard metadata storage/retrieval design needs refinement
    - Interface between libollmchatgtk and liboccoder needs proper decoupling
    - GTK4 clipboard API usage (async operations in sync signal handlers)
    - Need to handle edge cases (multiple copies, clipboard changes, etc.)
  * Files involved:
    - libollmchatgtk/ClipboardManager.vala (interface)
    - libollmchatgtk/ClipboardMetadata.vala (interface)
    - liboccoder/ClipboardMetadata.vala (implementation)
    - liboccoder/SourceView.vala (copy handler)
    - libollmchatgtk/ChatInput.vala (paste handler)
    - ollmchat/Window.vala (initialization)