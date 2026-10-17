// Compile an SBPL profile with libsandbox's private API and dump the bytecode.
// Compiling does not apply the sandbox, so this works inside another sandbox.
//
// usage: sbcompile <profile.sb | -> [out.bin]

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct sandbox_profile {
    uint32_t type;
    uint32_t pad;
    const void *bytecode;
    size_t bytecode_length;
};

extern void *sandbox_create_params(void);
extern int sandbox_set_param(void *params, const char *key, const char *value);
extern void sandbox_free_params(void *params);
extern struct sandbox_profile *sandbox_compile_string(const char *src, void *params, char **err);
extern void sandbox_free_profile(struct sandbox_profile *profile);

static char *read_all(FILE *f, size_t *len) {
    size_t cap = 1 << 16, n = 0, r;
    char *buf = malloc(cap);
    while ((r = fread(buf + n, 1, cap - n - 1, f)) > 0) {
        n += r;
        if (cap - n < 2) buf = realloc(buf, cap *= 2);
    }
    buf[n] = '\0';
    *len = n;
    return buf;
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: %s <profile.sb | -> [out.bin]\n", argv[0]);
        return 2;
    }
    FILE *in = strcmp(argv[1], "-") == 0 ? stdin : fopen(argv[1], "r");
    if (!in) { perror(argv[1]); return 2; }
    size_t srclen;
    char *src = read_all(in, &srclen);

    void *params = sandbox_create_params();
    char *err = NULL;
    struct sandbox_profile *p = sandbox_compile_string(src, params, &err);
    if (!p) {
        printf("FAIL src_bytes=%zu error=%s\n", srclen, err ? err : "(null)");
        return 1;
    }
    printf("OK src_bytes=%zu type=%u bytecode_bytes=%zu\n", srclen, p->type, p->bytecode_length);
    if (argc > 2) {
        FILE *out = fopen(argv[2], "wb");
        fwrite(p->bytecode, 1, p->bytecode_length, out);
        fclose(out);
    }
    sandbox_free_profile(p);
    sandbox_free_params(params);
    return 0;
}
