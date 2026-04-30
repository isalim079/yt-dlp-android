#!/bin/bash
echo "🔧 Fixing build issues & building Release APK..."

flutter clean
echo "✅ Flutter clean completed"

flutter pub get
echo "✅ Dependencies fetched"

flutter build apk --split-per-abi --release --obfuscate --split-debug-info=build/debug-info --tree-shake-icons
echo "✅ Release Build completed"
