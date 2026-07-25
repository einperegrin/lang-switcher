import AppKit

enum Sounds {
    static let available = ["Pop", "Tink", "Morse", "Bottle", "Frog", "Funk", "Glass", "Ping", "Purr", "Submarine"]

    static func playSwitch() {
        let prefs = Preferences.shared
        guard prefs.soundEnabled, let sound = NSSound(named: NSSound.Name(prefs.soundName)) else { return }
        sound.volume = 0.35
        sound.stop()
        sound.play()
    }
}
