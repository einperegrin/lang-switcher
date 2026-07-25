import AppKit

// Приложение живёт только в строке меню, поэтому никакого .xib / @main —
// собираем NSApplication вручную и переводим в режим .accessory (нет иконки в Dock).
let app = NSApplication.shared

if CommandLine.arguments.contains("--selftest") {
    exit(SelfTest.run())
}

let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
