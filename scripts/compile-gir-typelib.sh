#!/bin/sh
# Fix cross-library GIR type names, add missing <include> entries, compile typelib.
set -e
gir_in="$1"
gir_fixed="$2"
typelib_out="$3"
fix_sed="$4"
shift 4
sed -f "$fix_sed" "$gir_in" | sed '/<include name="OLLMchat" version="1.0"\/>/{
a <include name="OLLMfiles" version="1.0"/>
}' > "$gir_fixed"
g-ir-compiler "$gir_fixed" --output "$typelib_out" "$@"
