import atexit
import fcntl
import math
import os
import pty
import re
import select
import signal
import struct
import subprocess
import sys
import termios
import time
from collections import deque

import pyte

HUD_RE = re.compile(
    r"Score:(\d+)\|hp:\((-?\d+)/\d+\)\|floor:(\d+)\|"
    r"Argv\{:([0-9a-f]+):([0-9a-f]+):([0-9a-f]+):([0-9a-f]+):([0-9a-f]+):([0-9a-f]+):\}")


class Game:
    def __init__(self, save=None):
        self.screen = pyte.Screen(80, 24)
        self.stream = pyte.Stream(self.screen)
        master, slave = pty.openpty()
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 80, 0, 0))
        cmd = ["./prog3d"] + ([save] if save else [])
        env = dict(os.environ, TERM="xterm", LINES="24", COLUMNS="80")
        self.proc = subprocess.Popen(cmd, stdin=slave, stdout=slave,
                                     stderr=slave, env=env, close_fds=True)
        os.close(slave)
        self.master = master
        self.ang = 0.0
        self.mouse_x = 40
        self.tail = b""
        atexit.register(self._cleanup)
        self.pump(1.0)

    def _cleanup(self):
        if self.proc.poll() is None:
            self.proc.kill()

    def pump(self, seconds=0.25):
        end = time.time() + seconds
        while time.time() < end:
            r, _, _ = select.select([self.master], [], [], 0.05)
            if not r:
                continue
            try:
                data = os.read(self.master, 65536)
            except OSError:
                break
            if not data:
                break
            self.tail += data[-2000:]
            self.tail = self.tail[-2000:]
            self.stream.feed(data.decode("utf-8", "replace"))

    def send(self, text, wait=0.2):
        os.write(self.master, text.encode("latin-1"))
        self.pump(wait)

    def rows(self):
        return [self.screen.display[r] for r in range(24)]

    def hud(self):
        m = None
        for _ in range(5):
            m = HUD_RE.search(self.rows()[0])
            if m:
                break
            self.pump(0.15)
        if not m:
            return None
        return {"score": int(m.group(1)), "hp": int(m.group(2)),
                "floor": int(m.group(3)), "seed": int(m.group(4), 16),
                "y": int(m.group(7), 16), "x": int(m.group(8), 16),
                "money": int(m.group(9), 16)}

    def alive(self):
        return self.proc.poll() is None

    def quit(self):
        if self.alive():
            self.send("q", 0.5)
            try:
                self.proc.wait(3)
            except subprocess.TimeoutExpired:
                self.proc.kill()
        self.pump(0.3)
        os.close(self.master)

    def mouse(self, dx, dy=0):
        my = 12
        self.send("\x1b[<35;%d;%dM" % (self.mouse_x, my), 0.05)
        while dx or dy:
            sx = max(-24, min(24, dx))
            sy = max(-24, min(24, dy))
            dx -= sx
            dy -= sy
            nx = self.mouse_x + sx
            if nx < 1 or nx > 220:
                self.mouse_x = 100
                self.send("\x1b[<35;%d;%dM" % (self.mouse_x, my), 0.02)
                nx = self.mouse_x + sx
            self.send("\x1b[<35;%d;%dM" % (nx, my + sy), 0.02)
            self.mouse_x = nx
            self.ang += sx * 0.045
        self.pump(0.1)

    def face(self, heading):
        targets = {"e": 0.0, "s": math.pi / 2, "w": math.pi, "n": -math.pi / 2}
        want = targets[heading]
        best = want
        for k in range(-4, 5):
            cand = want + 2 * math.pi * k
            if abs(cand - self.ang) < abs(best - self.ang):
                best = cand
        cells = round((best - self.ang) / 0.045)
        if cells:
            self.mouse(cells)

    def find_all(self, ch):
        out = []
        rows = self.rows()
        for r in range(1, 24):
            for c, cc in enumerate(rows[r]):
                if cc == ch:
                    out.append((r, c))
        return out

    def bfs(self, src, goals, avoid_foes=True):
        rows = self.rows()
        walk = {".", "$", ">", "<", "@"}
        danger = set()
        if avoid_foes:
            rad = 3 if avoid_foes is True else avoid_foes
            for fr, fc in self.find_all("^"):
                for dr in range(-rad, rad + 1):
                    for dc in range(-rad, rad + 1):
                        danger.add((fr + dr, fc + dc))
        q = deque([src])
        prev = {src: None}
        while q:
            cur = q.popleft()
            if cur in goals:
                path = []
                while cur:
                    path.append(cur)
                    cur = prev[cur]
                return list(reversed(path))
            r, c = cur
            for dr, dc in ((0, 1), (0, -1), (1, 0), (-1, 0)):
                nxt = (r + dr, c + dc)
                if nxt in prev or not (1 <= nxt[0] <= 23 and 0 <= nxt[1] < 80):
                    continue
                ch = rows[nxt[0]][nxt[1]]
                if ch not in walk or (nxt in danger and nxt not in goals):
                    continue
                prev[nxt] = cur
                q.append(nxt)
        return None

    def step_to(self, target):
        for _ in range(5):
            h = self.hud()
            if h is None:
                return False
            if (h["y"], h["x"]) == target:
                return True
            dy, dx = target[0] - h["y"], target[1] - h["x"]
            if abs(dy) + abs(dx) != 1:
                return False
            self.face({(0, 1): "e", (0, -1): "w",
                       (1, 0): "s", (-1, 0): "n"}[(dy, dx)])
            self.send("wwwwwww", 0.08)
        return False

    def carrot_dist(self, src):
        return min((max(abs(fr - src[0]), abs(fc - src[1]))
                    for fr, fc in self.find_all("^")), default=99)

    def retreat(self):
        h = self.hud()
        if h is None:
            return
        src = (h["y"], h["x"])
        rows = self.rows()
        safe = set()
        for r in range(1, 24):
            for c in range(80):
                if rows[r][c] in ".$" and self.carrot_dist((r, c)) >= 4:
                    safe.add((r, c))
        path = self.bfs(src, safe, avoid_foes=1) or self.bfs(src, safe, avoid_foes=False)
        if not path:
            return
        for cell in path[1:5]:
            if not self.step_to(cell):
                break

    def collect_coin(self, max_cells=150):
        h0 = self.hud()
        return self.goto(["$"], max_cells,
                         done=lambda h: h["score"] > h0["score"])

    def take_stairs(self, ch, max_cells=150):
        h0 = self.hud()
        if not self.find_all(ch):
            src = (h0["y"], h0["x"])
            rows = self.rows()
            for d, head in (((0, 1), "e"), ((0, -1), "w"), ((1, 0), "s"), ((-1, 0), "n")):
                nr, nc = src[0] + d[0], src[1] + d[1]
                if 1 <= nr <= 23 and 0 <= nc < 80 and rows[nr][nc] in ".$":
                    self.face(head)
                    self.send("wwwww", 0.15)
                    break
        return self.goto([ch], max_cells,
                         done=lambda h: h["floor"] != h0["floor"])

    def goto(self, goal_chars, max_cells=150, done=None):
        nopath = 0
        stuck = 0
        last = None
        for _ in range(max_cells):
            h = self.hud()
            if h is None:
                return "gone"
            if done is not None and done(h):
                return "arrived"
            goals = set()
            for ch in goal_chars:
                goals.update(self.find_all(ch))
            src = (h["y"], h["x"])
            if done is None and src in goals:
                return "arrived"
            if not goals:
                return "no-goal"
            stuck = stuck + 1 if src == last else 0
            last = src
            near = self.carrot_dist(src)
            if h["hp"] <= 7 and h["money"] >= 3 and near <= 2:
                self.send("t", 0.3)
                continue
            if near <= 1 and stuck >= 1:
                self.retreat()
                continue
            path = self.bfs(src, goals)
            if path is None or len(path) < 2:
                path = self.bfs(src, goals, avoid_foes=1)
            if path is None or len(path) < 2:
                nopath += 1
                if nopath > 8:
                    path = self.bfs(src, goals, avoid_foes=False)
                    if path is None or len(path) < 2:
                        return "no-path"
                else:
                    self.pump(0.6)
                    continue
            else:
                nopath = 0
            d0 = (path[1][0] - path[0][0], path[1][1] - path[0][1])
            k = 1
            while k + 1 < len(path) and k < 3:
                d = (path[k + 1][0] - path[k][0], path[k + 1][1] - path[k][1])
                if d != d0:
                    break
                k += 1
            danger_ahead = min(self.carrot_dist(p) for p in path[1:k + 1])
            if danger_ahead <= 1:
                k = 1
            self.face({(0, 1): "e", (0, -1): "w",
                       (1, 0): "s", (-1, 0): "n"}[d0])
            self.send("w" * (5 * k), 0.05 + 0.02 * k)
        return "timeout"

    def dump(self):
        return "\n".join(self.rows())
