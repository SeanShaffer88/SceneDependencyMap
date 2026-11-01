#!/bin/sh
# Full gate for Scene Dependency Map. Usage: sh tests/run_tests.sh [godot-binary]
set -e
GODOT="${1:-godot}"
cd "$(dirname "$0")/.."
echo "== import (validates every demo scene/script parses in Godot) =="
"$GODOT" --headless --path . --import --quit-after 5
echo "== scanner test suite =="
"$GODOT" --headless --path . --script res://tests/test_scanner.gd
echo "== CLI scan (all formats) =="
"$GODOT" --headless --path . --script res://addons/scene_dependency_map/cli/sdm_cli.gd -- --out=res://dependency_reports
test -s dependency_reports/dependency_map.json
test -s dependency_reports/dependency_report.md
test -s dependency_reports/dependency_map.html
grep -q "old_enemy.tscn" dependency_reports/dependency_report.md
grep -q "ghost.svg" dependency_reports/dependency_map.json
echo "== CLI CI gate: --fail-on missing,cycles must exit 2 on the demo fixture =="
if "$GODOT" --headless --path . --script res://addons/scene_dependency_map/cli/sdm_cli.gd -- --fail-on=missing,cycles; then
  echo "FAIL: expected exit 2 from --fail-on gate"
  exit 1
else
  code=$?
  [ "$code" -eq 2 ] || { echo "FAIL: expected exit 2, got $code"; exit 1; }
fi
echo "ALL GATE CHECKS PASSED"
