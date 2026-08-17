#include <u.h>
#include <libc.h>
#include <draw.h>

typedef double Matrix[3][3];

void invm(Matrix);

/* 19.13 fixed-point number operations */

#define EPSILON		1e-6
#define flt2fix(n)	((long)((n)*(1<<13) + ((n) < 0? -0.5: 0.5)))

static double
fract(double n)
{
	double t;

	return modf(n, &t);
}

Warp
mkwarp(double m0[3][3])
{
	Matrix m;
	Warp w;

	memmove(m, m0, sizeof(Matrix));
	invm(m);

	memset(&w, 0, sizeof w);
	w.m[0][0] = flt2fix(m[0][0]); w.m[0][1] = flt2fix(m[0][1]); w.m[0][2] = flt2fix(m[0][2]);
	w.m[1][0] = flt2fix(m[1][0]); w.m[1][1] = flt2fix(m[1][1]); w.m[1][2] = flt2fix(m[1][2]);
	w.m[2][0] = 0; w.m[2][1] = 0; w.m[2][2] = 1<<13;

	if(m0[0][1] == 0 && m0[1][0] == 0
	&& m0[0][0] > 1 && (fract(m0[0][0]) <= EPSILON || 1.0 - fract(m0[0][0]) <= EPSILON)
	&& m0[1][1] > 1 && (fract(m0[1][1]) <= EPSILON || 1.0 - fract(m0[1][1]) <= EPSILON))
		w.flags |= WFintupscale;
	return w;
}
