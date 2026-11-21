import CoreServices
import Foundation

/// Observe des dossiers (FSEvents) et prévient dès qu'un fichier y est créé, modifié ou supprimé,
/// y compris quand il est réécrit « en place » (ce que ne voit pas un simple DispatchSource de dossier).
final class FileWatcher {
    private var stream: FSEventStreamRef?
    private let onChange: () -> Void

    init(paths: [String], latency: TimeInterval = 0.1, onChange: @escaping () -> Void) {
        self.onChange = onChange
        // Les dossiers observés sont créés par leur propriétaire (HookStore.ensureDir) ; on ignore ceux qui n'existent pas.
        let paths = paths.filter { FileManager.default.fileExists(atPath: $0) }
        guard !paths.isEmpty else { return }
        var ctx = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                       retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue().onChange()
        }
        let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        guard let s = FSEventStreamCreate(nil, callback, &ctx, paths as CFArray,
                                          FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency, flags) else { return }
        stream = s
        FSEventStreamSetDispatchQueue(s, DispatchQueue.main)
        FSEventStreamStart(s)
    }

    deinit {
        if let s = stream {
            FSEventStreamStop(s)
            FSEventStreamInvalidate(s)
            FSEventStreamRelease(s)
        }
    }
}
