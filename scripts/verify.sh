#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "== Rust: formatting =="
cargo fmt --all -- --check

echo "== Rust: workspace check =="
cargo check --workspace --all-targets

echo "== Rust: tests =="
cargo test --workspace --all-targets

FLUTTER_PROJECT="$ROOT/apps/desktop/pubspec.yaml"
if [[ -f "$FLUTTER_PROJECT" ]]; then
  pushd "$ROOT/apps/desktop" >/dev/null
  flutter pub get
  flutter analyze
  flutter test
  popd >/dev/null
else
  echo "WARNING: Flutter app not found at apps/desktop; Flutter checks skipped." >&2
fi
echo "Verification commands completed successfully."
