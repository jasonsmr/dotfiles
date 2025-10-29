#define _GNU_SOURCE
#include <unistd.h>
#include <errno.h>
#include <stdio.h>
#include <string.h>

// Hardcode your SDK aapt2 here to avoid env/paths at runtime.
static const char *REAL = "/data/data/com.termux/files/home/opt/android-sdk/build-tools/34.0.4/aapt2";

int main(int argc, char **argv, char **envp) {
    if (access(REAL, X_OK) != 0) {
        fprintf(stderr, "aapt2-trampoline: %s not executable: %s\n", REAL, strerror(errno));
        return 127;
    }
    execve(REAL, argv, envp);
    fprintf(stderr, "aapt2-trampoline: execve failed: %s\n", strerror(errno));
    return 127;
}
