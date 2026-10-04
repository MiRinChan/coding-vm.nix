#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <netinet/in.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>

/* Simulate a lost outbound interface in the temporary test VM. */
int setsockopt(int fd, int level, int option, const void *value, socklen_t length)
{
    int (*next)(int, int, int, const void *, socklen_t) = dlsym(RTLD_NEXT, "setsockopt");
    const char *family = getenv("VM_TEST_DENY_FAMILY");
    int type = 0;
    socklen_t size = sizeof(type);
    struct sockaddr_storage address;
    socklen_t address_size = sizeof(address);
    if (family && level == SOL_SOCKET && option == SO_BINDTODEVICE &&
        length >= 9 && !memcmp(value, "tailscale0", 9) &&
        !getsockopt(fd, SOL_SOCKET, SO_TYPE, &type, &size) && type == SOCK_STREAM &&
        !getsockname(fd, (struct sockaddr *)&address, &address_size) &&
        address.ss_family == (atoi(family) == 4 ? AF_INET : AF_INET6)) {
        errno = ENODEV;
        return -1;
    }
    return next(fd, level, option, value, length);
}
