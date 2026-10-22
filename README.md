# EMBERWAKE

A playable 3D action-roguelike prototype made with **Godot 4** and **Blender**.
Explore seeded rooms, fight guardians, gather soulfire, choose upgrades, heal at
shrines, and push into an endless crypt. It runs as a native desktop window.

## Status

Emberwake is an early desktop prototype, not a finished or store-published
game. The repository contains the game source, a headless smoke test, and the
scripts used to create its original low-poly models. It has no required network
service, account, ads, or paid dependency.

The game generates its room geometry, lighting, combat particles, and sound effects at runtime. Character and prop models are built in Blender from the reproducible script in `blender/`.

## Play

Install Godot 4.7.2, then run `./run.sh` from this folder, or open
`project.godot` in Godot and press F6. On the first editor launch, let Godot
import the project before playing.

| Input | Action |
| --- | --- |
| WASD or arrows | Move |
| Mouse | Aim |
| Left click or J | Strike |
| Space | Dash |
| E | Use nearby shrine |
| Esc | Pause |
| 1, 2, 3 | Choose a blessing |

Rooms are generated from a seed with open doorways in every direction. Generation continues as far as the player travels. Enemies scale with depth; each new room is populated once per run. Leveling gives a choice among three blessings. Death starts a new seed.

## Optional local agent bridge

The game exposes a **local TCP observation/action bridge** on `127.0.0.1:9327`
only when started with `./run.sh -- --agent`. It sends JSON observations and
accepts JSON actions. The Python harness at `agents/open_jev_player.py`
translates each observation into a typed Choice request for an Open-Jev server.
It is entirely optional and is off for normal play.

For a fully local setup, install the open source [lookski/openjev](https://github.com/lookski/openjev) decision engine in a separate directory and start its Qwen3-0.6B model:

```sh
git clone https://github.com/lookski/openjev.git
cd openjev
python3 -m venv .venv
.venv/bin/pip install -e .
.venv/bin/python -m openjev.server --port 8791 --model Qwen/Qwen3-0.6B --device cuda --dtype float16 --preload
```

Use `--device cpu --dtype float32` on machines without a compatible GPU. In a second terminal, from the Emberwake directory:

```sh
./run.sh -- --agent
python3 agents/open_jev_player.py --url http://127.0.0.1:8791/v1/systemone --steps 100
```

Use `--steps 0 --restart-on-death` to let the model play continuously until the window is closed.

The [Zefan-Cai/Open-Jev](https://github.com/Zefan-Cai/Open-Jev) server can also be used with its `/v1/inference` endpoint. The harness requires a live model endpoint; it does not replace model choices with a scripted policy. It offers room exploration, attack, dash, retreat, shrine, and upgrade choices. Simple doorway alignment makes a chosen exploration route usable in 3D.

The bridge is off for normal human play. The model sees structured state, not pixels. A decision freezes the game until the response arrives, so slow local inference does not silently kill the character. The action then plays for 0.38 seconds.

## Rebuild Blender models

```sh
blender -b --python blender/make_models.py
```

The script creates the hero, shade, guardian, pillar, brazier, and shrine as original low-poly `.glb` models. Godot imports the exported models directly. The Blender source is the Python model recipe, so every asset is reproducible.

## Verify

```sh
godot4 --headless --editor --path . --quit
godot4 --headless --path . --script tests/smoke.gd
```

The smoke test starts a run, checks generated rooms and collisions, spawns
enemies, exercises upgrades, and verifies death/restart behavior. It does not
replace interactive play-testing.

## License and credits

Game code and original models: MIT, see [LICENSE](LICENSE). [Godot](https://godotengine.org/license/) and [Blender](https://www.blender.org/about/license/) are open source. The included Cinzel and Inter fonts are licensed under the SIL Open Font License; their license texts are in `assets/fonts/`.
