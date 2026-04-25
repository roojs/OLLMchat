/*
 * POSIX SCM_RIGHTS over a connected Unix SOCK_STREAM socket.
 * Safe in a child after fork() before exec — do not use Gio there.
 */
#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include "seccomp-fd-pass.h"

#include <errno.h>
#include <stddef.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/uio.h>
#include <unistd.h>

int
seccomp_fd_pass_send (int socket_fd, int fd_to_pass)
{
	unsigned char buf[1] = { 0 };
	struct iovec iov = {
		.iov_base = buf,
		.iov_len = 1,
	};
	union {
		struct cmsghdr align;
		char cmsgbuf[CMSG_SPACE (sizeof (int))];
	} u;
	struct msghdr msg = {
		.msg_iov = &iov,
		.msg_iovlen = 1,
		.msg_control = u.cmsgbuf,
		.msg_controllen = sizeof (u.cmsgbuf),
	};
	struct cmsghdr *cmsg = CMSG_FIRSTHDR (&msg);

	cmsg->cmsg_level = SOL_SOCKET;
	cmsg->cmsg_type = SCM_RIGHTS;
	cmsg->cmsg_len = CMSG_LEN (sizeof (int));
	memcpy (CMSG_DATA (cmsg), &fd_to_pass, sizeof (int));
	if (sendmsg (socket_fd, &msg, 0) < 0)
		return -1;
	return 0;
}

int
seccomp_fd_pass_recv (int socket_fd)
{
	unsigned char buf[1];
	struct iovec iov = {
		.iov_base = buf,
		.iov_len = sizeof (buf),
	};
	union {
		struct cmsghdr align;
		char cmsgbuf[CMSG_SPACE (sizeof (int))];
	} u;
	memset (&u, 0, sizeof (u));
	struct msghdr msg = {
		.msg_iov = &iov,
		.msg_iovlen = 1,
		.msg_control = u.cmsgbuf,
		.msg_controllen = sizeof (u.cmsgbuf),
	};
	ssize_t nr = recvmsg (socket_fd, &msg, 0);
	if (nr < 0)
		return -1;
	if (nr == 0) {
		errno = ECONNRESET;
		return -1;
	}
	for (struct cmsghdr *cmsg = CMSG_FIRSTHDR (&msg); cmsg; cmsg = CMSG_NXTHDR (&msg, cmsg)) {
		if (cmsg->cmsg_level == SOL_SOCKET && cmsg->cmsg_type == SCM_RIGHTS) {
			int outfd;
			memcpy (&outfd, CMSG_DATA (cmsg), sizeof (int));
			return outfd;
		}
	}
	errno = ENOENT;
	return -1;
}

ssize_t
seccomp_vm_readv (
	int pid,
	void *local_iov,
	unsigned long liovcnt,
	void *remote_iov,
	unsigned long riovcnt,
	unsigned long flags)
{
	return process_vm_readv (
		pid,
		(struct iovec *) local_iov,
		liovcnt,
		(struct iovec *) remote_iov,
		riovcnt,
		flags);
}
