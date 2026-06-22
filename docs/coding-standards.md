# Coding Standards

Canonical Vala style and patterns for this project and related codebases. Written for **AI agents** — **mandatory** for agents implementing or changing Vala code. Human contributors may treat this as a helpful guide. Also see **`docs/build-rules.md`** and **`docs/code-documentation.md`**.

**AI agents:** Do **not** read this whole file blindly. Use
**`.cursor/rules/vala-coding-standards-router.mdc`** (and
**`docs/coding-standards-router.md`**) — answer the scenario checklist,
then read **every section it maps you to** (grep `section: <slug>` in this
file and read each block in full). Partial compliance is a violation.

**Plans:** This file is **code standards only**. Plan structure, code-proposal fences, implementation workflow, and the **checklist for verifying plans** are in **`docs/guide-to-writing-plans.md`**.

## Docblocks / code documentation <!-- section: docblocks -->

**IMPORTANT:** Docblocks (documentation comments for classes, methods, properties, and parameters) must follow the coding documentation standards and use **multiline** form. Do **not** use short one-line docblocks when documenting behaviour, parameters, or return values.

- Use full `/** ... */` blocks with a summary line, optional body (behaviour, context), and standard tags: `@param` for each parameter, `@return` for return value where relevant.
- For classes: include purpose, main roles or usage, and `@see` when referring to related types.
- For methods: include what the method does, when to use it, and document all parameters and return value.
- For properties: include what the property holds and when it is set or used.

**Bad (one-liner):**
```vala
/** Add all reference_targets to the given Tool. */
private void add_all_references_to(Tool ex)
```

**Good (multiline with @param):**
```vala
/**
 * Add all reference_targets to the given Tool. Used by add_exec_runs_for_tools() and by the combined branch in build_exec_runs().
 *
 * @param ex the Tool (exec run) to add references to
 */
private void add_all_references_to(Tool ex)
```

**Also Good (property with context):**
```vala
/**
 * Execution run id (e.g. "tool-0", "ref-1", "exec"). Empty for refinement-only.
 */
public string id { get; set; default = ""; }
```

Reserve single-line `/** ... */` only for trivial, self-explanatory cases where no parameters or behaviour need describing.

**Line length in docblocks:** Avoid long lines in docblocks. Break the summary or body into multiple lines (e.g. one sentence or clause per line) so that lines stay within a reasonable length; the same line-length and breaking rules apply to comments and documentation as to code.

**Literal syntax in docblocks:** Follow `docs/code-documentation.md` (Valadoc markup). Use triple braces `{{{ }}}` for code or literal snippets (e.g. URIs, ref syntax, config keys). Do **not** use `{@code …}` — valadoc rejects it. Do not use backticks for URIs or refs — in Valadoc backticks mean block quote and can trigger parse errors. Avoid literal `{` in running text (it starts inline taglets like `{@link}`); use `{{{ }}}` or rephrase. When adding `.vala` files, update `docs/meson.build` valadoc inputs (see **Valadoc build** in `docs/code-documentation.md`).

## String Interpolation <!-- section: string-interpolation -->

**IMPORTANT:** Do NOT use `@"` string interpolation unless explicitly asked. Use normal string concatenation instead.

**Exception:** Multi-line strings for usage/help text, error messages, or documentation may use `@"""` (triple-quoted string interpolation) for better readability.

**Bad:**
```vala
var message = @"Error: Tool '$tool_name' not found";
```

**Good:**
```vala
var message = "Error: Tool '" + tool_name + "' not found";
```

**Also Good (exception for multi-line usage/help text):**
```vala
var usage = @"Usage: $(args[0]) [OPTIONS] <folder> <query>

Search indexed codebase using semantic vector search.

Arguments:
  folder                 Folder path to search within (required)
  query                  Search query text (required)

Options:
  -d, --debug          Enable debug output
  -j, --json           Output results as JSON
";
```

## Temporary Variables <!-- section: temporary-variables -->

**CRITICAL — `var` on locals:** Always use **`var`** for local variables and
`for` / `foreach` loop variables. **Never** write an explicit primitive or
reference type on a local declaration.

**Forbidden on locals (non-exhaustive):** `string name = …`, `int count = …`,
`bool active = …`, `uint n = …`, `int64 x = …`, and the same for any other
built-in type used as a local initializer or declaration without assignment.

**Allowed explicit types:** method parameters, class/struct fields, properties,
`out` parameters in method signatures, and the **one** exception below.

**Exception — growable string arrays only:** `string[] name = {}` (see
ArrayList for Strings). Do **not** extend this exception to other array types
without user approval.

**Self-check before finishing Vala edits:** search changed files for
`^\s+(string|int|bool|uint|int64|float|double)\s+\w+\s*[=;]` inside method
bodies. Every match on a **local** must be fixed or justified in the diff
comment; parameters and fields are excluded.

**Bad (explicit type on local — forbidden):**
```vala
string elevation_password = "";
int exit_status = 0;
bool need_perm = this.build_perm_question();
```

**Good (`var` on locals; `string[]` exception only):**
```vala
var elevation_password = "";
var exit_status = 0;
var need_perm = this.build_perm_question();
string[] lines = {};
```

**IMPORTANT:** Avoid single-use temporary variables. If a variable is only used once, inline it directly.

**IMPORTANT:** Avoid temporary variables that are just pointers to object properties. Access the property directly instead.

**IMPORTANT:** Trivial aliases are forbidden. A variable that is only an alias for a single property or method result (e.g. `var path = file.path`, `var x = a.b`) must never be used — inline the expression at each use site instead.

**EXCEPTION:** The only allowed aliases are for long chains (4+ steps). Aliasing is permitted only when the expression is a long property/method chain such as `a.b.c.d.e` or `agent.session.manager.permission_provider`; in those cases a local may be used for readability.

**Bad:**
```vala
var width = this.scrolled_window.get_width();
if (width <= 1) {
    return;
}
var margin = this.text_view.margin_start;
this.calculate(margin);
```

**Also Bad (pointer to property):**
```vala
private void perform_search(string search_text)
{
    var buffer = this.current_buffer;
    if (buffer == null) {
        this.search_context = null;
        this.update_search_results();
        return;
    }
    
    var search_settings = new GtkSource.SearchSettings();
    search_settings.case_sensitive = this.case_sensitive_checkbox.active;
    this.search_context = new GtkSource.SearchContext(buffer, search_settings);
}
```

**Also Bad (simple alias):**
```vala
var model = model_usage.model_obj;
this.tools_button_binding = model.bind_property("can-call", this.tools_menu_button, "visible", 
    BindingFlags.SYNC_CREATE);
```

**Good:**
```vala
if (this.scrolled_window.get_width() <= 1) {
    return;
}
this.calculate(this.text_view.margin_start);
```

**Also Good (access property directly):**
```vala
private void perform_search(string search_text)
{
    if (this.current_buffer == null) {
        this.search_context = null;
        this.update_search_results();
        return;
    }
    
    var search_settings = new GtkSource.SearchSettings();
    search_settings.case_sensitive = this.case_sensitive_checkbox.active;
    this.search_context = new GtkSource.SearchContext(this.current_buffer, search_settings);
}
```

**Also Good (exception for long property chains - 4+ properties deep):**
```vala
// Long property chain (4+ properties) - OK to alias for readability
var permission_provider = this.agent.session.manager.permission_provider;
if (permission_provider.check_permission(path, Operation.READ)) {
    // ... use permission_provider multiple times ...
}
```

**Also Good (inline simple alias):**
```vala
this.tools_button_binding = model_usage.model_obj.bind_property(
    "can-call",
    this.tools_menu_button,
    "visible",
    BindingFlags.SYNC_CREATE
);
```

## Brace Placement <!-- section: brace-placement -->

**IMPORTANT:** Use line breaks for braces in namespaces, classes, and methods. Do NOT use line breaks for braces in control structures (if, case, switch, while, for, etc.).

**IMPORTANT:** Never put the whole if/else (or other control structure) on one line. Always use line breaks so the opening brace and body are on separate lines.

**Bad:**
```vala
class MyClass {
    public void method()
    {
        if (condition)
        {
            doSomething();
        }
    }
}
```

**Also Bad (one-line if with body):**
```vala
if (embed_response.embeddings.size == 0) { return; }
```

**Good:**
```vala
class MyClass
{
    public void method()
    {
        if (condition) {
            doSomething();
        }
    }
}
```

**Also Good (body on separate line):**
```vala
if (embed_response.embeddings.size == 0) {
    return;
}
```

**Also Good (namespace with line break):**
```vala
namespace MyNamespace
{
    class MyClass
    {
        public void method()
        {
            if (condition) {
                doSomething();
            }
        }
    }
}
```

## Underscore prefix on variables and fields <!-- section: underscore-prefix -->

**CRITICAL - FORBIDDEN:** Do NOT use a leading underscore (`_`) on variable names, field names, or property names. Use plain names and access with `this.` where needed.

**Bad:**
```vala
private Gee.HashMap<string, Skill> _by_path = new Gee.HashMap<string, Skill>();
private Gee.HashMap<string, Skill> _by_name = new Gee.HashMap<string, Skill>();
private string _cached_system_message = "";
this._by_path.clear();
```

**Good:**
```vala
private Gee.HashMap<string, Skill> by_path = new Gee.HashMap<string, Skill>();
private Gee.HashMap<string, Skill> by_name = new Gee.HashMap<string, Skill>();
private string cached_system_message = "";
this.by_path.clear();
```

## This Prefix <!-- section: this-prefix -->

**IMPORTANT:** Always use `this.` prefix when accessing properties or calling methods on the current instance.

**Bad:**
```vala
class MyClass
{
    private int value;
    
    public void method()
    {
        value = 10;
        calculate();
        var result = get_result();
    }
}
```

**Good:**
```vala
class MyClass
{
    private int value;
    
    public void method()
    {
        this.value = 10;
        this.calculate();
        var result = this.get_result();
    }
}
```

## Reducing Nesting <!-- section: reducing-nesting -->

**IMPORTANT:** Avoid nested code by using early returns, break/continue statements, and avoiding else clauses when possible. This improves readability and reduces cognitive complexity.

**STRICT — Loops:** In `foreach`/`for`/`while` loops, use **`continue`** to handle each case and keep the loop body flat. Do **not** use `else` or chain `else if` inside the loop; denest by handling one case, then `continue`, then the next case. The remainder of the iteration (the “default” path) stays at top level without being inside an `else`.

**STRICT — Else:** Prefer to avoid `else`. Use early return or `continue` so the main path is not inside an `else` block. If you have `if (a) { ... } else if (b) { ... } else { ... }`, restructure so each branch returns or continues and the flow is linear.

**IMPORTANT:** Put shorter code in if statements and return/continue if feasible, rather than having large nested code blocks. Extract complex logic into separate methods when the main flow becomes hard to follow.

**Bad:**
```vala
public void process_items(List<Item> items)
{
    if (items != null) {
        if (items.size > 0) {
            foreach (var item in items) {
                if (item.is_valid()) {
                    if (item.needs_processing()) {
                        this.process(item);
                    } else {
                        this.skip(item);
                    }
                }
            }
        } else {
            this.log("No items to process");
        }
    }
}
```

**Good:**
```vala
public void process_items(List<Item> items)
{
    if (items == null || items.size == 0) {
        if (items != null) {
            this.log("No items to process");
        }
        return;
    }
    
    foreach (var item in items) {
        if (!item.is_valid()) {
            continue;
        }
        
        if (item.needs_processing()) {
            this.process(item);
            continue;
        }
        
        this.skip(item);
    }
}
```

**Also Good (avoiding else):**
```vala
public bool is_authorized(User user)
{
    if (user == null) {
        return false;
    }
    
    if (!user.is_active()) {
        return false;
    }
    
    return user.has_permission();
}
```

**Also Good (extracting complex logic):**
```vala
public int64 cleanup_orphaned_vectors(SQ.Database sql_db) throws GLib.Error
{
    if (this.index == null) {
        throw new GLib.IOError.FAILED("Index not initialized");
    }
    
    uint64 total_vectors = this.vector_count;
    if (total_vectors == 0) {
        return 0;
    }
    
    var valid_ids_list = this.get_valid_vector_ids(sql_db, total_vectors);
    if (valid_ids_list.size == 0) {
        this.index = new Index(this.dimension);
        return (int64)total_vectors;
    }
    
    bool needs_cleanup = (uint64)valid_ids_list.size < total_vectors;
    bool needs_remapping = this.check_needs_remapping(valid_ids_list, needs_cleanup);
    
    if (!needs_cleanup && !needs_remapping) {
        return 0;
    }
    
    if (needs_cleanup) {
        this.rebuild_index_with_valid_vectors(valid_ids_list);
    }
    
    if (needs_remapping) {
        this.remap_metadata_vector_ids(sql_db, valid_ids_list);
    }
    
    return (int64)total_vectors - (int64)valid_ids_list.size;
}
```

## GLib Namespace Prefix <!-- section: glib-namespace-prefix -->

**IMPORTANT:** Always prefix GLib namespace classes and functions with `GLib.` prefix. Never use unqualified GLib types or functions.

**Bad:**
```vala
var path = Path.build_filename("/home", "user");
var file = File.new_for_path(path);
var home = Environment.get_home_dir();
```

**Good:**
```vala
var path = GLib.Path.build_filename("/home", "user");
var file = GLib.File.new_for_path(path);
var home = GLib.Environment.get_home_dir();
```

## File info and try/catch <!-- section: file-info-try-catch -->

**IMPORTANT:** Use try/catch around file metadata operations (e.g. `GLib.File.query_info()`, modification time) **only when we do not know if the file exists**. If we have already successfully read the file (or otherwise established that it exists), do not wrap the subsequent `query_info()` (or similar) call in try/catch or check `query_exists()` — just call it. Let failures propagate.

**Bad (redundant when file was just read):**
```vala
// ... we just read this.path into body ...
var file = GLib.File.new_for_path(this.path);
if (file.query_exists()) {
    try {
        var info = file.query_info(GLib.FileAttribute.TIME_MODIFIED, GLib.FileQueryInfoFlags.NOFOLLOW_SYMLINKS, null);
        this.mtime = info.get_modification_time().to_unix();
    } catch (GLib.Error e) {
        this.mtime = 0;
    }
}
```

**Good (file known to exist):**
```vala
// ... we just read this.path into body ...
var file = GLib.File.new_for_path(this.path);
var info = file.query_info(GLib.FileAttribute.TIME_MODIFIED, GLib.FileQueryInfoFlags.NOFOLLOW_SYMLINKS, null);
this.mtime = info.get_modification_time().to_unix();
```

**Good (file may not exist — try/catch appropriate):**
```vala
var file = GLib.File.new_for_path(path);
try {
    var info = file.query_info(GLib.FileAttribute.TIME_MODIFIED, GLib.FileQueryInfoFlags.NOFOLLOW_SYMLINKS, null);
    return info.get_modification_time().to_unix();
} catch (GLib.Error e) {
    return 0;
}
```

## Try/Catch Scope <!-- section: try-catch-scope -->

**IMPORTANT:** Keep try/catch focused on the **minimal code that can throw**. Do not blanket large areas of code. Wrap only the specific call(s) that may throw; keep setup, building arguments, and non-throwing code outside the try block.

**Bad (blanketing a large area):**
```vala
try {
    var definition = this.runner.task_definition.get(this);
    var tpl = PromptTemplate.template("task_refinement");
    var user_content = tpl.fill(...);
    var system_content = tpl.system_fill();
    var messages = new Gee.ArrayList<...>();
    messages.add(...);
    messages.add(...);
    var response = yield this.chat_call.send(messages, null);
    var response_text = response != null ? (response.content ?? "") : "";
    var parsed = Parser.parse(response_text);
    if (parsed.issues != "") {
        this.refine_error = new GLib.IOError.INVAL(parsed.issues);
    } else {
        this.tool_calls.clear();
        foreach (var call in parsed.tool_calls) {
            this.tool_calls.add(call);
        }
    }
} catch (GLib.Error e) {
    this.refine_error = e;
}
```

**Good (try only around the call that can throw):**
```vala
var definition = this.runner.task_definition.get(this);
var tpl = PromptTemplate.template("task_refinement");
var user_content = tpl.fill(...);
var system_content = tpl.system_fill();
var messages = new Gee.ArrayList<...>();
messages.add(...);
messages.add(...);
string response_text;
try {
    var response = yield this.chat_call.send(messages, null);
    response_text = response != null ? (response.content ?? "") : "";
} catch (GLib.Error e) {
    this.refine_error = e;
    this.refined_done = true;
    return;
}
RefinementOutputParserResult parsed;
try {
    parsed = RefinementOutputParser.parse(response_text);
} catch (GLib.Error e) {
    this.refine_error = e;
    this.refined_done = true;
    return;
}
if (parsed.issues != "") {
    this.refine_error = new GLib.IOError.INVAL(parsed.issues);
} else {
    this.tool_calls.clear();
    foreach (var call in parsed.tool_calls) {
        this.tool_calls.add(call);
    }
}
this.refined_done = true;
```

Alternatively, a single try can wrap only the send + parse if both are the only operations that throw:
```vala
// ... setup outside try ...
string response_text;
RefinementOutputParserResult parsed;
try {
    var response = yield this.chat_call.send(messages, null);
    response_text = response != null ? (response.content ?? "") : "";
    parsed = RefinementOutputParser.parse(response_text);
} catch (GLib.Error e) {
    this.refine_error = e;
    this.refined_done = true;
    return;
}
// ... handle parsed outside try ...
```

## Using Statements <!-- section: using-statements -->

**IMPORTANT:** Avoid using `using` statements. Use full namespace prefixes for class references instead. it is not required any information contrary to this is incorrect

**Bad:**
```vala
using System.Collections.Generic;
using System.Linq;

public class MyClass
{
    public void method()
    {
        var list = new List<string>();
        var result = list.Where(x => x.Length > 0);
    }
}
```

**Good:**
```vala
public class MyClass
{
    public void method()
    {
        var list = new System.Collections.Generic.List<string>();
        var result = System.Linq.Enumerable.Where(list, x => x.Length > 0);
    }
}
```

## Switch/Case vs If/Else If <!-- section: switch-case -->

**IMPORTANT:** Use `switch/case` statements rather than long chains of `if/else if/else if` statements. This improves readability and is more efficient.

**Bad:**
```vala
public string get_status_message(int status)
{
    if (status == 0) {
        return "Pending";
    } else if (status == 1) {
        return "Processing";
    } else if (status == 2) {
        return "Completed";
    } else if (status == 3) {
        return "Failed";
    } else {
        return "Unknown";
    }
}
```

**Good:**
```vala
public string get_status_message(int status)
{
    switch (status) {
        case 0:
            return "Pending";
        case 1:
            return "Processing";
        case 2:
            return "Completed";
        case 3:
            return "Failed";
        default:
            return "Unknown";
    }
}
```

## Property Initialization <!-- section: property-initialization -->

**IMPORTANT:** Do not set default values in constructors. For simple types (int, bool, string, etc.), use direct assignment. For complex types (objects, lists, etc.), use `get; set; default =` syntax.

**Bad:**
```vala
public class MyClass
{
    public string name { get; set; }
    public int count { get; set; }
    public List<string> items { get; set; }
    
    public MyClass()
    {
        this.name = "";
        this.count = 0;
        this.items = new List<string>();
    }
}
```

**Good:**
```vala
public class MyClass
{
    public string name = "";
    public int count = 0;
    public List<string> items { get; set; default = new List<string>(); }
}
```

**Also Good (for private simple fields):**
```vala
public class MyClass
{
    private string name = "";
    private int count = 0;
    private bool active = false;
}
```

**GObject subclasses — inherited properties:** To give a subclass its own default for a property declared on the parent, the parent property must be `virtual` and the subclass must use `override` with `default =`. Redeclaring the same property name without `virtual`/`override` **shadows** the parent property: code that holds a base-type reference (e.g. `OLLMchat.Agent.Factory`) or GTK `PropertyExpression` still reads the parent's empty value. Runtime values that are not fixed defaults belong in the **public constructor body** after `Object (...)` (see [GObject construct blocks](#gobject-construct-blocks)). See Vala manual: properties are overridable only when marked `virtual` on the parent.

**Bad (shadows parent — UI sees empty `title`):**
```vala
public class ChildFactory : Agent.Factory {
    public string title { get; protected set; default = "Chatter"; }
}
```

**Good (virtual on parent, override with default on child):**
```vala
public class Factory : Object {
    public virtual string title { get; protected set; default = ""; }
}
public class ChildFactory : Factory {
    public override string title { get; protected set; default = "Chatter"; }
}
```

## GObject construct blocks <!-- section: gobject-construct-blocks -->

**IMPORTANT:** Do **not** add a separate Vala `construct { }` block for ordinary instance setup. Put that code in the **public constructor body** after `Object (...)` (or after the chained `base (...)` call).

**Bad (pointless separate `construct` block — timestamp / path setup):**
```vala
public Overlay (FileVerification verification) {
    Object (verification: verification);
}

construct {
    var now = new GLib.DateTime.now_local();
    this.overlay_dir = GLib.Path.build_filename(
        GLib.Environment.get_user_cache_dir(), "ollmchat", "overlay-" + …);
}
```

**Good (same logic in the public constructor):**
```vala
public Overlay (FileVerification verification) {
    Object (verification: verification);

    var now = new GLib.DateTime.now_local();
    this.overlay_dir = GLib.Path.build_filename(
        GLib.Environment.get_user_cache_dir(), "ollmchat", "overlay-" + …);
}
```

**When a `construct` block *is* justified:**

1. **Signal wiring** — inline `connect` handlers; see [Signal handlers in construct blocks](#signal-handlers-in-construct-blocks).
2. **Must run after `{ get; construct; }` properties** from an object initializer on the same `new` expression, and that setup cannot live in the public constructor because those properties are not set until after the constructor returns.

Do not split one initialization story across public constructor + `construct` block unless case (2) applies. If the public constructor already receives every required value (e.g. sole `Object (verification: verification)` and the rest is computed locally), keep **all** setup in the constructor body.

**Async method + child `GLib.Object`:** From an `async` method, do **not** use object-initializer syntax on `new Child (...) { prop = … }`. Construct the child with the sole ctor/`Object (...)` arg, assign other properties on the next lines, and mark the block with `// avoid async vala ctor bug`.

## Serializable Classes <!-- section: serializable-classes -->

**IMPORTANT:** For serializable classes, use `get; set; default =` to initialize properties rather than creating objects in the constructor. Be careful with getter/setters to ensure proper serialization behavior.

**Bad:**
```vala
public class SerializableData : GLib.Object
{
    public string name { get; set; }
    public List<string> items { get; set; }
    
    public SerializableData()
    {
        this.items = new List<string>();
    }
}
```

**Good:**
```vala
public class SerializableData : GLib.Object
{
    public string name { get; set; default = ""; }
    public List<string> items { get; set; default = new List<string>(); }
}
```

## Avoiding Nullable Types <!-- section: avoiding-nullable-types -->

**IMPORTANT:** If possible, avoid using nullable types. Instead, create an object with a checkable value (like an `active` property defaulting to `false`) to indicate whether the object is in use.

**Bad:**
```vala
public class Renderer
{
    private Table? current_table;
    
    public void process()
    {
        if (this.current_table != null) {
            this.current_table.render();
        }
    }
    
    public void reset()
    {
        this.current_table = null;
    }
}
```

**Good:**
```vala
public class Renderer
{
    private Table current_table { get; set; default = new Table(); }
    
    public void process()
    {
        if (this.current_table.active) {
            this.current_table.render();
        }
    }
    
    public void reset()
    {
        this.current_table.active = false;
    }
}
```

Note: The `Table` class should have `public bool active { get; set; default = false; }` to ensure it defaults to `false`.

## Defensive code and null checks <!-- section: defensive-code-null-checks -->

**Defensive code (general):** Avoid branches and checks whose only purpose is to handle situations your own API and call graph should already rule out—redundant guards, duplicated validation, speculative "what if" fallbacks, silent recovery from states that indicate a programming error, empty-collection checks when the pipeline guarantees non-empty invariants, and similar patterns. They **hide bugs** and **mask broken invariants** the same way needless null checks do: execution continues in a half-valid state instead of failing at the real fault.

**Strong justification required:** Any defensive check (null, empty collection, range, type tag, swallowed error, default-on-failure) must be backed by a **concrete reason** it is unavoidable: e.g. return type from an external library, user or network input at a boundary, FFI where the platform can genuinely fail, or a documented protocol exception. **Not** sufficient: "just in case", "defensive programming", "future-proofing", "the caller might forget", or "doesn't hurt". If the situation should not happen in correct internal code, **fix the contract or the caller** instead of guarding everywhere downstream.

**Prefer:** Make invalid states unrepresentable; establish invariants at module boundaries; fail fast where a violation means a bug; use separate methods or types for distinct cases instead of one function that accepts everything and branches internally.

### Null checks (specific)

**CRITICAL - ZERO TOLERANCE:** Null checks are FORBIDDEN unless you can prove with 100% certainty that the object MUST be null due to an external API contract or system-level constraint that is completely outside your control. "Optional" properties, "might be null", "could be null", "may not be set", "legitimately null", or any similar excuses are NOT valid reasons. These are design flaws that must be fixed, not worked around with null checks.

**CRITICAL:** Null checks hide bugs and mask design problems. If you find yourself wanting to add a null check, STOP. The correct solution is to redesign the code so null is impossible, not to add a null check.

**CRITICAL:** Avoid nullable parameters (`Type?`) at all costs. Design your APIs to not require nullable parameters. Use alternative patterns like default objects, empty collections, or separate methods instead. If a property "might not be set", it should have a default value (empty string, empty list, default object with an `active` flag, etc.), not be nullable.

**The ONLY acceptable exceptions:**
1. External API calls that explicitly return nullable types (e.g., database queries, file system operations, network requests) - but even then, handle the null case immediately and convert to a non-nullable design
2. System-level constraints where null is truly unavoidable (e.g., GObject property bindings, signal handlers with optional parameters)

**If you're about to add a null check, ask yourself:**
- Can I make this property non-nullable with a default value? YES → Do that instead
- Can I use a separate method/flag for the "not set" case? YES → Do that instead  
- Can I redesign the API to not need null? YES → Do that instead
- Is this truly an external API/system constraint? NO → Fix the design, don't add a null check

**Bad:**
```vala
public void process_item(Item? item)
{
    if (item == null) {
        return;
    }
    this.do_something(item);
}
```

**Also Bad (nullable parameter):**
```vala
public void process_item(Item? item)
{
    if (item == null) {
        this.handle_null_case();
        return;
    }
    this.do_something(item);
}
```

**Good:**
```vala
public void process_item(Item item)
{
    this.do_something(item);
}
```

**Also Good (separate method instead of nullable parameter):**
```vala
public void process_item(Item item)
{
    this.do_something(item);
}

public void process_without_item()
{
    this.handle_no_item_case();
}
```

**Exception (when null is explicitly part of the design and absolutely unavoidable):**
```vala
// This is OK only if null is truly required by external API or design constraints
public void process_item(Item? item)
{
    if (item == null) {
        this.handle_null_case();
        return;
    }
    this.do_something(item);
}
```

## Line Length and Breaking <!-- section: line-length-breaking -->

**IMPORTANT:** Avoid long lines in code, docblocks, and comments. Break lines for readability.

**Maximum line length:** In docblocks and comments, no line may extend past **72 characters** (including leading spaces/tab). Break after a word so the next line continues the sentence; a good rule of thumb is “break after a comma or before the next phrase” so that the first line does not go beyond roughly “… add all references,” in length.

- **Code:** Break on `(` when function calls or method invocations are long; break on `+` when string concatenation creates long lines; if arguments are broken, put each argument on its own line.
- **Docblocks and comments:** Break so that no line exceeds 72 characters; prefer breaking after commas or natural phrase boundaries.

**Bad:**
```vala
this.buffer.insert_markup(ref end_iter, "<span size=\"small\" color=\"#1a1a1a\">" + renderer.toPango(message) + "</span>\n", -1);
```

**Good:**
```vala
this.buffer.insert_markup(
	ref end_iter,
	"<span size=\"small\" color=\"#1a1a1a\">" + renderer.toPango(message) + "</span>\n",
	-1
);
```

**Also Good (breaking on + for long concatenation):**
```vala
this.buffer.insert_markup(
	ref end_iter,
	"<span size=\"small\" color=\"#1a1a1a\">" +
		renderer.toPango(message) +
		"</span>\n",
	-1
);
```

**Good (each argument on its own line):**
```vala
this.some_method(
	arg1,
	arg2,
	arg3,
	arg4
);
```

## Debug and Warning Statements <!-- section: debug-warning-statements -->

**IMPORTANT:** When using `GLib.debug()` or `GLib.warning()`, do NOT include class names, method names, or location information in the message. The runtime logs file and line automatically, so including them is redundant.

**IMPORTANT:** When adding debug output using `GLib.debug()`, do NOT prefix the message with function names, class names, or location information. The debug output system already includes the filename and line number automatically, making such prefixes redundant.

**IMPORTANT:** Do NOT add timestamps or elapsed-time fields to
`GLib.debug()` or `GLib.warning()` messages (e.g.
`GLib.get_monotonic_time()`, wall-clock values, or `monotonic_us=…` /
`t=%lld` placeholders used only to correlate order). Log output
already includes a time prefix from the logging pipeline or
application; repeating time in the message is redundant and clutters
logs.

**IMPORTANT:** **Debugging is output, not new program structure.** Strongly avoid adding instance fields, static counters, extra parameters, flags, or branches whose **only** purpose is to support, sample, gate, or **reduce the volume of** debug output. Prefer placing `GLib.debug()` at **important existing points** in the real control flow (after a substantive call, before return, at a real phase boundary) and logging values already in scope. Do **not** add logic solely to make logs “sparse” or quieter—use logging controls instead. When you must choose between **more `GLib.debug()` lines** and **extra code** whose only job is to conditionalize or throttle those lines, add the lines unconditionally.

**WARNING (strict — do not repeat this mistake):** Do **not** introduce **sampling**, **throttling**, **gating**, or **“every Nth”** behaviour to control how much debug runs. That includes: counters, `i % N == 0`, boundary-crossing arithmetic (`len / 8192 != …`), locals like `crossed_*` used only around `GLib.debug()`, or `if (verbose)` flags whose only job is to skip logs. **Debug volume is not a problem to solve in code.** Operators disable or enable debug via the logging pipeline (`--debug`, `G_MESSAGES_DEBUG`, domains, build flags, or removing lines later)—**never** implement “sparse” debug inside the application. Prefer **unconditional** `GLib.debug()` at **fixed semantic sites** (real phase boundaries). Verbose logs in hot paths are acceptable; gating them is not. Violating this rule has wasted real debugging time; treat it as prohibited unless the user explicitly approves an exception.

**IMPORTANT:** When adding debugging, pick **meaningful** places (substantive calls, phase boundaries, returns)—preferably a **small number of high-value** `GLib.debug()` lines in one change, not noise on every line. That is **not** permission to throttle: do **not** gate or sample to stay under a numeric cap. If many lines are genuinely needed, add them unconditionally and rely on log controls to turn output off later.

**IMPORTANT:** For CLI/example apps, route debug output through the
standard `--debug` option handled by the app/test base classes. Do
not require `G_MESSAGES_DEBUG`, and do not add ad-hoc stdout/stderr
debug output when `GLib.debug()` is sufficient.

**Also Bad (redundant time in the message):**
```vala
GLib.debug("monotonic_us=%lld queueProject path=%s", GLib.get_monotonic_time(), path);
```

**Good (same intent, no duplicate time):**
```vala
GLib.debug("queueProject path=%s", path);
```

**Bad:**
```vala
GLib.debug("[Client.models] Starting models() call");
GLib.warning("SkillRunner.fill_model: Failed to customize model");
GLib.debug("[BaseCall.parse_models_array] Called for %s", call_type);
GLib.debug("[ChatInput.update_models] Got %d models", count);
```

**Also Bad (too many debug statements):**
```vala
GLib.debug("Starting function");
GLib.debug("Got input: %s", input);
GLib.debug("Processing item 1");
GLib.debug("Processing item 2");
GLib.debug("Processing item 3");
GLib.debug("Finished processing");
GLib.debug("Returning result");
```

**Bad (debug-only control flow — prohibited):**
```vala
this.feed_diag_n++;
if (this.feed_diag_n % 32 == 0) { GLib.debug("…"); }
// or: len_before / 8192 != len_after / 8192 solely to gate GLib.debug()
// or: bool crossed = … only used for if (crossed) { GLib.debug(…); }
```

**Good:**
```vala
GLib.debug("Starting models() call");
GLib.debug("Called for %s", call_type);
GLib.debug("Got %d models", count);
```

**Also Good (targeted single debug):**
```vala
GLib.debug("Model '%s' not found in available_models (current: '%s', available: %d)", 
	this.client.model, this.client.model, this.client.available_models.size);
```

The debug output will automatically show the file and line number (and typically a time prefix), so you don't need to include that information in the message itself.

**Same rule for GLib.warning():** Never include class or method names (e.g. `"MyClass.method_name:"`). Use a short, user- or operator-friendly phrase; file and line are in the log. Do not add redundant timestamps to the message text.


## Gee.HashMap Access <!-- section: gee-hashmap-access -->

**IMPORTANT:** Always use `.set()` and `.get()` methods for `Gee.HashMap` operations instead of array-style accessors (`[]`). This is more explicit and consistent with the API.

**Bad:**
```vala
var map = new Gee.HashMap<string, File>();
map[key] = value;
var item = map[key];
```

**Good:**
```vala
var map = new Gee.HashMap<string, File>();
map.set(key, value);
var item = map.get(key);
```

**Also Good (for checking existence):**
```vala
if (map.has_key(key)) {
    var item = map.get(key);
}
```

**Also Good (for removal):**
```vala
map.unset(key);
```

## Gee.ArrayList Access <!-- section: gee-arraylist-access -->

**IMPORTANT:** Always use `.set()` and `.get()` methods for `Gee.ArrayList` operations instead of array-style accessors (`[]`). This is more explicit and consistent with the API.

**Bad:**
```vala
var list = new Gee.ArrayList<string>();
list[0] = "value";
var item = list[0];
```

**Good:**
```vala
var list = new Gee.ArrayList<string>();
list.set(0, "value");
var item = list.get(0);
```

**Also Good (for iteration):**
```vala
for (int i = 0; i < list.size; i++) {
    var item = list.get(i);
    // process item
}
```

**Also Good (for adding/removing):**
```vala
list.add(item);
list.remove_at(index);
```

## SQL Table Aliases <!-- section: sql-table-aliases -->

**IMPORTANT:** Do NOT use table aliases in SQL queries. Always use full table names. This improves readability and avoids confusion.

**Bad:**
```vala
var sql = "SELECT DISTINCT vm.vector_id FROM vector_metadata vm WHERE vm.file_id IN (1, 2, 3)";
```

**Good:**
```vala
var sql = "SELECT DISTINCT vector_id FROM vector_metadata WHERE file_id IN (1, 2, 3)";
```

**Also Bad (with JOINs):**
```vala
var sql = "SELECT f.path, vm.vector_id FROM vector_metadata vm JOIN filebase f ON vm.file_id = f.id";
```

**Also Good (with JOINs, no aliases):**
```vala
var sql = "SELECT filebase.path, vector_metadata.vector_id FROM vector_metadata JOIN filebase ON vector_metadata.file_id = filebase.id";
```

## Building Strings in Loops <!-- section: building-strings-in-loops -->

**CRITICAL - FORBIDDEN:** Do NOT build strings inside a loop by repeated concatenation (e.g. `s += "x"` or `prefix += "> "` in a for-loop). Use built-in fill or join methods instead.

**CRITICAL:** Use `string.nfill(n, c)` for a single character repeated; for a multi-character unit use `string.nfill(n, 'X').replace("X", "unit")` or similar. Use `string.joinv(sep, array)` when joining an array. Never accumulate a string with `+=` in a loop.

**Bad:**
```vala
string prefix = "";
for (uint i = 0; i < this.level; i++) {
    prefix += "> ";
}
return prefix + inner;
```

**Good:**
```vala
var prefix = string.nfill((int)this.level, 'X').replace("X", "> ");
return prefix + inner;
```

**Also Good (when you have an array to join):**
```vala
var parts = new string[this.level];
for (int i = 0; i < this.level; i++) {
    parts[i] = "> ";
}
var prefix = string.joinv("", parts);
```
Prefer `nfill` + `replace` when the repeated unit is a fixed string; use `joinv` when the parts vary.

## Character Looping <!-- section: character-looping -->

**CRITICAL - FORBIDDEN:** Do NOT loop through strings character by character unless there is **absolutely 100% no other way** to do it. **Always** check string methods and regex first — only use character loops when every other option has been ruled out.

**CRITICAL:** This includes:
- `for (int i = 0; i < str.length; i++)` loops accessing `str[i]`
- `while` loops with character indexing
- Any iteration that accesses individual characters via indexing
- Character-by-character processing in any form

Character looping is extremely inefficient and error-prone. Prefer string library methods and regex.

**CRITICAL:** Before writing any character-by-character loop:
1. Check the GLib string library (`GLib.String`) for methods that do what you need.
2. Check whether a regex (`GLib.Regex`) can match or extract what you need.
3. Only if there is genuinely no string method and no regex that can do it, consider a character loop — and document why.

Common string operations:
- `contains()`, `has_prefix()`, `has_suffix()` - pattern matching
- `split()`, `split_set()` - splitting strings
- `replace()`, `replace_set()` - replacing substrings
- `strip()`, `chomp()` - trimming whitespace
- `up()`, `down()` - case conversion
- `substring()` - extracting substrings
- `index_of()`, `last_index_of()` - finding positions
- `slice()` - extracting ranges

**Bad:**
```vala
for (int i = 0; i < str.length; i++) {
    if (str[i] == '#') {
        level++;
    } else {
        break;
    }
}
```

**Good:**
```vala
// Use regex to replace leading # characters and check length difference
var regex = new GLib.Regex("^#+");
var without_hash = regex.replace(str, 0, "", 0);
var level = str.length - without_hash.length;
```

**Also Good (using regex match):**
```vala
// Use regex to find the match and get its length
var regex = new GLib.Regex("^#+");
GLib.MatchInfo match_info;
if (regex.match(str, 0, out match_info)) {
    var match = match_info.fetch(0);
    var level = match.length;
} else {
    var level = 0;
}
```

**Also Bad:**
```vala
string result = "";
for (int i = 0; i < str.length; i++) {
    if (str[i] != ' ') {
        result += str[i];
    }
}
```

**Good:**
```vala
var result = str.replace(" ", "");
```

## String Array Operations <!-- section: string-array-operations -->

**IMPORTANT:** Never loop over a string array to build another string array. Use Vala's array slicing syntax with `string.joinv()` instead.

**Bad:**
```vala
var result_lines = new Gee.ArrayList<string>();
for (int i = start_line; i <= end_line; i++) {
    result_lines.add(lines[i]);
}
return string.joinv("\n", result_lines.to_array());
```

**Good:**
```vala
return string.joinv("\n", lines[start_line:end_line+1]);
```

Note: Array slicing uses `[start:end]` where `end` is exclusive, so use `end_line+1` to include the end line.

## StringBuilder Usage <!-- section: stringbuilder-usage -->

**IMPORTANT:** Only use `GLib.StringBuilder` when frequently building and rebuilding strings in loops with **hundreds** of iterations (not tens). For general string concatenation, use normal string concatenation with `+` operator or `string.joinv()` instead. StringBuilder should only be used when there is a distinct performance advantage from avoiding repeated string allocations.

**IMPORTANT:** Do NOT use StringBuilder for:
- Simple string concatenation (use `+` operator)
- Joining a small number of strings (use `+` operator)
- Reading a few to dozens of lines from input (use `string.joinv()` with a `string[]` array)
- Any loop with fewer than hundreds of iterations

**Bad:**
```vala
var builder = new GLib.StringBuilder();
builder.append("Hello");
builder.append(" ");
builder.append("World");
var result = builder.str;
```

**Also Bad (reading stdin - typically only dozens of lines, not hundreds):**
```vala
var lines = new GLib.StringBuilder();
string? line;
while ((line = GLib.stdin.read_line()) != null) {
    if (lines.len > 0) {
        lines.append_c('\n');
    }
    lines.append(line);
}
var result = lines.str;
```

**Good:**
```vala
var result = "Hello" + " " + "World";
```

**Also Good (reading stdin with plain string concatenation - don't build array just to join):**
```vala
string result = "";
string? line;
while ((line = GLib.stdin.read_line()) != null) {
    result += line + "\n";
}
result = result.strip(); // Remove trailing newline
```

**Exception (StringBuilder only for hundreds of iterations):**
```vala
// Only use StringBuilder when you have hundreds of iterations
// Example: Processing thousands of log entries, building very large reports
var builder = new GLib.StringBuilder();
for (int i = 0; i < 1000; i++) {
    builder.append(process_item(i));
    builder.append_c('\n');
}
var result = builder.str;
```

## ArrayList for Strings <!-- section: arraylist-for-strings -->

**IMPORTANT:** Never use `Gee.ArrayList<string>` when building an array of strings just to join it. 

**STRICT — String array initialization:** When you declare a string array that you will grow with `+=`, initialize it **only** as `string[] name = {}`. Do **not** use `var name = new string[0]` or any other form. The empty array literal `{}` is the required form.

**Bad (string array init):**
```vala
var parts = new string[0];
string[] parts = new string[0];
```

**Good (string array init):**
```vala
string[] parts = {};
```

**IMPORTANT:** If you're building an array of strings **only** to join it, use plain string concatenation instead. Do NOT build an array just to join it - use string concatenation directly.

**IMPORTANT:** Only use `string[]` arrays when:
- You already have an array and need to join it (use `string.joinv()` with existing array)
- You need the array for other purposes besides joining
- You're using array slicing on an existing array

**Bad:**
```vala
var query_parts = new Gee.ArrayList<string>();
for (int i = 1; i < args.length; i++) {
    query_parts.add(args[i]);
}
var result = string.joinv(" ", query_parts.to_array());
```

**Also Bad (building array just to join it):**
```vala
string[] query_parts = {};
string? line;
while ((line = GLib.stdin.read_line()) != null) {
    query_parts += line;
}
var result = string.joinv("\n", query_parts);
```

**Good (using plain string concatenation when building just to join):**
```vala
string result = "";
string? line;
bool first = true;
while ((line = GLib.stdin.read_line()) != null) {
    if (!first) {
        result += "\n";
    }
    result += line;
    first = false;
}
```

**Also Good (using existing array with string.joinv):**
```vala
// args is already an array - use it directly with array slicing
var result = string.joinv(" ", args[1:args.length]);
```

**Also Good (when you need the array for other purposes):**
```vala
// If you need the array for filtering, processing, etc., then building it is OK
string[] lines = {};
string? line;
while ((line = GLib.stdin.read_line()) != null) {
    if (line.has_prefix("#")) {
        continue; // Skip comments
    }
    lines += line;
}
// Now we use it for joining AND we filtered it, so array is justified
var result = string.joinv("\n", lines);
```

## Signal handlers in construct blocks <!-- section: signal-handlers-construct -->

**CRITICAL:** Do **not** add private methods such as `on_hello`, `on_shutdown`, or `handle_*` solely to connect GObject/RPC signals. Wire handlers **inline** in the class `construct` block with a lambda/closure. Extracting a method is the **user’s** decision, not the LLM’s — especially for short RPC `rpc_*` signal handlers that only reply on the session.

**Bad:**
```vala
construct {
    this.rpc_hello.connect(this.on_hello);
}

private void on_hello(Request request) {
    request.session.reply(request, this);
}
```

**Good:**
```vala
construct {
    this.rpc_hello.connect((request) => {
        request.session.reply(request, this);
    });
}
```

## Property Getters vs Get Methods <!-- section: property-getters-vs-get-methods -->

**IMPORTANT:** Generally avoid `get_*()` method names. They conflict with Vala/GLib conventions (e.g. property getters expose `get_*` in C), are redundant when a verb-less or action name works (e.g. `system_message()` instead of `get_system_message()`), and encourage wasteful wrappers. Prefer: (1) **properties** with `get; private set;` or `get; set;` for simple or computed values; (2) **verb-less or action method names** for methods that build or compute something (e.g. `system_message()`, `user_prompt()`, `project_manager` property). Only use a `get_*()` name when the operation clearly requires parameters and “get” is the natural verb (e.g. `get_file_by_path(string path)`).

**Bad:**
```vala
public class MyClass
{
    private string name;
    
    public string get_name()
    {
        return this.name;
    }
    
    public ProjectManager get_project_manager()
    {
        if (this.cached_manager != null) {
            return this.cached_manager;
        }
        return this.create_manager();
    }
}
```

**Good:**
```vala
public class MyClass
{
    public string name { get; private set; }
    
    public ProjectManager project_manager {
        get {
            if (this.cached_manager != null) {
                return this.cached_manager;
            }
            return this.create_manager();
        }
    }
}
```

**Also Good (for computed properties with simple logic):**
```vala
public class MyClass
{
    private ProjectManager? cached_manager = null;
    
    public ProjectManager project_manager {
        get {
            if (this.cached_manager == null) {
                this.cached_manager = this.create_manager();
            }
            return this.cached_manager;
        }
    }
}
```

**Exception (use get_* method when operation requires parameters):**
```vala
public class MyClass
{
    // This is OK - requires a parameter
    public File? get_file_by_path(string path)
    {
        return this.files.get(path);
    }
}
```

## Method names and new methods <!-- section: method-names-new-methods -->

**IMPORTANT:** Prefer **short, concise** method and **property** names. Avoid long, narrative names that restate what the file or type already implies. Rule of thumb: **one word ideal, two okay, three risky, four you messed up** — context in the class name should carry the rest.

**Bad (four words; type already says “model usage” and “factory”):**
```vala
public int max_name_width_chars { get; construct; default = -1; }
```

**Better:**
```vala
public int max_chars { get; construct; default = -1; }
```

**IMPORTANT:** **Do not add new methods** unless the **user** or the **written plan** explicitly asks for one. Default to putting logic in an **existing** method or location the task already touches. Do **not** introduce a “helper” or `merge_*` / `build_*` method because it seems tidy — the **user** decides if extraction is appropriate.

**IMPORTANT:** If a change can be done by a few lines inside **`get_request_body()`**, **`serialize_property()`**, or another existing entry point, do that first. Only when the user approves a new method should you add one, and then keep the name **short**.

**Bad (long name; also assumes new method without user approval):**
```vala
private void merge_reasoning_effort_into_object(Json.Object obj)
```

**Better (still only if user approves a helper — shorter name):**
```vala
private void merge_reasoning(Json.Object obj)
```

**Often better (no new method — inline in existing `get_request_body()` until user asks otherwise):**
```vala
// inside get_request_body(), after building obj:
obj.set_string_member("reasoning_effort",
    this.reasoning_effort != "" ? this.reasoning_effort : (this.think ? "medium" : "none"));
```

## Agent compliance gate (mandatory before finishing Vala work) <!-- section: agent-compliance-gate -->

**AI agents:** Partial compliance is a violation. Use
**`docs/coding-standards-router.md`** to pick sections; read only those blocks
here (grep `section: <slug>`). Universal slugs plus scenario matches apply to
every task; see router.

### Before the first edit

1. Complete **`docs/coding-standards-router.md`** — universal table (question
   per row: locals, `this.`, `else`, enums, guards, new methods) plus scenario
   rows that apply.
2. Read every section slug in your set (grep `section: <slug>`; full block).
3. List the slugs you read before implementing.

### Before marking the task done

Re-scan your diff against the universal **“STOP if you…”** column (especially:
explicit type on locals, new private methods, gratuitous `else`). Then:

Run these checks on **every file you changed**. Fix violations; do not hand-wave.

| Check | How |
|-------|-----|
| **`var` on locals** | Search: `^\s+(string\|int\|bool\|uint\|int64)\s+\w+\s*[=;]` — no local matches except `string[] … = {}` |
| **No new private methods** | Diff adds no `private`/`protected` method unless user or plan asked |
| **No `handle_*` for signals** | Button/signal handlers inline in lambda, not new `handle_*` methods |
| **No gratuitous `else`** | New `else` / `else if` chains restructure to early return/`continue` |
| **Enum branches use `switch`** | Multi-value response/status checks use `switch`, not `\|\|` chains |
| **No defensive re-checks** | No duplicate validation after a module boundary already enforced it |
| **Debug text** | No class/method names in `GLib.debug()` / `GLib.warning()` messages |
| **Docblocks** | New/changed APIs have multiline `/** … */` with `@param` where needed |

If you skipped any row because you "already knew" the rule, **stop and run it
anyway**. Agents repeatedly miss rules they did not verify in the diff.

### Why agents fail this document

Reading once without **verification** is the same as skimming. The gate above
is part of the standard — not optional process advice.

