# Overtime

*Extra time for Intel Macs.*

Build x86_64 Mac software against a **newer macOS SDK on an Intel Mac**, after the newest
developer tools stopped running on Intel.

Newer Xcode releases install only on Apple silicon, but their macOS SDK still contains
everything needed to build for x86_64: headers, `.tbd` link stubs and x86_64 Swift
interfaces. Overtime combines three things that already exist on (or can be legally
obtained for) your Mac:

| Piece | Source |
| --- | --- |
| Newer macOS SDK | the newer Xcode **you** downloaded from Apple (only its SDK files are read) |
| Swift compiler matching that SDK | open-source toolchain from [swift.org](https://www.swift.org/install/macos/), universal binary |
| Linker, codesign, asset/interface compilers | the older Xcode that still runs on your Intel Mac |

This repository contains **only scripts, a small setup app in source form and
documentation**. It contains no Apple software,
SDK files or Xcode components, and never downloads any from third parties. Read
[LEGAL.md](LEGAL.md) before use.

## Requirements

- An **Intel Mac** (Apple hardware) with macOS supported by the older Xcode.
- The older, Intel-capable Xcode installed (default `/Applications/Xcode.app`).
- The newer Xcode downloaded from Apple and unpacked (default `/Applications/Xcode-27.app`).
  It does not need to run; only its SDK directory is read.
- About 5 GB of disk space for the swift.org toolchain. The SDK copy and the optional
  Xcode clone are APFS clones and use very little extra space.

## Setup

### With the app

```sh
scripts/build-app.sh
open build/Overtime.app
```

Drop both Xcode apps on the window, in any order. Overtime looks at each one and works
out which is the Xcode that runs on your Mac and which is the newer one; Xcodes in
`/Applications`, `~/Applications` and `~/Downloads` are found automatically. Click
**Set Up**. When it finishes, the window shows what was prepared, with buttons to open
the prepared Xcode and to copy the `PATH` line for the Terminal.

The app copies the scripts and commands to `~/Library/Developer/Overtime`, so it works
without this checkout afterwards. It is signed ad hoc for the Mac it was built on.

### In Terminal

```sh
scripts/setup.sh              # SDK copy + matching swift.org toolchain + xcconfig
scripts/setup.sh --with-ide   # additionally a private local Xcode clone for the IDE
export PATH="$PWD/bin:$PATH"
```

Paths can be changed with environment variables (`OT_HOST_XCODE`, `OT_NEW_XCODE`,
`OT_HOME`, `OT_TOOLCHAINS_DIR`, `OT_CLONE`), see [lib/common.sh](lib/common.sh).
Re-run the setup after updating either Xcode.

## Use

**In Xcode:** open your project with the local clone (`~/Applications/Xcode-SDK<version>.app`).
It builds with the newer SDK and the matching Swift compiler by itself; nothing has to be
changed in the project. The Xcode build system only resolves SDKs inside its own platform
folder, so the clone gets one symlink there and your installed Xcode stays untouched.
`xcodebuild` works the same way: `DEVELOPER_DIR=<clone>/Contents/Developer xcodebuild ...`.

To pin SDK, compiler and architecture for one project regardless of the defaults, use the
generated configuration as its base configuration (see
[Example/Overtime.xcconfig](Example/Overtime.xcconfig)).

**In Terminal:**

| Command | Purpose |
| --- | --- |
| `ot-clang`, `ot-clang++` | C, C++, Objective-C |
| `ot-swiftc` | Swift compiler |
| `ot-swift build/run/test` | Swift Package Manager |

```sh
ot-swiftc -target x86_64-apple-macos13 main.swift -o app
ot-swift build -c release
otool -l app | grep -A5 LC_BUILD_VERSION   # shows the newer SDK version
```

Notes on the clone:

- The added symlink changes the clone's bundle contents, so `codesign --verify` reports
  a modified bundle for the clone. That is expected; the installed Xcode is not changed.
- Xcode shows its platform selection window once for every SDK it has not seen. The
  script marks the new SDK as seen in your Xcode preferences so projects open directly.
- After updating the older Xcode, delete the clone and run the setup again.

## How it works

1. `scripts/make-sdk.sh` clones the newer SDK locally. The older linker rejects the new
   architecture token `arm64e.x1` in `.tbd` stubs, so the local copy renames it to `i386`.
   Only x86_64 slices are linked, so the renamed entries are never used. It also reads the
   Swift compiler version from the SDK's Swift interfaces.
2. `scripts/install-toolchain.sh` downloads exactly that Swift version from swift.org,
   checks the swift.org Developer ID signature and notarization, and installs it to
   `~/Library/Developer/Toolchains`.
   It also records the toolchain in the SDK copy's settings, which is how the Xcode build
   system finds the matching compiler without a project setting.
3. `scripts/make-xcode-clone.sh` (optional) makes an APFS clone of the older Xcode and
   links the SDK copy into it. Because it is then the newest SDK there, projects use it
   by default.
4. The wrappers point the compilers at the SDK copy. The Swift link step gets
   `-isysroot` so binaries record the real SDK version instead of the deployment target.

## Limits

- Swift deployment target must be macOS 13 or later with recent SDKs.
- A project without a deployment target defaults to the new SDK's version, which is newer
  than the macOS you are running. Set a deployment target your Mac can run.
- Asset catalogs and Interface Builder files are compiled by the older Xcode's tools,
  without features introduced later.
- No simulators of newer OS versions; the newer Xcode IDE itself does not run.
- The built app's `Info.plist` records the newer SDK (`DTSDKName`) but the version of the
  older Xcode (`DTXcode`). Stores or services that require a minimum Xcode version may
  reject such builds.
- Signing with a Developer ID, notarization and App Store upload are not yet verified
  with this setup (ad-hoc signing works).

## License

Scripts and documentation: [MIT](LICENSE). Third-party software used at runtime keeps its
own license (Apple's Xcode and SDK license, swift.org toolchain under Apache 2.0).

Overtime is an independent project and is not affiliated with, endorsed or sponsored
by Apple Inc. Apple, Xcode, macOS and Swift are trademarks of Apple Inc. Intel is a
trademark of Intel Corporation. The names are used only to describe compatibility.
