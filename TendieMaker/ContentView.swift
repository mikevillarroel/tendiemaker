import AVFoundation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var selectedTab = 0
    @State private var showPicker = false
    @State private var videoURL: URL?
    @State private var videoLabel = "No video selected"
    @State private var videoDuration: Double = 0
    @State private var mode: TendieMode = .cover
    @State private var tendieName = ""
    @State private var isBuilding = false
    @State private var progress = 0.0
    @State private var status = ""
    @State private var outputURL: URL?
    @State private var showShare = false
    @State private var previewImage: UIImage?
    @State private var buildLog: [String] = []
    @State private var logExpanded = true

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                buildTab
                    .tag(0)
                aboutTab
                    .tag(1)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            // AirCard-style floating pill tab bar
            HStack(spacing: 0) {
                tabButton(index: 0, icon: "hammer.fill", label: "Build")
                tabButton(index: 1, icon: "heart.fill", label: "About")
            }
            .padding(8)
            .background(Color(.systemGray6))
            .cornerRadius(28)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .sheet(isPresented: $showPicker) {
            VideoPicker { url, name in
                videoURL = url
                videoLabel = name
                loadDuration(for: url)
            }
        }
        .sheet(isPresented: $showShare) {
            if let outputURL {
                ShareSheet(url: outputURL)
            }
        }
        .onChange(of: showShare) { _, isPresented in
            if !isPresented, !isBuilding, outputURL != nil {
                resetForm()
            }
        }
    }

    private func tabButton(index: Int, icon: String, label: String) -> some View {
        Button {
            selectedTab = index
        } label: {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                Text(label)
                    .font(.caption2)
                    .fontWeight(.semibold)
            }
            .foregroundColor(selectedTab == index ? .blue : .secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(selectedTab == index ? Color(.systemGray5) : Color.clear)
            .cornerRadius(22)
        }
    }

    // MARK: - Build tab

    private var buildTab: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Logo header card
                VStack(spacing: 8) {
                    Image("nav-icon")
                        .resizable()
                        .frame(width: 88, height: 88)
                        .cornerRadius(20)
                    Text("TendieMaker")
                        .font(.title)
                        .fontWeight(.bold)
                    Text("Turn any video into an animated iPhone wallpaper")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .background(Color(.systemGray6))
                .cornerRadius(16)

                // Video section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Video")
                        .font(.headline)
                    Button {
                        showPicker = true
                    } label: {
                        Text("Pick Video")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.blue)
                            .cornerRadius(16)
                    }

                    if videoURL != nil {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(videoLabel)
                                .font(.subheadline)
                            if videoDuration > 0 {
                                Text("\(Int(videoDuration)) seconds")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        // Long video warning
                        if videoDuration > 15 {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Long video")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.orange)
                                    Text("This will make a file around \(estimatedSize). Wallpapers work best at 10 seconds or less — oversized files can cause bootloops when flashing.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(10)
                            .background(Color.orange.opacity(0.12))
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.orange.opacity(0.35), lineWidth: 1)
                            )
                        }
                    }
                }

                // Mode section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Mode")
                        .font(.headline)
                    Picker("Mode", selection: $mode) {
                        ForEach(TendieMode.allCases) { m in
                            Text(m.label).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text(mode.detail)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Name section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Name")
                        .font(.headline)
                    TextField("Tendie name (optional)", text: $tendieName)
                        .autocorrectionDisabled()
                        .padding(12)
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                }

                // Build button
                Button {
                    startBuild()
                } label: {
                    Text(isBuilding ? "Building…" : "Build Tendie")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(videoURL == nil || isBuilding ? Color.gray : Color.blue)
                        .cornerRadius(16)
                }
                .disabled(videoURL == nil || isBuilding)

                if let outputURL, !isBuilding {
                    Button("Share .tendies") {
                        showShare = true
                    }
                    .font(.headline)
                    .foregroundColor(.blue)
                }

                // Build log
                if !buildLog.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Button {
                            logExpanded.toggle()
                        } label: {
                            HStack {
                                Text("Build Log (\(buildLog.count) lines)")
                                    .font(.headline)
                                Spacer()
                                Image(systemName: logExpanded ? "chevron.up" : "chevron.down")
                                    .foregroundColor(.secondary)
                            }
                        }
                        .buttonStyle(.plain)

                        if logExpanded {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 2) {
                                    ForEach(buildLog, id: \.self) { line in
                                        Text(line)
                                            .font(.system(.caption, design: .monospaced))
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxHeight: 160)
                            .padding(10)
                            .background(Color.black)
                            .cornerRadius(8)
                        }
                    }
                }

                // Progress
                if isBuilding {
                    VStack(spacing: 8) {
                        ProgressView(value: progress)
                        Text(status)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        if let previewImage {
                            Text("First frame preview:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Image(uiImage: previewImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxHeight: 220)
                                .cornerRadius(8)
                        }
                    }
                }

                if !status.isEmpty, !isBuilding {
                    Button("Clear", role: .destructive) {
                        resetForm()
                    }
                }

                Spacer(minLength: 80)
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
        }
    }

    // MARK: - About tab

    private var aboutTab: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Refresh Wallpaper
                VStack(alignment: .leading, spacing: 12) {
                    Text("Refresh Wallpaper (Optional)")
                        .font(.headline)
                    Text("After flashing your .tendies with AirCard, iOS sometimes needs a push to reload the wallpaper. The free \"Apply Poster\" shortcut does this — but it only works when added to your Home Screen and run from there, not from inside the Shortcuts app.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Steps: 1) Install the shortcut from the button below. 2) In Shortcuts, long-press it → Share → Add to Home Screen. 3) After flashing, tap the Home Screen icon, then force close PosterBoard to complete the refresh.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button {
                        if let url = URL(string: "https://routinehub.co/shortcut/20381/") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Text("Get Apply Poster Shortcut")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.blue)
                            .cornerRadius(14)
                    }
                }
                .padding(16)
                .background(Color(.systemGray6))
                .cornerRadius(16)

                // About
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Image("profile-photo")
                            .resizable()
                            .frame(width: 44, height: 44)
                            .clipShape(Circle())
                        VStack(alignment: .leading) {
                            Text("Miguel Villarroel")
                                .font(.headline)
                            Text("Developer")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button(action: {
                            if let url = URL(string: "https://x.com/GOT_MUNCH1ES") {
                                UIApplication.shared.open(url)
                            }
                        }) {
                            Image("x-logo")
                                .resizable()
                                .frame(width: 32, height: 32)
                                .cornerRadius(7)
                        }
                        .buttonStyle(.plain)
                        Button(action: {
                            if let url = URL(string: "https://instagram.com/mikevillarroel") {
                                UIApplication.shared.open(url)
                            }
                        }) {
                            Image("instagram-logo")
                                .resizable()
                                .frame(width: 32, height: 32)
                                .cornerRadius(7)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 6)
                    Divider()
                    HStack {
                        Text("🤖")
                            .font(.title2)
                            .frame(width: 44, height: 44)
                            .background(Color(.systemGray5))
                            .clipShape(Circle())
                        VStack(alignment: .leading) {
                            Text("Jarvis")
                                .font(.headline)
                            Text("Collaborator")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                    Divider()

                    // Donate buttons
                    Text("Support TendieMaker")
                        .font(.headline)
                        .padding(.top, 12)
                        .padding(.bottom, 8)
                    Button {
                        if let url = URL(string: "https://paypal.me/mikevillarroel") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        VStack(spacing: 2) {
                            Text("Donate with PayPal")
                                .font(.headline)
                                .foregroundColor(.white)
                            Text("@mikevillarroel")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.blue)
                        .cornerRadius(14)
                    }
                    .padding(.bottom, 8)
                    Button {
                        if let url = URL(string: "https://cash.app/$mikevillarroel") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        VStack(spacing: 2) {
                            Text("Donate with Cash App")
                                .font(.headline)
                                .foregroundColor(.white)
                            Text("$mikevillarroel")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color(red: 0, green: 0.84, blue: 0.2))
                        .cornerRadius(14)
                    }

                    VStack(spacing: 2) {
                        Text("App version: v0.9.3")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Made with 🔥 and chicken tenders")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 12)
                }
                .padding(16)
                .background(Color(.systemGray6))
                .cornerRadius(16)

                Spacer(minLength: 80)
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
        }
    }

    // MARK: - Helpers

    private var estimatedSize: String {
        // ~186KB average per frame, capped at 400 frames
        let fps = 30.0
        let frames = min(400, Int(videoDuration * fps))
        let mb = Double(frames) * 186 / 1024
        if mb >= 100 {
            return "\(Int(mb))MB"
        }
        return String(format: "%.0fMB", mb)
    }

    private func loadDuration(for url: URL) {
        Task {
            let asset = AVURLAsset(url: url)
            if let duration = try? await asset.load(.duration).seconds, duration > 0 {
                await MainActor.run {
                    videoDuration = duration
                }
            }
        }
    }

    private func log(_ line: String) {
        buildLog.append(line)
    }

    private func resetForm() {
        videoURL = nil
        videoLabel = "No video selected"
        videoDuration = 0
        tendieName = ""
        outputURL = nil
        status = ""
        progress = 0
        previewImage = nil
        buildLog = []
    }

    private func startBuild() {
        guard let videoURL else { return }
        isBuilding = true
        progress = 0
        status = "Starting…"
        previewImage = nil
        buildLog = []
        log("tendie: loading video…")

        let raw = tendieName.trimmingCharacters(in: .whitespaces)
        let base = raw.isEmpty
            ? videoURL.deletingPathExtension().lastPathComponent
            : raw
        let safe = base.replacingOccurrences(
            of: "[^A-Za-z0-9_-]+", with: "_", options: .regularExpression)
        let finalName = String(safe.prefix(40))

        Task {
            do {
                let url = try await TendieBuilder.build(
                    videoURL: videoURL, name: finalName, mode: mode
                ) { p, s in
                    progress = p
                    status = s
                    log("tendie: \(s)")
                } onPreview: { img in
                    previewImage = img
                }
                await MainActor.run {
                    outputURL = url
                    status = "Done!"
                    isBuilding = false
                    log("tendie: done — \(url.lastPathComponent)")
                    showShare = true
                }
            } catch {
                let msg = error.localizedDescription
                await MainActor.run {
                    status = "Failed: \(msg)"
                    isBuilding = false
                    log("tendie: FAILED — \(msg)")
                }
            }
        }
    }
}

// MARK: - Video picker

struct VideoPicker: UIViewControllerRepresentable {
    var onPick: (URL, String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .videos
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ vc: PHPickerViewController, context: Context) {}

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        var onPick: (URL, String) -> Void

        init(onPick: @escaping (URL, String) -> Void) {
            self.onPick = onPick
        }

        func picker(_ picker: PHPickerViewController,
                    didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let item = results.first else { return }
            let typeId = item.itemProvider.registeredTypeIdentifiers.first
                ?? UTType.movie.identifier
            item.itemProvider.loadFileRepresentation(forTypeIdentifier: typeId) {
                url, _ in
                guard let url else { return }
                let tmp = FileManager.default.temporaryDirectory
                    .appendingPathComponent(url.lastPathComponent)
                try? FileManager.default.removeItem(at: tmp)
                do {
                    try FileManager.default.copyItem(at: url, to: tmp)
                    DispatchQueue.main.async {
                        self.onPick(tmp, url.lastPathComponent)
                    }
                } catch {
                    // ignore
                }
            }
        }
    }
}

// MARK: - Share sheet

struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
