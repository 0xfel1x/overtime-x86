# Legal notes

This is not legal advice. If you need certainty for your situation, ask a lawyer.

## What this repository contains

Only original scripts, a small setup app written from scratch and documentation, under
the MIT license. It contains **no** Apple software, no SDK files, no `.tbd` stubs, no
Swift interfaces, no Xcode components, no Apple artwork and no Apple logos. The app icon
is an original drawing (`scripts/make-icon.swift`). Overtime itself
downloads no Apple software: the only thing it downloads is the open-source Swift
toolchain from swift.org (Apache License 2.0 with Runtime Library Exception), verified
against the swift.org Developer ID signature.

To get the newer Xcode, the app reads the version number from Apple's public release
feed and opens Apple's own download link in your browser. You sign in with your own Apple
Account and download from Apple under Apple's terms; Overtime never sees your account. It
then unpacks the downloaded file with the `xip` tool that is part of macOS.

## Your responsibilities as a user

- **Obtain Xcode yourself from Apple** and accept Apple's license agreements
  (Xcode and Apple SDKs Agreement, macOS Software License Agreement). The scripts only
  operate on copies you already have on your own Mac.
- **Use Apple hardware.** Apple's licenses limit use of macOS, Xcode and the SDKs to
  Apple-branded computers. Overtime is meant for Intel-based Macs. Do not use it on
  non-Apple hardware.
- **Keep generated files private.** The SDK copy (`~/Library/Developer/Overtime`), the
  generated `config/local.xcconfig` and your patched Xcode stay on your Mac. Never
  commit, upload, share or redistribute them. `.gitignore` excludes them from this
  repository.
- **Local modification.** The scripts change local copies of the SDKs (renaming one
  architecture token in text-based link stubs, removing the `State` macro declarations from
  SwiftUI's Swift interfaces, adding one accepted member name to three App Intents macro
  declarations and adding entries to their settings files),
  add symlinks inside your installed Xcode and change the name it displays, pair the
  newer iOS and tvOS SDKs with your installed simulator runtimes in your own simulator
  settings (switching Overtime off undoes these three), and add entries to your own Xcode
  preferences. Whether that
  is permitted is governed by Apple's license agreement, which you should review yourself.
- **Distributing your apps** built with this setup is subject to Apple's normal rules
  (for example App Store requirements). Nothing here changes them.

## For contributors

- Never commit files copied or derived from Xcode, the SDKs or macOS: headers, `.tbd`,
  `.swiftinterface`, binaries, plists, screenshots of Apple UI or icons. The setup app shows the icons of the
  Xcode apps on your Mac at run time; do not add screenshots of it that show them.
- Describe Apple formats in your own words; do not paste Apple header or interface text.
- Use Apple, Xcode, macOS, Swift and Intel only as plain words to describe compatibility.
  No logos, no names that suggest an official product, no "Xcode" or "Apple" in the
  project name.

## Trademarks

Apple, Xcode, macOS, Swift and Apple silicon are trademarks of Apple Inc., registered in
the U.S. and other countries. Intel is a trademark of Intel Corporation. This project is
not affiliated with, endorsed or sponsored by either company.
