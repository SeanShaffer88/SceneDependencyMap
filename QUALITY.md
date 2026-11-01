# Scene Dependency Map — quality scorecard

Gate rule: any Fail = not done. Evidence is the full gate run on Godot 4.3.stable in this repo (`sh tests/run_tests.sh`): **31/31 checks passed**, CLI produced all three reports, `--fail-on=missing,cycles` exited 2 as designed, and a headless editor import loaded the plugin and fixture (Godot's own loader independently reported the fixture's cycle as "Busy" parse errors and its two missing files — the same problems the scanner flags).

| Dimension | Score (0–5) | Evidence |
|---|---|---|
| Correctness of analysis | 5 | Every promised flag has a fixture case and a passing check; two false-positive classes found by inspecting real output (folder-string literals, duplicate missing entries) were fixed and the gate re-run |
| Robustness | 4 | Unreadable/binary files are quarantined into a reported errors list, never silently dropped; layout uses BFS so cycles cannot loop it (a longest-path layout did loop during development — found, fixed, and the fixture cycle is now a permanent regression case). Large-project behaviour untested |
| Test coverage | 4 | 31 checks over scan, analysis and all three exporters, plus import + CLI + exit-code steps in the gate script. Editor UI interaction is not automated |
| Documentation | 5 | README follows the full structure checklist; install, CLI options, dependency rules, troubleshooting and limitations are all stated from the code as built |
| Usability | 4 | Auto-scan on open, tooltips on every control, plain-words help dialog, search/type/risk filters in dock and HTML. Hands-on editor feel Unverified |
| Performance | 3 | 53-file fixture scans in about a second headless; the 1,000-file budget in PROJECT_RULES.md is Unverified |
| Honesty of scope | 5 | Binary scenes, C# contents, uid:// refs and run-time-built paths are declared limitations in the README, not silent gaps |

**Total: 30/35 (86/100 scaled) — no dimension below 3, no Fail.**

Open follow-ups: hands-on Windows editor session (dock interaction + the three README captures); scan a large real project for the performance budget; Godot 4.2 confirmation run.
