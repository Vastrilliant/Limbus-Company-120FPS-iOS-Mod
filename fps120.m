
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <dispatch/dispatch.h>
#import <pthread.h>
#import <string.h>
#import <stddef.h>
#import <dlfcn.h>

#pragma mark - IL2CPP: Application.targetFrameRate / QualitySettings.vSyncCount

typedef void Il2CppDomain;
typedef void Il2CppAssembly;
typedef void Il2CppImage;
typedef void Il2CppClass;
typedef void Il2CppMethod;
typedef void Il2CppObject;

typedef Il2CppDomain*   (*il2cpp_domain_get_t)(void);
typedef const Il2CppAssembly** (*il2cpp_domain_get_assemblies_t)(Il2CppDomain*, size_t*);
typedef const Il2CppImage*     (*il2cpp_assembly_get_image_t)(const Il2CppAssembly*);
typedef Il2CppClass*    (*il2cpp_class_from_name_t)(const Il2CppImage*, const char*, const char*);
typedef const Il2CppMethod* (*il2cpp_class_get_method_from_name_t)(Il2CppClass*, const char*, int);
typedef Il2CppObject*   (*il2cpp_runtime_invoke_t)(const Il2CppMethod*, void*, void**, Il2CppObject**);

static il2cpp_domain_get_t                  p_il2cpp_domain_get;
static il2cpp_domain_get_assemblies_t       p_il2cpp_domain_get_assemblies;
static il2cpp_assembly_get_image_t          p_il2cpp_assembly_get_image;
static il2cpp_class_from_name_t             p_il2cpp_class_from_name;
static il2cpp_class_get_method_from_name_t  p_il2cpp_class_get_method_from_name;
static il2cpp_runtime_invoke_t              p_il2cpp_runtime_invoke;

static int resolve_il2cpp_symbols(void) {
    void *h = RTLD_DEFAULT;
    p_il2cpp_domain_get                 = dlsym(h, "il2cpp_domain_get");
    p_il2cpp_domain_get_assemblies      = dlsym(h, "il2cpp_domain_get_assemblies");
    p_il2cpp_assembly_get_image         = dlsym(h, "il2cpp_assembly_get_image");
    p_il2cpp_class_from_name            = dlsym(h, "il2cpp_class_from_name");
    p_il2cpp_class_get_method_from_name = dlsym(h, "il2cpp_class_get_method_from_name");
    p_il2cpp_runtime_invoke             = dlsym(h, "il2cpp_runtime_invoke");
    return p_il2cpp_domain_get && p_il2cpp_domain_get_assemblies &&
           p_il2cpp_assembly_get_image && p_il2cpp_class_from_name &&
           p_il2cpp_class_get_method_from_name && p_il2cpp_runtime_invoke;
}

static const Il2CppMethod *g_setTargetFrameRate = NULL;
static const Il2CppMethod *g_setVSyncCount = NULL;

static void resolve_il2cpp_methods_if_needed(void) {
    if (g_setTargetFrameRate && g_setVSyncCount) return;
    if (!resolve_il2cpp_symbols()) return;

    Il2CppDomain *domain = p_il2cpp_domain_get();
    if (!domain) return;

    size_t count = 0;
    const Il2CppAssembly **assemblies = p_il2cpp_domain_get_assemblies(domain, &count);
    if (!assemblies) return;

    for (size_t i = 0; i < count; i++) {
        const Il2CppImage *img = p_il2cpp_assembly_get_image(assemblies[i]);
        if (!img) continue;

        if (!g_setTargetFrameRate) {
            Il2CppClass *appCls = p_il2cpp_class_from_name(img, "UnityEngine", "Application");
            if (appCls) g_setTargetFrameRate =
                p_il2cpp_class_get_method_from_name(appCls, "set_targetFrameRate", 1);
        }
        if (!g_setVSyncCount) {
            Il2CppClass *qsCls = p_il2cpp_class_from_name(img, "UnityEngine", "QualitySettings");
            if (qsCls) g_setVSyncCount =
                p_il2cpp_class_get_method_from_name(qsCls, "set_vSyncCount", 1);
        }
    }

    if (g_setTargetFrameRate && g_setVSyncCount) {
        fprintf(stderr, "[fps120] resolved Application/QualitySettings IL2CPP methods\n");
    }
}

static void apply_il2cpp_frame_settings(void) {
    resolve_il2cpp_methods_if_needed();
    if (!g_setTargetFrameRate || !g_setVSyncCount) return;

    int targetFps = 120;
    void *args1[1] = { &targetFps };
    p_il2cpp_runtime_invoke(g_setTargetFrameRate, NULL, args1, NULL);

    int vsync = 0;
    void *args2[1] = { &vsync };
    p_il2cpp_runtime_invoke(g_setVSyncCount, NULL, args2, NULL);
}

#pragma mark - CADisplayLink lookup

static CADisplayLink *find_display_link(id appController) {
    CADisplayLink *found = nil;
    Class cls = [appController class];

    while (cls && !found) {
        unsigned int count = 0;
        Ivar *ivars = class_copyIvarList(cls, &count);
        for (unsigned int i = 0; i < count; i++) {
            const char *type = ivar_getTypeEncoding(ivars[i]);
            if (type && strstr(type, "CADisplayLink")) {
                id value = object_getIvar(appController, ivars[i]);
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

#pragma mark - Watcher: finds the link once, corrects it via KVO thereafter

@interface FPS120LinkWatcher : NSObject
@property (nonatomic, strong) CADisplayLink *currentLink;
+ (instancetype)shared;
- (void)refreshLinkIfNeeded;
@end

@implementation FPS120LinkWatcher

+ (instancetype)shared {
    static FPS120LinkWatcher *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [FPS120LinkWatcher new];
    });
    return instance;
}

- (void)refreshLinkIfNeeded {
    id appController = [[UIApplication sharedApplication] delegate];
    if (!appController) return;

    CADisplayLink *link = find_display_link(appController);
    if (!link || link == self.currentLink) return; // nothing changed

    if (self.currentLink) {
        [self.currentLink removeObserver:self forKeyPath:@"preferredFramesPerSecond"];
    }

    self.currentLink = link;
    [link addObserver:self forKeyPath:@"preferredFramesPerSecond"
              options:NSKeyValueObservingOptionNew context:NULL];

    link.preferredFramesPerSecond = 120;

    unsigned int reason = 0;
    BOOL known = get_high_frame_rate_reason(link, &reason);
    if (!known || reason != 1) {
        if (set_high_frame_rate_reason(link, 1)) {
            fprintf(stderr, "[fps120] set highFrameRateReason = 1 (was %u)\n", reason);
        }
    }

    fprintf(stderr, "[fps120] attached to CADisplayLink %p\n", (__bridge void *)link);
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                       ofObject:(id)object
                         change:(NSDictionary<NSKeyValueChangeKey, id> *)change
                        context:(void *)context {
    if (object == self.currentLink && [keyPath isEqualToString:@"preferredFramesPerSecond"]) {
        NSInteger newValue = [change[NSKeyValueChangeNewKey] integerValue];
        if (newValue != 120) {
            self.currentLink.preferredFramesPerSecond = 120;
            fprintf(stderr, "[fps120] reverted to %ld, corrected instantly\n", (long)newValue);
        }
    }
}

- (void)dealloc {
    if (self.currentLink) {
        [self.currentLink removeObserver:self forKeyPath:@"preferredFramesPerSecond"];
    }
}

@end

#pragma mark - On-screen FPS counter

@interface FPS120Counter : NSObject
@property (nonatomic, strong) UILabel *label;
@property (nonatomic, strong) CADisplayLink *measureLink;
@property (nonatomic, assign) CFTimeInterval windowStart;
@property (nonatomic, assign) NSInteger frameCount;
- (void)attachToWindow:(UIWindow *)window;
@end

@implementation FPS120Counter

- (void)attachToWindow:(UIWindow *)window {
    if (self.label) return;

    UILabel *label = [[UILabel alloc] init];
    label.backgroundColor = [UIColor colorWithWhite:0 alpha:0.45];
    label.textColor = [UIColor colorWithRed:0.35 green:1.0 blue:0.4 alpha:1.0];
    label.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightSemibold];
    label.textAlignment = NSTextAlignmentCenter;
    label.layer.cornerRadius = 6;
    label.layer.masksToBounds = YES;
    label.userInteractionEnabled = NO;
    label.text = @"-- FPS";
    label.autoresizingMask = UIViewAutoresizingFlexibleRightMargin |
                              UIViewAutoresizingFlexibleBottomMargin;

    CGFloat top = window.safeAreaInsets.top + 8;
    CGFloat left = window.safeAreaInsets.left + 8;
    label.frame = CGRectMake(left, top, 74, 26);

    [window addSubview:label];
    [window bringSubviewToFront:label];
    self.label = label;

    CADisplayLink *link = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
    link.preferredFrameRateRange = CAFrameRateRangeMake(10, 120, 120);
    [link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    self.measureLink = link;

    fprintf(stderr, "[fps120] fps counter attached\n");
}

- (void)tick:(CADisplayLink *)link {
    if (self.windowStart == 0) {
        self.windowStart = link.timestamp;
        return;
    }

    self.frameCount++;
    CFTimeInterval elapsed = link.timestamp - self.windowStart;

    if (elapsed >= 0.5) {
        double fps = self.frameCount / elapsed;
        self.label.text = [NSString stringWithFormat:@"%.0f FPS", fps];
        self.windowStart = link.timestamp;
        self.frameCount = 0;
        [self.label.superview bringSubviewToFront:self.label];
    }
}

@end

static FPS120Counter *g_counter = nil;

static UIWindow *find_key_window(void) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]] &&
            scene.activationState == UISceneActivationStateForegroundActive) {
            for (UIWindow *window in ((UIWindowScene *)scene).windows) {
                if (window.isKeyWindow) return window;
            }
        }
    }
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]]) {
            NSArray<UIWindow *> *windows = ((UIWindowScene *)scene).windows;
            if (windows.count > 0) return windows.firstObject;
        }
    }
    return nil;
}

#pragma mark - Main loop

static void *poll_and_apply(void *arg) {
    (void)arg;

    for (;;) {
        dispatch_async(dispatch_get_main_queue(), ^{
            @autoreleasepool {
                [[FPS120LinkWatcher shared] refreshLinkIfNeeded];

                if ([FPS120LinkWatcher shared].currentLink) {
                    apply_il2cpp_frame_settings();
                }

                if (!g_counter) {
                    UIWindow *window = find_key_window();
                    if (window) {
                        g_counter = [FPS120Counter new];
                        [g_counter attachToWindow:window];
                    }
                }
            }
        });
        usleep(1000 * 1000);
    }
    return NULL;
}

__attribute__((constructor))
static void fps120_init(void) {
    pthread_t t;
    pthread_create(&t, NULL, poll_and_apply, NULL);
    pthread_detach(t);
}
