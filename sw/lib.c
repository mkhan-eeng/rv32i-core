// GCC can emit calls to memset/memcpy even in freestanding code
// (struct copies, zeroing arrays). With no C library, we provide them.
#include <stddef.h>

void *memset(void *dst, int c, size_t n) {
    unsigned char *d = dst;
    while (n--) *d++ = (unsigned char)c;
    return dst;
}

void *memcpy(void *dst, const void *src, size_t n) {
    unsigned char *d = dst;
    const unsigned char *s = src;
    while (n--) *d++ = *s++;
    return dst;
}
