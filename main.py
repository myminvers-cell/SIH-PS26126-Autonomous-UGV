import numpy as np
import matplotlib.pyplot as plt
from matplotlib.animation import FuncAnimation
from matplotlib.patches import Rectangle, Circle, Polygon
from matplotlib.widgets import Button
import heapq
import random
import math

# ============================================================
# SIH PROTOTYPE
# Adaptive Path Planning and Collision Avoidance
# for Autonomous Vehicles on Unstructured Indian Roads
# ============================================================

np.random.seed(7)
random.seed(7)

# -----------------------------
# WORLD
# -----------------------------

WORLD_W = 100
WORLD_H = 140

GRID = 2.0

GRID_W = int(WORLD_W / GRID)
GRID_H = int(WORLD_H / GRID)

DT = 0.15

MAX_SPEED = 12.0
MIN_SPEED = 0.0

VEHICLE_LENGTH = 4.0
VEHICLE_WIDTH = 2.0

SAFETY_RADIUS = 3.0

# -----------------------------
# ROAD
# -----------------------------

def road_center(y):
    return (
        50
        + 8 * np.sin(y / 16)
        + 3 * np.sin(y / 6)
    )


def road_width(y):
    return (
        34
        + 5 * np.sin(y / 13)
    )


def road_bounds(y):
    c = road_center(y)
    w = road_width(y)

    return c - w / 2, c + w / 2


def on_road(x, y):
    left, right = road_bounds(y)
    return left <= x <= right


# ============================================================
# OBSTACLES
# ============================================================

class Obstacle:

    def __init__(
        self,
        x,
        y,
        kind,
        radius,
        vx=0,
        vy=0
    ):

        self.x = x
        self.y = y

        self.kind = kind
        self.radius = radius

        self.vx = vx
        self.vy = vy

        self.initial_x = x
        self.initial_y = y

    def update(self):

        self.x += self.vx * DT
        self.y += self.vy * DT

        # Keep moving obstacles around road
        left, right = road_bounds(self.y)

        if self.x < left + 2:

            self.x = left + 2
            self.vx *= -1

        if self.x > right - 2:

            self.x = right - 2
            self.vx *= -1

        if self.y < 5:

            self.y = 5
            self.vy *= -1

        if self.y > WORLD_H - 5:

            self.y = WORLD_H - 5
            self.vy *= -1


# ============================================================
# AUTONOMOUS VEHICLE
# ============================================================

class AutonomousVehicle:

    def __init__(self):

        self.x = road_center(8)

        self.y = 8

        self.heading = math.pi / 2

        self.speed = 0

        self.target_speed = 8

        self.steering = 0

        self.path = []

        self.history = []

        self.distance_travelled = 0

    def update(self):

        # Smooth acceleration

        acceleration = 1.8

        if self.speed < self.target_speed:

            self.speed += acceleration * DT

        else:

            self.speed -= acceleration * DT

        self.speed = np.clip(
            self.speed,
            0,
            MAX_SPEED
        )

        # Steering

        self.heading += (
            self.steering
            * self.speed
            * 0.018
        )

        # Movement

        dx = (
            self.speed
            * np.cos(self.heading)
            * DT
        )

        dy = (
            self.speed
            * np.sin(self.heading)
            * DT
        )

        self.x += dx
        self.y += dy

        self.distance_travelled += math.hypot(
            dx,
            dy
        )

        self.history.append(
            (self.x, self.y)
        )


# ============================================================
# A* PATH PLANNER
# ============================================================

class AdaptiveAStar:

    def __init__(self):

        self.last_path = []

    def world_to_grid(self, x, y):

        gx = int(x / GRID)
        gy = int(y / GRID)

        gx = np.clip(
            gx,
            0,
            GRID_W - 1
        )

        gy = np.clip(
            gy,
            0,
            GRID_H - 1
        )

        return int(gx), int(gy)

    def grid_to_world(self, gx, gy):

        return (
            gx * GRID + GRID / 2,
            gy * GRID + GRID / 2
        )

    def valid(self, gx, gy):

        if gx < 0 or gx >= GRID_W:
            return False

        if gy < 0 or gy >= GRID_H:
            return False

        return True

    def cell_cost(
        self,
        gx,
        gy,
        obstacles
    ):

        x, y = self.grid_to_world(
            gx,
            gy
        )

        # Road-edge penalty

        left, right = road_bounds(y)

        edge_distance = min(
            x - left,
            right - x
        )

        if edge_distance < 0:

            return 100000

        edge_cost = 0

        if edge_distance < 6:

            edge_cost = (
                20
                / max(edge_distance, 0.5)
            )

        # Obstacle risk

        obstacle_cost = 0

        for obs in obstacles:

            distance = math.hypot(
                x - obs.x,
                y - obs.y
            )

            if distance < obs.radius + SAFETY_RADIUS:

                return 100000

            if distance < 10:

                obstacle_cost += (
                    30
                    / max(distance, 1)
                )

        # Prefer forward direction slightly

        return (
            1
            + edge_cost
            + obstacle_cost
        )

    def heuristic(
        self,
        a,
        b
    ):

        return math.hypot(
            a[0] - b[0],
            a[1] - b[1]
        )

    def neighbors(
        self,
        node
    ):

        x, y = node

        moves = [

            (-1, 0),
            (1, 0),

            (0, -1),
            (0, 1),

            (-1, -1),
            (-1, 1),

            (1, -1),
            (1, 1)
        ]

        for dx, dy in moves:

            nx = x + dx
            ny = y + dy

            if self.valid(nx, ny):

                yield (
                    nx,
                    ny
                )

    def plan(
        self,
        start,
        goal,
        obstacles
    ):

        start_g = self.world_to_grid(
            *start
        )

        goal_g = self.world_to_grid(
            *goal
        )

        queue = []

        heapq.heappush(
            queue,
            (
                0,
                start_g
            )
        )

        came_from = {}

        cost_so_far = {
            start_g: 0
        }

        while queue:

            _, current = heapq.heappop(
                queue
            )

            if current == goal_g:

                break

            for nxt in self.neighbors(
                current
            ):

                gx, gy = nxt

                step_cost = self.cell_cost(
                    gx,
                    gy,
                    obstacles
                )

                if step_cost >= 100000:

                    continue

                new_cost = (
                    cost_so_far[current]
                    + step_cost
                )

                if (
                    nxt not in cost_so_far
                    or new_cost
                    < cost_so_far[nxt]
                ):

                    cost_so_far[nxt] = new_cost

                    priority = (
                        new_cost
                        + self.heuristic(
                            nxt,
                            goal_g
                        )
                    )

                    heapq.heappush(
                        queue,
                        (
                            priority,
                            nxt
                        )
                    )

                    came_from[nxt] = current

        if goal_g not in came_from:

            return []

        current = goal_g

        path = []

        while current != start_g:

            path.append(
                self.grid_to_world(
                    *current
                )
            )

            current = came_from[
                current
            ]

        path.append(
            self.grid_to_world(
                *start_g
            )
        )

        path.reverse()

        self.last_path = path

        return path


# ============================================================
# COLLISION AVOIDANCE
# ============================================================

class CollisionAvoidance:

    def __init__(self):

        self.closest_distance = 999

        self.risk = 0

    def evaluate(
        self,
        vehicle,
        obstacles
    ):

        closest = 999
        danger = None

        for obs in obstacles:

            dx = obs.x - vehicle.x
            dy = obs.y - vehicle.y

            distance = math.hypot(
                dx,
                dy
            )

            if distance < closest:

                closest = distance
                danger = obs

        self.closest_distance = closest

        # --------------------------------
        # Risk
        # --------------------------------

        if closest < 4:

            self.risk = 1.0

        elif closest < 7:

            self.risk = 0.7

        elif closest < 12:

            self.risk = 0.3

        else:

            self.risk = 0

        # --------------------------------
        # Emergency braking
        # --------------------------------

        if closest < 4:

            vehicle.target_speed = 0

        elif closest < 7:

            vehicle.target_speed = 3

        elif closest < 12:

            vehicle.target_speed = 6

        else:

            vehicle.target_speed = 10

        return danger


# ============================================================
# MAIN SIMULATION
# ============================================================

class AutonomousSystem:

    def __init__(self):

        self.vehicle = AutonomousVehicle()

        self.planner = AdaptiveAStar()

        self.avoidance = CollisionAvoidance()

        self.goal = (
            road_center(
                WORLD_H - 8
            ),
            WORLD_H - 8
        )

        self.obstacles = []

        self.time = 0

        self.replans = 0

        self.collisions = 0

        self.auto_mode = True

        self.paused = False

        self.create_environment()

        self.plan_route()

    def create_environment(self):

        self.obstacles.clear()

        # -------------------------
        # Cars
        # -------------------------

        for i in range(8):

            y = random.uniform(
                20,
                120
            )

            center = road_center(y)

            x = center + random.uniform(
                -10,
                10
            )

            self.obstacles.append(
                Obstacle(
                    x,
                    y,
                    "car",
                    2.5,
                    vx=random.uniform(
                        -0.8,
                        0.8
                    ),
                    vy=random.uniform(
                        -1.5,
                        1.5
                    )
                )
            )

        # -------------------------
        # Motorcycles
        # -------------------------

        for i in range(7):

            y = random.uniform(
                15,
                125
            )

            center = road_center(y)

            x = center + random.uniform(
                -12,
                12
            )

            self.obstacles.append(
                Obstacle(
                    x,
                    y,
                    "bike",
                    1.5,
                    vx=random.uniform(
                        -1,
                        1
                    ),
                    vy=random.uniform(
                        -2,
                        2
                    )
                )
            )

        # -------------------------
        # Pedestrians
        # -------------------------

        for i in range(5):

            y = random.uniform(
                20,
                125
            )

            center = road_center(y)

            x = center + random.uniform(
                -16,
                16
            )

            self.obstacles.append(
                Obstacle(
                    x,
                    y,
                    "person",
                    1.0,
                    vx=random.uniform(
                        -1.2,
                        1.2
                    ),
                    vy=0
                )
            )

        # -------------------------
        # Potholes
        # -------------------------

        for i in range(10):

            y = random.uniform(
                15,
                125
            )

            center = road_center(y)

            x = center + random.uniform(
                -13,
                13
            )

            self.obstacles.append(
                Obstacle(
                    x,
                    y,
                    "pothole",
                    1.5
                )
            )

        # -------------------------
        # Road blockage
        # -------------------------

        y = 82

        center = road_center(y)

        self.obstacles.append(
            Obstacle(
                center,
                y,
                "block",
                5
            )
        )

    def plan_route(self):

        self.planner = AdaptiveAStar()

        self.vehicle.path = self.planner.plan(
            (
                self.vehicle.x,
                self.vehicle.y
            ),
            self.goal,
            self.obstacles
        )

        self.replans += 1

    def choose_steering(self):

        if not self.vehicle.path:

            return 0

        # Find closest path point

        distances = [

            math.hypot(
                px - self.vehicle.x,
                py - self.vehicle.y
            )

            for px, py
            in self.vehicle.path
        ]

        nearest = int(
            np.argmin(
                distances
            )
        )

        # Look ahead

        target_index = min(
            nearest + 4,
            len(self.vehicle.path) - 1
        )

        tx, ty = self.vehicle.path[
            target_index
        ]

        desired_heading = math.atan2(
            ty - self.vehicle.y,
            tx - self.vehicle.x
        )

        error = (
            desired_heading
            - self.vehicle.heading
        )

        error = math.atan2(
            math.sin(error),
            math.cos(error)
        )

        steering = np.clip(
            error * 2.0,
            -1,
            1
        )

        # --------------------------------
        # Reactive obstacle avoidance
        # --------------------------------

        danger = self.avoidance.evaluate(
            self.vehicle,
            self.obstacles
        )

        if danger is not None:

            dx = (
                danger.x
                - self.vehicle.x
            )

            dy = (
                danger.y
                - self.vehicle.y
            )

            relative = (
                math.atan2(
                    dy,
                    dx
                )
                - self.vehicle.heading
            )

            relative = math.atan2(
                math.sin(relative),
                math.cos(relative)
            )

            # Steer away

            if relative > 0:

                steering -= 0.7

            else:

                steering += 0.7

        return np.clip(
            steering,
            -1,
            1
        )

    def update(self):

        if self.paused:

            return

        self.time += DT

        # -------------------------
        # Update obstacles
        # -------------------------

        for obs in self.obstacles:

            if obs.kind != "pothole" and obs.kind != "block":

                obs.update()

        # -------------------------
        # Replanning
        # -------------------------

        if (
            int(self.time * 10) % 10 == 0
        ):

            self.plan_route()

        # -------------------------
        # Collision avoidance
        # -------------------------

        self.vehicle.steering = (
            self.choose_steering()
        )

        # -------------------------
        # Vehicle
        # -------------------------

        self.vehicle.update()

        # -------------------------
        # Collision check
        # -------------------------

        for obs in self.obstacles:

            distance = math.hypot(
                obs.x - self.vehicle.x,
                obs.y - self.vehicle.y
            )

            if distance < (
                obs.radius + 1.2
            ):

                self.collisions += 1

                # Push vehicle back

                self.vehicle.x -= (
                    math.cos(
                        self.vehicle.heading
                    ) * 1
                )

                self.vehicle.y -= (
                    math.sin(
                        self.vehicle.heading
                    ) * 1
                )

                self.vehicle.speed = 0

        # -------------------------
        # Keep vehicle on map
        # -------------------------

        self.vehicle.x = np.clip(
            self.vehicle.x,
            2,
            WORLD_W - 2
        )

        self.vehicle.y = np.clip(
            self.vehicle.y,
            2,
            WORLD_H - 2
        )

        # -------------------------
        # Goal
        # -------------------------

        distance_goal = math.hypot(
            self.vehicle.x - self.goal[0],
            self.vehicle.y - self.goal[1]
        )

        if distance_goal < 5:

            self.vehicle.target_speed = 0


# ============================================================
# VISUALIZATION
# ============================================================

system = AutonomousSystem()

fig, ax = plt.subplots(
    figsize=(10, 12)
)

plt.subplots_adjust(
    bottom=0.13,
    right=0.78
)

# -----------------------------
# Buttons
# -----------------------------

ax_start = plt.axes(
    [0.80, 0.55, 0.15, 0.06]
)

ax_reset = plt.axes(
    [0.80, 0.47, 0.15, 0.06]
)

ax_mode = plt.axes(
    [0.80, 0.39, 0.15, 0.06]
)

button_start = Button(
    ax_start,
    "PAUSE / RUN"
)

button_reset = Button(
    ax_reset,
    "RESET"
)

button_mode = Button(
    ax_mode,
    "AUTO MODE"
)


def toggle_pause(event):

    system.paused = not system.paused


def reset(event):

    global system

    system = AutonomousSystem()


def toggle_mode(event):

    system.auto_mode = not system.auto_mode


button_start.on_clicked(
    toggle_pause
)

button_reset.on_clicked(
    reset
)

button_mode.on_clicked(
    toggle_mode
)


# ============================================================
# DRAW
# ============================================================

def draw_road():

    ys = np.linspace(
        0,
        WORLD_H,
        300
    )

    left = []
    right = []
    center = []

    for y in ys:

        c = road_center(y)
        w = road_width(y)

        left.append(
            (
                c - w / 2,
                y
            )
        )

        right.append(
            (
                c + w / 2,
                y
            )
        )

        center.append(
            (
                c,
                y
            )
        )

    left = np.array(left)
    right = np.array(right)
    center = np.array(center)

    ax.fill_betweenx(
        ys,
        left[:, 0],
        right[:, 0],
        alpha=0.22
    )

    ax.plot(
        left[:, 0],
        left[:, 1],
        "--",
        linewidth=2
    )

    ax.plot(
        right[:, 0],
        right[:, 1],
        "--",
        linewidth=2
    )

    ax.plot(
        center[:, 0],
        center[:, 1],
        ":",
        linewidth=1
    )


def draw_obstacle(obs):

    if obs.kind == "car":

        ax.scatter(
            obs.x,
            obs.y,
            marker="s",
            s=180
        )

        ax.text(
            obs.x,
            obs.y + 3,
            "CAR",
            fontsize=7,
            ha="center"
        )

    elif obs.kind == "bike":

        ax.scatter(
            obs.x,
            obs.y,
            marker="^",
            s=130
        )

        ax.text(
            obs.x,
            obs.y + 2.5,
            "BIKE",
            fontsize=7,
            ha="center"
        )

    elif obs.kind == "person":

        ax.scatter(
            obs.x,
            obs.y,
            marker="o",
            s=100
        )

        ax.text(
            obs.x,
            obs.y + 2,
            "PERSON",
            fontsize=7,
            ha="center"
        )

    elif obs.kind == "pothole":

        circle = Circle(
            (
                obs.x,
                obs.y
            ),
            obs.radius,
            fill=False,
            linewidth=2
        )

        ax.add_patch(
            circle
        )

        ax.text(
            obs.x,
            obs.y,
            "P",
            fontsize=8,
            ha="center",
            va="center"
        )

    elif obs.kind == "block":

        ax.scatter(
            obs.x,
            obs.y,
            marker="X",
            s=600
        )

        ax.text(
            obs.x,
            obs.y + 6,
            "ROAD BLOCK",
            fontsize=8,
            ha="center"
        )


def draw_vehicle():

    v = system.vehicle

    length = 5
    width = 2.5

    corners = np.array([
        [length / 2, width / 2],
        [length / 2, -width / 2],
        [-length / 2, -width / 2],
        [-length / 2, width / 2]
    ])

    rotation = np.array([
        [
            np.cos(v.heading),
            -np.sin(v.heading)
        ],
        [
            np.sin(v.heading),
            np.cos(v.heading)
        ]
    ])

    rotated = corners @ rotation.T

    rotated[:, 0] += v.x
    rotated[:, 1] += v.y

    polygon = Polygon(
        rotated,
        closed=True,
        alpha=0.9
    )

    ax.add_patch(
        polygon
    )

    # Sensor range

    sensor = Circle(
        (
            v.x,
            v.y
        ),
        12,
        fill=False,
        linestyle=":",
        alpha=0.25
    )

    ax.add_patch(
        sensor
    )


def update(frame):

    ax.clear()

    system.update()

    draw_road()

    # -----------------------------
    # Path
    # -----------------------------

    if system.vehicle.path:

        path = np.array(
            system.vehicle.path
        )

        ax.plot(
            path[:, 0],
            path[:, 1],
            linewidth=3,
            alpha=0.8,
            label="Adaptive A* Path"
        )

    # -----------------------------
    # History
    # -----------------------------

    if len(
        system.vehicle.history
    ) > 1:

        history = np.array(
            system.vehicle.history
        )

        ax.plot(
            history[:, 0],
            history[:, 1],
            linewidth=1,
            alpha=0.5
        )

    # -----------------------------
    # Obstacles
    # -----------------------------

    for obs in system.obstacles:

        draw_obstacle(
            obs
        )

    # -----------------------------
    # Vehicle
    # -----------------------------

    draw_vehicle()

    # -----------------------------
    # Goal
    # -----------------------------

    ax.scatter(
        system.goal[0],
        system.goal[1],
        marker="*",
        s=500
    )

    ax.text(
        system.goal[0],
        system.goal[1] + 5,
        "DESTINATION",
        ha="center",
        fontsize=9
    )

    # -----------------------------
    # Risk
    # -----------------------------

    risk = system.avoidance.risk

    if risk >= 0.9:

        risk_text = "CRITICAL"

    elif risk >= 0.6:

        risk_text = "HIGH"

    elif risk >= 0.2:

        risk_text = "MEDIUM"

    else:

        risk_text = "LOW"

    # -----------------------------
    # Dashboard
    # -----------------------------

    ax.text(
        1.02,
        0.98,
        "AUTONOMOUS VEHICLE",
        transform=ax.transAxes,
        fontsize=13,
        fontweight="bold",
        va="top"
    )

    ax.text(
        1.02,
        0.92,
        f"Speed\n"
        f"{system.vehicle.speed:.1f} m/s",
        transform=ax.transAxes,
        va="top"
    )

    ax.text(
        1.02,
        0.82,
        f"Nearest obstacle\n"
        f"{system.avoidance.closest_distance:.1f} m",
        transform=ax.transAxes,
        va="top"
    )

    ax.text(
        1.02,
        0.70,
        f"Collision Risk\n"
        f"{risk_text}",
        transform=ax.transAxes,
        va="top"
    )

    ax.text(
        1.02,
        0.59,
        f"Replanning\n"
        f"{system.replans}",
        transform=ax.transAxes,
        va="top"
    )

    ax.text(
        1.02,
        0.48,
        f"Distance\n"
        f"{system.vehicle.distance_travelled:.1f} m",
        transform=ax.transAxes,
        va="top"
    )

    ax.text(
        1.02,
        0.37,
        f"Collisions\n"
        f"{system.collisions}",
        transform=ax.transAxes,
        va="top"
    )

    ax.text(
        1.02,
        0.26,
        "AI STATUS\n"
        "PERCEPTION ✓\n"
        "MAPPING ✓\n"
        "A* PLANNING ✓\n"
        "COLLISION AVOIDANCE ✓",
        transform=ax.transAxes,
        va="top",
        fontsize=9
    )

    # -----------------------------
    # Title
    # -----------------------------

    ax.set_title(
        "Adaptive Path Planning & Collision Avoidance\n"
        "Autonomous Vehicle for Unstructured Indian Roads",
        fontsize=14,
        fontweight="bold"
    )

    ax.set_xlim(
        0,
        WORLD_W
    )

    ax.set_ylim(
        0,
        WORLD_H
    )

    ax.set_xlabel(
        "Road position (m)"
    )

    ax.set_ylabel(
        "Travel distance (m)"
    )

    ax.grid(
        alpha=0.15
    )


# ============================================================
# RUN
# ============================================================

animation = FuncAnimation(
    fig,
    update,
    interval=50,
    cache_frame_data=False
)

plt.show()
