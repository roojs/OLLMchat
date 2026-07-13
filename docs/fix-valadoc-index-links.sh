#!/bin/sh
# Valadoc adds target="_blank" to any URL with a scheme. The package overview wiki
# uses full GitHub Pages URLs so links resolve in the summary body; this pass rewrites
# those internal links to same-directory relative hrefs (no new tab).
set -e
INDEX="$1"
if [ ! -f "$INDEX" ]; then
	echo "fix-valadoc-index-links: missing $INDEX" >&2
	exit 1
fi
perl -pi -e \
	's/href="https:\/\/roojs\.github\.io\/OLLMchat\/ollmchat\/([^"]+)" target="_blank"/href="$1"/g' \
	"$INDEX"
