#!/bin/bash
echo "🔧 Deep cleaning Flutter project..."

rm -rf .dart_tool
rm -rf build
rm -rf android/.gradle
rm -rf android/app/build
rm -f pubspec.lock
flutter clean
echo "✅ Removed all build artifacts and lock files"

echo "Rebuilding..."
flutter pub get
echo "✅ Dependencies Installed"

flutter build apk --split-per-abi --release --obfuscate --split-debug-info=build/debug-info --tree-shake-icons
echo "✅ Release Build completed"
