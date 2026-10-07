import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var showPicker = false
    @State private var videoURL: URL?
    @State private var videoLabel = "No video selected"
    @State private var mode: TendieMode = .cover
    @State private var tendieName = ""
    @State private var isBuilding = false
    @State private var progress = 0.0
    @State private var status = ""
    @State private var outputURL: URL?
    @State private var showShare = false
    @State private var previewImage: UIImage?

    var body: some View {
        NavigationView {
            Form {
                Section("Video") {
                    Button("Pick Video") { showPicker = true }
                    Text(videoLabel)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                Section("Mode") {
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

                Section("Name") {
                    TextField("Tendie name (optional)", text: $tendieName)
                        .autocorrectionDisabled()
                }

                Section {
                    Button(isBuilding ? "Building…" : "Build Tendie") {
                        startBuild()
                    }
                    .disabled(videoURL == nil || isBuilding)
                    if let outputURL, !isBuilding {
                        Button("Share .tendies") {
                            showShare = true
                        }
                    }
                    if !status.isEmpty, !isBuilding {
                        Button("Clear", role: .destructive) {
                            outputURL = nil
                            status = ""
                            progress = 0
                            previewImage = nil
                        }
                    }
                }

                if isBuilding || !status.isEmpty {
                    Section("Progress") {
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
                Section {
                    Text("App version: v0.8.6")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Tendie Maker")
            .sheet(isPresented: $showPicker) {
                VideoPicker { url, name in
                    videoURL = url
                    videoLabel = name
                }
            }
            .sheet(isPresented: $showShare) {
                if let outputURL {
                    ShareSheet(url: outputURL)
                }
            }
            .onChange(of: showShare) { _, isPresented in
                // When the share sheet closes after a finished build,
                // reset the form so the app is ready for the next one.
                if !isPresented, !isBuilding, outputURL != nil {
                    resetForm()
                }
            }
        }
    }

    /// Return the form to its starting state (ready for the next build).
    private func resetForm() {
        videoURL = nil
        videoLabel = "No video selected"
        tendieName = ""
        outputURL = nil
        status = ""
        progress = 0
        previewImage = nil
    }

    private func startBuild() {
        guard let videoURL else { return }
        isBuilding = true
        progress = 0
        status = "Starting…"
        previewImage = nil

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
                } onPreview: { img in
                    previewImage = img
                }
                await MainActor.run {
                    outputURL = url
                    status = "Done!"
                    isBuilding = false
                    showShare = true
                }
            } catch {
                let msg = error.localizedDescription
                await MainActor.run {
                    status = "Failed: \(msg)"
                    isBuilding = false
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
                // The provided URL is transient — copy into our sandbox.
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
