# Coding Standards

## Checklist for all plans

Before marking a plan as ready to implement, make sure it answers these:

- **Nullable types**: Are new APIs and properties designed to avoid nullable types where possible (using default objects/flags instead)?
- **Null checks**: Does the plan avoid adding generic null checks, and only use them where the design explicitly requires null?
- **String interpolation**: Does the plan avoid `@"..."` string interpolation except for multi-line usage/help text or documentation?
- **Temporary variables**: Does the plan avoid introducing one-use temporaries or trivial aliases when describing new code?
- **Brace placement**: Does the plan keep brace style consistent (line breaks for namespaces/classes/methods, inline for control structures)?
- **`this.` prefix**: Does the plan assume/describe using `this.` for instance members in new/modified Vala code?
- **GLib prefix & using statements**: Does the plan require fully-qualified `GLib.*` and avoid `using` imports for new code?
- **Property initialization**: Are new properties initialized with defaults (`get; set; default =` or field defaults) instead of constructors?
- **Line length & breaking**: Does the plan call out breaking long lines (method calls, concatenations) for readability where relevant?
- **StringBuilder usage**: Does the plan avoid `GLib.StringBuilder` unless building strings in loops with hundreds of iterations? Does it use `string.joinv()` for joining arrays and `+` for simple concatenation?
- **ArrayList for strings**: Does the plan avoid `Gee.ArrayList<string>` when building arrays of strings just to join them? Does it use `string[]` arrays instead?

These checklist items should be copied (or referenced) at the top of new plan documents in `docs/plans/` so they can be quickly verified.

## String Interpolation

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

## Temporary Variables

**IMPORTANT:** Avoid single-use temporary variables. If a variable is only used once, inline it directly.

**IMPORTANT:** Avoid temporary variables that are just pointers to object properties. Access the property directly instead.

**IMPORTANT:** Avoid simple aliased variables and trivial aliases. If a variable is just an alias for a property or method result that's used once or trivially, inline it instead.

**EXCEPTION:** Long property chains (4+ properties deep) may be aliased into a local variable for readability. This exception applies when accessing deeply nested properties like `agent.session.manager.permission_provider`.

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

## Brace Placement

**IMPORTANT:** Use line breaks for braces in namespaces, classes, and methods. Do NOT use line breaks for braces in control structures (if, case, switch, while, for, etc.).

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

## This Prefix

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

## Reducing Nesting

**IMPORTANT:** Avoid nested code by using early returns, break/continue statements, and avoiding else clauses when possible. This improves readability and reduces cognitive complexity.

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

## GLib Namespace Prefix

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

## Using Statements

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

## Switch/Case vs If/Else If

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

## Property Initialization

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

## Serializable Classes

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

## Avoiding Nullable Types

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

## Null Checks

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

## Line Length and Breaking

**IMPORTANT:** Avoid creating long lines. Break lines for readability:
- **Always break on `(`** when function calls or method invocations are long
- **Break on `+`** when string concatenation creates long lines
- **If arguments are broken**, put each argument on its own line

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

## Debug Statements

**IMPORTANT:** When adding debug output using `GLib.debug()`, do NOT prefix the message with function names, class names, or location information. The debug output system already includes the filename and line number automatically, making such prefixes redundant.

**IMPORTANT:** When asked to add debugging, use at most 3-4 debug statements, preferably just one targeted debug statement. Avoid "splattering" debug statements everywhere - be selective and focus on the key points that will help diagnose the issue.

**Bad:**
```vala
GLib.debug("[Client.models] Starting models() call");
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

The debug output will automatically show the file and line number, so you don't need to include that information in the message itself.


## Gee.HashMap Access

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

## Gee.ArrayList Access

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

## SQL Table Aliases

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

## Character Looping

**CRITICAL - FORBIDDEN:** Do NOT loop through strings character by character. **ANY kind of character looping is FORBIDDEN unless specifically requested.** This includes:
- `for (int i = 0; i < str.length; i++)` loops accessing `str[i]`
- `while` loops with character indexing
- Any iteration that accesses individual characters via indexing
- Character-by-character processing in any form

This is extremely inefficient and error-prone. Always use string library methods instead.

**CRITICAL:** Before writing any character-by-character loop, examine the GLib string library (`GLib.String`) to find appropriate methods. Common operations:
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

## String Array Operations

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

## StringBuilder Usage

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

## ArrayList for Strings

**IMPORTANT:** Never use `Gee.ArrayList<string>` when building an array of strings just to join it. 

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

## Property Getters vs Get Methods

**IMPORTANT:** Avoid `get_*()` methods for simple property access. Use property getters with `get; private set;` or `get; set;` instead. Only use `get_*()` methods when the operation is complex, involves computation, or requires parameters.

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

