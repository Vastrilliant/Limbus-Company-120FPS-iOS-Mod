# Limbus120FPS-Mod

A lightweight jailed iOS tweak that unlocks the frame rate cap in **Limbus Company** on ProMotion devices.

## What it does

Unity's iOS player drives its entire render/update loop directly off a `CADisplayLink` owned by `UnityAppController` 
This tweak finds that `CADisplayLink` and forces its `preferredFramesPerSecond` to 120, then keeps it there for the life of the session.

## How it works

`UnityAppController` — Unity's standard iOS app delegate class l normally owns the display link directly. If the app also integrates Firebase or Google Mobile Ads, Google's SDK swizzles the delegate at runtime, inserting a dynamically-generated `GUL_UnityAppController-<uuid>` subclass above it. That subclass has no ivars of its own, so the code walks up the class hierarchy from the delegate's actual runtime class until it finds an ivar whose type encoding contains `CADisplayLink`

Everything else follows from having that object:
- `preferredFramesPerSecond` is set directly, then watched via `addObserver:forKeyPath:` for any future change
- A `NSTimer` on the main run loop re-checks the cached value 4x/second as a safety net for the one reset path that KVO can't see
- The on-screen counter runs a second, independent `CADisplayLink` purely for measurement, decoupled from the one being patched

## Requirements
- A decrypted .ipa of LimbusCompany

- A ProMotion-capable iDevice
- [LiveContainer's](https://github.com/LiveContainer/LiveContainer) Tweakloader or a sideloading service that allows dylib injection, such as Feather, Plumeimpactor or Sideloadly.

- You will need to locate `CADisableMinimumFrameDuration` and `CADisableMinimumFrameDurationOnPhone` in info.plist within the .ipa - both are set to false by default, they need to be set to true, otherwise Limbus will be hardcapped to 60 FPS by iOS itself.

## Building from source

.dylib can be found in the Actions tab.

To build locally instead, on a Mac with Xcode command line tools:

```bash
SDK=$(xcrun --sdk iphoneos --show-sdk-path)
xcrun --sdk iphoneos clang \
  -arch arm64 -arch arm64e \
  -dynamiclib \
  -isysroot "$SDK" \
  -miphoneos-version-min=15.0 \
  -fobjc-arc \
  -framework Foundation \
  -framework UIKit \
  -framework QuartzCore \
  -o LimbusFPS.dylib \
  fps120.m
```


## Disclaimers & Other stuff

Running the game at this framerate will double the game's  processing overhead, each frame will have to be processed within 8.3ms as opposed to 16.6ms on 60fps. This will signifcantly degrade the game's performance on combat encounters. 

A solution I found is by turning on the boolean `frameBufferOnly` in `UnityView > CAMetalLayer`

```objc
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
```

According to Apple's CAMetal API documentation, `frameBufferOnly` is meant to save memory by only processing textures exclusively for rendering. Limbus disables this value for its post-processing (Bloom and Blur). Enabling this value will eliminate the post-processing overhead, increasing performance.

120 FPS and other higher framerates are freely available on desktops using the 'Auto' Framerate setting. This .dylib does NOT provide any sort of game advantage such as speeding up the game. Although it's always best to be careful; provided as-is, use at your own risk. I will not be held responsible for any liabilities.

vibecoded with Claude
