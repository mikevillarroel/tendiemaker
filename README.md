# Tendie Maker — iOS app source

Builds `.tendies` wallpaper packages from a video, on your iPhone.
Same engine as the desktop `build_tendie.py`.

## Install (easy way)

1. Download the unsigned `.ipa` from [Releases](https://github.com/mikevillarroel/tendiemaker/releases).
2. Sign it with [ESign](https://esign.yyyue.xyz), SideStore, or AltStore using your own certificate.
3. Install it on your iPhone.

## Build from source

### Files

- `TendieMakerApp.swift` — app entry point
- `ContentView.swift` — UI: pick video, choose mode, build, share
- `TendieBuilder.swift` — frame extraction (AVFoundation) + .tendies packaging
- `ZipWriter.swift` — dependency-free ZIP writer

## Setup on your Mac (5 min, no terminal)

1. Open **Xcode** → File → New → Project → **iOS → App**.
   - Product Name: `TendieMaker`
   - Interface: **SwiftUI**, Language: **Swift**
   - Save it anywhere.
2. In the project navigator, delete the default `ContentView.swift`.
3. Drag these 4 files into the project (check "Copy items if needed"):
   - `TendieMakerApp.swift`
   - `ContentView.swift`
   - `TendieBuilder.swift`
   - `ZipWriter.swift`
4. Click the project name at the top → **Signing & Capabilities** →
   pick your Apple ID as Team (Xcode → Settings → Accounts to add it).
5. Connect your iPhone with a cable, select it in the run destination
   (top bar, next to the play button), and press **Run** (▶).

That's it — no compiling by hand, Xcode does everything.

## Using the app

1. Tap **Pick Video**, choose one from your library.
2. Pick a mode: **Cover** (fill screen), **Fit** (whole video),
   **Native** (untouched size).
3. Optionally set a name, tap **Build Tendie**.
4. When done, the share sheet pops up with the `.tendies` file —
   save it to Files, then flash it with AirCard like usual.

## Notes

- Free Apple IDs can install on their own devices (re-sign weekly).
- If you have your Signulous certificate, you can also archive an IPA
  in Xcode (Product → Archive) and sign it yourself for longer.
- Frame budget is 400 (PosterBoard cap), min 12 fps — same as desktop.
