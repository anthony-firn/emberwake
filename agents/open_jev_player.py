"""Let a local Open-Jev decision server play the native Godot game.

The server must expose POST /v1/inference or /v1/systemone. Every movement,
combat and upgrade decision comes from its typed Choice answer.
"""

from __future__ import annotations

import argparse
import itertools
import json
import socket
import time
from pathlib import Path
from urllib import request


DIRECTIONS = {
    "N": (0, -1), "NE": (0.707, -0.707), "E": (1, 0), "SE": (0.707, 0.707),
    "S": (0, 1), "SW": (-0.707, 0.707), "W": (-1, 0), "NW": (-0.707, -0.707),
}


def move_toward_exit(state: dict, exit_name: str) -> str:
    """Align with the three-tile doorway, then cross it."""
    local_x, local_z = state.get("local_x", 0), state.get("local_z", 0)
    if exit_name in ("N", "S") and abs(local_x) > 2.0:
        return "W" if local_x > 0 else "E"
    if exit_name in ("E", "W") and abs(local_z) > 2.0:
        return "N" if local_z > 0 else "S"
    return exit_name


def nearest_enemy(state: dict) -> tuple[dict | None, float]:
    enemies = state.get("enemies", [])
    if not enemies:
        return None, float("inf")
    x, z = state["x"], state["z"]
    enemy = min(enemies, key=lambda e: (e["x"] - x) ** 2 + (e["z"] - z) ** 2)
    distance = ((enemy["x"] - x) ** 2 + (enemy["z"] - z) ** 2) ** .5
    return enemy, distance


def closest_direction(dx: float, dz: float) -> str:
    return max(DIRECTIONS, key=lambda name: DIRECTIONS[name][0] * dx + DIRECTIONS[name][1] * dz)


def choose_request(state: dict, route: str | None = None) -> tuple[dict, dict[str, dict]]:
    if state["mode"] == "upgrade":
        options = {str(i): {"upgrade": i} for i in range(len(state["blessings"]))}
        descriptions = {str(i): f"Choose the {name} upgrade for this run." for i, name in enumerate(state["blessings"])}
        question = "Which upgrade gives the best survival and combat value for this run?"
    else:
        x, z = state["x"], state["z"]
        nearest, distance = nearest_enemy(state)
        options = {}
        descriptions = {}
        exits = state.get("unexplored_exits", [])
        if route is None:
            for name in exits:
                direction = move_toward_exit(state, name)
                options[f"explore_{name}"] = {"move": direction}
                descriptions[f"explore_{name}"] = f"Choose the unseen {name} room as the next destination, and take a step toward its doorway."
        else:
            direction = move_toward_exit(state, route)
            options["continue_exploring"] = {"move": direction}
            descriptions["continue_exploring"] = f"Keep moving toward the chosen {route} exit until entering the next room."
            options["explore_and_strike"] = {"move": direction, "attack": True}
            descriptions["explore_and_strike"] = f"Move toward the chosen {route} exit while swinging the sword defensively."
        if nearest:
            aim_x, aim_z = nearest["x"] - x, nearest["z"] - z
            if "explore_and_strike" in options:
                options["explore_and_strike"].update({"aim_x": aim_x, "aim_z": aim_z})
            if distance < 5.2:
                options["strike"] = {"attack": True, "aim_x": aim_x, "aim_z": aim_z}
                descriptions["strike"] = "Strike the nearest enemy with the sword. Effective within roughly 4.6 world units."
            if distance > 2.0:
                direction = closest_direction(aim_x, aim_z)
                options["approach"] = {"move": direction, "aim_x": aim_x, "aim_z": aim_z}
                descriptions["approach"] = "Approach the nearest enemy to get within sword range."
                if state["dash_ready"]:
                    options["dash_attack"] = {"move": direction, "dash": True, "aim_x": aim_x, "aim_z": aim_z}
                    descriptions["dash_attack"] = "Dash toward the enemy, briefly avoiding damage."
            if state["hp"] < state["max_hp"] * .6:
                away = closest_direction(-aim_x, -aim_z)
                options["retreat"] = {"move": away, "aim_x": aim_x, "aim_z": aim_z}
                descriptions["retreat"] = "Move away from the enemy to avoid damage while health is low."
        if state.get("shrine"):
            if abs(state.get("local_x", 0)) < 3 and abs(state.get("local_z", 0)) < 3:
                options["shrine"] = {"interact": True}
                descriptions["shrine"] = "Use the nearby shrine to restore health."
            elif state["hp"] < state["max_hp"] * .55:
                direction = closest_direction(-state["local_x"], -state["local_z"])
                options["seek_shrine"] = {"move": direction}
                descriptions["seek_shrine"] = "Move to the shrine at the center of this room to heal."
        if not options:
            options["explore_E"] = {"move": "E"}
            descriptions["explore_E"] = "Go east and explore a new room."
        if len(options) == 1:
            key = next(iter(options))
            options["cautious_" + key] = {**options[key], "attack": True}
            descriptions["cautious_" + key] = descriptions[key] + " Swing the sword while doing so."
        question = "Choose one immediate action. Prioritize killing nearby enemies in sword range, then explore unseen rooms. Use a shrine when hurt."

    summary = {
        "position": [round(state.get("x", 0), 1), round(state.get("z", 0), 1)],
        "room": [state.get("room_x", 0), state.get("room_z", 0)],
        "depth": state.get("depth", 0),
        "health": f"{round(state.get('hp', 0))}/{round(state.get('max_hp', 0))}",
        "level": state.get("level", 1),
        "kills": state.get("kills", 0),
        "dash_ready": state.get("dash_ready", False),
        "shrine": state.get("shrine", False),
        "blocked": state.get("blocked", {}),
        "local_position": [round(state.get("local_x", 0), 1), round(state.get("local_z", 0), 1)],
        "unexplored_exits": state.get("unexplored_exits", []),
        "nearby_enemies": [
            {"relative_x": round(e["x"] - state["x"], 1),
             "relative_z": round(e["z"] - state["z"], 1),
             "health": round(e["hp"]), "guardian": e["guardian"]}
            for e in state.get("enemies", [])[:8]
        ],
        "upgrades": state.get("blessings", []),
    }
    payload = {
        "state": f"Emberwake is a 3D endless action roguelike. {json.dumps(summary, separators=(',', ':'))}",
        "questions": {"action": {"type": "choice", "instructions": question, "criteria": descriptions}},
    }
    return payload, options


def query_model(url: str, payload: dict, timeout: float) -> dict:
    encoded = json.dumps(payload).encode()
    req = request.Request(url, encoded, {"Content-Type": "application/json"}, method="POST")
    with request.urlopen(req, timeout=timeout) as response:
        result = json.load(response)
    answer = result["answers"]["action"]
    if answer.get("type") != "choice" or answer.get("choice") not in payload["questions"]["action"]["criteria"]:
        raise ValueError(f"Model returned an invalid action: {answer}")
    return {"choice": answer["choice"], "confidence": answer.get("confidence"), "model": result.get("model")}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url", default="http://127.0.0.1:8791/v1/inference", help="Open-Jev decision endpoint")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=9327)
    parser.add_argument("--steps", type=int, default=100, help="Number of choices, or 0 for continuous play")
    parser.add_argument("--restart-on-death", action="store_true", help="Start a new run after death")
    parser.add_argument("--timeout", type=float, default=120.0)
    parser.add_argument("--trace", type=Path, default=Path("logs/open_jev_run.jsonl"))
    args = parser.parse_args()
    args.trace.parent.mkdir(parents=True, exist_ok=True)
    with socket.create_connection((args.host, args.port), timeout=10) as connection, args.trace.open("w") as trace:
        stream = connection.makefile("r", encoding="utf-8")
        route = None
        previous_room = None
        steps = itertools.count() if args.steps == 0 else range(args.steps)
        for step in steps:
            line = stream.readline()
            if not line:
                raise ConnectionError("Godot agent bridge disconnected")
            state = json.loads(line)
            if state["mode"] == "dead":
                print(f"Run ended after {step} decisions, {state['kills']} kills, depth {state['depth']}.")
                if args.restart_on_death:
                    connection.sendall(b'{"restart":true}\n')
                    route = None
                    previous_room = None
                    continue
                break
            if state["mode"] not in ("playing", "upgrade"):
                connection.sendall(b"{}\n")
                continue
            room = (state.get("room_x"), state.get("room_z"))
            if room != previous_room:
                route = None
                previous_room = room
            payload, actions = choose_request(state, route)
            started = time.monotonic()
            answer = query_model(args.url, payload, args.timeout)
            elapsed = time.monotonic() - started
            action = actions[answer["choice"]]
            if answer["choice"].startswith("explore_") and answer["choice"][8:] in DIRECTIONS:
                route = answer["choice"][8:]
            connection.sendall((json.dumps(action, separators=(",", ":")) + "\n").encode())
            record = {"step": step, "observation": state, "choice": answer["choice"],
                      "confidence": answer["confidence"], "model": answer["model"],
                      "action": action, "latency_seconds": round(elapsed, 3)}
            trace.write(json.dumps(record) + "\n")
            trace.flush()
            print(f"{step:03d}  {answer['choice']:<8}  hp {state['hp']:.0f}/{state['max_hp']:.0f}  "
                  f"depth {state['depth']}  {elapsed:.2f}s", flush=True)


if __name__ == "__main__":
    main()
