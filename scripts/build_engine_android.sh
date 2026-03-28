#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CRATE_DIR="$ROOT_DIR/engine/rust_core"
ANDROID_DIR="$ROOT_DIR/android"
LOCAL_PROPERTIES="$ANDROID_DIR/local.properties"
JNI_LIBS_DIR="$ANDROID_DIR/app/src/main/jniLibs"

if [[ -f "$HOME/.cargo/env" ]]; then
  # shellcheck disable=SC1090
  source "$HOME/.cargo/env"
fi

if [[ -n "${ANDROID_NDK_HOME:-}" ]]; then
  NDK_HOME="$ANDROID_NDK_HOME"
else
  SDK_DIR="$(grep '^sdk.dir=' "$LOCAL_PROPERTIES" | cut -d'=' -f2-)"
  SDK_DIR="${SDK_DIR//\\:/:}"
  SDK_DIR="${SDK_DIR//\\/}"
  NDK_VERSION="$(ls -1 "$SDK_DIR/ndk" | sort | tail -n1)"
  NDK_HOME="$SDK_DIR/ndk/$NDK_VERSION"
fi

export ANDROID_NDK_HOME="$NDK_HOME"
mkdir -p "$JNI_LIBS_DIR"

cd "$CRATE_DIR"

cargo ndk \
  -o "$JNI_LIBS_DIR" \
  -t armeabi-v7a \
  -t arm64-v8a \
  -t x86_64 \
  build \
  --release

echo "Android engine libraries created at:"
echo "  $JNI_LIBS_DIR"
