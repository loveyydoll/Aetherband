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

DESKTOP_PROJECT="$ROOT/apps/desktop/RouletteStudio.Desktop/RouletteStudio.Desktop.csproj"
if [[ -f "$DESKTOP_PROJECT" ]]; then
  echo "== .NET: restore and build desktop app =="
  dotnet restore "$DESKTOP_PROJECT"
  dotnet build "$DESKTOP_PROJECT" --no-restore --configuration Debug
else
  echo "WARNING: Desktop .csproj not found; .NET build skipped." >&2
fi

mapfile -t TEST_PROJECTS < <(find "$ROOT" -type f -name "*Tests.csproj" -not -path "*/bin/*" -not -path "*/obj/*" | sort)
if ((${#TEST_PROJECTS[@]})); then
  for project in "${TEST_PROJECTS[@]}"; do
    echo "== .NET tests: $project =="
    dotnet test "$project" --configuration Debug
  done
else
  echo "No *Tests.csproj projects found; .NET test step skipped."
fi

echo "Verification commands completed successfully."
