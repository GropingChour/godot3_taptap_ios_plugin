# STILL WORKING, NOT USE IT!!!

# Godot3 TapTap iOS Plugin

TapTap SDK integration plugin for Godot 3.x on iOS platform. This plugin wraps TapTap's login, compliance (anti-addiction), and core SDK functionalities as a Godot singleton accessible from GDScript.

## Features

- **TapTap Login**: Authenticate users with TapTap account
  - Support profile and friends scope authorization
  - Retrieve user profile (openId, unionId, name, avatar)
  - Session management (login/logout)

- **Compliance System** (Anti-addiction): 
  - Real-name verification required by Chinese regulations
  - Age-based playtime restrictions
  - Automatic compliance checks

- **Token Encryption**: 
  - XOR-based client token encryption
  - Visual configuration tool in Godot editor
  - Secure key storage in Info.plist

- **Cross-Platform API**: 
  - Unified GDScript API with Android version
  - Same method signatures and signals
  - Platform-specific implementations

## Limitations

⚠️ **iOS-Specific Notes**:
- License verification SDK not available (use Android/server-side)
- DLC query/purchase SDK not available (use Android/server-side)
- IAP (In-App Purchase) not supported (use iOS StoreKit directly)

## SDK Components

The plugin includes the following TapTap SDK frameworks (v3.x):
- TapTapLoginSDK - User authentication
- TapTapComplianceSDK - Anti-addiction system
- TapTapCoreSDK - Core functionality
- TapTapBasicToolsSDK - Utilities
- TapTapNetworkSDK - Network layer
- TapTapGidSDK - Global identifier
- tapsdkcorecpp - C++ bridge
- TapTapSDKBridgeCore - SDK bridge
- THEMISLite - Encryption library
- Resource bundles (Login & Compliance UI)

**Requirements**:
- iOS 12.0 or later
- Xcode 14.0 or later with Swift support
- **Always Embed Swift Standard Libraries must be enabled** (TapTap SDK uses Swift)

**Note:** iOS plugins are only effective on iOS (either on a physical device or
in the Xcode simulator). Their singletons will *not* be available when running
the project from the editor, so you need to export your project to test your changes.

## Quick Start

### 1. Installation

Download the latest release from [Releases](https://github.com/GropingChour/godot3_taptap_ios_plugin/releases) and extract to your Godot project:

```
YourProject/
├── ios/
│   └── plugins/
│       └── godot3_taptap/
│           ├── godot3_taptap.gdip
│           ├── godot3_taptap.release.xcframework
│           ├── godot3_taptap.debug.xcframework
│           └── sdk/  (11 xcframeworks + 2 bundles)
└── addons/
    └── godot3_taptap/
        ├── plugin.cfg
        ├── taptap.gd
        ├── taptap_config_window.gd
        └── ...
```

### 2. Configuration

1. Enable the plugin in Godot: **Project → Project Settings → Plugins → Godot3 TapTap** ✓
2. Open the configuration tool: **Project → Tools → TapTap Config Window**
3. Enter your TapTap Client ID and Client Token (from TapTap Developer Center)
4. Click **Generate Secure Key** to create encryption key
5. Click **Save iOS Key to .gdip** to store key in plugin configuration

### 3. Export Settings

In **Project → Export → iOS**:
- Add plugin: Check **Godot3 TapTap** in the Plugins section
- The encryption key will be automatically merged to app's Info.plist
- **Important**: Set **Always Embed Swift Standard Libraries = YES** in Xcode project settings
  (The TapTap SDK requires Swift runtime support)

### 4. Usage Example

```gdscript
extends Node

func _ready():
    var taptap = Engine.get_singleton("Godot3TapTap")
    if taptap:
        # Initialize SDK with encrypted token
        taptap.initSdkWithEncryptedToken(
            "your_client_id", 
            "encrypted_token_from_config_tool",
            true,  # enable log
            false  # without IAP
        )
        
        # Connect signals
        taptap.connect("onLoginSuccess", self, "_on_login_success")
        taptap.connect("onComplianceResult", self, "_on_compliance_result")
        
        # Login
        taptap.login(true, false)  # with profile, without friends

func _on_login_success():
    var profile = taptap.getUserProfile()
    print("User logged in: ", profile)
    
    # Start compliance check
    taptap.compliance()

func _on_compliance_result(code, info):
    print("Compliance result: ", code, " - ", info)
```

## API Reference

See [addons/godot3_taptap/README.md](addons/godot3_taptap/README.md) for complete API documentation.

## Troubleshooting

### Swift Compatibility Library Errors

If you see linker errors like:
```
Undefined symbols for architecture arm64:
  "__swift_FORCE_LOAD_$_swiftCompatibility50"
  "__swift_FORCE_LOAD_$_swiftCompatibilityConcurrency"
```

**Solution**: Enable Swift support in your Xcode project:

1. After exporting from Godot, open the `.xcodeproj` in Xcode
2. Select your project target → **Build Settings** tab
3. Search for "Always Embed Swift Standard Libraries"
4. Set to **YES**
5. Rebuild the project

**Alternative**: Add a dummy Swift file to your project:
1. In Xcode: **File → New → File → Swift File**
2. Name it `Dummy.swift`, add empty content
3. When prompted to create bridging header, click **Create**
4. This forces Xcode to link Swift runtime libraries

### Runtime Crash: "unrecognized selector sent to class"

If the app crashes at startup with:
```
'+[TapTapEvent captureUncaughtException]: unrecognized selector sent to class'
```

**Root Cause**: Objective-C categories and class methods from the TapTap SDK (written in Swift) aren't being loaded properly at runtime.

**Solution**: The plugin includes `-ObjC -all_load` linker flags in the `.gdip` file to force load all Objective-C symbols.

### Linker Error: "duplicate symbol" with `-all_load`

If you get duplicate symbol errors like:
```
duplicate symbol '_TapTapEvent' in:
    TapTapBasicToolsSDK.framework/TapTapBasicToolsSDK
    inappstore.framework/inappstore
ld: 1 duplicate symbol for architecture arm64
clang: error: linker command failed with exit code 1
```

**Cause**: Multiple frameworks contain the same symbols (likely from shared TapTap SDK code).

**Solution**: Use selective force loading instead of `-all_load`:

1. In Xcode, open your project
2. Select your target → **Build Settings** → **All** → **Combined**
3. Search for "Other Linker Flags"
4. Replace the default with selective force load:
   ```
   -ObjC -force_load $(BUILT_PRODUCTS_DIR)/libgodot3_taptap.a
   ```
   Or for XCFramework:
   ```
   -ObjC
   ```
5. Remove the `.gdip` linker_flags setting temporarily to test
6. Clean build and rebuild

**Alternative Solution (Recommended for multiple plugins)**:

1. Open Xcode project
2. Target → Build Settings → search "Symbols"
3. Set "Hide Symbols by Default" to **YES** 
4. Add this to "Other Linker Flags":
   ```
   -ObjC -undefined suppress -flat_namespace
   ```

**Option 3: Add Dummy Swift File**

This forces proper Swift/Objective-C runtime linking:
1. In Xcode: **File → New → File → Swift File**
2. Name it `Dummy.swift` (leave empty)
3. When prompted to create bridging header, click **Create**
4. Rebuild - this usually resolves symbol conflicts automatically

### Token Looks Like "Garbage" in Logs

If you see client token in logs as:
```
clientToken==j25Bb0{:qxz\^_v5q\^EOr[CUB08z3KJ8[H6...
```

**This is normal!** TapTap client tokens contain special characters (brackets, backslashes, etc.) after XOR decryption. The encryption/decryption is working correctly if:
- No "Failed to decrypt" errors appear
- SDK initialization succeeds
- Login works properly

The "garbage-looking" characters are valid token data, not a decryption error.

### Plugin Not Found

If `Engine.get_singleton("Godot3TapTap")` returns `null`:
- Verify plugin is checked in **Project → Export → iOS → Plugins**
- Ensure `ios/plugins/godot3_taptap/` directory exists with all files
- Plugins only work in exported builds, not in Godot editor

## Development & Building

### Prerequisites

- Clone this repository with submodules:

```bash
git clone --recursive https://github.com/GropingChour/godot3_taptap_ios_plugin.git
```

### Generate Godot Headers (Godot 3.x)

```bash
cd godot
scons platform=iphone target=release_debug
```

You can stop after headers are generated (<kbd>Ctrl + C</kbd> when compilation starts).

### Build Plugin Binary

- Run the command below to generate an `.a` static library for chosen target:

```bash
scons target=<release_debug|release> arch=arm64 simulator=<no|yes> plugin=godot3_taptap version=3.x
```

**Note:** Godot's official `debug` export templates use `release_debug`, not `debug` target.

### Build XCFramework (Recommended)

- Run the release script to generate `xcframework` for distribution:

```bash
./scripts/release_xcframework.sh 3.x
```

This will:
- Build for arm64 device + arm64/x86_64 simulators
- Create `.xcframework` bundles (release + debug)
- Package with SDK dependencies in `bin/release/godot3_taptap/`

The result includes:
- `godot3_taptap.release.xcframework`
- `godot3_taptap.debug.xcframework`
- `godot3_taptap.gdip` (plugin manifest)
- `sdk/` directory (11 TapTap SDK frameworks + 2 resource bundles)

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Credits

- Based on [Godot iOS Plugin Template](https://github.com/godotengine/godot-ios-plugins)
- TapTap SDK by [TapTap Developer Services](https://developer.taptap.cn/)
- Cross-platform with [godot3_taptap_android_plugin](https://github.com/GropingChour/godot3_taptap_android_plugin)
