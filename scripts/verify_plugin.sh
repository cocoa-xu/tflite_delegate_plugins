#!/usr/bin/env bash
# Checks that a built plugin exports the delegate plugin ABI and nothing else,
# and that it pulled in no dependency it should not have. Run on every target in
# CI: a plugin that exports its whole static half works locally and collides in
# a host process that already has TFLite in it.
set -euo pipefail

PLUGIN="${1:?usage: verify_plugin.sh <plugin>}"
[ -f "$PLUGIN" ] || { echo "no such file: $PLUGIN"; exit 1; }

fail=0
note() { printf '  %-8s %s\n' "$1" "$2"; }

echo "verifying $(basename "$PLUGIN")"

case "$(uname -s)" in
  Darwin)
    exported=$(nm -gU "$PLUGIN" | grep -v ' U ' | awk '{print $3}' | sort)
    expected=$'_tflite_plugin_create_delegate\n_tflite_plugin_destroy_delegate'
    deps=$(otool -L "$PLUGIN" | tail -n +2 | awk '{print $1}')
    bad_deps=$(echo "$deps" | grep -vE '^(/usr/lib/|/System/Library/Frameworks/)' | grep -v "$(basename "$PLUGIN")" || true)
    ;;
  Linux)
    exported=$(nm -D --defined-only "$PLUGIN" | awk '$2 ~ /^[TW]$/ {print $3}' | sed 's/@@.*//' | sort)
    expected=$'tflite_plugin_create_delegate\ntflite_plugin_destroy_delegate'
    deps=$(${OBJDUMP:-objdump} -p "$PLUGIN" | awk '/NEEDED/ {print $2}')
    bad_deps=$(echo "$deps" | grep -vE '^(libstdc\+\+|libm|libgcc_s|libc|libdl|libpthread|librt|ld-linux)' || true)
    ;;
  *) echo "unsupported platform"; exit 1 ;;
esac

if [ "$exported" = "$expected" ]; then
  note "symbols" "exactly the two plugin entry points"
else
  note "symbols" "UNEXPECTED export surface:"
  echo "$exported" | sed 's/^/             /'
  fail=1
fi

# OpenCL and Metal are reached through dlopen and the framework loader, so a
# link-time dependency on either means the plugin will not load on a machine
# that lacks it -- exactly the machines it has to fail gracefully on.
if [ -n "$bad_deps" ]; then
  note "deps" "unexpected runtime dependencies:"
  echo "$bad_deps" | sed 's/^/             /'
  fail=1
else
  note "deps" "system libraries only"
fi

exit $fail
