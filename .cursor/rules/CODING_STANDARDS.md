# Coding Standards

## String Interpolation

**IMPORTANT:** Do NOT use `@"` string interpolation unless explicitly asked. Use normal string concatenation instead.

**Bad:**
```vala
var message = @"Error: Tool '$tool_name' not found";
```

**Good:**
```vala
var message = "Error: Tool '" + tool_name + "' not found";
```

## Temporary Variables

**IMPORTANT:** Avoid single-use temporary variables. If a variable is only used once, inline it directly.

**Bad:**
```vala
var width = this.scrolled_window.get_width();
if (width <= 1) {
    return;
}
var margin = this.text_view.margin_start;
this.calculate(margin);
```

**Good:**
```vala
if (this.scrolled_window.get_width() <= 1) {
    return;
}
this.calculate(this.text_view.margin_start);
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

