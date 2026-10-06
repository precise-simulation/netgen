#!/usr/bin/env bash
set -euo pipefail

expected_arch="${1:?usage: select-toolchain.sh <arm64|x86_64>}"
case "$expected_arch" in
  arm64|x86_64) ;;
  *) echo "unsupported architecture: $expected_arch" >&2; exit 2 ;;
esac

export DEVELOPER_DIR="/Applications/Xcode_16.4.app/Contents/Developer"
if [[ ! -d "$DEVELOPER_DIR" ]]; then
  echo "required Xcode 16.4 is absent: $DEVELOPER_DIR" >&2
  exit 1
fi
sudo xcode-select --switch "$DEVELOPER_DIR"
[[ "$(xcode-select --print-path)" == "$DEVELOPER_DIR" ]]
[[ "$(uname -m)" == "$expected_arch" ]]

clang_path="$(xcrun --find clang)"
clangxx_path="$(xcrun --find clang++)"
sdk_path="$(xcrun --sdk macosx --show-sdk-path)"
xcodebuild -version
"$clang_path" --version | head -n 1
printf 'macOS SDK: %s (%s)\n' "$sdk_path" "$(xcrun --sdk macosx --show-sdk-version)"

echo "DEVELOPER_DIR=$DEVELOPER_DIR" >> "$GITHUB_ENV"
echo "NETGEN_CLANG=$clang_path" >> "$GITHUB_ENV"
echo "NETGEN_CLANGXX=$clangxx_path" >> "$GITHUB_ENV"
echo "NETGEN_MACOS_SDK=$sdk_path" >> "$GITHUB_ENV"
