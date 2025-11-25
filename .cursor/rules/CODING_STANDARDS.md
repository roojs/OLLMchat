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

