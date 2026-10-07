import AVFoundation
import CoreImage
import Foundation
import UIKit

enum TendieMode: String, CaseIterable, Identifiable {
    case cover, fit, native
    var id: String { rawValue }
    var label: String {
        switch self {
        case .cover: return "Cover"
        case .fit: return "Fit"
        case .native: return "Native"
        }
    }
    var detail: String {
        switch self {
        case .cover: return "Fill screen, crop"
        case .fit: return "Whole video, blurred bg"
        case .native: return "Untouched size"
        }
    }
}

enum TendieError: LocalizedError {
    case noVideoTrack
    case badDuration
    case step(String)
    var errorDescription: String? {
        switch self {
        case .noVideoTrack: return "No video track found."
        case .badDuration: return "Could not read video duration."
        case .step(let s): return s
        }
    }
}

struct TendieBuilder {
    static let targetW = 1170
    static let targetH = 2532
    static let frameBudget = 400

    /// providerInfo.plist (binary) from the desktop template, base64.
    private static let providerInfoB64 =
    "YnBsaXN0MDDUAQIDBAUGBwpYJHZlcnNpb25ZJGFyY2hpdmVyVCR0b3BYJG9iamVjdHMSAAGGoF8QD05TS2V5ZWRBcmNoaXZlctEICVRyb290gAGmCwwVFhogVSRudWxs0w0ODxASFFdOUy5rZXlzWk5TLm9iamVjdHNWJGNsYXNzoRGAAqETgAOABV8QHGtDb25maWd1cmF0aW9uTGFzdFVzZURhdGVLZXnSFw8YGVdOUy50aW1lI0HGwARI1HUUgATSGxwdHlokY2xhc3NuYW1lWCRjbGFzc2VzVk5TRGF0ZaIdH1hOU09iamVjdNIbHCEiXxATTlNNdXRhYmxlRGljdGlvbmFyeaMjJB9fEBNOU011dGFibGVEaWN0aW9uYXJ5XE5TRGljdGlvbmFyeQAIABEAGgAkACkAMgA3AEkATABRAFMAWgBgAGcAbwB6AIEAgwCFAIcAiQCLAKoArwC3AMAAwgDHANIA2wDiAOUA7gDzAQkBDQEjAAAAAAAAAgEAAAAAAAAAJQAAAAAAAAAAAAAAAAAAATA="

    /// Build a .tendies package from a video file.
    /// - progress: (0..1, status text), always called on the main actor.
    /// - onPreview: called on the main actor with the first rendered frame,
    ///   so the UI can show what was actually extracted.
    static func build(videoURL: URL, name: String, mode: TendieMode,
                      progress: @escaping (Double, String) -> Void,
                      onPreview: @escaping (UIImage) -> Void) async throws -> URL {
        let cleanName = name.isEmpty ? "Wallpaper" : name
        func report(_ p: Double, _ s: String) async {
            await MainActor.run { progress(p, s) }
        }

        await report(0.02, "Reading video…")
        let asset = AVURLAsset(url: videoURL)
        let duration = try await asset.load(.duration).seconds
        guard duration > 0 else { throw TendieError.badDuration }
        guard let track = try await asset.loadTracks(withMediaType: .video).first
        else { throw TendieError.noVideoTrack }

        let natural = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let display = natural.applying(transform)
        let sw = abs(display.width), sh = abs(display.height)
        var fpsIn = try await track.load(.nominalFrameRate)
        if fpsIn <= 0 { fpsIn = 30 }

        // Fit the 400-frame PosterBoard budget by lowering fps (keep >= 12).
        var fpsOut = min(fpsIn, Float(frameBudget) / Float(duration))
        fpsOut = max(12, min(fpsIn, fpsOut))
        var nframes = Int(duration * Double(fpsOut))
        if nframes > frameBudget {
            fpsOut = Float(frameBudget) / Float(duration)
            nframes = frameBudget
        }
        nframes = max(nframes, 1)

        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.requestedTimeToleranceBefore = .zero
        gen.requestedTimeToleranceAfter = .zero

        let fm = FileManager.default
        let work = fm.temporaryDirectory
            .appendingPathComponent("tendie_\(Int.random(in: 1000...9999))", isDirectory: true)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }

        let desc = work.appendingPathComponent("descriptors/\(cleanName)", isDirectory: true)
        let wpFolder = "\(cleanName)-1170w-2532h@3x~iphone.wallpaper"
        let caFolder = "\(cleanName)_Background-1170w-2532h@3x~iphone.ca"
        let contents = desc.appendingPathComponent("versions/1/contents/\(wpFolder)", isDirectory: true)
        let caDir = contents.appendingPathComponent(caFolder, isDirectory: true)
        let assetsDir = caDir.appendingPathComponent("assets", isDirectory: true)
        try fm.createDirectory(at: assetsDir, withIntermediateDirectories: true)

        let docW = mode == .native ? Int(sw) : targetW
        let docH = mode == .native ? Int(sh) : targetH
        let ciContext = CIContext()

        // 1. Extract + render frames, one JPEG per frame, straight to disk.
        // Uses the modern async API (more reliable than copyCGImage in a loop).
        var written = 0
        var skipped = 0
        for i in 0..<nframes {
            let cmTime = CMTime(seconds: Double(i) / Double(fpsOut), preferredTimescale: 600)
            let cg: CGImage
            do {
                let (img, _) = try await gen.image(at: cmTime)
                cg = img
            } catch {
                skipped += 1
                continue
            }
            guard cg.width > 0 && cg.height > 0 else { skipped += 1; continue }
            // Tone-map HDR (Dolby Vision) to SDR — otherwise JPEGs come out black.
            let ciImage = CIImage(cgImage: cg)
            guard let sdrCG = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
                skipped += 1
                continue
            }
            let rendered: CGImage
            switch mode {
            case .cover: rendered = renderCover(sdrCG)
            case .fit: rendered = renderFit(sdrCG, ciContext: ciContext)
            case .native: rendered = sdrCG
            }
            guard let jpeg = UIImage(cgImage: rendered).jpegData(compressionQuality: 0.82) else {
                skipped += 1
                continue
            }
            try jpeg.write(to: assetsDir.appendingPathComponent("\(written).jpg"))
            if written == 0 {
                let preview = UIImage(cgImage: rendered)
                let pxW = rendered.width, pxH = rendered.height
                await MainActor.run {
                    onPreview(preview)
                    progress(0.05, "First frame: \(pxW)x\(pxH)")
                }
            }
            written += 1
            if i % 10 == 0 {
                await report(0.05 + 0.75 * Double(i) / Double(nframes), "Frame \(i + 1)/\(nframes)…")
            }
        }
        guard written > 0 else {
            throw TendieError.step("No frames extracted (\(skipped) skipped).")
        }
        await report(0.82, "Extracted \(written) frames (\(skipped) skipped)")

        // 2. CAML animation files.
        await report(0.85, "Packaging…")
        try camlMain(width: docW, height: docH, nframes: written, fps: Double(fpsOut))
            .write(to: caDir.appendingPathComponent("main.caml"), atomically: true, encoding: .utf8)
        try camlIndex(width: docW, height: docH)
            .write(to: caDir.appendingPathComponent("index.xml"), atomically: true, encoding: .utf8)

        // 3. Plists.
        let ident = Int.random(in: 10000...99999)
        let wpPlist: [String: Any] = [
            "appearanceAware": true,
            "assets": ["lockAndHome": ["default": [
                "backgroundAnimationFileName": caFolder,
                "floatingAnimationFileNameKey": caFolder,
                "identifier": ident,
                "name": cleanName,
                "type": "LayeredAnimation",
            ]]],
            "contentVersion": 2.01,
            "family": cleanName,
            "identifier": ident,
            "logicalScreenClass": "1170w-2532h@3x~iphone",
            "name": cleanName,
            "preferredProminentColor": ["dark": "#00000", "default": "#FFFFFF"],
            "version": 1,
        ]
        let wpData = try PropertyListSerialization.data(fromPropertyList: wpPlist, format: .binary, options: 0)
        try wpData.write(to: contents.appendingPathComponent("Wallpaper.plist"))

        let userInfo: [String: Any] = [
            "posterEnvironmentOverrides": Data([0x7B, 0x30, 0x3D, 0x7D]), // "{0=}"
            "wallpaperRepresentingFileName": wpFolder,
            "wallpaperRepresentingIdentifier": String(ident),
        ]
        let uiData = try PropertyListSerialization.data(fromPropertyList: userInfo, format: .binary, options: 0)
        try uiData.write(to: desc.appendingPathComponent(
            "versions/1/contents/com.apple.posterkit.provider.contents.userInfo"))

        try "PRPosterRoleLockScreen".write(
            to: desc.appendingPathComponent("com.apple.posterkit.role.identifier"),
            atomically: true, encoding: .utf8)
        try String(ident).write(
            to: desc.appendingPathComponent("com.apple.posterkit.provider.descriptor.identifier"),
            atomically: true, encoding: .utf8)
        guard let provData = Data(base64Encoded: providerInfoB64) else {
            throw TendieError.step("Bad embedded template.")
        }
        try provData.write(to: desc.appendingPathComponent("providerInfo.plist"))

        // 4. Zip as .tendies.
        await report(0.93, "Zipping…")
        var zip = ZipWriter()
        let descriptors = work.appendingPathComponent("descriptors", isDirectory: true)
        guard let enumerator = fm.enumerator(at: descriptors,
                                            includingPropertiesForKeys: [.isDirectoryKey]) else {
            throw TendieError.step("Could not enumerate files.")
        }
        for case let file as URL in enumerator {
            let vals = try file.resourceValues(forKeys: [.isDirectoryKey])
            if vals.isDirectory == true { continue }
            let rel = file.path.replacingOccurrences(of: work.path + "/", with: "")
            zip.add(name: rel, data: try Data(contentsOf: file))
        }
        let zipData = try zip.archive()
        let outURL = fm.temporaryDirectory.appendingPathComponent("\(cleanName).tendies")
        try? fm.removeItem(at: outURL)
        try zipData.write(to: outURL)

        await report(1.0, "Done")
        return outURL
    }

    // MARK: - Frame rendering

    private static func makeContext(w: Int, h: Int) -> CGContext {
        CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    }

    /// Aspect-fill into 1170x2532 (crop).
    private static func renderCover(_ img: CGImage) -> CGImage {
        let w = targetW, h = targetH
        let ctx = makeContext(w: w, h: h)
        let iw = CGFloat(img.width), ih = CGFloat(img.height)
        let s = max(CGFloat(w) / iw, CGFloat(h) / ih)
        let dw = iw * s, dh = ih * s
        ctx.draw(img, in: CGRect(x: (CGFloat(w) - dw) / 2, y: (CGFloat(h) - dh) / 2,
                                 width: dw, height: dh))
        return ctx.makeImage()!
    }

    /// Blurred darkened fill background + whole video on top (no crop).
    private static func renderFit(_ img: CGImage, ciContext: CIContext) -> CGImage {
        let w = targetW, h = targetH
        var bg = renderCover(img)
        if let blur = CIFilter(name: "CIGaussianBlur") {
            blur.setValue(CIImage(cgImage: bg), forKey: kCIInputImageKey)
            blur.setValue(40, forKey: kCIInputRadiusKey)
            if let blurred = blur.outputImage?.cropped(to: CGRect(x: 0, y: 0, width: w, height: h)),
               let dark = CIFilter(name: "CIColorControls") {
                dark.setValue(blurred, forKey: kCIInputImageKey)
                dark.setValue(-0.35, forKey: kCIInputBrightnessKey)
                if let d = dark.outputImage,
                   let cg = ciContext.createCGImage(d, from: CGRect(x: 0, y: 0, width: w, height: h)) {
                    bg = cg
                }
            }
        }
        let ctx = makeContext(w: w, h: h)
        ctx.draw(bg, in: CGRect(x: 0, y: 0, width: w, height: h))
        let iw = CGFloat(img.width), ih = CGFloat(img.height)
        let s = min(CGFloat(w) / iw, CGFloat(h) / ih)
        let dw = iw * s, dh = ih * s
        ctx.draw(img, in: CGRect(x: (CGFloat(w) - dw) / 2, y: (CGFloat(h) - dh) / 2,
                                 width: dw, height: dh))
        return ctx.makeImage()!
    }

    // MARK: - CAML / plist templates

    private static func camlMain(width: Int, height: Int, nframes: Int, fps: Double) -> String {
        let duration = Double(nframes) / fps
        let cx = width / 2, cy = height / 2
        let values = (0..<nframes).map { "\t\t\t<CGImage src=\"assets/\($0).jpg\"/>" }
            .joined(separator: "\n")
        return """
        <?xml version="1.0" encoding="UTF-8"?>

        <caml xmlns="http://www.apple.com/CoreAnimation/1.0">
          <CALayer allowsEdgeAntialiasing="1" allowsGroupOpacity="1" bounds="0 0 \(width) \(height)" contentsFormat="RGBA8" cornerCurve="circular" hidden="0" name="_FLOATING" position="\(cx) \(cy)">
            <sublayers>
              <CATransformLayer allowsEdgeAntialiasing="1" allowsGroupOpacity="1" allowsHitTesting="1" bounds="0 0 \(width) \(height)" contentsFormat="RGBA8" cornerCurve="circular" name="Chip" position="\(cx) \(cy)">
        \t<sublayers>
        \t  <CALayer allowsEdgeAntialiasing="1" allowsGroupOpacity="1" bounds="0 0 \(width) \(height)" contentsFormat="RGBA8" cornerCurve="circular" name="CALayer1" position="\(cx) \(cy)">
        \t    <contents type="CGImage" src="assets/0.jpg"/>
        \t    <animations>
        \t      <animation type="CAKeyframeAnimation" calculationMode="discrete" keyPath="contents" beginTime="1e-100" duration="\(duration)" removedOnCompletion="0" repeatCount="inf" repeatDuration="0" speed="1" timeOffset="0" autoreverses="0">
        \t\t<values>
        \(values)
        \t\t</values>
        \t      </animation>
        \t    </animations>
        \t  </CALayer>
        \t</sublayers>
              </CATransformLayer>
            </sublayers>
            <states>
              <LKState name="Locked">
        \t<elements/>
              </LKState>
              <LKState name="Unlock">
        \t<elements/>
              </LKState>
              <LKState name="Sleep">
        \t<elements/>
              </LKState>
            </states>
            <stateTransitions>
              <LKStateTransition fromState="*" toState="Unlock">
        \t<elements/>
              </LKStateTransition>
              <LKStateTransition fromState="Unlock" toState="*">
        \t<elements/>
              </LKStateTransition>
              <LKStateTransition fromState="*" toState="Locked">
        \t<elements/>
              </LKStateTransition>
              <LKStateTransition fromState="Locked" toState="*">
        \t<elements/>
              </LKStateTransition>
              <LKStateTransition fromState="*" toState="Sleep">
        \t<elements/>
              </LKStateTransition>
              <LKStateTransition fromState="Sleep" toState="*">
        \t<elements/>
              </LKStateTransition>
            </stateTransitions>
          </CALayer>
        </caml>
        """
    }

    private static func camlIndex(width: Int, height: Int) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
        \t<key>assetManifest</key>
        \t<string>assetManifest.caml</string>
        \t<key>documentHeight</key>
        \t<real>\(height)</real>
        \t<key>documentResizesToView</key>
        \t<true/>
        \t<key>documentWidth</key>
        \t<real>\(width)</real>
        \t<key>dynamicGuidesEnabled</key>
        \t<true/>
        \t<key>geometryFlipped</key>
        \t<false/>
        \t<key>guidesEnabled</key>
        \t<true/>
        \t<key>interactiveMouseEventsEnabled</key>
        \t<true/>
        \t<key>interactiveShowsCursor</key>
        \t<true/>
        \t<key>interactiveTouchEventsEnabled</key>
        \t<false/>
        \t<key>loopEnd</key>
        \t<real>0.0</real>
        \t<key>loopStart</key>
        \t<real>0.0</real>
        \t<key>loopingEnabled</key>
        \t<false/>
        \t<key>multitouchDisablesMouse</key>
        \t<false/>
        \t<key>multitouchEnabled</key>
        \t<false/>
        \t<key>presentationMouseEventsEnabled</key>
        \t<true/>
        \t<key>presentationShowsCursor</key>
        \t<true/>
        \t<key>presentationTouchEventsEnabled</key>
        \t<false/>
        \t<key>rootDocument</key>
        \t<string>main.caml</string>
        \t<key>savesWindowFrame</key>
        \t<false/>
        \t<key>scalesToFitInPlayer</key>
        \t<true/>
        \t<key>showsTouches</key>
        \t<true/>
        \t<key>snappingEnabled</key>
        \t<true/>
        \t<key>timelineMarkers</key>
        \t<string>[(null)]</string>
        \t<key>touchesColor</key>
        \t<string>1 1 0 0.8</string>
        \t<key>unitsInPixelsInPlayer</key>
        \t<true/>
        </dict>
        </plist>
        """
    }
}
