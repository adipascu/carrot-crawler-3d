#include <curses.h>
#include <math.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#ifdef __APPLE__
#include <CoreGraphics/CoreGraphics.h>
#endif

#define M 1920
#define L 80
#define P 10
#define FOV 1.15
#define ZMAX 1024
#define TICK_MS 280
#define CHASE 6
#define STEP 0.2
#define BODY 0.28

typedef struct { double dist, wx, wy; int ch, pair; } Spr;

static int D[M], E[M], I[M], S[4];
static int depth, money, seed, ticks, regenat, gens, health = 10;
static int lo, hi, showmap, lastmx = -1, lastmy = -1, capturing = 1;
static volatile sig_atomic_t quitsig;
static double px, py, ang, pitch;
#ifdef __APPLE__
static double cellw = 8, cellh = 17;
static int pend, pendmx, pendmy, penddx, penddy;
#endif
static double zbuf[ZMAX];

static int edge(int i) { return i < L || i > 1839 || !(((i + 1) & ~1) % L); }

static int N(void) {
    int i;
    do i = rand() % M; while (D[i] != '.');
    return i;
}

static void gen(void) {
    gens++;
    srand(seed);
    for (int i = L; i < M; i++) {
        int carved = (((i + 1) & ~1) % L) && i / L < 13 && i / L > P;
        D[i] = !carved && (edge(i) || rand() % 100 < 45) ? '#' : '.';
    }
    for (int pass = 0; pass < 2; pass++)
        for (int i = L; i < M; i++) {
            E[i % 600] = I[i % 600] = pass;
            if (!edge(i))
                D[i] = D[i - 81] + D[i - L] + D[i - 79] + D[i - 1] + D[i] +
                       D[i + 1] + D[i + 79] + D[i + L] + D[i + 81] < 360 ? '#' : '.';
        }
    int present = depth < 100, cell = N();
    S[0] = cell / L * present;
    S[1] = cell % L * present;
    present = depth > 0;
    cell = N();
    S[2] = cell / L * present;
    S[3] = cell % L * present;
    srand(seed * gens);
    lo = 6 * depth;
    hi = lo + (depth < 100 ? 6 + depth / 5 : 0);
    for (int j = lo; j < hi; j++) {
        E[j] = E[j] ? N() : 0;
        I[j] = I[j] ? N() : 0;
    }
}

static int cellch(int r, int col) {
    if (r < 0 || col < 0 || r > 23 || col >= L) return '#';
    if (r == (int)py && col == (int)px) return '@';
    if (depth > 0 && r == S[2] && col == S[3]) return '<';
    if (depth <= 99 && r == S[0] && col == S[1]) return '>';
    int idx = r * L + col;
    for (int j = lo; j < hi; j++) if (E[j] == idx) return '^';
    for (int j = lo; j < hi; j++) if (I[j] == idx) return '$';
    return D[idx];
}

static int openplayer(int r, int col) {
    int ch = cellch(r, col);
    return ch == '.' || ch == '$' || ch == '>' || ch == '<' || ch == '@';
}

static int canstand(double x, double y) {
    return openplayer((int)(y - BODY), (int)(x - BODY)) &&
           openplayer((int)(y - BODY), (int)(x + BODY)) &&
           openplayer((int)(y + BODY), (int)(x - BODY)) &&
           openplayer((int)(y + BODY), (int)(x + BODY));
}

static void slide(double dx, double dy) {
    if (canstand(px + dx, py)) px += dx;
    if (canstand(px, py + dy)) py += dy;
}

static int openfoe(int r, int col) {
    int ch = cellch(r, col);
    return ch == '.' || ch == '$';
}

static int solid(int r, int col) {
    if (r < 0 || col < 0 || r > 23 || col >= L) return 1;
    return D[r * L + col] != '.';
}

static int sprcmp(const void *a, const void *b) {
    double d = ((const Spr *)b)->dist - ((const Spr *)a)->dist;
    return (d > 0) - (d < 0);
}

static long now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1000L + ts.tv_nsec / 1000000L;
}

static void clamp_pitch(void) {
    if (pitch > LINES) pitch = LINES;
    if (pitch < -LINES) pitch = -LINES;
}

static void recenter(int mx, int my) {
#ifdef __APPLE__
    if (!capturing) return;
    if (mx >= 4 && mx <= COLS - 5 && my >= 3 && my <= LINES - 4) return;
    CGEventRef ev = CGEventCreate(NULL);
    CGPoint p = CGEventGetLocation(ev);
    CFRelease(ev);
    penddx = COLS / 2 - mx;
    penddy = LINES / 2 - my;
    CGWarpMouseCursorPosition(
        CGPointMake(p.x + penddx * cellw, p.y + penddy * cellh));
    pend = 1;
    pendmx = mx;
    pendmy = my;
    lastmx = lastmy = -1;
#else
    (void)mx;
    (void)my;
#endif
}

static void mouselook(int mx, int my) {
#ifdef __APPLE__
    if (pend) {
        pend = 0;
        int adx = mx - pendmx, ady = my - pendmy;
        if (abs(penddx) >= 4 && adx && (penddx > 0) == (adx > 0)) {
            cellw = cellw * penddx / adx;
            if (cellw < 4) cellw = 4;
            if (cellw > 30) cellw = 30;
        }
        if (abs(penddy) >= 3 && ady && (penddy > 0) == (ady > 0)) {
            cellh = cellh * penddy / ady;
            if (cellh < 8) cellh = 8;
            if (cellh > 44) cellh = 44;
        }
        lastmx = mx;
        lastmy = my;
        return;
    }
#endif
    if (lastmx >= 0) {
        int dx = mx - lastmx, dy = my - lastmy;
        if (abs(dx) < 25 && abs(dy) < 25) {
            ang += dx * 0.045;
            pitch -= dy * 2.0;
            clamp_pitch();
        }
    }
    lastmx = mx;
    lastmy = my;
    recenter(mx, my);
}

static void sgrmouse_rest(void) {
    int c = getch();
    if (c != '<') {
        while (c != ERR && !(c >= 'A' && c <= 'Z') && !(c >= 'a' && c <= 'z'))
            c = getch();
        return;
    }
    int n[3] = {0, 0, 0}, k = 0;
    for (;;) {
        c = getch();
        if (c >= '0' && c <= '9') n[k] = n[k] * 10 + c - '0';
        else if (c == ';' && k < 2) k++;
        else break;
    }
    if (c == 'M' || c == 'm') mouselook(n[1] - 1, n[2] - 1);
}

static void sgrmouse(void) {
    if (getch() == '[') sgrmouse_rest();
}

static int esc_or_mouse(void) {
    timeout(15);
    int c = getch();
    timeout(0);
    if (c == ERR) return 1;
    if (c == '[') sgrmouse_rest();
    return 0;
}

static void pause_menu(int *running) {
    int wascap = capturing;
    capturing = 0;
    lastmx = lastmy = -1;
    timeout(250);
    int done = 0;
    while (!done && !quitsig) {
        erase();
        attron(COLOR_PAIR(7) | A_BOLD);
        mvprintw(LINES / 2 - 2, (COLS - 6) / 2, "PAUSED");
        attroff(A_BOLD);
        mvprintw(LINES / 2, (COLS - 27) / 2, "Mouse released while paused");
        attron(A_BOLD);
        mvprintw(LINES / 2 + 2, (COLS - 22) / 2, "Esc/P resume    Q quit");
        attroff(COLOR_PAIR(7) | A_BOLD);
        refresh();
        int k = getch();
        switch (k) {
        case 27:
            if (esc_or_mouse()) done = 1;
            timeout(250);
            break;
        case 'p': case 'P': case ' ': case '\n': done = 1; break;
        case 'q': case 'Q': case 3: *running = 0; done = 1; break;
        case KEY_MOUSE: {
            MEVENT ev;
            getmouse(&ev);
            break;
        }
        }
    }
    capturing = wascap;
    lastmx = lastmy = -1;
    flushinp();
    timeout(0);
}

static void render(void) {
    int rows = LINES, cols = COLS;
    if (cols > ZMAX) cols = ZMAX;
    int horizon = rows / 2 + (int)lround(pitch);
    double pwx = px, pwy = py;
    erase();
    for (int col = 0; col < cols; col++) {
        double ca = ang - FOV / 2 + FOV * (col + 0.5) / cols;
        double rdx = cos(ca), rdy = sin(ca);
        if (fabs(rdx) < 1e-9) rdx = 1e-9;
        if (fabs(rdy) < 1e-9) rdy = 1e-9;
        int mx = (int)pwx, my = (int)pwy;
        double ddx = fabs(1 / rdx), ddy = fabs(1 / rdy);
        int stx = rdx > 0 ? 1 : -1, sty = rdy > 0 ? 1 : -1;
        double sdx = (rdx > 0 ? mx + 1 - pwx : pwx - mx) * ddx;
        double sdy = (rdy > 0 ? my + 1 - pwy : pwy - my) * ddy;
        double raylen = 40;
        for (int it = 0; it < 220; it++) {
            if (sdx < sdy) { raylen = sdx; sdx += ddx; mx += stx; }
            else { raylen = sdy; sdy += ddy; my += sty; }
            if (solid(my, mx) || raylen > 40) break;
        }
        double corrected = raylen * cos(ca - ang);
        if (corrected < 0.05) corrected = 0.05;
        zbuf[col] = corrected;
        int hgt = (int)(rows / corrected);
        if (hgt > 3 * rows) hgt = 3 * rows;
        int top = horizon - hgt / 2, bot = top + hgt;
        static const char wc[] = "##%%++==--::....";
        int shade = (int)(raylen / 3) * 2;
        if (shade > 14) shade = 14;
        attron(COLOR_PAIR(1));
        if (raylen < 4) attron(A_BOLD);
        for (int r = top; r < bot; r++)
            if (r > 0 && r < rows - 1) mvaddch(r, col, wc[shade]);
        attroff(A_BOLD);
        attroff(COLOR_PAIR(1));
        attron(COLOR_PAIR(2));
        for (int r = bot; r < rows - 1; r++)
            if (r > 0 && (r + col) % 2 == 0) mvaddch(r, col, '.');
        attroff(COLOR_PAIR(2));
    }
    Spr sp[64];
    int ns = 0;
    for (int j = lo; j < hi && ns < 60; j++) {
        if (E[j]) sp[ns++] = (Spr){0, E[j] % L + 0.5, E[j] / L + 0.5, '^', 4};
        if (I[j]) sp[ns++] = (Spr){0, I[j] % L + 0.5, I[j] / L + 0.5, '$', 3};
    }
    if (depth <= 99) sp[ns++] = (Spr){0, S[1] + 0.5, S[0] + 0.5, '>', 5};
    if (depth > 0) sp[ns++] = (Spr){0, S[3] + 0.5, S[2] + 0.5, '<', 6};
    for (int i = 0; i < ns; i++)
        sp[i].dist = hypot(sp[i].wx - pwx, sp[i].wy - pwy);
    qsort(sp, ns, sizeof *sp, sprcmp);
    for (int i = 0; i < ns; i++) {
        double dx = sp[i].wx - pwx, dy = sp[i].wy - pwy;
        double a = atan2(dy, dx) - ang;
        while (a > M_PI) a -= 2 * M_PI;
        while (a < -M_PI) a += 2 * M_PI;
        if (fabs(a) > FOV / 2 + 0.5) continue;
        double dc = sp[i].dist * cos(a);
        if (dc < 0.2) continue;
        int scol = (int)((a / FOV + 0.5) * cols);
        int hgt = (int)(rows / dc);
        if (hgt > 2 * rows) hgt = 2 * rows;
        int hs = hgt / 2;
        if (hs < 1) hs = 1;
        int wdt = hs;
        if (wdt > 13) wdt = 13;
        int bot = horizon + hgt / 2, top = bot - hs;
        attron(COLOR_PAIR(sp[i].pair) | A_BOLD);
        for (int c = scol - wdt / 2; c <= scol + wdt / 2; c++) {
            if (c < 0 || c >= cols || dc >= zbuf[c]) continue;
            for (int r = top; r < bot; r++)
                if (r > 0 && r < rows - 1) mvaddch(r, c, sp[i].ch);
        }
        attroff(COLOR_PAIR(sp[i].pair) | A_BOLD);
    }
    if (showmap)
        for (int r = 1; r < 24; r++)
            for (int col = 0; col < L; col++) {
                int ch = cellch(r, col);
                int pair = ch == '$' ? 3 : ch == '^' ? 4 : ch == '>' ? 5 :
                           ch == '<' ? 6 : ch == '@' ? 7 : 1;
                attron(COLOR_PAIR(pair));
                if (ch == '@' || ch == '$' || ch == '^') attron(A_BOLD);
                mvaddch(r, col, ch ? ch : '#');
                attroff(COLOR_PAIR(pair) | A_BOLD);
            }
    attron(COLOR_PAIR(7) | A_BOLD);
    if (!showmap && horizon > 0 && horizon < LINES - 1)
        mvaddch(horizon, cols / 2, '+');
    mvprintw(0, 0, "Score:%d|hp:(%d/%d)|floor:%d|Argv:%x:%02x:%02x:%02x:%02x:%02x",
             money, health, P, depth, seed, depth, health, (int)py, (int)px, money);
    mvprintw(LINES - 1, 0, "WASD move  mouse looks  T teleport(3$)  M map  C capture  Esc pause  Q quit");
    attroff(COLOR_PAIR(7) | A_BOLD);
    refresh();
}

static void mouse_off(void) {
    printf("\033[?1000l\033[?1002l\033[?1003l\033[?1006l");
    fflush(stdout);
}

static void die(int sig) {
    (void)sig;
    quitsig = 1;
}

static int ishex(int ch) {
    return (ch >= '0' && ch <= '9') || (ch >= 'a' && ch <= 'f') ||
           (ch >= 'A' && ch <= 'F');
}

int main(int argc, char **argv) {
    seed = (int)time(0);
    gen();
    int cell = N();
    py = cell / L + 0.5;
    px = cell % L + 0.5;
    if (argc > 1) {
        int ldrow = (int)py, ldcol = (int)px;
        int *slot[] = {&seed, &depth, &health, &ldrow, &ldcol, &money};
        char *cur = argv[1], *end;
        if (*cur && !ishex(*cur)) cur++;
        int nf = 0;
        while (nf < 6 && *cur) {
            slot[nf][0] = (int)strtol(cur, &end, 16);
            nf++;
            cur = *end == ':' ? end + 1 : end;
        }
        if (nf == 6) {
            gen();
            py = ldrow + 0.5;
            px = ldcol + 0.5;
        }
    }
    signal(SIGINT, die);
    signal(SIGTERM, die);
    signal(SIGHUP, die);
    initscr();
    ESCDELAY = 25;
    raw();
    noecho();
    curs_set(0);
    keypad(stdscr, TRUE);
    start_color();
    init_pair(1, COLOR_CYAN, COLOR_BLACK);
    init_pair(2, COLOR_BLUE, COLOR_BLACK);
    init_pair(3, COLOR_YELLOW, COLOR_BLACK);
    init_pair(4, COLOR_RED, COLOR_BLACK);
    init_pair(5, COLOR_BLACK, COLOR_CYAN);
    init_pair(6, COLOR_BLACK, COLOR_MAGENTA);
    init_pair(7, COLOR_WHITE, COLOR_BLACK);
    if (getenv("PROG3D_NOCAPTURE")) capturing = 0;
    mousemask(ALL_MOUSE_EVENTS | REPORT_MOUSE_POSITION, NULL);
    mouseinterval(0);
    printf("\033[?1002h\033[?1003h\033[?1006h");
    fflush(stdout);
    regenat = P;
    long last = now_ms();
    int running = 1, lastcell = (int)py * L + (int)px, eofspin = 0;
    while (running) {
        render();
        timeout(25);
        long before = now_ms();
        int ch = getch();
        if (ch == ERR && now_ms() - before < 5) {
            if (++eofspin > 200) break;
        } else
            eofspin = 0;
        timeout(0);
        while (ch != ERR) {
            double fx = cos(ang) * STEP, fy = sin(ang) * STEP;
            switch (ch) {
            case 'w': case 'W': slide(fx, fy); break;
            case 's': case 'S': slide(-fx, -fy); break;
            case 'a': case 'A': slide(fy, -fx); break;
            case 'd': case 'D': slide(-fy, fx); break;
            case KEY_LEFT: ang -= 0.12; break;
            case KEY_RIGHT: ang += 0.12; break;
            case KEY_UP: pitch += 1.5; clamp_pitch(); break;
            case KEY_DOWN: pitch -= 1.5; clamp_pitch(); break;
            case 'm': case 'M': showmap = !showmap; break;
            case 'c': case 'C': capturing = !capturing; break;
            case 't': case 'T':
                if (money >= 3) {
                    cell = N();
                    py = cell / L + 0.5;
                    px = cell % L + 0.5;
                    money -= 3;
                    lastcell = -1;
                }
                break;
            case KEY_MOUSE: {
                MEVENT ev;
                if (getmouse(&ev) == OK) mouselook(ev.x, ev.y);
                break;
            }
            case 27:
                if (esc_or_mouse()) {
                    pause_menu(&running);
                    last = now_ms();
                }
                break;
            case 'p': case 'P':
                pause_menu(&running);
                last = now_ms();
                break;
            case 'q': case 'Q': case 3: running = 0; break;
            }
            ch = getch();
        }
        int cur = (int)py * L + (int)px;
        if (cur != lastcell) {
            lastcell = cur;
            int prow = cur / L, pcol = cur % L;
            if (depth <= 99 && prow == S[0] && pcol == S[1]) {
                depth++; seed++;
                gen();
                py = S[2] + 0.5;
                px = S[3] + 0.5;
                lastcell = S[2] * L + S[3];
            } else if (depth > 0 && prow == S[2] && pcol == S[3]) {
                depth--; seed--;
                gen();
                py = S[0] + 0.5;
                px = S[1] + 0.5;
                lastcell = S[0] * L + S[1];
            }
        }
        cur = (int)py * L + (int)px;
        for (int j = lo; j < hi; j++)
            if (I[j] && I[j] == cur) {
                money++;
                I[j] = 0;
            }
        long nowt = now_ms();
        while (nowt - last >= TICK_MS) {
            last += TICK_MS;
            ticks++;
            int prow = (int)py, pcol = (int)px;
            for (int j = lo; j < hi; j++) {
                int e = E[j];
                if (!e) continue;
                int a = e / L, b = e % L;
                int yd = abs(a - prow), xd = abs(b - pcol), f = rand() % 4;
                if (ticks % 3 == 0) {
                    int delta = 0;
                    if (yd <= CHASE && xd <= CHASE) {
                        if (xd <= yd)
                            delta = prow <= a ? (a > 0 && openfoe(a - 1, b) ? -L : 0)
                                              : (a < 23 && openfoe(a + 1, b) ? L : 0);
                        else
                            delta = pcol <= b ? (openfoe(a, b - 1) ? -1 : 0)
                                              : (openfoe(a, b + 1) ? 1 : 0);
                    } else if (f == 1) delta = openfoe(a, b - 1) ? -1 : 0;
                    else if (f == 2) delta = e < M - L && openfoe(a + 1, b) ? L : 0;
                    else if (f == 3) delta = openfoe(a, b + 1) ? 1 : 0;
                    else delta = e > L && openfoe(a - 1, b) ? -L : 0;
                    E[j] = e + delta;
                }
                if (ticks % 4 == 1)
                    health -= (yd == 1 && !xd) || (!yd && xd == 1) ? 1 : 0;
            }
            if (ticks == regenat) {
                health += health < P;
                regenat = ticks + P;
            }
        }
        if (health < 1 || depth > 99 || quitsig) running = 0;
    }
    capturing = 0;
    if (!quitsig && (health < 1 || depth > 99)) {
        const char *title = health < 1 ? "EATEN BY CARROTS" : "YOU WIN!";
        timeout(-1);
        erase();
        attron(COLOR_PAIR(7) | A_BOLD);
        mvprintw(LINES / 2 - 1, (COLS - (int)strlen(title)) / 2, "%s", title);
        mvprintw(LINES / 2 + 1, (COLS - 20) / 2, "Score: %d   floor: %d", money, depth);
        mvprintw(LINES / 2 + 3, (COLS - 21) / 2, "Press any key to exit");
        attroff(COLOR_PAIR(7) | A_BOLD);
        refresh();
        flushinp();
        timeout(250);
        int k;
        do {
            k = getch();
            if (k == 27) { sgrmouse(); k = KEY_MOUSE; }
        } while (!quitsig && (k == KEY_MOUSE || k == ERR));
    }
    endwin();
    mouse_off();
    printf("U %s! Score: %d\n",
           health < 1 ? "lose" : depth > 99 ? "win" : "", money);
    return 0;
}
