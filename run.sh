#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"
swift_compiler="$(xcrun --toolchain org.swift.64202609041a --find swiftc)"
build_directory="$PWD/DerivedData"
result_directory="$(mktemp -d "${TMPDIR:-/tmp}/database-studio-build.XXXXXX")"

# Xcode evaluates manifests with its bundled compiler; sources use the snapshot.
perl -e 'alarm shift; exec @ARGV' 900 env \
    TOOLCHAINS=com.apple.dt.toolchain.XcodeDefault \
    xcodebuild \
    -project "Database Studio/Database Studio.xcodeproj" \
    -scheme "Database Studio" \
    -destination "platform=macOS,arch=arm64" \
    -derivedDataPath "$build_directory" \
    -resultBundlePath "$result_directory/Build.xcresult" \
    SWIFT_EXEC="$swift_compiler" \
    CODE_SIGNING_ALLOWED=NO \
    build 2>&1 | tee "$result_directory/build.log"

open "$build_directory/Build/Products/Debug/Database Studio.app"
