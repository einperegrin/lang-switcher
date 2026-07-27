# LangSwitcher

Automatic keyboard layout correction for macOS — in the spirit of Punto Switcher and
Caramba Switcher. Lives in the menu bar, notices words typed in the wrong layout,
fixes them, and switches the layout for you.

```
ghbdtn ,скщ    →    привет мир
руддщ цщкдв    →    hello world
```

## Why another one

Written for myself, to avoid depending on paid and closed-source layout switchers.
I wanted three things: to work on modern macOS, to be open source (a program that
reads everything you type should be one you can actually look inside), and to send
nothing anywhere.

Nothing is saved to disk or sent over the network. The buffer of typed keystrokes
lives only in memory, holds the last 96 keypresses, and is cleared on a mouse click,
app switch, Enter, or Esc. There is deliberately no "diary" — a log of everything
typed, which some alternatives have.

## Features

- **Automatic layout correction.** A word typed in the wrong layout is corrected the
  moment it's finished — by a space or punctuation mark — along with the layout
  itself.
- **Correcting the last word with a double right Shift.** Press Shift twice in a
  row — the last word flips. Pressing it again undoes the flip.
- **Correcting selected text** — `⌃⌥L`. If nothing is selected, it behaves like a
  double Shift.
- **Transliterating the selection** — `⌃⌥T` (`привет` ⇄ `privet`).
- **Changing the case of the selection** — `⌃⌥U` (lowercase → UPPERCASE → Title
  Case).
- **Autocorrect** — a custom dictionary of abbreviations, triggered at word
  boundaries.
- **Layout indicator** in the menu bar, a sound on switch, launch at login.
- **Exceptions** — apps where input isn't analyzed; terminals and password managers
  are excluded by default. Hotkeys keep working in them.

All shortcuts and the double-press key can be changed in settings.

## Installation

Requires Xcode Command Line Tools and macOS 13+.

```bash
git clone https://github.com/einperegrin/lang-switcher.git
cd lang-switcher
make install
```

The app will build and install to `/Applications/LangSwitcher.app`.

### Input access

On first launch, macOS will ask for access in **System Settings → Privacy &
Security → Accessibility**. Without it, keyboard capture isn't possible. The app
picks up the permission automatically — no restart needed.

### The checkbox is on, but the app keeps asking for access

This happens after every rebuild, and here's why. The app has no Developer ID, so
macOS ties the permission to a requirement like
`identifier "com.langswitcher.app" and cdhash H"…"` — that is, **to the hash of the
specific binary**. A new build produces a new hash, the old TCC database entry stops
matching, but the list still shows a row with the toggle switched on. Toggling it
off and on again doesn't help — the entry needs to be removed entirely:

```bash
tccutil reset Accessibility com.langswitcher.app
open /Applications/LangSwitcher.app
```

After that, grant access once — the entry will be created for the current binary.
`make install` prints the same two commands.

If you rebuild often, you can make the permission stick: create a self-signed code
signing certificate (Keychain Access → Certificate Assistant → Create a Certificate
→ type "Code Signing") and replace `--sign -` with `--sign "Certificate Name"` in
the `Makefile`. Then the TCC requirement will be tied to the certificate instead of
the hash, and will survive rebuilds.

## How it works

1. A `CGEvent tap` intercepts keypresses. For each one, the **physical keyCode with
   modifiers** is remembered, not just the typed character.
2. To "flip" a word, the same keyCodes are re-run through `UCKeyTranslate` with
   another layout's data. That's why there are no lookup tables like `й→q` in the
   code, and any pair of layouts installed on the system works — even Russian with
   German.
3. Word boundaries are also determined by keys, not by characters. The keys `,` `.`
   `;` `'` `[` `]` produce the letters `б ю ж э х ъ` in the Russian layout, so `,.hj`
   is a single word ("бюро"), not punctuation followed by `hj`. Such a mark counts as
   part of the word only when letters follow it; the period ending `hello.` stays
   punctuation.
4. A two-stage detector makes the decision. First, the system spelling dictionary
   (`NSSpellChecker`): a word that doesn't exist in the current language but becomes
   a dictionary word after conversion is almost certainly a layout mistake. Words
   outside the dictionaries — and there are plenty, the system Russian dictionary
   doesn't even know the word "раскладку" (layout) — are evaluated by a phonotactic
   model: allowed letter combinations plus vowel ratio. This second check catches
   what bigrams miss: `hfcrkflrf` — nine consonants in a row, an impossible pattern
   for a real word.
5. The correction is performed with backspaces and unicode-event insertion, so it
   doesn't depend on the active layout.

The trigger threshold is deliberately conservative: missing a correction is less
annoying than mangling a correctly typed word.

## Development

```bash
swift build -c release
.build/release/LangSwitcher --selftest   # 52 checks on your layouts
make run                                 # build and run without installing
```

The self-test synthesizes real keyCodes from the installed layouts and runs the
whole pipeline end to end — from the physical key to the detector's decision,
including false-positive checks (`npm`, `git`, `ssh`, `kubectl` must not be
touched).

## Limitations

- **Sentences mixing words from different languages** are processed word by word,
  which works worse than uniform text: short foreign-language insertions are often
  missed by the detector. That's exactly what the double Shift is for.
- The double Shift corrects the word from the internal buffer. If you clicked
  elsewhere with the mouse or switched apps, the buffer is empty and the app just
  beeps briefly.
- macOS doesn't hand keyboard events to any app, including this one, in password
  fields. That's correct behavior and isn't fixable.
- Working with selected text uses the clipboard (⌘C/⌘V) and then restores its
  previous contents.

## License

MIT.
