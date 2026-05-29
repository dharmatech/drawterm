#ifdef _MSC_VER
#include <intrin.h>
typedef long MsvcLong;
#pragma intrinsic(_InterlockedExchange)
#endif

#include "u.h"
#include "libc.h"

int
tas(int *x)
{
#ifdef _MSC_VER
	return _InterlockedExchange((volatile MsvcLong*)x, 1);
#else
	return __atomic_test_and_set(x, __ATOMIC_ACQ_REL);
#endif
}
