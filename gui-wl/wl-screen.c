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
	wl->scale = 1;
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
	int dx, s, x, xx, y, yy;
	u32int *dst, *src;

	s = wl->scale;
	if(wl->compositorversion >= WL_SURFACE_SET_BUFFER_SCALE_SINCE_VERSION)
		wl_surface_set_buffer_scale(wl->surface, s);
	wl_surface_attach(wl->surface, wl->screenbuffer, 0, 0);
	if(wl->dirty){
		dx = Dx(wl->r);
		if(s == 1){
			for(y = wl->r.min.y; y < wl->r.max.y; y++)
				memcpy(wl->shm_data+(y*wl->dx+wl->r.min.x)*4,
					byteaddr(gscreen, Pt(wl->r.min.x, y)), dx*4);
		}else{
			/* Keep Plan 9 coordinates unchanged while supplying a
			 * high-resolution buffer to the compositor. */
			for(y = wl->r.min.y; y < wl->r.max.y; y++){
				src = (u32int*)byteaddr(gscreen, Pt(wl->r.min.x, y));
				for(yy = 0; yy < s; yy++){
					dst = (u32int*)wl->shm_data
						+ (y*s+yy)*(wl->dx*s) + wl->r.min.x*s;
					for(x = 0; x < dx; x++)
						for(xx = 0; xx < s; xx++)
							*dst++ = src[x];
				}
			}
		}
		wl_surface_damage(wl->surface, wl->r.min.x, wl->r.min.y, dx, Dy(wl->r));
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
