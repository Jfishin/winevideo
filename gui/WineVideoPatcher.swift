// WineVideoPatcher — small drag-and-drop GUI to patch a CrossOver 26.2 app with
// the winevideo VP9/video fix. Drop a CrossOver.app, it duplicates it to
// "CrossOver winevideo.app", you scan & pick bottles, then Patch.
//
// The actual patching is delegated to the bundled patch.sh + payload (in
// Contents/Resources), so the GUI is just a thin front-end.

import SwiftUI
import AppKit
import UniformTypeIdentifiers

final class Model: ObservableObject {
    @Published var dupAppPath: String? = nil      // the duplicated "CrossOver winevideo.app"
    @Published var bottles: [String] = []
    @Published var selected: Set<String> = []
    @Published var log: String = "Drop a CrossOver.app above to begin.\n"
    @Published var busy: Bool = false
    @Published var stage: String = ""

    var bottlesDir: String {
        (NSHomeDirectory() as NSString).appendingPathComponent("Library/Application Support/CrossOver/Bottles")
    }
    var resDir: String { Bundle.main.resourcePath ?? "." }

    func append(_ s: String) {
        DispatchQueue.main.async { self.log += s.hasSuffix("\n") ? s : s + "\n" }
    }

    // Duplicate the dropped CrossOver.app -> "CrossOver winevideo.app" next to it.
    func duplicate(from src: URL) {
        guard src.pathExtension == "app",
              FileManager.default.fileExists(atPath: src.appendingPathComponent("Contents/SharedSupport/CrossOver").path) else {
            append("⚠️ That doesn't look like a CrossOver app (no Contents/SharedSupport/CrossOver).")
            return
        }
        // Put the duplicate in ~/Applications (user-writable). Writing INTO an app
        // bundle in /Applications is blocked for Finder-launched apps by macOS
        // "App Management" (TCC); the home Applications folder is not protected.
        // Use a NO-SPACE name (spaces broke copy/verify) and `ditto` (a faithful
        // copy that keeps wine runnable — clonefile copies did not), then strip
        // quarantine so macOS won't SIGKILL the wine binaries.
        let userApps = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Applications")
        try? FileManager.default.createDirectory(at: userApps, withIntermediateDirectories: true)
        let dst = userApps.appendingPathComponent("CrossOver-winevideo.app")
        DispatchQueue.main.async { self.busy = true; self.stage = "Duplicating CrossOver.app → ~/Applications … (this can take a minute)" }
        append("Duplicating (ditto):\n  \(src.path)\n→ \(dst.path)")
        DispatchQueue.global(qos: .userInitiated).async {
            func sh(_ tool: String, _ a: [String]) -> Int32 {
                let pr = Process(); pr.executableURL = URL(fileURLWithPath: tool); pr.arguments = a
                try? pr.run(); pr.waitUntilExit(); return pr.terminationStatus
            }
            if FileManager.default.fileExists(atPath: dst.path) {
                _ = sh("/bin/rm", ["-rf", dst.path])
            }
            let rc = sh("/usr/bin/ditto", [src.path, dst.path])
            _ = sh("/usr/bin/xattr", ["-dr", "com.apple.quarantine", dst.path])
            let ok = rc == 0 && FileManager.default.fileExists(atPath: dst.appendingPathComponent("Contents/SharedSupport/CrossOver/bin/wine").path)
            DispatchQueue.main.async {
                self.busy = false; self.stage = ""
                if ok {
                    self.dupAppPath = dst.path
                    self.append("✅ Duplicate created in your HOME ~/Applications folder:\n   \(dst.path)\n(revealing it in Finder). Now click “Scan bottles”, choose which to patch, then “Patch”.")
                    NSWorkspace.shared.activateFileViewerSelecting([dst])
                } else {
                    self.append("❌ Duplicate failed (ditto rc=\(rc)). Check free disk space.")
                }
            }
        }
    }

    // Only scans when the user asks (no surprise auto-scan).
    func scanBottles() {
        bottles = []; selected = []
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: bottlesDir) else {
            append("No bottles found at \(bottlesDir)"); return
        }
        var found: [String] = []
        for e in entries.sorted() {
            let reg = (bottlesDir as NSString).appendingPathComponent("\(e)/system.reg")
            if fm.fileExists(atPath: reg) { found += [e] }
        }
        bottles = found
        append("Scanned bottles: \(found.isEmpty ? "(none)" : found.joined(separator: ", "))")
    }

    func runPatch() {
        guard let app = dupAppPath else { append("Duplicate an app first."); return }
        let script = (resDir as NSString).appendingPathComponent("patch.sh")
        guard FileManager.default.fileExists(atPath: script) else { append("❌ bundled patch.sh missing"); return }
        var args = [script, app]
        args += Array(selected)
        DispatchQueue.main.async { self.busy = true; self.stage = "Patching…" }
        append("\n=== Patching ===\n\(app)\nbottles: \(selected.isEmpty ? "(all)" : selected.sorted().joined(separator: ", "))")
        run("/bin/bash", args)
    }

    private func run(_ tool: String, _ args: [String]) {
        DispatchQueue.global(qos: .userInitiated).async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: tool)
            p.arguments = args
            // Finder-launched apps get a minimal PATH; give the script the full set
            // so otool/install_name_tool/codesign/python3 resolve.
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin"
            p.environment = env
            let pipe = Pipe()
            p.standardOutput = pipe; p.standardError = pipe
            pipe.fileHandleForReading.readabilityHandler = { h in
                let d = h.availableData
                if !d.isEmpty, let s = String(data: d, encoding: .utf8) { self.append(s) }
            }
            do { try p.run(); p.waitUntilExit() } catch {
                self.append("❌ failed to run: \(error.localizedDescription)")
            }
            pipe.fileHandleForReading.readabilityHandler = nil
            DispatchQueue.main.async {
                self.busy = false; self.stage = ""
                self.append(p.terminationStatus == 0 ? "\n✅ Done. Launch the patched app and play." : "\n❌ exited \(p.terminationStatus)")
            }
        }
    }
}

struct DropZone: View {
    @ObservedObject var m: Model
    @State private var hovering = false
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
                .foregroundColor(hovering ? .accentColor : .secondary)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(hovering ? 0.12 : 0.05)))
            VStack(spacing: 6) {
                Image(systemName: "wineglass").font(.system(size: 28))
                Text(m.dupAppPath == nil ? "Drag your CrossOver.app here" : "Duplicated ✓")
                    .font(.headline)
                Text(m.dupAppPath ?? "creates “CrossOver winevideo.app” next to it")
                    .font(.caption).foregroundColor(.secondary).lineLimit(1).truncationMode(.middle)
            }.padding()
        }
        .frame(height: 110)
        .onDrop(of: [UTType.fileURL], isTargeted: $hovering) { providers in
            guard let p = providers.first else { return false }
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                if let url = url { DispatchQueue.main.async { m.duplicate(from: url) } }
            }
            return true
        }
    }
}

struct ContentView: View {
    @StateObject var m = Model()
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("winevideo — CrossOver 26.2 VP9 / video patcher").font(.title3).bold()
            DropZone(m: m)
            HStack {
                Button { m.scanBottles() } label: { Label("Scan bottles", systemImage: "magnifyingglass") }
                    .disabled(m.busy)
                Spacer()
                Button { m.runPatch() } label: { Label("Patch", systemImage: "bandage") }
                    .keyboardShortcut(.defaultAction).disabled(m.busy || m.dupAppPath == nil)
            }
            if !m.bottles.isEmpty {
                Text("Bottles to patch (none checked = all):").font(.caption).foregroundColor(.secondary)
                ScrollView {
                    VStack(alignment: .leading) {
                        ForEach(m.bottles, id: \.self) { b in
                            Toggle(b, isOn: Binding(
                                get: { m.selected.contains(b) },
                                set: { on in if on { m.selected.insert(b) } else { m.selected.remove(b) } }))
                        }
                    }
                }.frame(height: 90)
            }
            if m.busy { HStack { ProgressView().controlSize(.small); Text(m.stage).font(.caption) } }
            Text("Log").font(.caption).foregroundColor(.secondary)
            ScrollView {
                Text(m.log).font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
            }.frame(maxHeight: .infinity).background(Color.black.opacity(0.04)).cornerRadius(6)
        }
        .padding(16).frame(width: 520, height: 560)
    }
}

@main
struct WineVideoPatcherApp: App {
    var body: some Scene {
        Window("winevideo Patcher", id: "main") { ContentView() }
            .windowResizability(.contentSize)
    }
}
