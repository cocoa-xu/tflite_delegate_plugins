// Opens a plugin the way TFLite's external delegate loader does and exercises
// both entry points. Passing means the ABI is right and, on a machine without a
// usable GPU, that being refused is survivable -- which is the case that takes a
// host process down when a plugin gets it wrong.
#include <dlfcn.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>

typedef struct TfLiteDelegate TfLiteDelegate;
typedef TfLiteDelegate *(*create_fn)(const char *const *, const char *const *,
                                     size_t, void (*)(const char *));
typedef void (*destroy_fn)(TfLiteDelegate *);

static void on_error(const char *message) {
    printf("  plugin reported: %s\n", message);
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: %s <plugin> [--reject-unknown-options]\n", argv[0]);
        return 2;
    }
    int strict = argc > 2 && strcmp(argv[2], "--reject-unknown-options") == 0;

    void *lib = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
    if (lib == NULL) {
        printf("  dlopen failed: %s\n", dlerror());
        return 1;
    }
    printf("  dlopen ok\n");

    create_fn create = (create_fn)dlsym(lib, "tflite_plugin_create_delegate");
    destroy_fn destroy = (destroy_fn)dlsym(lib, "tflite_plugin_destroy_delegate");
    if (create == NULL || destroy == NULL) {
        printf("  missing entry points: create=%p destroy=%p\n",
               (void *)create, (void *)destroy);
        return 1;
    }
    printf("  both entry points resolved\n");

    TfLiteDelegate *delegate = create(NULL, NULL, 0, on_error);
    if (delegate == NULL) {
        // A refusal is a valid outcome: no device, no driver, unusable options.
        printf("  create declined (no usable device here) -- survived\n");
    } else {
        printf("  create returned a delegate\n");
        destroy(delegate);
        printf("  destroy ok\n");
    }

    // Upstream's own ParseOptions tests every key with a bare strcmp, which is
    // true on mismatch, so the OpenCL plugin accepts invented option names and
    // files their values under the wrong field. Adaptors we write must not.
    if (strict) {
        const char *keys[] = {"definitely_not_an_option"};
        const char *values[] = {"1"};
        TfLiteDelegate *bogus = create(keys, values, 1, on_error);
        if (bogus != NULL) {
            printf("  FAIL: an unknown option was accepted\n");
            destroy(bogus);
            return 1;
        }
        printf("  unknown option refused\n");
    }

    dlclose(lib);
    printf("  PASS\n");
    return 0;
}
