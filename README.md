<p align="center">
  <img src="docs/icon.png" width="128" height="128" alt="Overtime icon">
</p>

<h1 align="center">Overtime</h1>

<p align="center">
  <em>Extra time for Intel Macs.</em><br>
  Build with the newest macOS SDK on an x64_x86 Mac, after the newest developer tools stopped running there.
</p>

<p align="center">
  <a href="https://github.com/0xfel1x/overtime-x86/releases/latest"><img src="https://img.shields.io/github/v/release/0xfel1x/overtime-x86?label=download" alt="Latest release"></a>
  <img src="https://img.shields.io/badge/platform-macOS%20on%20Intel-lightgrey" alt="Platform: macOS on Intel">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="License: MIT"></a>
</p>

## In short

Newer Xcode releases install only on Apple silicon. Their SDKs, however, still contain
everything needed to build on Intel: for macOS, and for iOS and tvOS devices and simulators.
Overtime puts the pieces together for you:

1. **You keep your Xcode.** The Xcode that runs on your Intel Mac keeps providing the
   editor, linker and signing tools.
2. **Overtime gets the newest Xcode.** One click opens Apple's download in your browser; you
   sign in with your own Apple Account, and Overtime picks up the download and unpacks it.
   Only the SDKs inside it are used.
3. **It makes the SDKs usable on Intel.** Local copies of the SDKs are adjusted so the older
   Xcode accepts them, and the matching open-source Swift compiler is installed from
   [swift.org](https://www.swift.org/install/macos/).
4. **It prepares your Xcode.** Overtime adds the new SDKs to your Xcode, which then builds
   with them by default. Nothing has to be changed in the projects, and a switch in the
   Overtime window turns the patch off again.

The result: apps built on your Intel Mac against the newest SDKs, from Xcode or (for macOS)
from the Terminal.

### What works

Tested on an Intel Mac with macOS Sequoia, Xcode 26.3 and the SDKs of Xcode 27.2.

| Area | Status |
| --- | --- |
| macOS apps (x86_64 and universal) | build and run |
| iOS apps for devices | build, unsigned archive tested |
| iOS simulator | builds; runs in the simulator versions you have installed |
| tvOS | builds with a tvOS simulator runtime installed; not run |
| DriverKit | SDK prepared; not tested with a project |
| watchOS, visionOS | not supported |
| Swift macros | all but four, see [Limits](#limits) |
| C, C++, Objective-C, asset and string catalogs, xib/storyboard, Core ML, Metal | build and run |
| Debugger, SwiftUI previews, editor | work |
| Developer ID, notarization, App Store upload | not tested |

## Get started

1. Download `Overtime-<version>.zip` from the
   [Releases](https://github.com/0xfel1x/overtime-x86/releases/latest) page and unpack it.
2. Open **Overtime**. It is not signed with an Apple Developer ID, so macOS blocks the first
   start: dismiss the warning, then go to System Settings > Privacy & Security and click
   **Open Anyway**.
3. Overtime finds the Xcode on your Mac. Click **Get Newest Xcode** and sign in to Apple in
   your browser. If you already have the newer Xcode, drop the app or the `.xip` file on
   the window instead.
4. Click **Set Up**. When it is done, the window shows the prepared Xcode and the commands
   for the Terminal.

### What you need

Overtime tells you which Xcode fits your macOS and offers the download:

| Your macOS | Xcode to use | Status |
| --- | --- | --- |
| Tahoe 26.2 or later | 26.6 | supported |
| Sequoia 15.6 or later | 26.3 | supported, tested |
| Sonoma 14.5 or later | 16.2 | untested |
| Ventura 13.5 or later | 15.2 | untested |
| Monterey 12.5 or later | 14.2 | untested, reported to work with manual changes |

- An **Intel Mac** (obviously) with the Xcode you use today. Tested on macOS Sequoia 15
  with Xcode 26.3 and the SDK from Xcode 27.2.
- A free Apple Account to download Xcode from Apple.
- About 25 GB of free disk space during the setup (the unpacked newer Xcode is removed
  again) and about 6 GB afterwards for the Swift compiler.

## Using it

**In Xcode:** open your projects as usual. Your Xcode builds with the newer SDKs and the
matching Swift compiler by itself; `xcodebuild` does too. iOS and tvOS apps run in the
simulators you already have (see Limits). While the patch is on, the menu
bar, the Dock and the app switcher call it "Xcode SDK 27.2". In a project, Build Settings >
Base SDK shows the SDK in use.

**In Terminal:** add the tools to your shell once (the app copies the line for you), then:

| Command | Purpose |
| --- | --- |
| `ot-clang`, `ot-clang++` | C, C++, Objective-C |
| `ot-swiftc` | Swift compiler |
| `ot-swift build/run/test` | Swift Package Manager |
| `ot-sdk on/off/status` | Switch the Overtime patch in your Xcode on or off |

```sh
ot-swiftc -target x86_64-apple-macos13 main.swift -o app
ot-swift build -c release
otool -l app | grep -A5 LC_BUILD_VERSION   # shows the newer SDK version
```

**Switching it off:** with the new SDK in place, plain `swiftc`, `swift build` and
`xcodebuild` in the Terminal pick it up too, with a compiler that cannot read it. The
switch at the top of the Overtime window, or `ot-sdk off`, removes the SDK from your Xcode
and gives it back its name, so that it behaves exactly as without Overtime; `ot-sdk on`
brings the patch back. Restart Xcode after switching.

To pin SDK, compiler and architecture for a single project, add an `.xcconfig` file to it
that contains `#include "<home>/Library/Developer/Overtime/config/local.xcconfig"` and
select it under Project > Info > Configurations.

## How it works in detail

1. `scripts/make-sdk.sh` clones the newer SDKs locally: macOS, iOS, tvOS, their
   simulators and DriverKit. The older linker rejects the new architecture token
   `arm64e.x1` in the `.tbd` link stubs, so the local copies rename it to `i386`, which no
   build here links; arm64 code links against the `arm64e` entries, which list every symbol.
   The newer SDKs also declare SwiftUI's `State` as a macro whose older implementation does
   not fit them (`@State private var` fails), so the copies drop those declarations and
   `@State` stays the property wrapper. The renamed App Intents schema macros
   (`@AppIntent(schema:)` and its siblings) also accept the member name the older
   implementation generates. Each copy is checked with a test link. The script also reads
   the Swift compiler version from the SDK's Swift interfaces.
2. `scripts/install-toolchain.sh` downloads exactly that Swift version from swift.org,
   checks the swift.org Developer ID signature and notarization, and installs it to
   `~/Library/Developer/Toolchains`. It records the toolchain in the settings of the SDK
   copies, which is how the Xcode build system finds the matching compiler without a
   project setting, and adds a default build setting there that turns on cross-import
   overlays (`PhotosPicker`, `@Query` and the like), which Apple's compiler loads by default
   and the swift.org one does not. It also adds a small `ld` forwarder to the toolchain so
   that Swift package manifests link.
3. `scripts/patch-xcode.sh` links each SDK copy into the matching platform folder of your
   Xcode. The Xcode build system only resolves SDKs there; as the newest SDK of its
   platform, each becomes the default. Xcode uses an iOS or tvOS SDK only with a simulator
   runtime of the same version, even for device builds (asset catalogs are compiled with
   it), so the newer SDK is paired with the newest runtime you have installed
   (`simctl runtime match`). The app is also renamed to "Xcode SDK <version>".
   `scripts/sdk-switch.sh off` undoes all of it. An Xcode that is updated or installed
   again comes without the patch: run the setup again.
4. The `ot-*` wrappers point the compilers at the SDK copy. The Swift link step gets
   `-isysroot` so binaries record the real SDK version.

The app in `App/` is a front end for these scripts. It tells the two Xcodes apart by the
processor architecture of their main program, reads the newest Xcode version from Apple's
public release feed, and unpacks the download with the system's `xip` tool. Everything is
installed to `~/Library/Developer/Overtime`.

## Build from source

```sh
scripts/build-app.sh          # add --zip to also pack it into releases/
open build/Overtime.app
```

Without the app, the same steps run in the Terminal:

```sh
scripts/setup.sh              # the last step patches the Xcode in OT_HOST_XCODE
export PATH="$PWD/bin:$PATH"
```

Paths can be changed with environment variables (`OT_HOST_XCODE`, `OT_NEW_XCODE`,
`OT_HOME`, `OT_TOOLCHAINS_DIR`), see [lib/common.sh](lib/common.sh).
Run the setup again after updating either Xcode.

## Limits

- Swift deployment target must be macOS 13 or later with recent SDKs.
- A project without a deployment target defaults to the new SDK's version, which is newer
  than the macOS you are running. Set a deployment target your Mac can run.
- Asset catalogs, Interface Builder files, string catalogs, Core ML models and Metal
  shaders are compiled by the older Xcode's tools, without features introduced later.
  Metal needs that Xcode's Metal toolchain, a separate download in Xcode 26 (Xcode >
  Settings > Components). C, C++ and Objective-C
  are compiled by the clang of the swift.org toolchain while the newer SDK is in use
  (Xcode switches the whole toolchain), with implicit instead of explicit modules.
  Universal macOS apps (arm64 + x86_64) build. All of this is checked with
  [tests/tools](tests/tools) for macOS and iOS.
- No simulators of newer OS versions; the newer Xcode itself does not run. iOS and tvOS
  apps built against the newer SDK run in the simulator runtimes you have installed, so
  their deployment target must not be newer than those. Building for tvOS needs a tvOS
  simulator runtime to be installed (Xcode > Settings > Components).
- watchOS and visionOS are not supported.
- **Swift macros** are expanded by compiler plugins, which the newer Xcode ships for Apple
  silicon only. Overtime uses the Intel plugins of the older Xcode and of the swift.org
  toolchain, so the generated code is the one the older Xcode would produce. Checked with
  [tests/macros](tests/macros) for macOS and iOS:
  - Work: `@Observable`, `@ObservationIgnored`, `#Predicate`, `#Expression`, `#bundle`,
    `@DebugDescription`, `@TaskLocal`, `@Resolvable`, `@Model`, `@Attribute`,
    `@Relationship`, `@Transient`, `#Index`, `#Unique`, `@ModelActor`, `@Query`, `@State`
    (as the property wrapper), `@Entry`, `@Animatable`, `@AnimatableIgnored`, `#Preview`
    (SwiftUI, AppKit, UIKit, WidgetKit), `@Previewable`, `@Parameter` and `#Rule` (TipKit),
    `@AppIntent(schema:)`, `@UnionValue`, `@ComputedProperty`, `@DeferredProperty`,
    `@Generable`, `@Guide`.
  - Do not work, because their implementation exists only in the newer Xcode:
    `@ReportableMetadata`, `@ReportableMetadataIgnored`, `@ReportableMetadataKey`
    (StateReporting) and `@SessionPropertyEntry` (Foundation Models). The build stops with
    "plugin for module ... not found" or "could not be found in library plugin".
  - Not checked one by one: `@AppEntity(schema:)` and `@AppEnum(schema:)`, which get the
    same adjustment as `@AppIntent(schema:)`.
- iOS device builds are verified up to an unsigned archive; installing on a device needs
  your own signing setup and is not tested.
- The built app's `Info.plist` records the newer SDK (`DTSDKName`) but the version of the
  older Xcode (`DTXcode`). Stores or services that require a minimum Xcode version may
  reject such builds.
- Debugging, SwiftUI previews and the editor work: while the newer SDK is in use, Xcode
  loads the debugger (LLDB) and the editor service (SourceKit) of the swift.org toolchain.
  The older Xcode's own debugger cannot evaluate expressions (`po`, `p`) in such builds,
  and its own editor service cannot read the newer SDK; Xcode does not use them then.
- Signing to run locally (ad hoc, also with the hardened runtime) works. Signing with a
  Developer ID, notarization and App Store upload are not tested.
- Overtime changes your Xcode in place, so your user must be able to write to it. An Xcode
  unpacked from Apple's `.xip` download is; one from the App Store is not. If macOS blocks
  the change, allow Overtime under System Settings > Privacy & Security > App Management.
- `codesign --verify` reports your Xcode as modified while the patch is on (added links to
  the SDKs, changed name). That is expected; Xcode still starts.

## Credits

The Swift compiler it installs comes from the [Swift open-source project](https://www.swift.org).

## License and legal

Scripts, app and documentation: [MIT](LICENSE). This repository contains **no Apple
software**: no SDK files, no Xcode components, no Apple artwork. You download Xcode
yourself from Apple, with your own account and under Apple's terms. Read
[LEGAL.md](LEGAL.md) before use.

Overtime is an independent project and is not affiliated with, endorsed or sponsored
by Apple Inc. Apple, Xcode, macOS and Swift are trademarks of Apple Inc. Intel is a
trademark of Intel Corporation. The names are used only to describe compatibility.
