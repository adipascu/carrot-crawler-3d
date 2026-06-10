# Carrot Crawler 3D

A vibed 3D version of [`jhshrvdp`](https://www.ioccc.org/2025/jhshrvdp/index.html), a winning entry of the 2025 International Obfuscated C Code Contest. The original is a tiny obfuscated curses rogue-like; this repo grew it, step by step, into a first-person 3D dungeon crawler that runs in the browser.

All three generations are playable in the browser:

- **[Full 3D](https://adipascu.github.io/carrot-crawler-3d/godot/)** - first-person dungeon crawler with 3D assets, music, and mouse look
- **[Terminal raycaster](https://adipascu.github.io/carrot-crawler-3d/terminal3d/)** - the curses version rendered Wolfenstein-style, with mouse look
- **[The original](https://adipascu.github.io/carrot-crawler-3d/original/)** - the untouched IOCCC entry, turn-based and top-down

You are `@`. Collect gold, avoid the carrots, and descend past floor 99 to win. Teleport costs 3 gold and may save your life.

## Contents

- `prog.c`, `Makefile` - the original IOCCC entry, untouched
- `prog3d.c` - a terminal raycaster port of the same game logic (curses, mouse look, WASD)
- `godot3d/` - the full 3D version: Godot 4, procedural assets and music, targets the web
- `gamedriver.py` - pty test harness that plays the terminal version for regression testing
- `web/` - curses-compatible shim and pages that put the two C versions in the browser

## Running

Terminal version:

```
make prog3d && ./prog3d
```

Web version (needs Godot 4 and its web export templates):

```
godot --headless --path godot3d --export-release "Web" web/index.html
python3 -m http.server -d godot3d/web
```

Then open http://localhost:8000 in a browser.

## License

[CC BY-SA 4.0](LICENSE), the license of the original entry. Original game by the author of IOCCC 2025 entry [`jhshrvdp`](https://www.ioccc.org/2025/jhshrvdp/index.html).
