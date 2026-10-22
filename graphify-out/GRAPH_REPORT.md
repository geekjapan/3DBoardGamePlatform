# Graph Report - 3DBoardGamePlatform  (2026-10-23)

## Corpus Check
- 26 semantic source files; AST status: extracted. Exclusions and reuse evidence: build-audit.json.

## Summary
- 121 nodes · 140 edges · 32 communities (15 shown, 17 thin omitted)
- Extraction: 100% EXTRACTED · 0% INFERRED · 0% AMBIGUOUS
- Token usage: per-project usage unavailable (native Codex semantic extraction).

## Graph Freshness
- Built from commit: `67e41707`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- pmx_to_vrm.py
- batch_pmx_to_vrm.py
- verify.sh
- 3DBoardGamePlatform
- Piece
- Verification map
- VRM addon for Godot
- VRM addon for Godot
- Agent instructions
- Game selection
- verify-3dboardgame
- Third-party notices
- Chess piece movement
- Match start
- Godot headless tests
- fake_usi_engine.sh
- Team editor
- Match settings
- GDScript language server
- fake_uci_engine.sh
- run.sh
- Small purple bone-shaped icon
- Bone constraint icon
- Godot 4 selection
- VRM canonical format
- External UCI engine
- Domain documentation
- GitHub issue tracker
- Triage labels
- VRM model import
- USI soak-test plan
- USI coverage assessment

## God Nodes (most connected - your core abstractions)
1. `verify.sh script` - 9 edges
2. `main()` - 7 edges
3. `cmd_launch()` - 7 edges
4. `main()` - 6 edges
5. `cmd_doctor()` - 6 edges
6. `3DBoardGamePlatform` - 6 edges
7. `main()` - 5 edges
8. `die()` - 5 edges
9. `require_state()` - 5 edges
10. `rpc()` - 5 edges

## Surprising Connections (you probably didn't know these)
- `argv()` --calls--> `sys`  [EXTRACTED]
  tools/batch_pmx_to_vrm.py →   _Bridges community 1 → community 0_

## Import Cycles
- None detected.

## Communities (32 total, 17 thin omitted)

### Community 0 - "pmx_to_vrm.py"
Cohesion: 0.20
Nodes (7): main(), argv(), enable_addons(), main(), mesh_height(), missing_required_bones(), normalize_height()

### Community 1 - "batch_pmx_to_vrm.py"
Cohesion: 0.24
Nodes (7): argv(), convert(), main(), mesh_height(), pick_sources(), reset_scene(), slugify()

### Community 2 - "verify.sh"
Cohesion: 0.44
Nodes (12): cmd_cleanup(), cmd_doctor(), cmd_launch(), die(), evidence_path(), parse_flag(), require_state(), resolve_godot() (+4 more)

### Community 3 - "3DBoardGamePlatform"
Cohesion: 0.29
Nodes (7): 3DBoardGamePlatform, Chess, Godot 4.7.1, Shogi, Speech modes, UCI, USI

### Community 4 - "Piece"
Cohesion: 0.33
Nodes (6): Character, GameEvent, Piece, Shogi drops and promotion, SpeechMode, Team

### Community 5 - "Verification map"
Cohesion: 0.33
Nodes (6): Game selection, Match start, Piece movement, Settings, Team editor, Verification map

### Community 6 - "VRM addon for Godot"
Cohesion: 0.40
Nodes (5): Head hiding, MToon, SkeletonModifier3D, VRM 1.0, VRM addon for Godot

### Community 7 - "VRM addon for Godot"
Cohesion: 0.50
Nodes (4): glTF 2.0, MToon, VRM 1.0, VRM addon for Godot

### Community 8 - "Agent instructions"
Cohesion: 0.50
Nodes (4): Agent instructions, Domain docs, GitHub Issues, Triage labels

### Community 9 - "Game selection"
Cohesion: 0.50
Nodes (4): Chess, Game selection, Saved game settings, Shogi

### Community 10 - "verify-3dboardgame"
Cohesion: 0.50
Nodes (4): Evidence, Isolated user data, Mouse-driven verification, verify-3dboardgame

### Community 11 - "Third-party notices"
Cohesion: 0.50
Nodes (4): Godot MToon Shader, Local model assets, Third-party notices, VRM addon

### Community 12 - "Chess piece movement"
Cohesion: 0.67
Nodes (3): Chess piece movement, e2-e4, Turn switching

### Community 13 - "Match start"
Cohesion: 0.67
Nodes (3): Match start, Team selection, Two-player mode

### Community 14 - "Godot headless tests"
Cohesion: 0.67
Nodes (3): Apery material engine, Godot headless tests, USI soak diagnostics

## Knowledge Gaps
- **58 isolated node(s):** `Bone constraint icon`, `Head hiding`, `MToon`, `SkeletonModifier3D`, `VRM 1.0` (+53 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 69 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **17 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **What connects `Bone constraint icon`, `Head hiding`, `MToon` to the rest of the system?**
  _58 weakly-connected nodes found - possible documentation gaps or missing edges._