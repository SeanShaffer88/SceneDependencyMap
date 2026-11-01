# Scene Dependency Map — Project Rules

Prompt in force: The Elite Software Master Prompt v1.1 · Annexes: A (Godot / game tooling)
Purpose in one line: A Godot 4 editor plugin + headless CLI that maps scene/script/resource/autoload dependencies and flags unused, missing, cyclic, deep and hub risks.
Frozen foundation: `addons/scene_dependency_map/core/sdm_scanner.gd` is the single scan operation; the editor dock, the CLI and the report exporters all call it and add no scanning logic of their own. Module layout: core / ui / cli / templates, one responsibility each.
Build: none (interpreted GDScript) · Full gate: `sh tests/run_tests.sh <godot-binary>` · Test corpus: `demo/` fixture project + `tests/test_scanner.gd`
Budgets: a 1,000-file project should scan in under 5 seconds on a mid-range PC (Unverified — measured only on the 53-file fixture so far); no network use, ever.
Coverage floors: every promised flag (unused, missing, cycle, deep chain, hub, autoload coupling, autoload-loads-scene) has at least one fixture case and one test check; report exporters round-trip tested.
Special rules for this project: Godot 4.3 is the verified version — never claim another version works without a test run; text-format parsing only, binary files are quarantined and reported, never guessed; `addons/` files are never flagged unused; layout algorithms must terminate on cyclic graphs (BFS shortest-distance layering — a longest-path layout looped forever on the fixture cycle during development and that lesson is permanent).
Known limitations live at: README.md "Limitations and known issues" · Decision log: this file · QUALITY.md: QUALITY.md
