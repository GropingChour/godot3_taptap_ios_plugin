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

**Note:** iOS plugins are only effective on iOS (either on a physical device or
in the Xcode simulator). Their singletons will *not* be available when running
the project from the editor, so you need to export your project to test your changes.

## Quick Start

### 1. Installation

Download the latest release from [Releases](https://github.com/GropingChour/godot3_taptap_ios_plugin/releases) and extract to your Godot project:

```
YourProject/
├── ios_plugins/
│   └── godot3_taptap/
│       ├── godot3_taptap.gdip
│       ├── godot3_taptap.xcframework
│       └── sdk/  (11 xcframeworks + 2 bundles)
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
