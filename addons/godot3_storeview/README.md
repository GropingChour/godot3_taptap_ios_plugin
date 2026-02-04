# Godot3StoreView Plugin - GDScript API

iOS App Store Review plugin for Godot 3.x. Wraps SKStoreReviewController API for requesting in-app reviews and generating App Store review URLs.

## Quick Start

### 1. Enable Plugin

Enable the plugin in Project Settings → Plugins → Godot3StoreView

### 2. Basic Usage

```gdscript
# Access via autoload singleton
extends Node

func _ready():
    # Request in-app review (system controlled)
    StoreView.request_review()
    
    # Or open App Store review page directly
    var app_store_id = "1234567890"  # Your App Store ID
    StoreView.open_review_page(app_store_id)
```

## API Reference

### Core Functions

#### `is_supported() -> bool`
Check if the plugin is available on current platform.

```gdscript
if StoreView.is_supported():
    print("StoreView is ready")
```

#### `request_review() -> void`
Request in-app review dialog (iOS 10.3+).

**Important Notes:**
- System decides whether to show the dialog
- Rate limited by iOS (max 3 times per 365 days)
- No callback provided
- Best called after positive user interactions

```gdscript
# Good times to request review:
# - After completing a level
# - After making a purchase
# - After achieving a milestone

func on_level_completed():
    if should_request_review_now():
        StoreView.request_review()
```

#### `get_write_review_url(app_store_id: String) -> String`
Get App Store URL that opens the review writing page.

```gdscript
var app_store_id = "1234567890"
var url = StoreView.get_write_review_url(app_store_id)
# Returns: "https://apps.apple.com/app/id1234567890?action=write-review"
```

#### `open_review_page(app_store_id: String) -> void`
Convenience function to directly open App Store review page.

```gdscript
# Use for explicit "Rate Us" buttons
func on_rate_button_pressed():
    StoreView.open_review_page("1234567890")
```

#### `should_request_review() -> bool`
Helper to check if plugin is available.

**Note:** Only checks plugin availability, not iOS rate limits. Implement your own tracking logic.

## Best Practices

### 1. Smart Review Requests

Implement custom rate limiting and tracking:

```gdscript
var last_review_request: int = 0
const COOLDOWN_DAYS = 30

func request_review_if_appropriate():
    var current_time = OS.get_unix_time()
    var days_passed = (current_time - last_review_request) / 86400
    
    if days_passed >= COOLDOWN_DAYS:
        last_review_request = current_time
        StoreView.request_review()
```

### 2. Request Timing

**Good times to request:**
- After positive interactions (level complete, purchase, achievement)
- When user demonstrates engagement
- After user has experienced core features

**Bad times:**
- On first app launch
- During gameplay
- After errors or crashes
- Too frequently

### 3. Two-Tier Approach

Combine automatic requests with manual option:

```gdscript
# Automatic: Smart timing, respects iOS limits
func on_milestone_reached():
    if conditions_met():
        StoreView.request_review()

# Manual: User-initiated, always works
func on_rate_us_button():
    StoreView.open_review_page(APP_STORE_ID)
```

## iOS Rate Limits

Apple restricts in-app review requests:
- **Maximum 3 times per 365 days** per device
- System may suppress requests based on:
  - Recent review submissions
  - User interaction patterns
  - Time since app installation

**Solution:** Implement your own tracking to avoid wasted requests.

## Platform Availability

- **iOS 10.3+**: Full support
- **iOS 14.0+**: Uses scene-based API
- **Simulators**: Limited testing (reviews don't actually submit)
- **Other platforms**: Plugin safely does nothing

## Example Implementation

See [storeview_example.gd](example/storeview_example.gd) for complete example.

## Finding Your App Store ID

1. Go to App Store Connect
2. Select your app
3. Find the App ID in the URL: `https://appstoreconnect.apple.com/apps/{APP_ID}/appstore`
4. Or find in App Store URL: `https://apps.apple.com/app/id{APP_ID}`

## Troubleshooting

### Review dialog doesn't appear
- iOS rate limit reached (3 times per year)
- System suppressed request (too frequent, user behavior)
- Not running on physical device
- App not distributed via App Store/TestFlight

### Plugin not available
- Check singleton: `Engine.has_singleton("Godot3StoreView")`
- Verify plugin is enabled in Project Settings
- Ensure running on iOS platform

## Technical Details

**C++ Singleton:** `Godot3StoreView`  
**GDScript Autoload:** `StoreView`  
**iOS Framework:** StoreKit (SKStoreReviewController)

## Logging

All operations log to console with `[StoreView]` prefix:

```
[StoreView] Initialized
[StoreView] Requesting review...
[StoreView] Opening review page: https://...
```
