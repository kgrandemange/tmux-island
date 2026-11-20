import Carbon
import Foundation

/// Raccourcis globaux (Carbon : aucune permission d'accessibilité requise).
final class HotKeyCenter {
    static let shared = HotKeyCenter()
    private var handlers: [UInt32: () -> Void] = [:]
    private var refs: [EventHotKeyRef] = []
    private var installed = false
    private var nextID: UInt32 = 1

    func register(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        if !installed {
            installed = true
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
                var hk = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                  nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
                HotKeyCenter.shared.handlers[hk.id]?()
                return noErr
            }, 1, &spec, nil, nil)
        }
        let id = nextID
        nextID += 1
        handlers[id] = handler
        var ref: EventHotKeyRef?
        RegisterEventHotKey(keyCode, modifiers, EventHotKeyID(signature: OSType(0x544D5849), id: id),
                            GetApplicationEventTarget(), 0, &ref)
        if let ref { refs.append(ref) }
    }

    /// Libère tous les raccourcis (avant de les réenregistrer après un changement de réglage).
    func unregisterAll() {
        for r in refs { UnregisterEventHotKey(r) }
        refs.removeAll()
        handlers.removeAll()
    }
}
