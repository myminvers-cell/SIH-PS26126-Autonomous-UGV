# SIH PS 26126: Vision Based Autonomous Navigation for UGV

This is a **Demonstration Prototype** for the Smart India Hackathon (SIH) Problem Statement **26126**:
*"Vision Based Autonomous Navigation for Unmanned Ground Vehicle for Outdoor environment"*

## Overview

This project provides a complete, lightweight 3D simulation of an autonomous Unmanned Ground Vehicle (UGV) designed to run on low-end hardware without requiring a dedicated GPU or external frameworks like ROS. It simulates:
- **Simulated Visual Odometry** (GPS-denied localization).
- **Environment Perception** using multi-ray forward scanning for obstacle detection.
- **Cost Map-Based Path Planning** with 8-directional A* algorithm.
- **Dynamic Replanning** and **Stuck Recovery** behaviors.

## System Requirements
- **OS**: Windows (64-bit)
- **CPU**: Intel Core i5-4440S or better
- **RAM**: 8 GB
- **GPU**: Intel HD Graphics 4600 (or any GPU supporting OpenGL 3.3 / Compatibility mode)
- **Software**: Godot Engine 4.x (Tested on 4.7.2)

> **Note**: This prototype is entirely self-contained. It does **not** require CUDA, YOLO, ROS, MATLAB, or Simulink.

## How to Run
1. Ensure you have [Godot Engine 4.7.2](https://godotengine.org/download/) installed (or you can use the provided `godot.exe` if present in the project folder).
2. Double-click the `run.bat` or `run_prototype.bat` script to launch the simulation.
   - Alternatively, open the project in Godot Engine and press **F5** to run the `Main.tscn` scene.

## Architecture & Modules

| Module | Script | Description |
|---|---|---|
| **UGV** | `UGV.gd` | Handles physical movement, state machine (NAVIGATING, AVOIDING, etc.), stuck recovery. |
| **A* Planner** | `AStarPlanner.gd` | Computes the optimal path from A to B considering terrain cost and obstacles. |
| **Cost Map** | `CostMap.gd` | 60x60 grid representation of the environment, used by the planner. |
| **Perception** | `Perception.gd` | AI simulated forward camera; scans for obstacles and determines distance/type. |
| **Localization** | `Localization.gd` | Simulates odometry to estimate position without GPS. |
| **Obstacle Manager** | `ObstacleManager.gd` | Handles procedural environment generation and dynamic obstacle spawning. |

## Controls

| Action | Control / UI Element |
|---|---|
| **Toggle Autonomy** | `MODE` Button |
| **Start Navigation** | `START AUTONOMY` Button |
| **Stop Navigation** | `STOP` Button |
| **Inject Obstacle** | `SPAWN OBSTACLE` Button (spawns an obstacle in the UGV's path) |
| **Force Replan** | `FORCE REPLAN` Button |
| **Reset Scenario** | `RESET SCENARIO` Button |
| **Manual Drive** | `W, A, S, D` or `Arrow Keys` (only when in MANUAL mode) |
| **Change Camera** | `Camera Mode` Dropdown (Chase, Front, Top-Down) |

## Demonstration Flow
1. The UGV starts at **Point A**.
2. An initial route is calculated to **Point B** through a field of rocks, trees, and ditches.
3. Once **START AUTONOMY** is pressed, the UGV follows the path.
4. Clicking **SPAWN OBSTACLE** injects a dynamic red obstacle directly into the UGV's path.
5. The **Perception** system detects the blockage, stops the UGV, and triggers **REPLANNING**.
6. A new route is calculated, and the UGV successfully maneuvers around the obstacle to reach **Point B**.

## Disclaimer
This is a **Demonstration Prototype** designed solely to illustrate the conceptual logic of vision-based navigation, pathfinding, and obstacle avoidance. It is not a production UGV system.

## License
MIT License
