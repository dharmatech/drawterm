#ifdef _MSC_VER
#include <intrin.h>
#pragma intrinsic(_ReturnAddress)
#endif

#include "u.h"
#include "libc.h"

uintptr
getcallerpc(void *a)
{
	USED(a);
#ifdef _MSC_VER
	return (uintptr)_ReturnAddress();
#else
	return (uintptr)__builtin_extract_return_addr(__builtin_return_address(0));
#endif
}
