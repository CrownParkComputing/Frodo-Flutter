# Frodo Flutter

A cross-platform Commodore 64 emulator built with Flutter, powered by the
[Frodo V4 emulation core](https://github.com/cebix/frodo4) (by Christian Bauer)
bridged into Dart through a Rust FFI layer.

![Frodo](Frodo.png)

## Supported Platforms

| Platform | Status |
|----------|--------|
| Android  | ✅ arm64-v8a |
| iOS      | ✅ arm64 |
| Windows  | ✅ x86-64 |

## Architecture

```
Flutter UI (Dart)
    │
    └── Dart FFI  ──►  frodo_bridge  (Rust cdylib)
                            │
                            ├── frodo_ffi.cpp  (C FFI shim)
                            │
                            └── Frodo core C++ (cebix/frodo4 – git submodule)
                                    │
                                    └── SDL2 (libsdl-org/SDL@SDL2 – git submodule)
```

The Rust crate lives in `flutter_app/rust/frodo_bridge/` and uses the
[`cc`](https://crates.io/crates/cc) crate to compile the upstream Frodo C++
sources and the C FFI shim into the native library at build time.

---

## Prerequisites

### All platforms
| Tool | Version |
|------|---------|
| [Flutter SDK](https://docs.flutter.dev/get-started/install) | ≥ 3.29 |
| [Rust toolchain](https://rustup.rs/) | stable |
| Git (with submodule support) | any recent |

### Android
| Tool | Notes |
|------|-------|
| Android Studio / SDK | includes `sdkmanager` |
| Android NDK | 29.0.14206865 (set via `ndkVersion` in `build.gradle.kts`) |
| [cargo-ndk](https://github.com/bbqsrc/cargo-ndk) | `cargo install cargo-ndk` |

```bash
rustup target add aarch64-linux-android
cargo install cargo-ndk
```

### Windows
CMake (≥ 3.14) and the MSVC toolchain are sufficient – SDL2 is compiled from
source as part of the CMake build.

### iOS (macOS only)
```bash
rustup target add aarch64-apple-ios
brew install pkg-config
sudo gem install cocoapods
```

---

## Getting Started

### 1. Clone with submodules

```bash
git clone --recurse-submodules https://github.com/CrownParkComputing/Frodo-4.5.git
cd Frodo-4.5
```

If you already cloned without `--recurse-submodules`:

```bash
git submodule update --init --recursive
```

### 2. Install Flutter dependencies

```bash
cd flutter_app
flutter pub get
```

### 3. Build

#### Android
```bash
cd flutter_app
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk
```

#### Windows
```bash
cd flutter_app
flutter build windows --release
# Output: build/windows/x64/runner/Release/
```

#### iOS
```bash
cd flutter_app
flutter build ios --no-codesign --release
# Output: build/ios/iphoneos/Runner.app
```

---

## Submodule dependency – Frodo core

The emulator core is tracked as a **Git submodule** at
`flutter_app/frodo4` pointing to
[cebix/frodo4](https://github.com/cebix/frodo4) (`main` branch).

SDL2 is similarly tracked at `flutter_app/third_party/SDL2` pointing to
[libsdl-org/SDL](https://github.com/libsdl-org/SDL) (`SDL2` branch).

To update both to their latest upstream commits:

```bash
git submodule update --remote flutter_app/frodo4
git submodule update --remote flutter_app/third_party/SDL2
git add flutter_app/frodo4 flutter_app/third_party/SDL2
git commit -m "chore: bump frodo4 and SDL2 submodules"
```

### Migrating from the previously vendored sources

If you have an older checkout that still contains the vendored `flutter_app/frodo_core/`
and `flutter_app/third_party/SDL2/` directories (not managed as submodules), run:

```bash
# Remove vendored copies
git rm -r flutter_app/frodo_core
git rm -r flutter_app/third_party/SDL2

# Add submodules
git submodule add https://github.com/cebix/frodo4.git flutter_app/frodo4
git submodule add -b SDL2 https://github.com/libsdl-org/SDL.git flutter_app/third_party/SDL2

git commit -m "chore: replace vendored sources with git submodules"
```

---

## Repository Layout

```
Frodo-4.5/
├── .github/workflows/      # CI/CD GitHub Actions
├── flutter_app/
│   ├── frodo4/             # ← git submodule: cebix/frodo4
│   ├── third_party/
│   │   └── SDL2/           # ← git submodule: libsdl-org/SDL@SDL2
│   ├── rust/frodo_bridge/  # Rust crate – native bridge
│   │   ├── build.rs        # Compiles C++ via cc crate
│   │   ├── src/lib.rs      # Rust FFI wrappers
│   │   └── cpp/            # frodo_ffi.{h,cpp} + sysconfig.h
│   ├── lib/                # Flutter/Dart app code
│   ├── android/            # Android platform project
│   ├── ios/                # iOS platform project
│   └── windows/            # Windows (CMake) platform project
└── README.md
```

---

## CI / Continuous Integration

GitHub Actions workflows are defined in `.github/workflows/`:

| Workflow | Trigger | Artifact |
|----------|---------|----------|
| `build-android.yml` | push to `main`, PR, manual | `app-release.apk` |
| `build-windows.yml` | push to `main`, PR, manual | `frodo_app-windows-x64.zip` |
| `build-ios.yml`     | push to `main`, PR, manual | `Runner.app.zip` (unsigned) |
| `build-release.yml` | push tag `v*`, manual | versioned Android, Windows, and unsigned iOS release assets |

To publish a versioned release build, either push a tag matching the Flutter app version:

```bash
git tag v1.0.0
git push origin v1.0.0
```

Or run `build-release.yml` from the GitHub Actions UI and provide `1.0.0` or `v1.0.0` as the version input.

That workflow creates a GitHub release and attaches:

- `frodo-app-1.0.0-android-arm64.apk`
- `frodo-app-1.0.0-windows-x64.zip`
- `frodo-app-1.0.0-ios-unsigned.zip`

---

## Credits

- Original Frodo emulator: Christian Bauer
- Upstream Frodo source: [cebix/frodo4](https://github.com/cebix/frodo4)
- This repository packages the upstream Frodo core behind a Flutter UI and Rust FFI bridge.
- SDL2: [libsdl-org/SDL](https://github.com/libsdl-org/SDL), maintained by Sam Lantinga and contributors

---

## License

This repository includes and depends on third-party open source software.

The root [LICENSE](LICENSE) file contains the GNU General Public License v2,
which applies to the Frodo-derived emulator code in this repository.

The Frodo emulation core is © Christian Bauer and released under the
[GNU General Public License v2](https://www.gnu.org/licenses/old-licenses/gpl-2.0.html).
Upstream source and project history are available at
[cebix/frodo4](https://github.com/cebix/frodo4).

The Flutter application code and Rust bridge in this repository are also
distributed under the GPL-2.0.

SDL2 is © Sam Lantinga and contributors, licensed under the
[zlib license](https://www.libsdl.org/license.php). The SDL2 license text is
available in `flutter_app/third_party/SDL2/LICENSE.txt`.
