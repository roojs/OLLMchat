#!/bin/bash
#
# Curl script for testing analysis API call
# Usage: ./test-curl.sh [api_key]
# Modify test-curl-body.txt to change settings (temperature, num_ctx, model, etc.)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BODY_FILE="${SCRIPT_DIR}/test-curl-body.txt"

if [ ! -f "$BODY_FILE" ]; then
  echo "Error: Request body file not found: $BODY_FILE"
  exit 1
fi

curl -X POST "https://ollama.roojs.com/api/chat" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer " \
  -d "@${BODY_FILE}" \
  --silent \
  --show-error

