import AppKit

/// Работа с выделенным текстом: копируем ⌘C, преобразуем, вставляем ⌘V,
/// после чего возвращаем буфер обмена в исходное состояние.
enum SelectionService {
    private static let queue = DispatchQueue(label: "langswitcher.selection", qos: .userInitiated)

    /// - Parameters:
    ///   - transform: выполняется на главном потоке (внутри может дёргаться NSSpellChecker).
    ///   - fallback: вызывается, если выделения не оказалось.
    static func transformSelection(_ transform: @escaping (String) -> String?,
                                   fallback: (() -> Void)? = nil) {
        queue.async {
            TextInjector.waitForModifiersRelease()
            let pasteboard = NSPasteboard.general
            let saved = snapshot(pasteboard)
            let previousChange = pasteboard.clearContents()

            TextInjector.keyStroke(virtualKey: 8, flags: .maskCommand) // ⌘C

            var copied: String?
            let deadline = Date().addingTimeInterval(0.6)
            while Date() < deadline {
                usleep(15_000)
                if pasteboard.changeCount != previousChange {
                    copied = pasteboard.string(forType: .string)
                    if copied != nil { break }
                }
            }

            guard let text = copied, !text.isEmpty else {
                restore(saved, to: pasteboard)
                if let fallback {
                    DispatchQueue.main.async(execute: fallback)
                } else {
                    NSSound.beep()
                }
                return
            }

            let result = DispatchQueue.main.sync { transform(text) }
            guard let output = result, output != text else {
                restore(saved, to: pasteboard)
                return
            }

            pasteboard.clearContents()
            pasteboard.setString(output, forType: .string)
            usleep(30_000)
            TextInjector.keyStroke(virtualKey: 9, flags: .maskCommand) // ⌘V
            usleep(250_000)
            restore(saved, to: pasteboard)
        }
    }

    private static func snapshot(_ pasteboard: NSPasteboard) -> [[String: Data]] {
        pasteboard.pasteboardItems?.map { item in
            var stored: [String: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { stored[type.rawValue] = data }
            }
            return stored
        } ?? []
    }

    private static func restore(_ snapshot: [[String: Data]], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let items: [NSPasteboardItem] = snapshot.map { stored in
            let item = NSPasteboardItem()
            for (type, data) in stored { item.setData(data, forType: NSPasteboard.PasteboardType(type)) }
            return item
        }
        if !items.isEmpty { pasteboard.writeObjects(items) }
    }
}
