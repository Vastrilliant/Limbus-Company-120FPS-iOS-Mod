# Limbus-Company-120FPS-iOS-Mod
Force Limbus to run at 120FPS using CADisplayLink

.dylib can be found in Actions

## Requirements 
1. Decrypted .ipa of LimbusCompany 
2. Sideloading service that supports .dylib injection or LiveContainer's TweakLoader

## How it works
Finds CADisplayLink located in UnityAppController, within CADisplayLink there are two relevant strings: PreferredFramesPerSecond & an undocumented int HighFrameRateReason 

The .dylib overrides these values to force the game to run at 120FPS. 

You'll need to edit the info.plist inside Limbus' app bundle and locate CADisableMinimumFrameDuration and CADisableMinimumFrameDurationOnPhone, both values are set to false by default, you need to set them to true

## Disclaimer 
Because this will make limbus run at 120 frames at all times, obviously you should not use this if you're playing on Rien's beeper. I will not be held responsible by you nor the Index if your device suffers any damages

vibecoded using Claude Sonnet 5 Max because I'm a fraud
