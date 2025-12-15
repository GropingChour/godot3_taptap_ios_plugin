# Godot iOS Plugins - AI Coding Guidelines

## Architecture Overview
This repository builds iOS-specific plugins for the Godot game engine. Each plugin (`plugins/*/`) exposes iOS APIs (Game Center, In-App Store, ARKit, etc.) as Godot singletons accessible from GDScript.

**Key Components:**
- `plugins/<name>/`: Plugin source (C++ module registration + Objective-C++ iOS integration)
- `godot/`: Godot engine headers (submodule or extracted from releases)
- `SConstruct`: SCons build configuration for cross-compiling to iOS architectures
- `scripts/`: Automation for generating fat libraries and XCFrameworks

**Data Flow:** Plugins register singletons with `Engine::get_singleton()->add_singleton()`. iOS APIs are wrapped in Objective-C++ classes (`.mm` files) called from C++ modules.

## Build Workflows
- **Generate headers:** `cd godot; scons platform=ios target=debug` (interrupt after headers generate)
- **Build plugin lib:** `scons target=release_debug arch=arm64 simulator=no plugin=gamecenter version=3.x`
- **Create XCFramework:** `./scripts/generate_xcframework.sh gamecenter release_debug 3.x` (builds device + simulator variants, combines with lipo/xcodebuild)

**Critical Notes:**
- Use `release_debug` for official Godot templates, not `debug`
- Plugins only function on iOS devices/simulators; singletons unavailable in editor
- Requires Xcode/iOS SDK; builds fail without proper `xcrun` setup

## Code Patterns
- **Plugin Structure:** `<plugin>_module.{h,cpp}` registers singleton; `<plugin>.{h,mm}` implements iOS logic
- **Version Handling:** Conditional compilation for Godot 3.x vs 4.0 (e.g., `#if VERSION_MAJOR == 4`)
- **Memory Management:** Use Godot's `memnew`/`memdelete` for singleton lifecycle
- **Event System:** Plugins queue events for GDScript polling via `get_pending_event_count()`/`pop_pending_event()`

**Examples:**
- Singleton registration: `Engine::get_singleton()->add_singleton(Engine::Singleton("GameCenter", game_center));`
- iOS API calls: Objective-C++ methods in `.mm` files bridge to Godot variants/dictionaries

## Integration Points
- **Dependencies:** iOS frameworks (GameKit, StoreKit, etc.) linked via SCons
- **Cross-Component:** Plugins communicate via Godot's Variant system; no direct inter-plugin coupling
- **External APIs:** iOS SDK calls wrapped in try/catch; errors reported as Godot events

## Conventions
- Follow Godot's C++ style (snake_case, Godot license headers)
- Plugins use `.gdip` files for Godot editor integration
- Build outputs: `bin/lib<plugin>.<arch>-<platform>.<target>.a` static libraries</content>
<parameter name="filePath">d:\Workspace\Godot\Source\godot-ios-plugins\.github\copilot-instructions.md