# 1.15. URGENT - Truncate Web Fetch Responses

## Overview

By default, web fetch responses should be truncated to the first 200 lines. When the markdown version is fetched, a truncation indicator should be added at the end to inform the LLM that the content has been truncated.

Additionally, relative links in HTML should be resolved to absolute URLs during the HTML-to-markdown conversion process, so that links in the markdown output are usable.

## Status

⏳ **TODO** - Not yet implemented.

## Problem

Web pages can be very long, and sending the entire content to the LLM can:
- Consume excessive tokens
- Slow down processing
- Include irrelevant content that distracts from the main information
- Hit token limits for very long pages

The LLM typically only needs the beginning of a web page to understand its content, as most important information is usually at the top.

Additionally, relative links in HTML (e.g., `href="/page.html"` or `href="../other.html"`) are not useful in the markdown output because they lack the base URL context. These should be resolved to absolute URLs (e.g., `https://example.com/page.html`) so the LLM can access the linked resources.

## Solution

1. Truncate web fetch responses to the first 200 lines by default. When the format is "markdown" (the default), append a truncation indicator at the end to inform the LLM that the content has been truncated.

2. Resolve relative links to absolute URLs during HTML-to-markdown conversion. This needs to be implemented in the html2md code (`libocmarkdown/HtmlParser.vala` and `libocmarkdown/Tags.vala`).

## Implementation Details

### Phase 1: Add Truncation Logic to RequestWebFetch

#### File: `liboctools/RequestWebFetch.vala`

Add a method to truncate content to the first N lines and append a truncation indicator:

```vala
/**
 * Truncate content to the first N lines and append truncation indicator.
 * 
 * @param content The full content string
 * @param max_lines Maximum number of lines to keep (default: 200)
 * @return Truncated content with indicator appended if truncation occurred
 */
protected string truncate_content(string content, int max_lines = 200)
{
    var lines = content.split("\n");
    
    // If content is already within limit, return as-is
    if (lines.length <= max_lines) {
        return content;
    }
    
    // Truncate to first max_lines
    var truncated = new StringBuilder();
    for (int i = 0; i < max_lines; i++) {
        truncated.append(lines[i]);
        if (i < max_lines - 1) {
            truncated.append("\n");
        }
    }
    
    // Append truncation indicator
    truncated.append("\n\n---\n");
    truncated.append("_Content truncated to first " + max_lines.to_string() + " lines. " + 
                     (lines.length - max_lines).to_string() + " more lines available._");
    
    return truncated.str;
}
```

### Phase 2: Apply Truncation in convert_content Method

Modify the `convert_content` method to apply truncation when format is "markdown":

```vala
protected string convert_content(Bytes content, string content_type)
{
    // ... existing content type detection logic ...
    
    // After conversion, apply truncation for markdown format
    string result;
    
    // Normalize content type to lowercase for comparison
    var normalized_type = content_type.down();
    
    // Content-Type starts with "image/" → always base64 (regardless of format parameter)
    if (normalized_type.has_prefix("image/")) {
        this.format = "base64";
        result = this.convert_to_base64(content);
        return result; // Don't truncate base64
    }
    
    // Content-Type is "text/html" → handle based on format parameter
    if (normalized_type == "text/html") {
        switch (this.format) {
            case "raw":
                this.format = "raw";
                result = (string)content.get_data();
                break;
            case "base64":
            case "markdown":
            default:
                this.format = "markdown";
                result = this.convert_html_to_markdown(content);
                // Apply truncation for markdown
                if (this.format == "markdown") {
                    result = this.truncate_content(result);
                }
                return result;
        }
    }
    
    // Content-Type starts with "text/" (non-HTML) → return raw text
    if (normalized_type.has_prefix("text/")) {
        this.format = "raw";
        result = (string)content.get_data();
        // Apply truncation if format is markdown (though this shouldn't happen for text/)
        if (this.format == "markdown") {
            result = this.truncate_content(result);
        }
        return result;
    }
    
    // Content-Type is "application/json" → return raw JSON
    if (normalized_type == "application/json") {
        this.format = "raw";
        result = (string)content.get_data();
        return result; // Don't truncate JSON
    }
    
    // Content-Type is anything else → base64
    this.format = "base64";
    result = this.convert_to_base64(content);
    return result; // Don't truncate base64
}
```

**Note**: Actually, we should apply truncation specifically when `this.format == "markdown"` after all conversions are done, regardless of content type (except base64 which shouldn't be truncated). Let's refactor to apply truncation at the end:

```vala
protected string convert_content(Bytes content, string content_type)
{
    // Normalize content type to lowercase for comparison
    var normalized_type = content_type.down();
    
    string result;
    
    // Content-Type starts with "image/" → always base64 (regardless of format parameter)
    if (normalized_type.has_prefix("image/")) {
        this.format = "base64";
        return this.convert_to_base64(content);
    }
    
    // Content-Type is "text/html" → handle based on format parameter
    if (normalized_type == "text/html") {
        switch (this.format) {
            case "raw":
                this.format = "raw";
                result = (string)content.get_data();
                break;
            case "base64":
            case "markdown":
            default:
                this.format = "markdown";
                result = this.convert_html_to_markdown(content);
                break;
        }
    }
    // Content-Type starts with "text/" (non-HTML) → return raw text
    else if (normalized_type.has_prefix("text/")) {
        this.format = "raw";
        result = (string)content.get_data();
    }
    // Content-Type is "application/json" → return raw JSON
    else if (normalized_type == "application/json") {
        this.format = "raw";
        result = (string)content.get_data();
    }
    // Content-Type is anything else → base64
    else {
        this.format = "base64";
        return this.convert_to_base64(content);
    }
    
    // Apply truncation for markdown format (after all conversions)
    if (this.format == "markdown") {
        result = this.truncate_content(result);
    }
    
    return result;
}
```

### Phase 3: Resolve Relative Links in HTML-to-Markdown Conversion

#### File: `libocmarkdown/HtmlParser.vala`

Add a `base_url` property to `HtmlParser` to store the base URL for resolving relative links:

```vala
public class HtmlParser : Object
{
    // ... existing properties ...
    
    /**
     * Base URL for resolving relative links.
     * If set, relative URLs in href attributes will be resolved to absolute URLs.
     */
    public string? base_url { get; set; default = null; }
    
    /**
     * Constructor.
     *
     * @param html Input HTML string to convert
     * @param base_url Optional base URL for resolving relative links
     */
    public HtmlParser(string html, string? base_url = null)
    {
        this.html = html;
        this.base_url = base_url;
        this.tag_stack = new Gee.ArrayList<string>();
        this.initialize_tag_registry();
    }
    
    // ... rest of existing code ...
}
```

#### File: `libocmarkdown/Tags.vala`

Modify `TagAnchor` class to resolve relative URLs. The `HtmlParser` instance (`c`) is passed to the `close()` method, so we can access `c.base_url` directly:

```vala
public class TagAnchor : TagIgnored
{
    private string current_title = "";
    private string current_href = "";

    public TagAnchor(Writer writer)
    {
        base(writer);
    }

    public override void open(HtmlParser c)
    {
        if (c.prev_tag == "img") {
            this.writer.append("\n");
        }

        this.current_title = c.attr.has_key("title") ? c.attr.get("title") : "";
        this.writer.append("[");
        this.current_href = c.attr.has_key("href") ? c.attr.get("href") : "";
    }

    public override void close(HtmlParser c)
    {
        // Check if we need to shorten (if previous char is '[')
        if (this.writer.md.len > 0 && this.writer.md.str[this.writer.md.len - 1] == '[') {
            this.writer.shorten(1);
            return;
        }

        this.writer.append("](");
        
        // Resolve relative URLs to absolute URLs if base_url is set
        var resolved_href = this.current_href;
        if (c.base_url != null && c.base_url != "" && this.current_href != "") {
            resolved_href = this.resolve_relative_url(this.current_href, c.base_url);
        }
        
        this.writer.append(resolved_href);

        // If title is set append it
        if (this.current_title != "") {
            this.writer.append(" \"");
            this.writer.append(this.current_title);
            this.writer.append("\"");
            this.current_title = "";
        }

        this.writer.append(")");

        if (c.prev_tag == "img") {
            this.writer.append("\n");
        }
    }
    
    /**
     * Resolve a relative URL against a base URL.
     * 
     * @param relative_url The relative URL to resolve
     * @param base_url The base URL to resolve against
     * @return Absolute URL
     */
    private string resolve_relative_url(string relative_url, string base_url)
    {
        // If already absolute, return as-is
        if (relative_url.has_prefix("http://") || relative_url.has_prefix("https://") || 
            relative_url.has_prefix("mailto:") || relative_url.has_prefix("#")) {
            return relative_url;
        }
        
        try {
            var base_uri = GLib.Uri.parse(base_url, GLib.UriFlags.NONE);
            if (base_uri == null) {
                return relative_url; // Return original if base URL is invalid
            }
            
            var resolved_uri = base_uri.resolve_relative(relative_url);
            if (resolved_uri != null) {
                return resolved_uri.to_string();
            }
        } catch (GLib.Error e) {
            // If resolution fails, return original URL
        }
        
        return relative_url;
    }
}
```

Also update `TagImage` class to resolve relative URLs in `src` attributes:

```vala
public class TagImage : TagIgnored
{
    public TagImage(Writer writer)
    {
        base(writer);
    }

    public override void open(HtmlParser c)
    {
        if (c.prev_tag != "a" && this.writer.prev_ch_in_md != '\n') {
            this.writer.append("\n");
        }

        this.writer.append("![");
        this.writer.append(c.attr.has_key("alt") ? c.attr.get("alt") : "");
        this.writer.append("](");
        
        var src = c.attr.has_key("src") ? c.attr.get("src") : "";
        // Resolve relative URLs to absolute URLs if base_url is set
        var resolved_src = src;
        if (c.base_url != null && c.base_url != "" && src != "") {
            resolved_src = this.resolve_relative_url(src, c.base_url);
        }
        this.writer.append(resolved_src);

        var title = c.attr.has_key("title") ? c.attr.get("title") : "";
        if (title != "") {
            this.writer.append(" \"");
            this.writer.append(title);
            this.writer.append("\"");
        }

        this.writer.append(")");
    }

    public override void close(HtmlParser c)
    {
        if (c.prev_tag == "a") {
            this.writer.append("\n");
        }
    }
    
    /**
     * Resolve a relative URL against a base URL (same as TagAnchor).
     */
    private string resolve_relative_url(string relative_url, string base_url)
    {
        // If already absolute, return as-is
        if (relative_url.has_prefix("http://") || relative_url.has_prefix("https://") || 
            relative_url.has_prefix("mailto:") || relative_url.has_prefix("#")) {
            return relative_url;
        }
        
        try {
            var base_uri = GLib.Uri.parse(base_url, GLib.UriFlags.NONE);
            if (base_uri == null) {
                return relative_url;
            }
            
            var resolved_uri = base_uri.resolve_relative(relative_url);
            if (resolved_uri != null) {
                return resolved_uri.to_string();
            }
        } catch (GLib.Error e) {
            // If resolution fails, return original URL
        }
        
        return relative_url;
    }
}
```

#### File: `libocmarkdown/HtmlParser.vala`

The tag registry initialization doesn't need to change - `TagAnchor` and `TagImage` already receive the `HtmlParser` instance (`c`) as a parameter in their `open()` and `close()` methods, so they can access `c.base_url` directly. The existing initialization remains:

```vala
private void initialize_tag_registry()
{
    // ... existing tag registrations ...
    
    // No changes needed - TagAnchor and TagImage access base_url via the HtmlParser parameter
    this.tags.set("a", new TagAnchor(this.writer));
    this.tags.set("img", new TagImage(this.writer));
    
    // ... rest of existing code ...
}
```

#### File: `liboctools/RequestWebFetch.vala`

Update `convert_html_to_markdown` to pass the URL as base_url:

```vala
/**
 * Convert HTML content to markdown format.
 * 
 * @param html The HTML content as Bytes
 * @return Markdown string
 */
protected string convert_html_to_markdown(Bytes html)
{
    var parser = new Markdown.HtmlParser((string)html.get_data(), this.url);
    return parser.convert();
}
```

## Related Plans

- **2.9** - Web Fetch Tool (original implementation)
- **2.9.1** - Web Fetch HTML2MD Cleanup (related cleanup work)

## Files to Modify

1. `liboctools/RequestWebFetch.vala` - Add `truncate_content()` method, apply truncation in `convert_content()` when format is "markdown", and pass URL to HtmlParser for link resolution
2. `libocmarkdown/HtmlParser.vala` - Add `base_url` property and constructor parameter, update tag registry initialization
3. `libocmarkdown/Tags.vala` - Update `TagAnchor` and `TagImage` classes to resolve relative URLs using base_url

## Usage Example

### Truncation Example

After implementation, when fetching a web page that has 500 lines:

**Before truncation:**
```
[Full 500 lines of markdown content]
```

**After truncation:**
```
[First 200 lines of markdown content]

---
_Content truncated to first 200 lines. 300 more lines available._
```

### Link Resolution Example

**Before link resolution:**
If HTML contains: `<a href="/about.html">About</a>`
Markdown output: `[About](/about.html)`

**After link resolution:**
If fetching from `https://example.com/page.html` and HTML contains: `<a href="/about.html">About</a>`
Markdown output: `[About](https://example.com/about.html)`

**Relative path example:**
If HTML contains: `<a href="../other.html">Other</a>`
Markdown output: `[Other](https://example.com/other.html)` (resolved from base URL)

## Notes

### Truncation
- Default truncation limit: 200 lines
- Truncation only applies when `format == "markdown"` (the default)
- Base64 content is never truncated (binary data)
- Raw format is not truncated (user explicitly requested raw)
- JSON is not truncated (structured data should be complete)
- The truncation indicator clearly shows how many lines were removed
- Truncation happens after format conversion (e.g., after HTML→Markdown conversion)

### Link Resolution
- Link resolution happens during HTML-to-markdown conversion, not after
- Only relative URLs are resolved; absolute URLs (http://, https://, mailto:, #) are left unchanged
- Both anchor tags (`<a href="...">`) and image tags (`<img src="...">`) have their URLs resolved
- Uses `GLib.Uri.resolve_relative()` for proper URL resolution
- If base_url is not provided or URL resolution fails, the original URL is preserved
- The base_url is the URL that was fetched (available in `RequestWebFetch.url`)
