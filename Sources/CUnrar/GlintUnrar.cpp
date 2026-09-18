#include "GlintUnrar.h"
#include "vendor/rar.hpp"
#include <mutex>

// UnRAR has a global error handler. Serialize its API, including construction
// and destruction, while retaining independent decompressor state per handle.
static std::mutex rarMutex;
struct GlintRAR {
    HANDLE handle = nullptr;
    GlintRARConsumer consumer = nullptr;
    void *context = nullptr;
    bool solid = false;
};
static int callback(UINT message, LPARAM user, LPARAM first, LPARAM second) {
    auto *reader = reinterpret_cast<GlintRAR *>(user);
    if (message == UCM_PROCESSDATA)
        return reader->consumer ? reader->consumer(reinterpret_cast<void *>(first), second, reader->context) : 0;
    // Never prompt on stdin, request passwords, accept large dictionaries,
    // or follow archive volume paths.
    return -1;
}
GlintRAR *glint_rar_open(const char *path, int listing, int *error) {
    std::lock_guard<std::mutex> lock(rarMutex);
    auto *reader = new (std::nothrow) GlintRAR;
    if (!reader) { *error = ERAR_NO_MEMORY; return nullptr; }
    std::wstring name;
    UtfToWide(path, name);
    RAROpenArchiveDataEx options{};
    options.ArcNameW = name.data();
    options.OpenMode = listing ? RAR_OM_LIST : RAR_OM_EXTRACT;
    options.Callback = callback;
    options.UserData = reinterpret_cast<LPARAM>(reader);
    reader->handle = RAROpenArchiveEx(&options);
    reader->solid = (options.Flags & ROADF_SOLID) != 0;
    *error = options.OpenResult;
    if (reader->handle && (options.Flags & (ROADF_VOLUME | ROADF_ENCHEADERS))) {
        *error = (options.Flags & ROADF_ENCHEADERS) ? ERAR_MISSING_PASSWORD : ERAR_UNKNOWN_FORMAT;
        RARCloseArchive(reader->handle);
        reader->handle = nullptr;
    }
    if (!reader->handle) { delete reader; return nullptr; }
    return reader;
}
int glint_rar_is_solid(GlintRAR *reader) { return reader->solid; }
int glint_rar_next(GlintRAR *reader, GlintRARHeader *result) {
    std::lock_guard<std::mutex> lock(rarMutex);
    ErrHandler.Clean();
    RARHeaderDataEx header{};
    int status = RARReadHeaderEx(reader->handle, &header);
    if (status) return status;
    WideToUtf(header.FileNameW, result->name, sizeof(result->name));
    result->size = (uint64_t(header.UnpSizeHigh) << 32) | header.UnpSize;
    result->flags = header.Flags;
    result->dictionaryKB = header.DictSize;
    result->regular = !(header.Flags & RHDF_DIRECTORY) && header.RedirType == 0;
    return 0;
}
int glint_rar_process(GlintRAR *reader, int skip, GlintRARConsumer consumer, void *context) {
    std::lock_guard<std::mutex> lock(rarMutex);
    ErrHandler.Clean();
    reader->consumer = consumer;
    reader->context = context;
    int status = RARProcessFile(reader->handle, skip ? RAR_SKIP : RAR_TEST, nullptr, nullptr);
    reader->consumer = nullptr;
    reader->context = nullptr;
    return status;
}
void glint_rar_close(GlintRAR *reader) {
    std::lock_guard<std::mutex> lock(rarMutex);
    RARCloseArchive(reader->handle);
    delete reader;
}
