#define _GNU_SOURCE

#include "u.h"
#include "lib.h"
#include "dat.h"
#include "fns.h"
#include "user.h"
#include <draw.h>
#include <memdraw.h>

#undef up

#include <wayland-client.h>
#include <wayland-client-protocol.h>
#include <linux/input-event-codes.h>
#include <xkbcommon/xkbcommon.h>
#include <libdecor-0/libdecor.h>
#include "xdg-shell-protocol.h"

#include "screen.h"
#include "wl-inc.h"

static Wlwin *gwin;

Memimage *gscreen;

static Wlwin*
newwlwin(void)
{
	Wlwin *wl;

	wl = mallocz(sizeof *wl, 1);
	if(wl == nil)
		panic("malloc Wlwin");
	wl->dx = 1024;
	wl->dy = 1024;
	wl->monx = wl->dx;
	wl->mony = wl->dy;
	return wl;
}

void
wlclose(Wlwin *wl)
{
	wl->runing = 0;
	exits(nil);
}

void
wlflush(Wlwin *wl)
{
	Point p;

	wl_surface_attach(wl->surface, wl->screenbuffer, 0, 0);
	if(wl->dirty){
		p.x = wl->r.min.x;
		for(p.y = wl->r.min.y; p.y < wl->r.max.y; p.y++)
			memcpy(wl->shm_data+(p.y*wl->dx+p.x)*4, byteaddr(gscreen, p), Dx(wl->r)*4);
		wl_surface_damage(wl->surface, p.x, wl->r.min.y, Dx(wl->r), Dy(wl->r));
		wl->dirty = 0;
	}
	wl_surface_commit(wl->surface);
}

void
wlresize(Wlwin *wl, int x, int y)
{
	Rectangle r;

	r = Rect(0, 0, x, y);
	screenresize(r);
}

void
dispatchproc(void *a)
{
	Wlwin *wl;
	wl = a;
	while(wl->runing)
		libdecor_dispatch(wl->decor, -1);
}

static Wlwin*
wlattach(char *label)
{
	Rectangle r;
	Wlwin *wl;

	wl = newwlwin();
	gwin = wl;
	wl->display = wl_display_connect(nil);
	if(wl->display == nil)
		panic("could not connect to display");

	memimageinit();
	wlsetcb(wl);
	wlflush(wl);
	wlsettitle(wl, label);

	r = Rect(0, 0, wl->dx, wl->dy);
	gscreen = allocmemimage(r, XRGB32);
	gscreen->clipr = r;

	wl->runing = 1;
	kproc("wldispatch", dispatchproc, wl);
	qlock(&drawlock);

	terminit();
	wlflush(wl);
	qunlock(&drawlock);
	return wl;
}

void
screeninit(void)
{
	wlattach("drawterm");
}

void
guimain(void)
{
	cpubody();
}

Memdata*
attachscreen(Rectangle *r, ulong *chan, int *depth, int *width, int *softscreen)
{
	*r = gscreen->clipr;
	*chan = gscreen->chan;
	*depth = gscreen->depth;
	*width = gscreen->width;
	*softscreen = 1;

	gscreen->data->ref++;
	return gscreen->data;
}

void
flushmemscreen(Rectangle r)
{
	gwin->dirty = 1;
	gwin->r = r;
	wlflush(gwin);
}

void
screensize(Rectangle r, ulong chan)
{
	gwin->dx = Dx(r);
	gwin->dy = Dy(r);

	wlallocbuffer(gwin);
	if(gscreen != nil)
		freememimage(gscreen);
	gscreen = allocmemimage(r, chan);
	gscreen->clipr = ZR;
	flushmemscreen(r);
}

void
setcursor(void)
{
	qlock(&drawlock);
	wldrawcursor(gwin, &cursor);
	qunlock(&drawlock);
}

void
mouseset(Point p)
{
	wlsetmouse(gwin, p);
}

char*
clipread(void)
{
	return wlgetsnarf(gwin);
}

int
clipwrite(char *data)
{
	wlsetsnarf(gwin, data);
	return strlen(data);
}

void
getcolor(ulong i, ulong *r, ulong *g, ulong *b)
{
}

void
setcolor(ulong index, ulong red, ulong green, ulong blue)
{
}
