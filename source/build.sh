#!/bin/zsh
set -eu
cd "${0:A:h}/.."
mkdir -p XDRLight.app/Contents/MacOS XDRLight.app/Contents/Resources XDRLight.app/Contents/Frameworks
ditto source/vendor/Sparkle.framework XDRLight.app/Contents/Frameworks/Sparkle.framework
xcrun clang -fobjc-arc -O2 -Wall -Wextra -mmacosx-version-min=13.0 source/main.m -framework Cocoa -framework MetalKit -framework Metal -framework QuartzCore -framework CoreGraphics -framework IOKit -framework ServiceManagement -F source/vendor -framework Sparkle -Wl,-rpath,@executable_path/../Frameworks -o XDRLight.app/Contents/MacOS/XDRLight
cat > XDRLight.app/Contents/Info.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>XDRLight</string>
<key>CFBundleIdentifier</key><string>local.xdrlight</string>
<key>CFBundleName</key><string>XDRLight</string>
<key>CFBundleDisplayName</key><string>XDRLight</string>
<key>CFBundleVersion</key><string>4</string>
<key>CFBundleShortVersionString</key><string>1.3.0</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>SUPublicEDKey</key><string>+QvmYqXG7JZamcLCntyMcduMTjanyAs/e0SeALHRi2g=</string>
<key>SUEnableAutomaticChecks</key><true/>
<key>SUAutomaticallyUpdate</key><false/>
<key>SUEnableSystemProfiling</key><false/>
<key>SUUpdateCheckInterval</key><integer>86400</integer>
<key>LSUIElement</key><true/>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
cp assets/AppIcon.icns XDRLight.app/Contents/Resources/AppIcon.icns
python3 source/configure_build.py
codesign --force --sign - XDRLight.app
