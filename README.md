# SIH PS 26126: Vision Based Autonomous UGV Navigation

A Godot 4 3D driving and navigation prototype for the Smart India Hackathon problem statement **26126**. The scene combines autonomous UGV navigation with an Indian left-hand-drive road environment.

## World and gameplay

- A **1.2 km route** through a **1.28 km × 256 m** playable map.
- A broad, one-way **four-lane highway** with left-hand traffic, five town junctions, connecting service roads, and moving cross traffic.
- Procedural Indian-style shopfronts, bus shelters, streetlights, road signs, and lane markings.
- Moving cars, buses, delivery trucks, auto-rickshaws, motorcycles, and pedestrians. Traffic follows Indian left-hand-drive lanes, leaves safe gaps, yields at junctions, and uses the right-hand lane to pass. Vehicle impacts stop and visibly damage traffic cars; wrecks remain as hazards for the UGV and other traffic.
- A* route planning, simulated vision sensing, localization, collision-aware motion, traffic bypassing, and recovery behavior for the UGV.

## System requirements

These are **estimated targets** for the current GL Compatibility renderer and procedural scene. Actual frame rate depends on drivers and background applications.

| Target | CPU | Memory | Graphics | Resolution and frame rate |
|---|---|---:|---|---|
| Minimum | Modern 2-core x64 CPU, 3.0 GHz class | 4 GB RAM | OpenGL 3.3 compatible GPU, integrated or discrete, with 1 GB graphics memory or shared equivalent | 1280×720, low settings, target 30 FPS |
| Recommended | Modern 4-core x64 CPU, 3.5 GHz class | 8 GB RAM | Discrete GPU in the MX150 / RX 550 performance class or better, 2 GB VRAM | 1920×1080, medium settings, target 60 FPS |

**Development:** Godot Engine 4.7.2. Standalone game builds include the runtime and project resources, so players do not need Godot installed.

## Run

1. Run `run.bat` or `run_prototype.bat`, or open the project in Godot.
2. Press **F5** to start the main scene.
3. Press **START AUTONOMY** to drive the route, or select manual mode and use **W/A/S/D** or the arrow keys.

## Standalone game builds

- **Windows:** Run `builds/windows/SIH UGV.exe`. It is a single self-contained executable with the project data embedded; Godot is not required on the target PC.
- **Rebuild:** Run `build_game.ps1` from this project folder. Building requires Godot 4.7.2 and its matching Windows export template installed on the build PC. The packaged game itself has no Godot installation requirement.

## Controls

| Action | Control |
|---|---|
| Start autonomous driving | **START AUTONOMY** or **Space** |
| Stop | **STOP** |
| Manual / autonomous mode | **MODE** |
| Manual driving | **W/A/S/D** or arrow keys in manual mode |
| Force route recalculation | **FORCE REPLAN** |
| Reset route | **RESET** or **R** |
| Chase, front, top-down camera | Camera buttons or **1/2/3** |

## Architecture

| Module | Script | Purpose |
|---|---|---|
| UGV | `scripts/UGV.gd` | Vehicle physics, steering, collision response, traffic bypass, and navigation state machine. |
| A* planner | `scripts/AStarPlanner.gd` | Plans over the rectangular long-distance cost map. |
| Cost map | `scripts/CostMap.gd` | 64 × 320 cells at 4 m resolution, covering 256 m × 1280 m. |
| Traffic AI | `scripts/TrafficManager.gd` | Moving road users, lane following, safe-gap control, passing, and junction yielding. |
| Road and town | `scripts/RoadVisuals.gd` | Highway, service roads, junctions, buildings, lighting, materials, and reflection probes. |
| Perception | `scripts/Perception.gd` | Forward ray sensing and dynamic road-user detection. |
| Main scene | `scripts/Main.gd` | World setup, bounds, route, and subsystem connections. |

The project uses Godot's GL Compatibility renderer for wider hardware support, procedural PBR-style materials, and one-time local reflection probes of the static city and sky. It does not enable ray/path tracing or live screen-space reflections; Godot's built-in SSR is limited to Forward+, which needs a RenderingDevice-compatible graphics driver. It does not require CUDA, ROS, MATLAB, or Simulink.

## Disclaimer

This project is a demonstration prototype. Its simulated perception and navigation are not intended for real-world vehicle control.
