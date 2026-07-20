# LimbusFPS

A lightweight jailed iOS tweak that unlocks the frame rate cap in **Limbus Company** on ProMotion devices.

## What it does

Unity's iOS player drives its entire render/update loop directly off a `CADisplayLink` owned by `UnityAppController` 
This tweak finds that `CADisplayLink` and forces its `preferredFramesPerSecond` to 120, then keeps it there for the life of the session.

## Features

- **Unlocks 120fps** on ProMotion-capable devices (iPhone 13 Pro and later)

- **On-screen FPS counter**, top-left corner, measured independently via its own `CADisplayLink`
  
- **Double-tap the counter** to toggle the cap between 120 and 60 on the fly. Text turns orange while the unlock is off, green while it's on.

## How it works

`UnityAppController` — Unity's standard iOS app delegate class — normally owns the display link directly. If the app also integrates Firebase or Google Mobile Ads, Google's SDK swizzles the delegate at runtime, inserting a dynamically-generated `GUL_UnityAppController-<uuid>` subclass above it. That subclass has no ivars of its own, so the code walks up the class hierarchy from the delegate's *actual* runtime class until it finds an ivar whose type encoding contains `CADisplayLink`, rather than assuming any single fixed class or ivar name.

Everything else follows from having that object:
- `preferredFramesPerSecond` is set directly, then watched via `addObserver:forKeyPath:` for any future change
- A `NSTimer` on the main run loop re-checks the cached value 4x/second as a safety net for the one reset path that KVO can't see
- The on-screen counter runs a second, independent `CADisplayLink` purely for measurement, decoupled from the one being patched

## Requirements

- A ProMotion-capable iPhone or iPad (120Hz panel) — without one, there's no higher rate to unlock and this tweak has nothing to do
- [LiveContainer](https://github.com/LiveContainer/LiveContainer)'s Tweakloader or a sideloading service that allows dylib injection, such as Feather, Plumeimpactor or Sideloadly.

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


## Disclaimer

This modifies client-side rendering pacing only (a frame rate cap), no game logic, network traffic, or save data is touched. Provided as-is; use at your own risk and in accordance with the target game's terms of service.

vibecoded with Claude
