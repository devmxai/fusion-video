# Fusion Video Engine Build

This document describes how to prepare and build the local Rust engine
artifacts for Flutter on iOS and Android.

## 1. Prepare the toolchain

Run:

```bash
./scripts/setup_engine_toolchain.sh
```

This installs or verifies:

- Rust toolchain
- iOS Rust targets
- Android Rust targets
- `cargo-ndk`

## 2. Build for the current host

Useful for validating the Rust engine compiles before platform packaging:

```bash
./scripts/build_engine_host.sh
```

## 3. Build iOS artifacts

```bash
./scripts/build_engine_ios.sh
```

Output:

- `ios/Frameworks/FusionVideoEngine.xcframework`

This script builds:

- iPhone device static library
- simulator static library
- universal simulator archive
- xcframework package

## 4. Build Android artifacts

```bash
./scripts/build_engine_android.sh
```

Output:

- `android/app/src/main/jniLibs/armeabi-v7a/libfusion_video_engine.so`
- `android/app/src/main/jniLibs/arm64-v8a/libfusion_video_engine.so`
- `android/app/src/main/jniLibs/x86_64/libfusion_video_engine.so`

The script reads the Android SDK location from:

- `android/local.properties`

If needed, you can override the NDK path:

```bash
ANDROID_NDK_HOME=/path/to/ndk ./scripts/build_engine_android.sh
```

## 5. Build all artifacts

```bash
./scripts/build_engine_all.sh
```

## Current scope

The current engine build only packages the first FFI scaffold:

- version
- create project
- dispose project
- play
- pause
- seek

More editor operations will be promoted into Rust in later phases.
