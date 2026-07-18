//
// fps120.m
//
// Loaded via LiveContainer's TweakLoader.
//
// Two things gate the actual frame rate here, and neither is the IL2CPP
// scripting layer:
//   - CADisplayLink.preferredFramesPerSecond -- what we ask for. The game
//     re-applies its own saved setting (60) on loading screens and
//     whenever the settings screen is touched, so this has to be
//     continuously re-asserted, not set once.
//   - CADisplayLink's private `highFrameRateReason` ivar (unsigned int,
//     default 0) -- an internal gate Apple's CA/ProMotion arbitration
//     checks before actually honoring a >60Hz request. Unlike
//     preferredFramesPerSecond, nothing in the game's own code has a
//     reason to touch this, so once set it stays set.
//
// highFrameRateReason is a private scalar ivar, not an object -- so
// object_getIvar/object_setIvar (which only handle `id`-typed ivars) are
// the wrong tool here. This uses ivar_getOffset + a direct pointer poke
// at that byte offset instead.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <dispatch/dispatch.h>
#import <pthread.h>
#import <string.h>
#import <stddef.h>

static CADisplayLink *find_display_link(id UnityAppController) {
    fprintf(stderr, "[fps120] delegate class = %s\n",
            class_getName([UnityAppController class]));

    CADisplayLink *found = nil;
    Class cls = [UnityAppController class];

    // class_copyIvarList only returns ivars declared directly on the class
    // passed in -- it does NOT walk superclasses. The delegate's real
    // runtime class is a dynamically generated GUL_UnityAppController-<uuid>
    // subclass (Google/Firebase's app-delegate swizzler), which adds no
    // ivars of its own -- CADisplayLink actually lives on UnityAppController,
    // one level up. So walk the chain ourselves instead of checking one
    // class only.
    while (cls && !found) {
        unsigned int count = 0;
        Ivar *ivars = class_copyIvarList(cls, &count);
        for (unsigned int i = 0; i < count; i++) {
            const char *type = ivar_getTypeEncoding(ivars[i]);
            if (type && strstr(type, "CADisplayLink")) {
                id value = object_getIvar(UnityAppController, ivars[i]);
                if ([value isKindOfClass:[CADisplayLink class]]) {
                    found = (CADisplayLink *)value;
                    break;
                }
            }
        }
        free(ivars);
        cls = class_getSuperclass(cls);
    }

    return found;
}


// Raw ivar access for a scalar (non-object) field. object_getIvar/
// object_setIvar assume an `id`-sized/typed slot and will read the wrong
// bytes for something like `unsigned int` -- this instead locates the
// ivar's byte offset and pokes memory directly, the same way FLEX does.
static BOOL uint_ivar_ptr(id obj, const char *name, unsigned int **outPtr) {
    Ivar ivar = class_getInstanceVariable([obj class], name);
    if (!ivar) return NO;

    const char *enc = ivar_getTypeEncoding(ivar);
    if (!enc || strcmp(enc, "I") != 0) {
        fprintf(stderr, "[fps120] ivar '%s' has unexpected encoding '%s', skipping\n",
                name, enc ? enc : "(null)");
        return NO;
    }

    ptrdiff_t offset = ivar_getOffset(ivar);
    *outPtr = (unsigned int *)((char *)(__bridge void *)obj + offset);
    return YES;
}

static BOOL set_high_frame_rate_reason(CADisplayLink *link, unsigned int value) {
    unsigned int *field;
    if (uint_ivar_ptr(link, "highFrameRateReason", &field) ||
        uint_ivar_ptr(link, "_highFrameRateReason", &field)) {
        *field = value;
        return YES;
    }
    return NO;
}

static BOOL get_high_frame_rate_reason(CADisplayLink *link, unsigned int *outVal) {
    unsigned int *field;
    if (uint_ivar_ptr(link, "highFrameRateReason", &field) ||
        uint_ivar_ptr(link, "_highFrameRateReason", &field)) {
        *outVal = *field;
        return YES;
    }
    return NO;
}

static void apply_to_link(CADisplayLink *link) {
    if (!link) return;

    if (link.preferredFramesPerSecond != 120) {
        link.preferredFramesPerSecond = 120;
        fprintf(stderr, "[fps120] re-applied preferredFramesPerSecond = 120\n");
    }

    unsigned int reason = 0;
    BOOL known = get_high_frame_rate_reason(link, &reason);
    if (!known || reason != 1) {
        if (set_high_frame_rate_reason(link, 1)) {
            fprintf(stderr, "[fps120] set highFrameRateReason = 1 (was %u)\n", reason);
        }
    }
}

static void *poll_and_apply(void *arg) {
    (void)arg;

    for (;;) {
        dispatch_async(dispatch_get_main_queue(), ^{
            @autoreleasepool {
                id UnityAppController = [[UIApplication sharedApplication] delegate];
                if (UnityAppController) {
                    CADisplayLink *link = find_display_link(UnityAppController);
                    apply_to_link(link);
                }
            }
        });
        sleep(1);
    }
    return NULL;
}

__attribute__((constructor))
static void fps120_init(void) {
    pthread_t t;
    pthread_create(&t, NULL, poll_and_apply, NULL);
    pthread_detach(t);
}
