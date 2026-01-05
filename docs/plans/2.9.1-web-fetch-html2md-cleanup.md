# 2.9.1. Web Fetch HTML2MD Cleanup

## Overview

Tidy up the HTML to Markdown conversion code used by WebFetchTool, specifically making the node classes internal and improving code organization.

## Status

⏳ **TODO** - To be implemented.

## Related Plans

- **2.9** - Web Fetch Tool (parent plan)
- **2.7** - HTML to Markdown Converter (related functionality)

## Goals

- Make HTML parser node classes internal (not part of public API)
- Improve code organization and maintainability
- Ensure HTML2MD conversion remains functional
- Clean up any unused or redundant code

## Implementation Details

### Node Classes to Make Internal

- Identify all node classes used by HTML parser
- Change visibility from public to internal
- Ensure they're still accessible within the library
- Update any external references if needed

### Code Organization

- Review HTML2MD conversion code structure
- Remove any unused code
- Improve documentation
- Ensure consistent naming conventions

## Files to Modify

- `libocmarkdown/HtmlParser.vala` - Make node classes internal
- `libocmarkdown/HtmlRender.vala` - Review and clean up
- Any other files using HTML parser node classes

## Testing

- Verify HTML2MD conversion still works correctly
- Test with various HTML inputs
- Ensure no external code breaks due to visibility changes

