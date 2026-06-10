#ifndef SHIM_CURSES_H
#define SHIM_CURSES_H

#include <stdio.h>

typedef unsigned long chtype;
typedef struct _win_st WINDOW;
typedef struct { short id; int x, y, z; unsigned long bstate; } MEVENT;

#define ERR (-1)
#define OK 0
#ifndef TRUE
#define TRUE 1
#endif
#ifndef FALSE
#define FALSE 0
#endif

#define COLOR_BLACK 0
#define COLOR_RED 1
#define COLOR_GREEN 2
#define COLOR_YELLOW 3
#define COLOR_BLUE 4
#define COLOR_MAGENTA 5
#define COLOR_CYAN 6
#define COLOR_WHITE 7

#define A_BOLD (1L << 24)
#define A_DIM (1L << 25)
#define COLOR_PAIR(n) (((long)(n) & 0xff) << 8)

#define KEY_DOWN 0x102
#define KEY_UP 0x103
#define KEY_LEFT 0x104
#define KEY_RIGHT 0x105
#define KEY_MOUSE 0x199
#define KEY_RESIZE 0x19a

#define ALL_MOUSE_EVENTS 0xffffffL
#define REPORT_MOUSE_POSITION 0x1000000L

extern int LINES, COLS, ESCDELAY;
extern WINDOW *stdscr;

WINDOW *initscr(void);
int endwin(void);
int noecho(void);
int raw(void);
int cbreak(void);
int curs_set(int visibility);
int start_color(void);
int init_pair(short pair, short fg, short bg);
int attron(long attrs);
int attroff(long attrs);
int erase(void);
int refresh(void);
int move(int y, int x);
int mvaddch(int y, int x, chtype ch);
chtype mvinch(int y, int x);
int mvprintw(int y, int x, const char *fmt, ...);
int getch(void);
void timeout(int delay_ms);
int keypad(WINDOW *win, int enable);
unsigned long mousemask(unsigned long mask, unsigned long *oldmask);
int mouseinterval(int interval);
int getmouse(MEVENT *event);
int flushinp(void);

#endif
