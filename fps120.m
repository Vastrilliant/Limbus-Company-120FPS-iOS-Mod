#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <dispatch/dispatch.h>
#import <pthread.h>
#import <string.h>

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

@interface FPS120LinkWatcher : NSObject
@property (nonatomic, strong) CADisplayLink *currentLink;
@property (nonatomic, assign) NSInteger targetFPS;
@property (nonatomic, strong) NSTimer *safetyTimer;
+ (instancetype)shared;
- (void)refreshLinkIfNeeded;
- (NSInteger)toggleEnabled;
@end

@implementation FPS120LinkWatcher

+ (instancetype)shared {
    static FPS120LinkWatcher *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [FPS120LinkWatcher new];
        instance.targetFPS = 120;
    });
    return instance;
}

- (void)refreshLinkIfNeeded {
    if (self.currentLink) return;

    id appController = [[UIApplication sharedApplication] delegate];
    if (!appController) return;

    CADisplayLink *link = find_display_link(appController);
    if (!link) return;

    self.currentLink = link;
    [link addObserver:self forKeyPath:@"preferredFramesPerSecond"
              options:NSKeyValueObservingOptionNew context:NULL];

    if (link.preferredFramesPerSecond != self.targetFPS) {
        link.preferredFramesPerSecond = self.targetFPS;
    }

    self.safetyTimer = [NSTimer timerWithTimeInterval:0.25
                                                 target:self
                                               selector:@selector(safetyCheck)
                                               userInfo:nil
                                                repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:self.safetyTimer forMode:NSRunLoopCommonModes];
}

- (void)safetyCheck {
    if (!self.currentLink) return;
    if (self.currentLink.preferredFramesPerSecond != self.targetFPS) {
        self.currentLink.preferredFramesPerSecond = self.targetFPS;
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                       ofObject:(id)object
                         change:(NSDictionary<NSKeyValueChangeKey, id> *)change
                        context:(void *)context {
    if (object == self.currentLink && [keyPath isEqualToString:@"preferredFramesPerSecond"]) {
        NSInteger newValue = [change[NSKeyValueChangeNewKey] integerValue];
        if (newValue != self.targetFPS) {
            self.currentLink.preferredFramesPerSecond = self.targetFPS;
        }
    }
}

- (NSInteger)toggleEnabled {
    self.targetFPS = (self.targetFPS == 120) ? 60 : 120;
    if (self.currentLink) {
        self.currentLink.preferredFramesPerSecond = self.targetFPS;
    }
    return self.targetFPS;
}

- (void)dealloc {
    [self.safetyTimer invalidate];
    if (self.currentLink) {
        [self.currentLink removeObserver:self forKeyPath:@"preferredFramesPerSecond"];
    }
}

@end

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
    label.userInteractionEnabled = YES;
    label.text = @"-- FPS";
    label.autoresizingMask = UIViewAutoresizingFlexibleRightMargin |
                              UIViewAutoresizingFlexibleBottomMargin;

    CGFloat top = window.safeAreaInsets.top + 8;
    CGFloat left = window.safeAreaInsets.left + 8;
    label.frame = CGRectMake(left, top, 74, 26);

    [window addSubview:label];
    [window bringSubviewToFront:label];
    self.label = label;

    UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc] initWithTarget:self
                                                                                  action:@selector(handleDoubleTap:)];
    doubleTap.numberOfTapsRequired = 2;
    [label addGestureRecognizer:doubleTap];

    CADisplayLink *link = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
    link.preferredFrameRateRange = CAFrameRateRangeMake(10, 120, 120);
    [link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    self.measureLink = link;
}

- (void)handleDoubleTap:(UITapGestureRecognizer *)gesture {
    NSInteger newTarget = [[FPS120LinkWatcher shared] toggleEnabled];

    self.measureLink.preferredFrameRateRange = CAFrameRateRangeMake(10, newTarget, newTarget);

    self.label.textColor = (newTarget == 120)
        ? [UIColor colorWithRed:0.35 green:1.0 blue:0.4 alpha:1.0]
        : [UIColor colorWithRed:1.0 green:0.6 blue:0.1 alpha:1.0];
}

- (void)tick:(CADisplayLink *)link {
    if (self.windowStart == 0) {
        self.windowStart = link.timestamp;
        return;
    }

    self.frameCount++;
    CFTimeInterval elapsed = link.timestamp - self.windowStart;

    if (elapsed >= 0.2) {
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

static void *background_worker(void *arg) {
    (void)arg;

    __block BOOL linkReady = NO;
    __block BOOL counterReady = NO;

    while (!linkReady || !counterReady) {
        dispatch_sync(dispatch_get_main_queue(), ^{
            if (!linkReady) {
                [[FPS120LinkWatcher shared] refreshLinkIfNeeded];
                if ([FPS120LinkWatcher shared].currentLink) {
                    linkReady = YES;
                }
            }
            if (!counterReady) {
                UIWindow *window = find_key_window();
                if (window) {
                    g_counter = [FPS120Counter new];
                    [g_counter attachToWindow:window];
                    counterReady = YES;
                }
            }
        });
        if (!linkReady || !counterReady) usleep(200 * 1000);
    }

    return NULL;
}

__attribute__((constructor))
static void fps120_init(void) {
    pthread_t t;
    pthread_create(&t, NULL, background_worker, NULL);
    pthread_detach(t);
}
