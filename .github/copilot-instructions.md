# Godot 3.x iOS Plugins - AI Coding Guidelines

## Project Overview
This repository contains **two iOS plugins for Godot 3.x**, both following the official Godot iOS plugin architecture pattern:

### 1. Godot3 TapTap Plugin (`godot3_taptap`)
Wraps TapTap SDK (login, compliance, license verification, DLC) as a Godot singleton.
- **Cross-Platform**: Shares GDScript layer (`addons/godot3_taptap/`) with [Android version](https://github.com/GropingChour/godot3_taptap_android_plugin)
- **TapTap SDKs**: Bundles ~12 XCFrameworks in `plugins/godot3_taptap/sdk/`
- **Token Encryption**: XOR encryption via iOS Info.plist (key: `TapTapDecryptKey`)
- **Limitations**: iOS lacks license/DLC/IAP SDKs (Android-only)

### 2. Godot3 ASA Plugin (`godot3_asa`)
Apple Search Ads attribution using AdServices framework (iOS 14.3+).
- **Client-Side Attribution**: No backend required, direct AdServices API calls
- **AppSA Integration**: Reports attribution data to 七麦 (QiMai) analytics platform
- **Signal-Based API**: Async token/attribution via GDScript signals (`onASATokenReceived`, `onASAAttributionReceived`)
- **Pending Queue**: Buffers events during attribution to prevent data loss
- **Debug Panel**: `addons/godot3_asa/example/asa_debug_panel.gd` - visual attribution debugger with mock editor preview

## Architecture Pattern (Critical for .mm Files)

### Dual-Layer Structure (C++ + Objective-C)
**Both plugins** follow this mandatory pattern - C++ singleton + ObjC delegate:

```
GDScript (autoload) → C++ Singleton → ObjC Delegate → iOS SDK
    ↓                     ↓                 ↓
  Signals ← _post_event/emit_signal ← completion handlers
```

**Examples:**
- **TapTap**: `taptap.gd` → `Godot3TapTap` → `GodotTapTapDelegate` → TapTap SDK
- **ASA**: `asa.gd` (autoload `ASA`) → `Godot3ASA` → `GodotASADelegate` → AdServices API

**Reference:** Compare with [official in_app_store.mm](https://github.com/godot-sdk-integrations/godot-ios-plugins/blob/master/plugins/inappstore/in_app_store.mm).

### File Structure Requirements (Per Plugin)
```
plugins/<plugin>/
├── <plugin>.h          # C++ class (inherits Object, declares singleton)
├── <plugin>.mm         # ObjC++ implementation
│   ├── @interface <Plugin>Delegate (@implementation)
│   └── C++ methods calling ObjC delegate
├── <plugin>_module.{h,cpp}  # Register with Engine::add_singleton()
└── <plugin>.gdip       # Plugin manifest (binaries, frameworks, init functions)

addons/<plugin>/
├── plugin.cfg          # Editor plugin manifest
├── <main>.gd           # GDScript autoload (signal forwarding)
└── example/            # Demo code & debug tools
```

**Critical:** `.gdip` `initialization=` MUST match `_module.cpp` function name exactly.

## Logging Conventions

**Prefix Standards:**
- **C++/ObjC Layer** (`.mm` files): Use `[<PluginName>]` prefix
  - TapTap: `NSLog(@"[Godot3TapTap] ...")`
  - ASA: `NSLog(@"[Godot3ASA] ...")`
- **GDScript Layer** (`.gd` files): Use `[<Abbrev>]` prefix
  - TapTap: `print("[TapTap] ...")`
  - ASA: `print("[ASA] ...")` (autoload node)

This convention helps distinguish which layer produced each log entry during debugging.

## ASA Plugin Specifics

### Architecture Differences from TapTap
- **Direct Signal Emission**: Uses `emit_signal()` instead of event queue (simpler async pattern)
- **No Event Polling**: Signals fire immediately when AdServices API responds
- **Autoload Pattern**: GDScript accessible via `ASA` global (registered in `plugin.gd`)
- **Device Detection**: Check `ASA.is_supported()` before use (iOS 14.3+, real device required)

### AppSA Reporting System
```gdscript
# Pending queue prevents data loss during attribution
ASA.set_appsa_from_key("your_qimai_key")
ASA.perform_attribution()  # Starts attribution

# These calls are queued if attribution still in progress:
ASA.report_activation()    # Only after attribution succeeds
ASA.report_register()      # Safe to call immediately - will queue if needed
```

**Queue Behavior:**
- `is_attribution_pending` flag set during `perform_attribution()`
- All `report_*` calls queued until `onASAAttributionReceived` fires
- Queue processed automatically after successful attribution
- Skip reporting if `attribution=false` (user not from ASA)

### Debug Panel Usage
```gdscript
# Attach to CanvasLayer for always-on-top display
var panel = preload("res://addons/godot3_asa/example/asa_debug_panel.gd").new()
$CanvasLayer.add_child(panel)  # Auto-connects to ASA signals
```

Features:
- **Editor Preview**: Mock data shown via `OS.has_feature("editor")`
- **Real-time Display**: Token and attribution JSON with copy buttons
- **Error Handling**: Shows device incompatibility, network errors in red
- **Smart Parenting**: Adds UI as child of script node (not root) for flexible placement

### Simulator Limitations
AdServices **does not work in iOS Simulator** - `AAAttribution` class unavailable even on iOS 18 simulator. The plugin detects this:

```objective-c
// In godot3_asa.mm
- (BOOL)isAdServicesSupported {
    if (@available(iOS 14.3, *)) {
        Class aaClass = NSClassFromString(@"AAAttribution");
        if (aaClass == nil) {
            NSLog(@"[Godot3ASA] AAAttribution class not found (may not be available on simulator)");
            return NO;
        }
        return YES;
    }
    return NO;
}
```

**Always test ASA features on physical iOS devices.**

## API Consistency with Android Version (TapTap Only)

### Mandatory Method Signatures (Must Match taptap.gd)
```cpp
// SDK Initialization
void initSdk(String clientId, String clientToken, bool enableLog, bool withIAP);
void initSdkWithEncryptedToken(String clientId, String encryptedToken, bool enableLog, bool withIAP);

// Login
void login(bool useProfile, bool useFriends);
bool isLogin();
String getUserProfile();  // Returns JSON string
void logout();
void logoutThenRestart();

// Compliance
void compliance();

// License & DLC
void checkLicense(bool forceCheck);
void queryDLC(Array skuIds);
void purchaseDLC(String skuId);

// IAP (not supported on iOS, log warnings)
void queryProductDetailsAsync(Array products);
void launchBillingFlow(String productId, String accountId);
void finishPurchaseAsync(String orderId, String token);
void queryUnfinishedPurchaseAsync();

// Utilities
void showTip(String text);
void restartApp();
```

### Signal Names (Must Match Android)
```cpp
ADD_SIGNAL(MethodInfo("onLoginSuccess"));
ADD_SIGNAL(MethodInfo("onLoginFail", PropertyInfo(Variant::STRING, "message")));
ADD_SIGNAL(MethodInfo("onLoginCancel"));
ADD_SIGNAL(MethodInfo("onComplianceResult", PropertyInfo(Variant::INT, "code"), PropertyInfo(Variant::STRING, "info")));
ADD_SIGNAL(MethodInfo("onLicenseSuccess"));
ADD_SIGNAL(MethodInfo("onLicenseFailed"));
ADD_SIGNAL(MethodInfo("onDLCQueryResult", PropertyInfo(Variant::STRING, "jsonString")));
ADD_SIGNAL(MethodInfo("onDLCPurchaseResult", PropertyInfo(Variant::STRING, "skuId"), PropertyInfo(Variant::INT, "status")));
```

## Token Encryption System (iOS-Specific)

### Configuration via Info.plist
Unlike Android's `res/values/strings.xml`, iOS stores the decrypt key in `Info.plist`:

```xml
<!-- Info.plist -->
<key>TapTapDecryptKey</key>
<string>TapTapz9mdoNZSItSxJOvG</string>
```

### Encryption Workflow
1. **Generate Key**: Use `addons/godot3-taptap/generate_secure_key.gd` or GUI tool
2. **Encrypt Token**: XOR encryption with key (same algorithm as Android)
3. **Store Key**: Add to project's `Info.plist` manually or via export template
4. **Runtime Decryption**: Read plist → XOR decrypt → init SDK

### Implementation Pattern
```objective-c
// In GodotTapTapDelegate
- (NSString *)getDecryptKey {
    NSDictionary *infoPlist = [[NSBundle mainBundle] infoDictionary];
    NSString *key = [infoPlist objectForKey:@"TapTapDecryptKey"];
    return key ?: @"TapTapz9mdoNZSItSxJOvG";  // Fallback key
}

- (NSString *)decryptToken:(NSString *)encryptedToken {
    NSString *decryptKey = [self getDecryptKey];
    NSData *encryptedData = [[NSData alloc] initWithBase64EncodedString:encryptedToken options:0];
    NSData *keyData = [decryptKey dataUsingEncoding:NSUTF8StringEncoding];
    
    // XOR decryption
    NSMutableData *decryptedData = [NSMutableData dataWithLength:encryptedData.length];
    const uint8_t *encBytes = [encryptedData bytes];
    const uint8_t *keyBytes = [keyData bytes];
    uint8_t *decBytes = [decryptedData mutableBytes];
    
    for (NSUInteger i = 0; i < encryptedData.length; i++) {
        decBytes[i] = encBytes[i] ^ keyBytes[i % keyData.length];
    }
    
    return [[NSString alloc] initWithData:decryptedData encoding:NSUTF8StringEncoding];
}
```

## Critical Build Workflows

### Complete Build Pipeline (from CI)
```bash
# 1. Generate Godot headers (interrupt after headers, ~30sec)
./scripts/generate_headers.sh 3.x  # Runs: cd godot && timeout scons platform=iphone target=release_debug

# 2. Build XCFrameworks for all targets
./scripts/release_xcframework.sh 3.x
# This runs:
#   - scons for arm64 device + x86_64/arm64 simulators
#   - lipo to create fat simulator library  
#   - xcodebuild -create-xcframework
#   - Generates both .release and .debug.xcframework (rename of release_debug)
#   - Outputs to bin/release/<plugin>/

# 3. Manual single build (for development)
scons target=release_debug arch=arm64 simulator=no plugin=godot3taptap version=3.x
scons target=release_debug arch=arm64 simulator=no plugin=godot3_asa version=3.x
```

**Target Confusion Alert:**
- Use `release_debug` for builds matching official Godot templates (NOT `debug`)
- CI renames `release_debug.xcframework` → `debug.xcframework` for distribution
- SCons naming: `lib<plugin>.<arch>-<simulator|ios>.<target>.a`

### Caching Strategy (CI)
CI uses three cache layers for speed:
1. **Python pip**: Built into `setup-python` action (`cache: 'pip'`)
2. **SCons build cache**: `~/.scons_cache`, `godot/.scons_cache` - keyed by source file hashes
3. **Godot headers**: `godot/bin` - keyed by `version.py` + core files hash

This reduces 15-min builds to ~5 mins on cache hit.

### Local Development Testing
```bash
# Test compilation only (no full build)
scons target=release_debug arch=arm64 simulator=no plugin=godot3taptap version=3.x --dry-run

# Clean build artifacts
rm -rf bin/*.a bin/*.xcframework

# Verify .gdip function names match module registration
grep "initialization=" plugins/godot3taptap/godot3taptap.gdip
# Must match: void register_godot3taptap_types() in godot3taptap_module.cpp
```

## Code Patterns & Conventions

### Objective-C Delegate Pattern (MANDATORY)
```objective-c
// In .mm file, BEFORE C++ implementation:
@interface GodotTapTapDelegate : NSObject
@property(nonatomic, strong) NSString *clientId;
- (void)initSDKWithClientId:(NSString *)clientId ...;
- (void)loginWithProfile:(BOOL)useProfile ...;
@end

@implementation GodotTapTapDelegate
- (void)loginWithProfile:(BOOL)useProfile ... {
    // Call real TapTap SDK here
    [TapTapLogin startWithScopes:scopes completion:^(TapTapAccount *account, NSError *error) {
        // Post results back to Godot via C++ singleton
        Dictionary ret;
        ret["type"] = "login";
        ret["result"] = error ? "error" : "success";
        Godot3TapTap::get_singleton()->_post_event(ret);
    }];
}
@end

static GodotTapTapDelegate *taptap_delegate = nil;  // Static instance
```

### Version Compatibility (Godot 3.x vs 4.x)
```cpp
#if VERSION_MAJOR == 4
    #include "core/object/class_db.h"
    typedef PackedStringArray GodotStringArray;
#else
    #include "core/object.h"
    typedef PoolStringArray GodotStringArray;
#endif
```

### Event Queue System
```cpp
// In .h file:
List<Variant> pending_events;
void _post_event(Variant p_event);  // Called from ObjC callbacks

// In .mm file:
void Godot3TapTap::_post_event(Variant p_event) {
    pending_events.push_back(p_event);
}

int Godot3TapTap::get_pending_event_count() { return pending_events.size(); }
Variant Godot3TapTap::pop_pending_event() {
    Variant front = pending_events.front()->get();
    pending_events.pop_front();
    return front;
}
```

### Singleton Registration
```cpp
// In <plugin>_module.cpp:
#include "core/engine.h"  // Godot 3.x
Godot3TapTap *godot3taptap;

void register_godot3taptap_types() {
    godot3taptap = memnew(Godot3TapTap);
    Engine::get_singleton()->add_singleton(Engine::Singleton("Godot3TapTap", godot3taptap));
}
```

## TapTap SDK Integration

### Embedded Frameworks (in .gdip)
```ini
embedded=[
    "sdk/TapTapLoginSDK.xcframework",
    "sdk/TapTapComplianceSDK.xcframework",
    "sdk/TapTapBasicToolsSDK.xcframework",
    "sdk/TapTapCoreSDK.xcframework",
    "sdk/TapTapGidSDK.xcframework",
    "sdk/TapTapNetworkSDK.xcframework",
    "sdk/tapsdkcorecpp.xcframework",
    "sdk/TapTapSDKBridgeCore.xcframework",
    "sdk/THEMISLite.xcframework",
    "sdk/TapTapLoginResource.bundle",
    "sdk/TapTapComplianceResource.bundle"
]
```

### Import Headers (when SDK integrated)
```objective-c
// In .mm file, replace TODO comments:
#import <TapTapLoginSDK/TapTapLoginSDK.h>
#import <TapTapComplianceSDK/TapTapComplianceSDK.h>
```

## Common Pitfalls

1. **Missing ObjC Delegate Classes:** `.mm` files without `@interface/@implementation` will compile but won't integrate iOS APIs properly
2. **Wrong Target Names:** Using `debug` instead of `release_debug` causes template mismatch
3. **Function Name Mismatches:** `.gdip` initialization/deinitialization MUST match `_module.cpp` function names exactly (currently has mismatch - needs fixing!)
4. **Simulator vs Device:** Builds for `simulator=yes` use different SDK path (`iphonesimulator` vs `iphoneos`)
5. **Memory Management:** Always use `memnew`/`memdelete`, never `new`/`delete`
6. **API Inconsistency:** Method signatures must EXACTLY match Android version for cross-platform compatibility (TapTap only)
7. **Plist Key Names:** Use consistent keys like `TapTapDecryptKey` (not `taptap_decrypt_key` like Android resources)
8. **ASA Simulator Testing:** AdServices doesn't work on simulators - always test on real devices
9. **Logging Prefixes:** Use `[Godot3<Plugin>]` in .mm files, `[<Abbrev>]` in .gd files for clear debugging

## Testing & Debugging

- Plugins **only work on iOS devices/simulators**, not in Godot editor
- Use `NSLog(@"...")` for ObjC debugging; logs appear in Xcode console
- To test: Export Godot project → Open in Xcode → Run on device/simulator
- Check singleton availability: `if Engine.has_singleton("Godot3TapTap"): ...`
- Test encryption: Verify plist key exists with `[[NSBundle mainBundle] infoDictionary]`

## File Naming Convention
- Build outputs: `bin/libgodot3taptap.arm64-ios.release_debug.a`
- XCFramework: `bin/godot3taptap.release.xcframework` (device + simulator)
- Distribution: `bin/release/godot3taptap/` (contains .xcframework + .gdip)

## Shared Addons System
- **Unified GDScript API**: `addons/godot3-taptap/taptap.gd` works for both Android & iOS
- **Platform Detection**: Singleton auto-detects `Engine.has_singleton("Godot3TapTap")`
- **Encryption Tools**: `generate_secure_key.gd` and `taptap_config_window.gd` generate keys for both platforms
- **Key Storage**: Android uses `res/values/strings.xml`, iOS uses `Info.plist`</content>
<parameter name="filePath">d:\Workspace\Godot\Source\godot-ios-plugins\.github\copilot-instructions.md