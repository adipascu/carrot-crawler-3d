#include <emscripten.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>
#include "curses.h"

#ifndef SHIM_ROWS
#define SHIM_ROWS 24
#endif
#ifndef SHIM_COLS
#define SHIM_COLS 80
#endif
#ifndef SHIM_MOUSE
#define SHIM_MOUSE 0
#endif

int LINES = SHIM_ROWS;
int COLS = SHIM_COLS;
int ESCDELAY = 1000;
WINDOW *stdscr = (WINDOW *)1;

static unsigned int cells[SHIM_ROWS][SHIM_COLS];
static long cur_attr;
static int cur_y, cur_x, timeout_ms = -1, dirty = 1;

EM_JS(void, js_init, (int rows, int cols, int mouse), {
	var M = Module;
	M.q = [];
	M.wake = null;
	M.pairs = [];
	M.term = document.getElementById("term");
	M.push = function(v) {
		if (M.wake) { var w = M.wake; M.wake = null; w(v); }
		else M.q.push(v);
	};
	M.pushStr = function(s) {
		for (var i = 0; i < s.length; i++) M.push(s.charCodeAt(i));
	};
	var special = {
		ArrowUp: 0x103, ArrowDown: 0x102, ArrowLeft: 0x104, ArrowRight: 0x105,
		Escape: 27, Enter: 10, Backspace: 8
	};
	addEventListener("keydown", function(e) {
		if (e.metaKey || e.ctrlKey || e.altKey) return;
		if (e.key in special) { M.push(special[e.key]); e.preventDefault(); }
		else if (e.key.length == 1) { M.push(e.key.charCodeAt(0)); e.preventDefault(); }
	});
	if (mouse) {
		var vx = 300, vy = 300, fx = 0, fy = 0;
		M.term.style.cursor = "crosshair";
		M.term.addEventListener("click", function() {
			if (document.pointerLockElement != M.term)
				M.term.requestPointerLock();
			M.pushStr("\x1b[<0;" + vx + ";" + vy + "M");
		});
		addEventListener("blur", function() { M.push(0x1a0); });
		document.addEventListener("pointerlockchange", function() {
			if (document.pointerLockElement != M.term) M.push(27);
		});
		addEventListener("mousemove", function(e) {
			if (document.pointerLockElement != M.term) return;
			fx += e.movementX / 9.0;
			fy += e.movementY / 16.0;
			var dx = Math.trunc(fx), dy = Math.trunc(fy);
			if (!dx && !dy) return;
			fx -= dx;
			fy -= dy;
			vx = ((vx + dx - 1 + 6000) % 600) + 1;
			vy = ((vy + dy - 1 + 6000) % 600) + 1;
			M.pushStr("\x1b[<35;" + vx + ";" + vy + "M");
		});
	}
});

EM_JS(void, js_set_pair, (int n, int fg, int bg), {
	Module.pairs[n] = [fg, bg];
});

EM_JS(void, js_flush, (int ptr, int rows, int cols), {
	var M = Module;
	var colors = ["#0a0a0a", "#cc4433", "#44bb44", "#ccbb33",
			"#4466cc", "#bb44bb", "#33bbbb", "#c8c8c8"];
	var bright = ["#555555", "#ff6655", "#66ee66", "#ffee55",
			"#6699ff", "#ee66ee", "#55eeee", "#ffffff"];
	var html = "";
	var open = null;
	for (var r = 0; r < rows; r++) {
		for (var c = 0; c < cols; c++) {
			var v = HEAPU32[(ptr >> 2) + r * cols + c];
			var ch = v & 0xff;
			var pair = (v >> 8) & 0xff;
			var bold = v & (1 << 24);
			var p = M.pairs[pair] || [7, 0];
			var fg = (bold ? bright : colors)[p[0] & 7];
			var bg = colors[p[1] & 7];
			var key = fg + bg;
			if (key != open) {
				if (open != null) html += "</span>";
				html += '<span style="color:' + fg + ";background:" + bg + '">';
				open = key;
			}
			var s = String.fromCharCode(ch ? ch : 32);
			html += s == "<" ? "&lt;" : s == "&" ? "&amp;" : s;
		}
		html += "\n";
	}
	if (open != null) html += "</span>";
	M.term.innerHTML = html;
});

EM_ASYNC_JS(int, js_getch, (int tmo), {
	var M = Module;
	if (M.q.length) return M.q.shift();
	if (tmo == 0) return -1;
	return await new Promise(function(res) {
		var t = null;
		M.wake = function(v) {
			if (t) clearTimeout(t);
			res(v);
		};
		if (tmo > 0)
			t = setTimeout(function() { M.wake = null; res(-1); }, tmo);
	});
});

static void flush_screen(void) {
	if (!dirty)
		return;
	dirty = 0;
	js_flush((int)(unsigned long)&cells[0][0], LINES, COLS);
}

WINDOW *initscr(void) {
	js_init(LINES, COLS, SHIM_MOUSE);
	erase();
	return stdscr;
}

int endwin(void) {
	flush_screen();
	return OK;
}

int noecho(void) { return OK; }
int raw(void) { return OK; }
int cbreak(void) { return OK; }
int curs_set(int v) { (void)v; return OK; }
int start_color(void) { return OK; }
int keypad(WINDOW *w, int e) { (void)w; (void)e; return OK; }
unsigned long mousemask(unsigned long m, unsigned long *o) { (void)o; return m; }
int mouseinterval(int i) { (void)i; return OK; }
int getmouse(MEVENT *e) { (void)e; return ERR; }

int init_pair(short pair, short fg, short bg) {
	js_set_pair(pair, fg, bg);
	return OK;
}

int attron(long attrs) {
	if (attrs & 0xff00)
		cur_attr = (cur_attr & ~0xff00L) | (attrs & 0xff00);
	cur_attr |= attrs & (A_BOLD | A_DIM);
	return OK;
}

int attroff(long attrs) {
	cur_attr &= ~(attrs & (A_BOLD | A_DIM));
	if (attrs & 0xff00)
		cur_attr &= ~0xff00L;
	return OK;
}

int erase(void) {
	memset(cells, 0, sizeof cells);
	dirty = 1;
	return OK;
}

int refresh(void) {
	flush_screen();
	return OK;
}

int move(int y, int x) {
	cur_y = y;
	cur_x = x;
	return OK;
}

int mvaddch(int y, int x, chtype ch) {
	if (y < 0 || x < 0 || y >= LINES || x >= COLS)
		return ERR;
	cells[y][x] = (unsigned int)((ch & 0xff) | cur_attr);
	cur_y = y;
	cur_x = x + 1;
	dirty = 1;
	return OK;
}

chtype mvinch(int y, int x) {
	if (y < 0 || x < 0 || y >= LINES || x >= COLS)
		return ' ';
	chtype ch = cells[y][x] & 0xff;
	return ch ? ch : ' ';
}

int mvprintw(int y, int x, const char *fmt, ...) {
	char buf[512];
	va_list ap;
	va_start(ap, fmt);
	vsnprintf(buf, sizeof buf, fmt, ap);
	va_end(ap);
	for (int i = 0; buf[i]; i++)
		mvaddch(y, x + i, (unsigned char)buf[i]);
	return OK;
}

void timeout(int delay_ms) {
	timeout_ms = delay_ms;
}

int getch(void) {
	flush_screen();
	return js_getch(timeout_ms);
}

int flushinp(void) {
	EM_ASM({ Module.q = []; });
	return OK;
}
