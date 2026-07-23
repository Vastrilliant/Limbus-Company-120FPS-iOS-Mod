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

static UIView *find_unity_view(id appController) {
    UIView *found = nil;
    Class cls = [appController class];

    while (cls && !found) {
        unsigned int count = 0;
        Ivar *ivars = class_copyIvarList(cls, &count);
        for (unsigned int i = 0; i < count; i++) {
            const char *type = ivar_getTypeEncoding(ivars[i]);
            if (type && strstr(type, "UnityView")) {
                id value = object_getIvar(appController, ivars[i]);
                if ([value isKindOfClass:[UIView class]]) {
                    found = (UIView *)value;
                    break;
                }
            }
        }
        free(ivars);
        cls = class_getSuperclass(cls);
    }
    return found;
}

static void configure_metal_layer(UIView *unityView) {
    if (!unityView) return;
    if (![unityView.layer isKindOfClass:[CAMetalLayer class]]) return;

    CAMetalLayer *metalLayer = (CAMetalLayer *)unityView.layer;
    metalLayer.framebufferOnly = YES;
}

@interface FPS120LinkWatcher : NSObject
@property (nonatomic, strong) CADisplayLink *currentLink;
@property (nonatomic, assign) NSInteger targetFPS;
@property (nonatomic, strong) NSTimer *safetyTimer;
+ (instancetype)shared;
- (void)refreshLinkIfNeeded;
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

    self.safetyTimer = [NSTimer timerWithTimeInterval:1
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

- (void)dealloc {
    [self.safetyTimer invalidate];
    if (self.currentLink) {
        [self.currentLink removeObserver:self forKeyPath:@"preferredFramesPerSecond"];
    }
}

@end

static void *background_worker(void *arg) {
    (void)arg;

    __block BOOL linkReady = NO;
    __block BOOL metalConfigured = NO;

    while (!linkReady || !metalConfigured) {
        dispatch_sync(dispatch_get_main_queue(), ^{
            if (!linkReady) {
                [[FPS120LinkWatcher shared] refreshLinkIfNeeded];
                if ([FPS120LinkWatcher shared].currentLink) {
                    linkReady = YES;
                }
            }
            if (!metalConfigured) {
                id appController = [[UIApplication sharedApplication] delegate];
                if (appController) {
                    UIView *unityView = find_unity_view(appController);
                    if (unityView) {
                        configure_metal_layer(unityView);
                        metalConfigured = YES;
                    }
                }
            }
        });
        if (!linkReady || !metalConfigured) usleep(200 * 1000);
    }

    return NULL;
}

__attribute__((constructor))
static void fps120_init(void) {
    pthread_t t;
    pthread_create(&t, NULL, background_worker, NULL);
    pthread_detach(t);
}
