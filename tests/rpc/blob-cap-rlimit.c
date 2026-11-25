#include "blob-cap-rlimit.h"

#include <stdint.h>
#include <sys/resource.h>

int
blob_cap_getrlimit_as (uint64_t *cur, uint64_t *max)
{
	struct rlimit saved;
	if (getrlimit (RLIMIT_AS, &saved) != 0) {
		return -1;
	}
	*cur = (uint64_t) saved.rlim_cur;
	*max = (uint64_t) saved.rlim_max;
	return 0;
}

int
blob_cap_setrlimit_as (uint64_t cur, uint64_t max)
{
	struct rlimit tight;
	tight.rlim_cur = (rlim_t) cur;
	tight.rlim_max = (rlim_t) max;
	return setrlimit (RLIMIT_AS, &tight);
}
