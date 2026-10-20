// Portable strchrnul for linking the macOS 27 runtime objects with older SDKs.
// The CLT SDK does not yet export this libc declaration/import.
#include <string.h>
char *strchrnul(const char *s, int c) {
    const unsigned char ch = (unsigned char)c;
    while (*s && (unsigned char)*s != ch) ++s;
    return (char *)s;
}
