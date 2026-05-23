#include	"u.h"
#include	"lib.h"
#include	"dat.h"
#include	"fns.h"
#include	"error.h"

Pgrp*
newpgrp(void)
{
	Pgrp *p;

	p = malloc(sizeof(Pgrp));
	if(p == nil)
		error(Enomem);
	p->ref.ref = 1;
	p->mntordertail = &p->mntorder;
	return p;
}

Rgrp*
newrgrp(void)
{
	Rgrp *r;

	r = malloc(sizeof(Rgrp));
	if(r == nil)
		error(Enomem);
	r->ref.ref = 1;
	return r;
}

void
closergrp(Rgrp *r)
{
	if(decref(&r->ref) == 0)
		free(r);
}

void
closepgrp(Pgrp *p)
{
	Mhead **h, **e, *f;
	Mount *m;

	if(decref(&p->ref))
		return;

	e = &p->mnthash[MNTHASH];
	for(h = p->mnthash; h < e; h++) {
		while((f = *h) != nil){
			*h = f->hash;
			wlock(&f->lock);
			m = f->mount;
			f->mount = nil;
			wunlock(&f->lock);
			mountfree(m);
			putmhead(f);
		}
	}
	free(p);
}

void
pgrpinsert(Pgrp *pg, Mount *m)
{
	m->order = nil;
	*pg->mntordertail = m;
	pg->mntordertail = &m->order;
}

void
pgrpremove(Pgrp *pg, Mount *m)
{
	Mount *f, **l = &pg->mntorder;

	for(f = pg->mntorder; f != nil; f = f->order) {
		if(f == m){
			if((*l = f->order) == nil)
				pg->mntordertail = l;
			f->order = nil;
			return;
		}
		l = &f->order;
	}
}

int
canmount(Pgrp *pgrp)
{
	/*
	 * Devmnt is not usable directly from user procs, so
	 * having it masked is interpreted to block any mounts.
	 */
	return !devmasked(pgrp, devno('M'));
}

int
devmasked(Pgrp *pgrp, int i)
{
	return (pgrp->devmask[i>>3] & 1<<(i&7)) != 0;
}

void
devmask(Pgrp *pgrp, int invert, char *devs)
{
	uchar mask[sizeof pgrp->devmask];
	Rune r;
	int i;

	if(invert)
		invert = 0xFF;

	memset(mask, 0, sizeof mask);		
	while(*devs != '\0') {
		devs += chartorune(&r, devs);
		i = devno(r);
		if(i < 0)
			continue;
		mask[i>>3] |= 1<<(i&7);
	}

	wlock(&pgrp->ns);
	for(i=0; i < sizeof mask; i++)
		pgrp->devmask[i] |= mask[i] ^ invert;
	wunlock(&pgrp->ns);
}

Fgrp*
dupfgrp(Fgrp *f)
{
	Fgrp *new;
	Chan *c;
	int i;

	new = malloc(sizeof(Fgrp));
	if(new == nil)
		error(Enomem);
	new->ref.ref = 1;
	if(f == nil){
		new->nfd = DELTAFD;
		new->fd = malloc(DELTAFD*sizeof(new->fd[0]));
		new->flag = malloc(DELTAFD*sizeof(new->flag[0]));
		if(new->fd == nil || new->flag == nil){
			free(new->flag);
			free(new->fd);
			free(new);
			error(Enomem);
		}
		return new;
	}

	lock(&f->ref.lk);
	/* Make new fd list shorter if possible, preserving quantization */
	new->nfd = f->maxfd+1;
	i = new->nfd%DELTAFD;
	if(i != 0)
		new->nfd += DELTAFD - i;
	new->fd = malloc(new->nfd*sizeof(new->fd[0]));
	new->flag = malloc(new->nfd*sizeof(new->flag[0]));
	if(new->fd == nil || new->flag == nil){
		unlock(&f->ref.lk);
		free(new->flag);
		free(new->fd);
		free(new);
		error(Enomem);
	}
	new->maxfd = f->maxfd;
	for(i = 0; i <= f->maxfd; i++) {
		if((c = f->fd[i]) != nil){
			new->fd[i] = c;
			new->flag[i] = f->flag[i];
			incref(&c->ref);
		}
	}
	unlock(&f->ref.lk);

	return new;
}

void
closefgrp(Fgrp *f)
{
	int i;
	Chan *c;

	if(f == nil || decref(&f->ref))
		return;

	free(f->flag);
	free(f->fd);
	free(f);
}

Mount*
newmount(Chan *to, int flag, char *spec)
{
	Mount *m;

	if(spec == nil)
		spec = "";
	m = malloc(sizeof(Mount)+strlen(spec)+1);
	if(m == nil)
		error(Enomem);
	m->to = to;
	incref(&to->ref);
	m->mflag = flag;
	strcpy(m->spec, spec);
	setmalloctag(m, getcallerpc(&to));
	return m;
}

void
mountfree(Mount *m)
{
	Mount *f;

	while((f = m) != nil) {
		m = m->next;
		cclose(f->to);
		free(f);
	}
}
