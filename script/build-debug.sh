#!/bin/bash
echo "🔧 Fixing build issues & building Debug APK..."

flutter clean
echo "✅ Flutter clean completed"

flutter pub get
echo "✅ Dependencies fetched"

flutter build apk --debug
echo "✅ Debug Build completed"
