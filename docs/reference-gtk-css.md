# GTK CSS Reference

This document provides a reference for valid CSS properties and values in GTK4.

## Official Documentation

- **GTK CSS Properties**: https://docs.gtk.org/gtk4/css-properties.html
- **GTK CSS Overview**: https://docs.gtk.org/gtk4/css-overview.html

## Common CSS Properties

### Layout & Sizing

| Property | Valid Values | Notes |
|----------|-------------|-------|
| `width` | `<length>`, `<percentage>`, `auto` | e.g., `200px`, `50%`, `auto` |
| `height` | `<length>`, `<percentage>`, `auto` | e.g., `200px`, `50%`, `auto` |
| `min-width` | `<length>`, `<percentage>`, `0` | e.g., `100px`, `0` |
| `max-width` | `<length>`, `<percentage>`, `none` | e.g., `500px`, `100%`, `none` |
| `min-height` | `<length>`, `<percentage>`, `0` | e.g., `100px`, `0` |
| `max-height` | `<length>`, `<percentage>`, `none` | e.g., `500px`, `100%`, `none` |
| `margin` | `<length>`, `<percentage>` | Shorthand for all margins |
| `margin-top` | `<length>`, `<percentage>` | |
| `margin-right` | `<length>`, `<percentage>` | |
| `margin-bottom` | `<length>`, `<percentage>` | |
| `margin-start` | `<length>`, `<percentage>` | GTK-specific (respects RTL) |
| `margin-end` | `<length>`, `<percentage>` | GTK-specific (respects RTL) |
| `padding` | `<length>`, `<percentage>` | Shorthand for all padding |
| `padding-top` | `<length>`, `<percentage>` | |
| `padding-right` | `<length>`, `<percentage>` | |
| `padding-bottom` | `<length>`, `<percentage>` | |
| `padding-start` | `<length>`, `<percentage>` | GTK-specific (respects RTL) |
| `padding-end` | `<length>`, `<percentage>` | GTK-specific (respects RTL) |

### Colors & Backgrounds

| Property | Valid Values | Notes |
|----------|-------------|-------|
| `background-color` | `<color>` | e.g., `#ffffff`, `rgb(255,0,0)`, `white` |
| `color` | `<color>` | Text color |
| `opacity` | `<number>` (0.0-1.0) | e.g., `0.5` for 50% opacity |

**GTK Color Functions:**
- `@theme_text_color` - Theme's text color
- `@theme_bg_color` - Theme's background color
- `@theme_fg_color` - Theme's foreground color
- `shade(color, factor)` - Lighten/darken a color (factor > 1.0 lightens, < 1.0 darkens)
- `mix(color1, color2, factor)` - Mix two colors (factor 0.0-1.0)
- `alpha(color, alpha)` - Set alpha channel (0.0-1.0)

**Color Formats:**
- Hex: `#RRGGBB`, `#RRGGBBAA`
- RGB: `rgb(r, g, b)`, `rgba(r, g, b, a)`
- Named colors: `white`, `black`, `red`, etc.

### Borders

| Property | Valid Values | Notes |
|----------|-------------|-------|
| `border` | Shorthand for border-width, style, color | |
| `border-width` | `<length>` | e.g., `1px`, `2px` |
| `border-style` | `none`, `solid`, `dashed`, `dotted` | |
| `border-color` | `<color>` | |
| `border-radius` | `<length>` | e.g., `4px`, `8px` |
| `border-top` | Shorthand | |
| `border-right` | Shorthand | |
| `border-bottom` | Shorthand | |
| `border-left` | Shorthand | |

### Typography

| Property | Valid Values | Notes |
|----------|-------------|-------|
| `font-family` | Font name or family | e.g., `monospace`, `Sans`, `serif` |
| `font-size` | `<length>`, `<percentage>`, `<relative-size>` | e.g., `12px`, `1.2em`, `0.9em` |
| `font-weight` | `normal`, `bold`, `100-900` | |
| `font-style` | `normal`, `italic`, `oblique` | |
| `text-decoration` | `none`, `underline`, `line-through` | |
| `text-align` | `left`, `right`, `center`, `justify` | |

### Transformations

| Property | Valid Values | Notes |
|----------|-------------|-------|
| `transform` | `scale(x)`, `scale(x, y)`, `translate(x, y)`, `rotate(angle)` | e.g., `scale(0.7)`, `translate(10px, 5px)` |
| `transform-origin` | `center`, `top`, `bottom`, `left`, `right`, or coordinates | e.g., `center`, `top left` |

### Shadows & Effects

| Property | Valid Values | Notes |
|----------|-------------|-------|
| `box-shadow` | `offset-x offset-y blur-radius color` | e.g., `0 2px 4px rgba(0,0,0,0.3)` |
| `outline` | Shorthand for outline-width, style, color | |
| `outline-color` | `<color>` | |
| `outline-width` | `<length>` | |
| `outline-style` | `none`, `solid`, `dashed`, `dotted` | |

### Cursor

| Property | Valid Values | Notes |
|----------|-------------|-------|
| `cursor` | `default`, `pointer`, `text`, `wait`, `help`, etc. | Standard CSS cursor values |

### Display & Visibility

| Property | Valid Values | Notes |
|----------|-------------|-------|
| `visibility` | `visible`, `hidden` | |
| `opacity` | `<number>` (0.0-1.0) | |

## GTK-Specific Properties

GTK CSS supports properties prefixed with `-gtk-` for GTK-specific features:

| Property | Description | Notes |
|----------|-------------|-------|
| `-gtk-icon-effect` | Icon effects | e.g., `none`, `highlight` |
| `-gtk-icon-shadow` | Icon shadow | |
| `-gtk-icon-palette` | Icon color palette | |
| `-gtk-icon-style` | Icon style | |

See the [official GTK CSS Properties documentation](https://docs.gtk.org/gtk4/css-properties.html) for a complete list.

## Widget Selectors

GTK CSS uses widget names as selectors:

- `entry` - Text entry widget
- `button` - Button widget
- `label` - Label widget
- `popover` - Popover widget
- `listview` - List view widget
- `row` - List row widget
- `scrolledwindow` - Scrolled window widget
- `textview` - Text view widget
- `box` - Box container
- `frame` - Frame widget
- `viewport` - Viewport widget

## CSS Classes

You can add CSS classes to widgets using `add_css_class()`:

```vala
widget.add_css_class("my-class");
```

Then style them in CSS:

```css
.my-class {
  background-color: red;
}
```

## Pseudo-classes

GTK CSS supports some pseudo-classes:

- `:hover` - When mouse is over the widget
- `:active` - When widget is active/pressed
- `:focus` - When widget has focus
- `:selected` - When item is selected (for list items)
- `:disabled` - When widget is disabled
- `:checked` - When checkbox/radio is checked

## Child Selectors

- `>` - Direct child selector
- ` ` (space) - Descendant selector

Example:
```css
popover.menu > scrolledwindow {
  padding: 0;
}

popover.menu listview > row {
  padding: 8px;
}
```

## Units

GTK CSS supports standard CSS units:

- `px` - Pixels
- `em` - Relative to font size
- `rem` - Relative to root font size
- `%` - Percentage
- `pt` - Points
- `in`, `cm`, `mm` - Physical units

## Examples from This Codebase

### Popover Styling
```css
popover.menu {
  margin-top: 6px;
  padding: 0;
  min-width: 0;
}
```

### Button Scaling
```css
.oc-user-sent-frame button {
  transform: scale(0.7);
  transform-origin: center;
}
```

### Theme-Aware Colors
```css
popover.menu listview > row:selected {
  color: @theme_text_color;
  background-color: shade(#f6f5f4, 0.97);
}
```

### Border Styling
```css
.oc-user-sent-frame {
  border-radius: 8px;
  border: 3px solid #3584E4;
  box-shadow: 0 2px 4px rgba(53, 132, 228, 0.3);
}
```

## Notes

- GTK CSS is similar to web CSS but not identical
- Some web CSS properties may not be supported
- Always refer to the [official GTK documentation](https://docs.gtk.org/gtk4/css-properties.html) for definitive information
- GTK-specific functions like `shade()` and theme color references like `@theme_text_color` are GTK extensions
- Widget names are used as element selectors (e.g., `entry`, `button`)
