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
        let bottles = Array(selected)
        DispatchQueue.main.async { self.busy = true; self.stage = "Patching… (you'll be asked for your password once)" }
        append("\n=== Patching ===\n\(app)\nbottles: \(bottles.isEmpty ? "(all)" : bottles.sorted().joined(separator: ", "))")
        DispatchQueue.global(qos: .userInitiated).async {
            // 1) APP files as ADMIN — macOS blocks a GUI app from modifying another
            //    .app's contents (App Management TCC); an admin prompt bypasses that.
            //    Wrap in a temp script so spaced paths don't fight AppleScript escaping.
            let tmp = "/tmp/winevideo-apppatch.sh"
            let body = "#!/bin/bash\nexport PATH=/usr/bin:/bin:/usr/sbin:/sbin\nexec /bin/bash \"\(script)\" --app-only \"\(app)\"\n"
            try? body.write(toFile: tmp, atomically: true, encoding: .utf8)
            _ = self.shell("/bin/chmod", ["+x", tmp])
            let osa = "do shell script \"/bin/bash /tmp/winevideo-apppatch.sh 2>&1\" with administrator privileges"
            let (rc1, out1) = self.shellOut("/usr/bin/osascript", ["-e", osa])
            self.append(out1.isEmpty ? "(app-file step finished, rc=\(rc1))" : out1)
            try? FileManager.default.removeItem(atPath: tmp)
            // confirm the app files actually landed (the real success signal)
            let soOK = (try? Data(contentsOf: URL(fileURLWithPath: app + "/Contents/SharedSupport/CrossOver/lib64/gstreamer-1.0/libgstvpx.dylib")))?.count ?? 0 > 0
            // 2) BOTTLE registry as the USER — ONLY if bottles were selected (wine must NOT run as root).
            var rc2: Int32 = 0
            if !bottles.isEmpty {
                var bargs = [script, "--bottle-only", app]; bargs += bottles
                let (r, out2) = self.shellOut("/bin/bash", bargs); rc2 = r
                self.append(out2)
            } else {
                self.append("(no bottles selected — app is patched; use “Scan bottles” + select to register VP9 per game bottle)")
            }
            DispatchQueue.main.async {
                self.busy = false; self.stage = ""
                if soOK && rc2 == 0 { self.append("\n✅ APP PATCHED. Launch it and play. (rc app=\(rc1))") }
                else if !soOK { self.append("\n❌ App files did NOT get installed (admin step rc=\(rc1)). If no password prompt appeared, the admin step was blocked — try again, or run the patcher from Terminal.") }
                else { self.append("\n⚠️ App patched but a bottle step had issues (rc=\(rc2)).") }
            }
        }
    }

    // run a tool, return exit code only
    @discardableResult private func shell(_ tool: String, _ args: [String]) -> Int32 {
        let p = Process(); p.executableURL = URL(fileURLWithPath: tool); p.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin"; p.environment = env
        do { try p.run() } catch { return -1 }
        p.waitUntilExit(); return p.terminationStatus
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
            Text(m.dupAppPath == nil
                 ? "Step 1 — drop your CrossOver.app above (it makes a copy)."
                 : "Step 2 — click “Patch app” (asks for your password; this is what actually applies the fix).\nStep 3 (optional) — Scan bottles, tick the ones holding your games, then Patch app again.")
                .font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button { m.runPatch() } label: { Label("Patch app", systemImage: "bandage.fill").frame(maxWidth: .infinity) }
                    .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                    .disabled(m.busy || m.dupAppPath == nil)
                Button { m.scanBottles() } label: { Label("Scan bottles (optional)", systemImage: "magnifyingglass") }
                    .disabled(m.busy || m.dupAppPath == nil)
            }
            if !m.bottles.isEmpty {
                Text("Bottles to register VP9 in (tick the ones with your games, then Patch app):").font(.caption).foregroundColor(.secondary)
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
