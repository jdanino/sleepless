#!/bin/bash
# Builds and runs the tests. It links the real source files, minus main.swift,
# which holds the top-level code of the app.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$HERE/build"
SOURCES=()
for f in "$HERE"/src/*.swift; do
  [ "$(basename "$f")" = "main.swift" ] && continue
  SOURCES+=("$f")
done
swiftc -o "$HERE/build/tests" "${SOURCES[@]}" "$HERE/tests/main.swift"
"$HERE/build/tests"
