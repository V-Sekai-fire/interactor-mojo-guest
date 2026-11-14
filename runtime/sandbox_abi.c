/* The guest-side half of the godot-sandbox host contract: the size of this
 * program's Variant, in a .sandbox_variant section. A host whose own Variant
 * differs (24 bytes single precision, 40 bytes double) refuses the program at
 * load. Same layout as program/cpp/docker/api/api.cpp in godot-sandbox. */
#include <stdint.h>

struct SandboxVariantSize {
    char magic[4];
    uint32_t size;
};

__attribute__((used, retain, section(".sandbox_variant")))
const struct SandboxVariantSize sandbox_variant_size = { { 'S', 'B', 'X', 'V' }, SANDBOX_VARIANT_SIZE };
