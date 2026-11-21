import AppKit
import ServiceManagement
import SwiftUI

/// Command-line tools used by scripts, documentation and debugging. Each one does its job and exits;
/// nothing here runs during a normal launch.
enum DebugCommands {
    /// Runs the first requested tool and exits; returns normally if none was requested.
    static func handleIfRequested() {
        renderDemoImages()
        renderSnapshot()
        handleLoginOptions()
    }

    // MARK: - --demo-images <dir>

    private static func renderDemoImages() {
    if let i = CommandLine.arguments.firstIndex(of: "--demo-images"), i + 1 < CommandLine.arguments.count {
        let dir = CommandLine.arguments[i + 1]
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        MainActor.assumeIsolated {
            let store = AgentStore()
            store.loadDemo()

            @MainActor func backdrop<Content: View>(width: CGFloat, height: CGFloat, @ViewBuilder _ content: () -> Content) -> some View {
                ZStack(alignment: .top) {
                    LinearGradient(colors: [Color(red: 0.10, green: 0.12, blue: 0.30), Color(red: 0.05, green: 0.36, blue: 0.42),
                                            Color(red: 0.36, green: 0.18, blue: 0.48)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Rectangle().fill(Color.white.opacity(0.10)).frame(height: 24).frame(maxHeight: .infinity, alignment: .top)
                    content()
                }
                .frame(width: width, height: height)
            }

            @MainActor func write(_ name: String, _ view: some View) {
                let renderer = ImageRenderer(content: view)
                renderer.scale = 2
                if let img = renderer.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                   let png = rep.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: dir + "/" + name))
                    print(name, img.size)
                }
            }

            @MainActor func model(expanded: Bool) -> IslandModel {
                let m = IslandModel()
                m.expanded = expanded
                m.naturalHeight = true
                m.notchH = 32
                m.notchW = 190
                return m
            }

            // Île dépliée
            let m1 = model(expanded: true)
            write("island-expanded.png", backdrop(width: 760, height: 520) {
                IslandView(store: store, model: m1).frame(width: m1.expandedW, height: 490, alignment: .top)
            })

            // Île dépliée, aperçu du pane au survol
            let m2 = model(expanded: true)
            m2.hoveredPane = store.agents.first { $0.state == .working }?.id
            write("island-preview.png", backdrop(width: 760, height: 640) {
                IslandView(store: store, model: m2).frame(width: m2.expandedW, height: 610, alignment: .top)
            })

            // Île compacte
            let m3 = model(expanded: false)
            write("island-compact.png", backdrop(width: 560, height: 90) {
                IslandView(store: store, model: m3).frame(width: m3.compactW, height: m3.notchH, alignment: .top)
            })

            // Toast à la fin d'une tâche
            let m4 = model(expanded: false)
            m4.toast = store.agents.first { $0.state == .done }
            write("island-toast.png", backdrop(width: 560, height: 90) {
                IslandView(store: store, model: m4).frame(width: m4.compactW, height: m4.notchH, alignment: .top)
            })
        }
        exit(0)
    }
    }

    // MARK: - --snapshot <file>

    private static func renderSnapshot() {
    // Renders the expanded island, with your real sessions, into a PNG (no window is shown).
    if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
        let out = CommandLine.arguments[i + 1]
        MainActor.assumeIsolated {
            let store = AgentStore()
            let model = IslandModel()
            model.naturalHeight = true
            model.expanded = true
            model.historyOpen = true
            store.start()
            RunLoop.main.run(until: Date().addingTimeInterval(2.5))
            let hi = Int(ProcessInfo.processInfo.environment["HOVER_INDEX"] ?? "0") ?? 0
            model.hoveredPane = store.visibleAgents.indices.contains(hi) ? store.visibleAgents[hi].id : nil
            let renderer = ImageRenderer(content: IslandView(store: store, model: model).frame(width: model.expandedW).fixedSize(horizontal: false, vertical: true).background(Color(white: 0.5)))
            renderer.scale = 2
            if let img = renderer.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: out))
                print("snapshot \(img.size)")
            }
        }
        exit(0)
    }
    }

    // MARK: - --login-status | --enable-login | --disable-login

    private static func handleLoginOptions() {
    // Launch-at-login switches, handy in scripts.
    if let flag = CommandLine.arguments.first(where: { ["--login-status", "--enable-login", "--disable-login"].contains($0) }) {
        do {
            if flag == "--enable-login" { try SMAppService.mainApp.register() }
            if flag == "--disable-login" { try SMAppService.mainApp.unregister() }
        } catch { print("erreur: \(error.localizedDescription)"); exit(1) }
        switch SMAppService.mainApp.status {
        case .enabled: print("enabled")
        case .requiresApproval: print("requiresApproval")
        case .notRegistered: print("notRegistered")
        case .notFound: print("notFound")
        @unknown default: print("unknown")
        }
        exit(0)
    }
    }
}
