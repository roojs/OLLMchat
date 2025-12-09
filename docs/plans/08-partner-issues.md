# Partner Issues - CSS Styling and Frame Classes

## Issues Addressed

### Issue 255: CSS Class Names for Frames
**Status:** Implemented

- Updated user message frames to use CSS class matching the chat role name (`user-sent`)
- Updated code block frames to use `blockcode-frame` CSS class
- This allows better styling control and matches the semantic meaning of the content

**Changes:**
- `ChatView.vala`: Changed `user-message-box` to `user-sent` CSS class
- `RenderSourceView.vala`: Changed `code-block-box` to `blockcode-frame` CSS class
- `ChatView.vala` (tool messages): Updated to use `blockcode-frame` for consistency

### Issue 191: Border and Shadow Styling for User Messages
**Status:** Implemented

- Added border and box-shadow styling for user-sent messages using color `#3584E4`
- Border: 2px solid #3584E4
- Box shadow: 0 2px 4px rgba(53, 132, 228, 0.3)

**CSS Implementation:**
```css
.user-sent {
  border-radius: 8px;
  border: 2px solid #3584E4;
  box-shadow: 0 2px 4px rgba(53, 132, 228, 0.3);
}
```

### Issue 127: Blockcode Frame Styling
**Status:** Implemented

- Created `blockcode-frame` CSS class for code block frames
- Maintains existing border-radius and background styling
- Provides consistent styling for all code-related frames

**CSS Implementation:**
```css
.blockcode-frame {
  border-radius: 8px;
}

.blockcode-frame text {
  background-color: white;
}
```

## Additional Notes

- User mentioned sorting sgap / folders/ocript, config etc. - this appears to be a separate organizational task
- All frame styling now uses semantic CSS class names that match their content type
- The `#3584E4` color provides a clear visual distinction for user-sent messages

## Files Modified

1. `libollmchatgtk/ChatView.vala` - Updated user message frame CSS class
2. `libocmarkdowngtk/RenderSourceView.vala` - Updated code block frame CSS class
3. `resources/style.css` - Added styling for `user-sent` and `blockcode-frame` classes
