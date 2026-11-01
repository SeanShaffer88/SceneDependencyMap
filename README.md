# Scene Dependency Map

A Godot 4 editor plugin that draws a map of how your scenes, scripts, resources and autoloads connect — and flags unused files, missing files, dependency cycles, deep chains and risky hub files before they break your game.

## TL;DR

Think of your game as a town. Scenes, scripts, pictures and sounds are the houses, and the roads between them are "this file needs that file". This tool draws the whole town map for you. Houses nobody ever visits (unused files), roads that lead to a house that isn't there (missing files), and roads that go round in a circle (dependency cycles) are all marked in red, so you can fix them before they break your game.

## Key features

- **Visual map in the editor** — a dock with a graph: one box per file, one line per "depends on" link, layered from the main scene and autoloads outward. Click a box to see what it depends on and what depends on it; double-click a problem to open the file.
- **Unused file detection** — files that cannot be reached from the main scene or any autoload, split into *orphans* (nothing references them) and *dead clusters* (referenced only by other unreachable files). Files under `addons/` are never flagged — they are tooling, not game content.
- **Missing file detection** — references to files that do not exist, the breakage that usually surfaces at export or on a teammate's machine.
- **Cycle detection** — strongly-connected groups of files that depend on each other in a loop, including scene-instancing cycles Godot itself refuses to load.
- **Deep chain detection** — dependency chains longer than a threshold (default 8 steps): a break near the top cascades all the way down.
- **Hub detection** — files with many dependents (changing them is risky) and files with many dependencies (many things can break them).
- **Autoload analysis** — every autoload from `project.godot`, which scripts use which autoloads, scripts coupled to 3+ autoloads, and autoloads that pull in scenes (load-order risk).
- **Headless CLI with a CI gate** — the exact same scan from the command line, with `--fail-on=missing,cycles,...` exit codes so a broken map fails your build.
- **Three exports** — an interactive standalone HTML map (search, risk filter, click-for-details, works offline in any browser), a JSON data file, and a plain-words Markdown report.
- **Search and filters everywhere** — by name, by file type, and "risks only", in both the editor dock and the HTML map.
- **Built-in help** — the `?` button in the dock explains every flag in plain words, offline.

## Screenshots

Real captures are still to be taken on a Windows machine with the plugin installed in a real project. Capture list:

1. The Dependency Map dock after a scan, showing the layered graph and the problem list.
2. The dock with a hub file selected, showing its depends-on / depended-on-by details.
3. The exported HTML map in a browser with "risks only" turned on.

No placeholder images are used in the meantime.

## Requirements

- Godot **4.3** (verified). Godot 4.2 is expected to work — the APIs used (`GraphEdit`, `ConfigFile`, `RegEx`, `DirAccess`) are all present in 4.2 — but this is **to be confirmed** by a test run.
- No third-party dependencies. No network access is used at any point.

## Install

1. Copy the `addons/scene_dependency_map` folder into your project's `addons/` folder. (Or unzip `SceneDependencyMap-Addon-v1.0.0.zip` into your project root — it contains just that folder.)
2. In Godot: **Project → Project Settings → Plugins**, enable **Scene Dependency Map**.
3. The **Dependency Map** dock appears on the right and scans your project automatically. You can also re-scan from **Project → Tools → Scene Dependency Map: Scan Project**.

## How to use

### In the editor

1. Open the **Dependency Map** dock. The scan runs on its own.
2. Read the top line: file and link totals, then counts of unused, missing, cycles, deep chains and hubs.
3. Work the problem list from the top: missing files first (they break things), then cycles, then unused files.
4. Click any problem or graph box for details. Double-click to open the file.
5. Use the search box, the type filter and **Risks only** to cut a large project down to size.
6. **Export HTML / JSON / Report** saves into `res://dependency_reports/`.

Before deleting an "unused" file, check the one known blind spot: a file loaded only through a path built as a string while the game runs (for example `"res://levels/" + level_name + ".tscn"`) can look unused, because the full path never appears in any file. Plain string literals that name a complete `res://...` file *are* counted as references.

### From the command line (CI, scripts, pre-commit)

From your project root, with the addon installed:

```sh
godot --headless --path . --script res://addons/scene_dependency_map/cli/sdm_cli.gd -- [options]
```

| Option | Meaning |
|---|---|
| `--out=<dir>` | Output folder as a `res://` path (default `res://dependency_reports`) |
| `--format=json,md,html` | Which exports to write (default: all three) |
| `--deep=<n>` | Deep-chain threshold in steps (default 8) |
| `--fail-on=missing,cycles,unused,deep,hubs,errors` | Exit with code 2 if any listed problem is found |
| `--help` | Print a pointer to the option list |

Exit codes: `0` = clean or no `--fail-on` match · `2` = a `--fail-on` problem was found · `3` = the scan itself failed.

## What counts as a dependency

| Source file | Dependencies found |
|---|---|
| `.tscn` / `.tres` | Every `[ext_resource]` path (scenes instanced, scripts attached, textures, resources), plus any other complete `res://` file literal (exported properties) |
| `.gd` | `preload()` / `load()` paths (relative paths resolved), `extends "path"` and `extends ClassName` (via the project's `class_name` registry), autoload singleton use (`GameState.` etc.), complete `res://` string literals (probable dynamic loads) |
| `project.godot` | The main scene, the icon, and every autoload (autoloads and the main scene are the map's entry points) |
| `.import` | Registered as a node so imported assets are counted; adds no edges of its own |

Cycles are found with Tarjan's strongly-connected-components algorithm. Deep chains are the longest dependency path from each entry point. Reachability is a breadth-first walk from the entry points.

## This repo's layout

```
addons/scene_dependency_map/   the plugin (copy this into your project)
  plugin.cfg, plugin.gd        editor entry point
  core/sdm_scanner.gd          the scan operation (no editor APIs)
  core/sdm_report.gd           JSON / Markdown / HTML exporters
  ui/sdm_dock.gd               the editor dock (graph, problems, details)
  cli/sdm_cli.gd               headless command-line scan
  templates/report_template.html  standalone interactive HTML map
demo/                          a fixture project with deliberate problems
tests/test_scanner.gd          the test suite (scans the fixture)
tests/run_tests.sh             the full gate
project.godot                  the demo project (plugin enabled)
docs/PARITY.md                 capability matrix, scored from test evidence
QUALITY.md                     quality scorecard
PROJECT_RULES.md               project rule sheet
```

The root of this repo is itself a Godot project: open it and the dock scans the `demo/` fixture, which deliberately contains an unused scene/script/asset, a dead two-scene cycle, a live two-scene instancing cycle, a 14-step deep chain, a scene referencing two missing files, a hub autoload used by six scripts, a script coupled to three autoloads, and an autoload that preloads a scene.

## Tests

```sh
sh tests/run_tests.sh /path/to/godot
```

The gate imports the project (Godot itself then reports the fixture's cycle and missing files as engine errors — expected), runs the 31-check scanner suite, runs the CLI in all three formats, and verifies the `--fail-on` CI gate exits with code 2 on the fixture. Current status: **31/31 checks pass** on Godot 4.3.stable.

## Troubleshooting

- **A file I load at run time is flagged unused.** Its path is probably built from pieces at run time. Either load it once through a literal `preload()` somewhere reachable, or treat the flag as a prompt to check, not proof.
- **The dock is empty.** Project → Project Settings → Plugins: make sure the plugin is enabled, then press **↻ Scan project**.
- **Huge project, cluttered graph.** Use search, the type filter, and **Risks only**; or read the HTML export, which layers and filters the same data in a browser.
- **Binary `.scn` / `.res` files.** Their contents are not parsed in v1; the scan lists them under "files that could not be parsed" instead of guessing.

## Privacy and network behaviour

Everything runs locally, in the editor or headless Godot process. The tool reads your project files and writes only the reports you ask for, into your project. Nothing is uploaded, tracked, or sent anywhere. There are no accounts and no update checks.

## Limitations and known issues

- Text-format scenes and resources only; binary `.scn`/`.res` contents are reported as unparsed, never guessed.
- C# (`.cs`) files are classified as scripts and counted, but their contents are not parsed for references in v1.
- Run-time-built path strings cannot be followed (see Troubleshooting).
- `uid://` references are not graphed in v1.
- Graph layout in the dock and HTML is layered by shortest distance from an entry point; it is a working layout, not an auto-optimised diagram.
- Editor behaviour (dock interaction, double-click to open) is verified by code inspection and a headless editor import; a hands-on editor session on Windows is still owed — see `QUALITY.md`.

## License

MIT — see `LICENSE`.

## Credits

Built for Godot 4. Uses only the Godot engine's own APIs; no third-party code.
