# Godot3StoreView Plugin

iOS App Store review plugin for Godot 3.x.

## Features

- **In-App Review Requests**: Request review dialog using SKStoreReviewController
- **App Store Review URL**: Generate and open direct App Store review page
- **iOS 10.3+ Support**: Automatic API version detection (iOS 14+ scene-based, iOS 10.3-13.x legacy)
- **Rate Limit Aware**: Respects iOS system limits (max 3 requests per 365 days)

## Installation

### 1. Copy Plugin Files

Copy the following to your Godot iOS export template:

```
plugins/godot3_storeview/
├── godot3_storeview.h
├── godot3_storeview.mm
├── godot3_storeview_module.h
├── godot3_storeview_module.cpp
└── godot3_storeview.gdip
```

### 2. Enable GDScript Layer

Copy to your Godot project:

```
addons/godot3_storeview/
├── plugin.cfg
├── plugin.gd
├── storeview.gd
├── README.md
└── example/
    └── storeview_example.gd
```

Enable plugin in: **Project Settings → Plugins → Godot3StoreView**

### 3. Configure iOS Export

In Godot Export Settings:
1. Select iOS platform
2. Under "Plugins" section, enable "Godot3StoreView"
3. Export and build with Xcode

## Quick Usage

```gdscript
# Request in-app review (system controlled)
StoreView.request_review()

# Open App Store review page directly (always works)
StoreView.open_review_page("YOUR_APP_STORE_ID")
```

## API Overview

| Function | Description |
|----------|-------------|
| `request_review()` | Request in-app review dialog (iOS 10.3+) |
| `get_write_review_url(app_store_id)` | Get App Store review URL |
| `open_review_page(app_store_id)` | Open App Store review page |
| `is_supported()` | Check if plugin is available |
| `should_request_review()` | Helper to check plugin availability |

## Important Notes

### iOS Rate Limits

Apple restricts in-app review requests:
- **Maximum 3 times per 365 days** per device
- System may suppress requests based on user behavior
- No guarantee the dialog will appear

**Best Practice:** Implement your own tracking to avoid wasted requests.

### When to Request Reviews

**Good Times:**
- After positive user interactions (level complete, purchase, achievement)
- When user demonstrates sustained engagement
- After user experiences core features

**Bad Times:**
- On first app launch
- During gameplay or active tasks
- After errors or crashes
- Too frequently (implement 30+ day cooldown)

### Two Approaches

1. **In-App Review (`request_review()`)**: 
   - Gentle, non-intrusive
   - Rate limited by iOS
   - May not appear
   
2. **Direct URL (`open_review_page()`)**: 
   - Always works
   - Leaves app to open App Store
   - Use for explicit "Rate Us" buttons

## Architecture

Follows Godot iOS plugin pattern:

```
GDScript (autoload) → C++ Singleton → iOS API
    ↓                     ↓              ↓
StoreView.gd → Godot3StoreView → SKStoreReviewController
```

**C++ Singleton:** `Godot3StoreView`  
**GDScript Autoload:** `StoreView`  
**iOS Framework:** StoreKit (SKStoreReviewController)

## Building from Source

### Prerequisites

- macOS with Xcode
- SCons build system
- Godot 3.x source code

### Build Commands

```bash
# Build for device (arm64)
scons target=release_debug arch=arm64 simulator=no plugin=godot3_storeview version=3.x

# Build for simulator (x86_64)
scons target=release_debug arch=x86_64 simulator=yes plugin=godot3_storeview version=3.x

# Build for simulator (arm64, Apple Silicon Macs)
scons target=release_debug arch=arm64 simulator=yes plugin=godot3_storeview version=3.x

# Create XCFramework (all architectures)
./scripts/release_xcframework.sh 3.x
```

Output: `bin/godot3_storeview.arm64-ios.release_debug.a`

## File Structure

```
plugins/godot3_storeview/          # C++/ObjC layer
├── godot3_storeview.h             # C++ class declaration
├── godot3_storeview.mm            # ObjC++ implementation
├── godot3_storeview_module.h      # Module registration header
├── godot3_storeview_module.cpp    # Module registration implementation
└── godot3_storeview.gdip          # Plugin manifest

addons/godot3_storeview/           # GDScript layer
├── plugin.cfg                     # Editor plugin config
├── plugin.gd                      # Editor plugin (autoload registration)
├── storeview.gd                   # Main GDScript API
├── README.md                      # API documentation
└── example/
    └── storeview_example.gd       # Usage examples
```

## Documentation

- **GDScript API:** See [addons/godot3_storeview/README.md](../../addons/godot3_storeview/README.md)
- **Example Code:** See [example/storeview_example.gd](../../addons/godot3_storeview/example/storeview_example.gd)

## Troubleshooting

### Review dialog not appearing

1. Check iOS rate limit (max 3 per year)
2. Test on physical device (not simulator)
3. Ensure app is distributed via App Store/TestFlight
4. Verify timing (not too frequent)

### Plugin not found

1. Check export settings: iOS → Plugins → Godot3StoreView enabled
2. Verify singleton: `Engine.has_singleton("Godot3StoreView")`
3. Check Xcode build logs for errors

### Build errors

1. Verify Godot 3.x headers are generated
2. Check `SConstruct` has `godot3_storeview` in plugin list
3. Ensure StoreKit framework is linked

## License

MIT License - See LICENSE file

## Credits

Based on official Godot iOS plugin architecture.
Compatible with Godot 3.x engine.
