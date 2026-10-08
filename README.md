# TendieMaker 🍗

Turn any video into an animated `.tendies` wallpaper for your iPhone.

TendieMaker is a native iOS app that extracts frames from a video on your phone and packages them as a `.tendies` file — ready to flash with [AirCard-iOS]([https://github.com/](https://github.com/Mak5er/AirCard-iOS)]) for animated lock screen / home screen wallpapers.

![TendieMaker icon](TendieMaker/Assets.xcassets/AppIcon.appiconset/icon-1024.png)

## Features

- **Pick any video** from your photo library
- **Three build modes:**
  - **Cover** — fill the screen, crop to fit (default)
  - **Fit** — whole video visible, blurred-fill background
  - **Native** — video's own resolution, untouched
- **Live first-frame preview** while building
- **Up to 400 frames** per tendie (auto-adjusts fps to fit the budget)
- **HDR tone-mapping** — Dolby Vision videos won't come out black
- **Exact frame seeking** — no duplicate frames, smooth playback
- **Stored (uncompressed) ZIP packaging** — avoids a whole class of corruption bugs
- Share the `.tendies` file straight from the app

## Requirements

- iPhone running iOS 17.0+
- Xcode 16+ on a Mac (to build & install)
- An Apple Developer account (free tier works) for signing
- AirCard-iOS to flash the `.tendies` onto your wallpaper

## Build & Install

1. Clone this repo
2. Open `TendieMaker.xcodeproj` in Xcode
3. Select the **TendieMaker** target → **Signing & Capabilities** → pick your Team
4. Select your iPhone as the run destination
5. Hit **Run** (⌘R)

No CocoaPods, no SPM dependencies — pure Swift + SwiftUI, only Apple frameworks (`AVFoundation`, `CoreImage`, `UIKit`).

## How it works

1. `TendieBuilder.swift` — loads the video with `AVAsset`, extracts frames at exact timestamps via `AVAssetImageGenerator` (zero time tolerance), tone-maps HDR→SDR through `CoreImage`, renders per the selected mode, and writes one JPEG per frame.
2. `ZipWriter.swift` — minimal hand-rolled ZIP writer using **stored** (method 0, no compression). JPEGs barely compress anyway, and this sidesteps deflate corruption entirely.
3. The frames + a generated `main.caml` (`CAKeyframeAnimation`, discrete, infinite repeat) are zipped into the `.tendies` package.

## Project structure

```
TendieMaker/
├── TendieMaker/
│   ├── TendieMakerApp.swift   # App entry point
│   ├── ContentView.swift      # UI: picker, mode select, progress, share
│   ├── TendieBuilder.swift    # Frame extraction + .tendies packaging
│   ├── ZipWriter.swift         # Minimal stored-ZIP writer
│   └── Assets.xcassets/       # App icon
└── TendieMaker.xcodeproj/
```

## Lessons learned the hard way

- **Don't deflate in a hand-rolled ZIP writer.** A subtle bug in our custom deflate path produced archives where every entry failed to inflate (`invalid compressed data to inflate`) — tendies flashed completely black. Storing uncompressed fixed it with negligible size cost.
- **`AVAssetImageGenerator` needs zero time tolerance.** Without `requestedTimeToleranceBefore/After = .zero`, it returns the nearest keyframe for many timestamps — we shipped a 149-frame tendie containing only a handful of unique images. Smooth after the fix.
- **HDR videos need tone-mapping** before JPEG encoding, or every frame comes out black.

## Contact

Questions or something broken? Hit me up on X: @GOT_MUNCH1ES or IG @mikevillarroel

## License

MIT — see [LICENSE](LICENSE).
