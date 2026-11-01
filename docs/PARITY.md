# Scene Dependency Map — capability parity

Scored only from test/corpus evidence. The three surfaces (editor dock, headless CLI, HTML export) all run the same core scan operation, so analysis results are identical by construction; this matrix tracks which surface *presents* each capability.

| Capability | Editor dock | CLI | HTML export | Evidence |
|---|---|---|---|---|
| Full project scan (scenes/scripts/resources/assets) | Yes | Yes | data only | 31-check suite, Godot 4.3 |
| Autoload map from project.godot | Yes | Yes | Yes | suite: 3 autoloads + paths verified |
| Unused files (orphan + dead cluster) | Yes | Yes (counts + `--fail-on=unused`) | Yes | suite checks on fixture |
| Missing files | Yes | Yes (`--fail-on=missing`, exit 2 verified) | Yes | suite + gate script |
| Dependency cycles (Tarjan SCC) | Yes | Yes (`--fail-on=cycles`, exit 2 verified) | Yes | live + dead fixture cycles |
| Deep chains | Yes | Yes (`--fail-on=deep`, `--deep=<n>`) | Yes | 14-step fixture chain |
| Hub files (fan-in / fan-out) | Yes | Yes (`--fail-on=hubs`) | Yes | GameState hub check |
| Autoload coupling + autoload-loads-scene | Yes | Yes (count) | Yes | hud.gd + audio_bus.gd checks |
| Visual graph | Yes (GraphEdit, layered) | No | Yes (layered SVG, search + risk filter) | editor import loads plugin; HTML content checks |
| Click node → depends-on / depended-on-by | Yes | No | Yes | code inspection (editor interaction Unverified hands-on) |
| Open file from map/list | Yes (double-click) | No | No | code inspection (Unverified hands-on) |
| Search / type filter / risks-only | Yes | n/a | Yes (search + risks-only) | code inspection |
| JSON export | Yes | Yes | embedded | suite: JSON parses back |
| Markdown report | Yes | Yes | No | suite content checks |
| Built-in plain-words help | Yes (`?` dialog) | `--help` pointer | in-page labels | code inspection |

Unverified on a real machine: hands-on editor interaction (dock clicks, double-click opening, GraphEdit feel) and scan performance on a large (1,000+ file) project.
