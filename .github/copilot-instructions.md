# Godot3 TapTap iOS Plugin - AI Coding Guidelines

## Project Overview
This is a **TapTap SDK integration plugin for Godot 3.x on iOS**. It wraps TapTap's login, compliance (anti-addiction), license verification, and DLC APIs as a Godot singleton accessible from GDScript. The plugin follows the official Godot iOS plugin architecture pattern.

**Cross-Platform Integration:** This iOS plugin shares the same `addons/godot3-taptap/` GDScript layer with the [Android version](https://github.com/GropingChour/godot3_taptap_android_plugin), ensuring unified API across platforms.

**Key Differences from Official Plugins:** 
- Bundles pre-built TapTap SDK XCFrameworks in `plugins/godot3_taptap/sdk/` (~12 frameworks)
- Implements token encryption via iOS Info.plist (vs Android's string.xml resources)

## Architecture Pattern (Critical for .mm Files)

### Dual-Layer Structure (C++ + Objective-C)
Plugins MUST use both layers - C++ wrapper + ObjC delegate classes:

```
GDScript (taptap.gd) → Godot3TapTap (C++ singleton) → GodotTapTapDelegate (@interface) → TapTap SDK (Objective-C)
                ↓                                      ↓
           _post_event() ← async callbacks ← completion handlers
                ↓
         pending_events queue → GDScript polls via pop_pending_event()
```

**Reference:** Compare `plugins/godot3taptap/godot3taptap.mm` with [official in_app_store.mm](https://github.com/godot-sdk-integrations/godot-ios-plugins/blob/master/plugins/inappstore/in_app_store.mm). Both use `@interface/@implementation` for iOS SDK callbacks.

### File Structure Requirements
Each plugin needs:
- `<plugin>.h` - C++ class declaration (inherits `Object`, declares singleton)
- `<plugin>.mm` - **Objective-C++ implementation** with:
  - `@interface <Plugin>Delegate` for SDK callbacks
  - C++ methods calling ObjC delegate
  - Event posting via `_post_event(Dictionary)`
- `<plugin>_module.{h,cpp}` - Registration (`register_<plugin>_types()` calls `memnew()` and `Engine::add_singleton()`)
- `<plugin>.gdip` - Godot plugin manifest (lists binary, embedded frameworks, initialization functions)

## API Consistency with Android Version

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
```

**Target Confusion Alert:**
- Use `release_debug` for builds matching official Godot templates (NOT `debug`)
- CI renames `release_debug.xcframework` → `debug.xcframework` for distribution
- SCons naming: `lib<plugin>.<arch>-<simulator|ios>.<target>.a`

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
6. **API Inconsistency:** Method signatures must EXACTLY match Android version for cross-platform compatibility
7. **Plist Key Names:** Use consistent keys like `TapTapDecryptKey` (not `taptap_decrypt_key` like Android resources)

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