//
// fps120.m
//
// Loaded via LiveContainer's TweakLoader.
//
// - Continuously re-applies CADisplayLink.preferredFramesPerSecond = 120
//   and highFrameRateReason = 1 on UnityAppController's display link.
// - Adds a minimalist on-screen FPS counter, measured via its own
//   independent CADisplayLink so the number reflects real screen
//   refreshes, not our polling rate.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <dispatch/dispatch.h>
#import <pthread.h>
#import <string.h>
#import <stddef.h>

#pragma mark - CADisplayLink lookup (frame-rate override)

static CADisplayLink *find_display_link(id appController) {
    CADisplayLink *found = nil;
    Class cls = [appController class];

    // class_copyIvarList only returns ivars declared directly on the class
    // passed in -- it does NOT walk superclasses. The delegate's real
    // runtime class is a dynamically generated GUL_UnityAppController-<uuid>
    // subclass (Google/Firebase's app-delegate swizzler); CADisplayLink
    // actually lives on UnityAppController, one level up. Walk the chain.
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

// Raw ivar access for a scalar (non-object) field -- object_getIvar/
// object_setIvar only handle `id`-typed ivars correctly.
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
    if (self.label) return; // already attached

    UILabel *label = [[UILabel alloc] init];
    label.backgroundColor = [UIColor colorWithWhite:0 alpha:0.45];
    label.textColor = [UIColor colorWithRed:0.35 green:1.0 blue:0.4 alpha:1.0];
    label.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightSemibold];
    label.textAlignment = NSTextAlignmentCenter;
    label.layer.cornerRadius = 6;
    label.layer.masksToBounds = YES;
    label.userInteractionEnabled = NO;
    label.text = @"-- fps";
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

    if (elapsed >= 0.5) { // update the readout twice a second
        double fps = self.frameCount / elapsed;
        self.label.text = [NSString stringWithFormat:@"%.0f FPS", fps];
        self.windowStart = link.timestamp;
        self.frameCount = 0;

        // Cheap insurance in case the game adds subviews above ours later.
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

#pragma mark - Polling loop

static void *poll_and_apply(void *arg) {
    (void)arg;

    for (;;) {
        dispatch_async(dispatch_get_main_queue(), ^{
            @autoreleasepool {
                id appController = [[UIApplication sharedApplication] delegate];
                if (appController) {
                    apply_to_link(find_display_link(appController));
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
        usleep(50 * 1000);
    }
    return NULL;
}

__attribute__((constructor))
static void fps120_init(void) {
    pthread_t t;
    pthread_create(&t, NULL, poll_and_apply, NULL);
    pthread_detach(t);
}
