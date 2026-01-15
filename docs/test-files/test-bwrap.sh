#!/bin/bash
# Test script for bubblewrap overlay functionality
# This tests the exact command structure that Bubble.build_bubble_args() generates

# Clean up from previous runs
rm -rf /home/alan/test/test-overlay-project
rm -rf /home/alan/test/overlay-upper
rm -rf /home/alan/test/overlay-work

# Create test project directory
mkdir -p /home/alan/test/test-overlay-project
echo "original content" > /home/alan/test/test-overlay-project/test.txt

# Create overlay directories (what Overlay.create() does)
mkdir -p /home/alan/test/overlay-upper/overlay1
mkdir -p /home/alan/test/overlay-work/work1

# Test bubblewrap command with overlay
# This matches what Bubble.build_bubble_args() generates:
bwrap \
  --unshare-user \
  --tmpfs /tmp \
  --ro-bind / / \
  --dir /home/alan/test/test-overlay-project \
  --overlay-src /home/alan/test/test-overlay-project \
  --overlay /home/alan/test/overlay-upper/overlay1 /home/alan/test/overlay-work/work1 /home/alan/test/test-overlay-project \
  --unshare-net \
  -- \
  /bin/sh \
  -c \
  "cd /home/alan/test/test-overlay-project && echo 'new content' > test.txt && cat test.txt"

echo ""
echo "--- Checking results ---"
echo "Original file content:"
cat /home/alan/test/test-overlay-project/test.txt
echo ""
echo "Overlay upper directory contents:"
ls -la /home/alan/test/overlay-upper/overlay1/
