#pragma once
#include <stdint.h>
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct GlintRAR GlintRAR;
typedef int (*GlintRARConsumer)(const void *, size_t, void *);
// Names are UTF-8. Readers never write member paths to disk.
typedef struct {
    char name[4096];
    uint64_t size;
    uint32_t flags;
    uint32_t dictionaryKB;
    int regular;
} GlintRARHeader;
GlintRAR *glint_rar_open(const char *path, int listing, int *error);
int glint_rar_is_solid(GlintRAR *);
int glint_rar_next(GlintRAR *, GlintRARHeader *);
int glint_rar_process(GlintRAR *, int skip, GlintRARConsumer, void *);
void glint_rar_close(GlintRAR *);
#ifdef __cplusplus
}
#endif
