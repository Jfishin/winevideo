// WineVideoPatcher — small drag-and-drop GUI to patch a CrossOver 26.2 app with
// the winevideo VP9/video fix.
//
// Flow (no admin password, no special permissions):
//   1. Drop a CrossOver.app -> it is DUPLICATED to a staging FOLDER
//      "~/Applications/CrossOver-winevideo" (note: not a .app yet).
//   2. Scan bottles, tick the bottle your game runs in.
//   3. Patch -> patch.sh patches + signs the folder as the normal user (macOS
//      "App Management" only protects real .app bundles, so a folder is writable
//      without elevation), renames it to "CrossOver-winevideo.app", and registers
//      VP9 in the selected bottle(s) — all in one step.
//
// The actual patching is delegated to the bundled patch.sh + payload (in
// Contents/Resources), so the GUI is just a thin front-end.

import SwiftUI
import AppKit
import UniformTypeIdentifiers

final class Model: ObservableObject {
    @Published var stagePath: String? = nil       // the staging folder "~/Applications/CrossOver-winevideo"
    @Published var patched: Bool = false          // true once the .app exists (patched)
    @Published var bottles: [String] = []
    @Published var selected: Set<String> = []
    @Published var log: String = "Drop a CrossOver.app above to begin.\n"
    @Published var busy: Bool = false
    @Published var stage: String = ""

    var bottlesDir: String {
        (NSHomeDirectory() as NSString).appendingPathComponent("Library/Application Support/CrossOver/Bottles")
    }
    var resDir: String { Bundle.main.resourcePath ?? "." }
    var finalApp: String? { stagePath.map { $0 + ".app" } }

    func append(_ s: String) {
        DispatchQueue.main.async { self.log += s.hasSuffix("\n") ? s : s + "\n" }
    }

    // Duplicate the dropped CrossOver.app -> a STAGING FOLDER (no .app extension)
    // in ~/Applications. patch.sh later renames it to .app. Using a folder (not a
    // .app) is what lets us patch with no admin prompt: macOS App Management only
    // guards real .app bundles.
    func duplicate(from src: URL) {
        guard src.pathExtension == "app",
              FileManager.default.fileExists(atPath: src.appendingPathComponent("Contents/SharedSupport/CrossOver/bin/wine").path) else {
            append("⚠️ That doesn't look like a CrossOver app (no Contents/SharedSupport/CrossOver/bin/wine).")
            return
        }
        // ~/Applications is user-writable; /Applications is not (for Finder-launched apps).
        // Use a NO-SPACE name (spaces broke copy/verify) and `ditto` (a faithful copy
        // that keeps wine runnable — clonefile copies did not).
        let userApps = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Applications")
        try? FileManager.default.createDirectory(at: userApps, withIntermediateDirectories: true)
        let stageDir = userApps.appendingPathComponent("CrossOver-winevideo").path        // folder
        let appDir   = stageDir + ".app"                                                  // eventual .app
        DispatchQueue.main.async { self.busy = true; self.stage = "Copying CrossOver … (this can take a minute)" }
        append("Copying (ditto):\n  \(src.path)\n→ \(stageDir)")
        DispatchQueue.global(qos: .userInitiated).async {
            func sh(_ tool: String, _ a: [String]) -> Int32 {
                let pr = Process(); pr.executableURL = URL(fileURLWithPath: tool); pr.arguments = a
                try? pr.run(); pr.waitUntilExit(); return pr.terminationStatus
            }
            // clear any previous staging folder AND previously-patched .app
            for p in [stageDir, appDir] where FileManager.default.fileExists(atPath: p) { _ = sh("/bin/rm", ["-rf", p]) }
            let rc = sh("/usr/bin/ditto", [src.path, stageDir])
            _ = sh("/usr/bin/xattr", ["-dr", "com.apple.quarantine", stageDir])
            let ok = rc == 0 && FileManager.default.fileExists(atPath: stageDir + "/Contents/SharedSupport/CrossOver/bin/wine")
            DispatchQueue.main.async {
                self.busy = false; self.stage = ""
                if ok {
                    self.stagePath = stageDir; self.patched = false
                    self.append("✅ Copied — but NOT patched yet.\n   Next: click “Scan bottles”, tick the bottle your game runs in, then click “Patch”.")
                } else {
                    self.append("❌ Copy failed (ditto rc=\(rc)). Check free disk space.")
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
        guard let stage = stagePath, let app = finalApp else { append("Duplicate an app first (drag CrossOver.app above)."); return }
        let script = (resDir as NSString).appendingPathComponent("patch.sh")
        guard FileManager.default.fileExists(atPath: script) else { append("❌ bundled patch.sh missing"); return }
        let fm = FileManager.default
        let stageExists = fm.fileExists(atPath: stage + "/Contents/SharedSupport/CrossOver/bin/wine")  // not yet patched
        let appExists   = fm.fileExists(atPath: app   + "/Contents/SharedSupport/CrossOver/bin/wine")  // already patched
        let bottles = Array(selected)

        // Already patched + nothing new selected -> guide instead of redoing.
        if !stageExists && appExists && bottles.isEmpty {
            append("Already patched. To patch a bottle: click “Scan bottles”, tick it, then “Patch”.")
            return
        }

        DispatchQueue.main.async { self.busy = true; self.stage = "Patching…" }
        append("\n=== Patching ===\nbottles: \(bottles.isEmpty ? "(none selected)" : bottles.sorted().joined(separator: ", "))")
        DispatchQueue.global(qos: .userInitiated).async {
            var rc: Int32 = 0
            if stageExists {
                // Full patch: app files + sign + rename folder->.app + bottle(s). Runs as
                // the user — no admin prompt, no App Management block (it's a folder).
                var args = [script, stage]; args += bottles
                let (r, out) = self.shellOut("/bin/bash", args); rc = r; self.append(out)
            } else if appExists {
                // Re-run for additional bottles only (no bundle writes needed).
                var args = [script, "--bottle-only", app]; args += bottles
                let (r, out) = self.shellOut("/bin/bash", args); rc = r; self.append(out)
            } else {
                DispatchQueue.main.async { self.busy = false; self.stage = "" }
                self.append("❌ Nothing to patch — drag CrossOver.app above first.")
                return
            }
            // Success signal: the patched .app exists and our plugin landed.
            let landed = (try? Data(contentsOf: URL(fileURLWithPath: app + "/Contents/SharedSupport/CrossOver/lib64/gstreamer-1.0/libgstvpx.dylib")))?.count ?? 0 > 0
            DispatchQueue.main.async {
                self.busy = false; self.stage = ""
                if landed {
                    self.patched = true
                    let appURL = URL(fileURLWithPath: app)
                    let extra = bottles.isEmpty ? " (no bottle selected — VP9 games like Ninja Gaiden 4 need their bottle patched: Scan bottles, tick it, Patch again)" : " + bottle(s): \(bottles.sorted().joined(separator: ", "))"
                    self.append("\n✅ PATCHED: \(appURL.lastPathComponent)\(extra)\n   Launch it from ~/Applications and play. (revealing in Finder)")
                    NSWorkspace.shared.activateFileViewerSelecting([appURL])
                } else {
                    self.append("\n❌ Patch did not complete (rc=\(rc)). See the log above for the first error.")
                }
            }
        }
    }

    // run a tool, return (exit code, combined output)
    private func shellOut(_ tool: String, _ args: [String]) -> (Int32, String) {
        let p = Process(); p.executableURL = URL(fileURLWithPath: tool); p.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin"; p.environment = env
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
        do { try p.run() } catch { return (-1, "failed to run \(tool): \(error.localizedDescription)") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
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
                Text(m.stagePath == nil ? "Drag your CrossOver 26.2 app here"
                     : (m.patched ? "Patched ✓" : "Copied — not patched yet"))
                    .font(.headline)
                Text(m.stagePath == nil ? "copies it to ~/Applications/CrossOver-winevideo.app"
                     : (m.finalApp ?? ""))
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
            Text(m.stagePath == nil
                 ? "Step 1 — drag your CrossOver 26.2 app here. This only makes a copy; it does NOT patch anything yet."
                 : (m.patched
                    ? "Done. Launch CrossOver-winevideo.app from ~/Applications. To add another game's bottle: Scan bottles, tick it, Patch."
                    : "Copied — NOT patched yet.\nStep 2 — click “Scan bottles” and tick the bottle your game runs in.\nStep 3 — click “Patch” (patches the app AND the selected bottle together — no password needed)."))
                .font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button { m.scanBottles() } label: { Label("Scan bottles", systemImage: "magnifyingglass").frame(maxWidth: .infinity) }
                    .disabled(m.busy || m.stagePath == nil)
                Button { m.runPatch() } label: { Label("Patch", systemImage: "bandage.fill").frame(maxWidth: .infinity) }
                    .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                    .disabled(m.busy || m.stagePath == nil)
            }
            if !m.bottles.isEmpty {
                Text("Tick the bottle your VP9 game runs in, then click Patch:").font(.caption).foregroundColor(.secondary)
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
        .padding(16).frame(width: 520, height: 580)
    }
}

@main
struct WineVideoPatcherApp: App {
    var body: some Scene {
        Window("winevideo Patcher", id: "main") { ContentView() }
            .windowResizability(.contentSize)
    }
}
