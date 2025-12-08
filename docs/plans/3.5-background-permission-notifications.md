# 3.5. Background Permission Notifications

## Overview

Handle permission requests from background tools when the window is not active. Use ADW (AdwMessageDialog or similar) message warning system to notify users.

## Status

⏳ **TODO** - To be implemented.

## Implementation Details

### Problem
- When a background tool asks for permission and the window is not active, user may miss the request
- Need a way to notify user even when window is not in focus

### Solution
- Use ADW (libadwaita) message/warning system
- Show notification when permission is requested in background
- Highlight the requesting tool/session
- Possibly use system notifications as well

### Features
- Detect when permission request occurs while window is inactive
- Show ADW message dialog/notification
- Highlight the session/tool requesting permission
- Allow user to respond to permission request from notification
- System notification integration (optional)

### Files to Create/Modify
- Permission request handling in `ChatPermission.ChatView`
- ADW message dialog integration
- Window focus detection
- Notification system

### Implementation Notes
- Research ADW message/warning APIs
- Detect window active/inactive state
- Design notification UI
- Handle multiple simultaneous permission requests
- Ensure notifications are dismissible and actionable
