We need to modify the label on the frame (title_label) to ellipsize when the container is too small. In GTK, Gtk.Label has property "ellipsize" (Pango.EllipsizeMode). Also can set "max_width_chars" or "width_chars". To shrink the text, we can set ellipsize = Pango.EllipsizeMode.END and set "hexpand = true"? Actually we want the label to not cause horizontal scroll, so set ellipsize and maybe set "ellipsize" and "wrap" etc.

In code, title_label is created at lines 116-122. Need to add property ellipsize = Pango.EllipsizeMode.END and maybe set "max_width_chars = 30" or set "hexpand = true" to allow it to shrink. Title_label currently has hexpand = false. Changing to hexpand = true may allow expansion. But we might keep false but ellipsize ensures it truncates.

Implementation: modify title_label creation block.

Add property `ellipsize = Pango.EllipsizeMode.END` and maybe `max_width_chars = 0` (not needed). We'll edit lines 116-122.

We need to use edit_mode tool to edit file.

First, we need to read more lines after 122 maybe later code references title_label. Not needed.

We'll open edit mode for the file and replace lines 116-122 with updated version.

But need to include full block lines. We'll edit lines 116-122.

Let's produce code reference for original lines for context. Use CODE REFERENCE format.

We will then call edit_mode tool with modifications.


I'll add an ellipsis setting to the `Gtk.Label` that displays the language name. By setting the label's `ellipsize` property to `Pango.EllipsizeMode.END`, the text will be truncated with an ellipsis when the available width is insufficient, preventing a horizontal scrollbar.

**Current label creation (lines 116‑122):**

```startLine:endLine:filepath
116:             var title_label = new Gtk.Label(language_label_text) {
117:                 hexpand = false,
118:                 halign = Gtk.Align.START,
119:                 valign = Gtk.Align.CENTER,
120:                 margin_start = 5
121:             };
122:             title_label.add_css_class("oc-code-frame-title");
```

**Updated label creation:** we'll enable ellipsis and allow the label to expand horizontally.

```startLine:endLine:filepath
116:             var title_label = new Gtk.Label(language_label_text) {
117:                 hexpand = true,
118:                 halign = Gtk.Align.START,
119:                 valign = Gtk.Align.CENTER,
120:                 margin_start = 5,
121:                 ellipsize = Pango.EllipsizeMode.END
122:             };
123:             title_label.add_css_class("oc-code-frame-title");
```

I'll now apply this change using the edit mode tool.

Total Duration: 68.23s | Tokens In: 5818 Out: 689 | 32.00 t/s

```txt Edit Mode Activated
Edit mode activated for file: /home/alan/gitlive/OLLMchat/libocmarkdowngtk/RenderSourceView.vala
File status: exists
Project file: yes (auto-approved)
```

We need to output a code block with type vala (since file is Vala) and range. The original lines 116-122 we are replacing, but we also added a new line (123) which shifts later lines. So we need to replace from 116 to 123 (exclusive). That means start 116, end 124 (since exclusive). We'll provide new lines 116-124. Let's include the modified block.


```vala:116:124
            var title_label = new Gtk.Label(language_label_text) {
                hexpand = true,
                halign = Gtk.Align.START,
                valign = Gtk.Align.CENTER,
                margin_start = 5,
                ellipsize = Pango.EllipsizeMode.END
            };
            title_label.add_css_class("oc-code-frame-title");
```

```txt Applying Changes
Applying changes to file: /home/alan/gitlive/OLLMchat/libocmarkdowngtk/RenderSourceView.vala
Changes to apply: 1
Project file: yes
Mode: Line range edits
```

Total Duration: 7.67s | Tokens In: 6577 Out: 175 | 32.10 t/s
