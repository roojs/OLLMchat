#ifndef BLOB_CAP_RLIMIT_H
#define BLOB_CAP_RLIMIT_H

#include <stdint.h>

int blob_cap_getrlimit_as (uint64_t *cur, uint64_t *max);
int blob_cap_setrlimit_as (uint64_t cur, uint64_t max);

#endif
