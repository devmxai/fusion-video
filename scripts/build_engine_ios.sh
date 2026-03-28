#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CRATE_DIR="$ROOT_DIR/engine/rust_core"
HEADER_DIR="$CRATE_DIR/include"
OUT_DIR="$ROOT_DIR/engine/build/ios"
FRAMEWORK_DIR="$ROOT_DIR/ios/Frameworks"
LIB_NAME="libfusion_video_engine.a"

if [[ -f "$HOME/.cargo/env" ]]; then
  # shellcheck disable=SC1090
  source "$HOME/.cargo/env"
fi

mkdir -p "$OUT_DIR" "$FRAMEWORK_DIR"

cargo build \
  --manifest-path "$CRATE_DIR/Cargo.toml" \
  --target aarch64-apple-ios \
  --release

cargo build \
  --manifest-path "$CRATE_DIR/Cargo.toml" \
  --target aarch64-apple-ios-sim \
  --release

cargo build \
  --manifest-path "$CRATE_DIR/Cargo.toml" \
  --target x86_64-apple-ios \
  --release

lipo -create \
  "$CRATE_DIR/target/aarch64-apple-ios-sim/release/$LIB_NAME" \
  "$CRATE_DIR/target/x86_64-apple-ios/release/$LIB_NAME" \
  -output "$OUT_DIR/$LIB_NAME"

rm -rf "$FRAMEWORK_DIR/FusionVideoEngine.xcframework"

xcodebuild -create-xcframework \
  -library "$CRATE_DIR/target/aarch64-apple-ios/release/$LIB_NAME" \
  -headers "$HEADER_DIR" \
  -library "$OUT_DIR/$LIB_NAME" \
  -headers "$HEADER_DIR" \
  -output "$FRAMEWORK_DIR/FusionVideoEngine.xcframework"

echo "iOS engine xcframework created at:"
echo "  $FRAMEWORK_DIR/FusionVideoEngine.xcframework"
