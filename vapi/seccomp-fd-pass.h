/* Helpers for seccomp user-notify: pass the listener fd to a supervisor over Unix SCM_RIGHTS.
 * Implementation: seccomp-fd-pass.c (linked alongside Vala code that uses Seccomp.pass_unix_fd). */
#ifndef SECCOMP_FD_PASS_H
#define SECCOMP_FD_PASS_H

int seccomp_fd_pass_send (int socket_fd, int fd_to_pass);
int seccomp_fd_pass_recv (int socket_fd);

#endif
