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

