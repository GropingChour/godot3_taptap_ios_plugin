# Apple Sign In — Native Plugin Layer (Objective-C++)

This directory contains the native iOS plugin implementation for **Sign In with Apple** (`ASAuthorizationAppleIDProvider`), built as a Godot 3.x iOS plugin.

## File Structure

| File | Description |
|---|---|
| `apple_signin.h` | C++ class declaration; inherits `Object`; declares the Godot singleton |
| `apple_signin.mm` | Objective-C++ implementation; contains `GodotAppleSignInDelegate` and all C++ method bodies |
| `apple_signin_module.h` | Module registration function declarations |
| `apple_signin_module.cpp` | `register_apple_signin_types` / `unregister_apple_signin_types` entry points |
| `apple_signin.gdip` | Godot plugin manifest — tells the engine which binary to load and which system framework to link |

## Methods

### Sign In

`sign_in(bool request_email, bool request_name)` — Initiates the Sign In with Apple flow.  
Both parameters scope what information the OS dialog will request. Apple **only provides the email and name on the very first sign-in**; subsequent calls return empty strings for those fields.  
Generates an event with `"type": "sign_in"`.

### Credential State

`check_credential_state(String user_id)` — Asynchronously verifies whether a previously-obtained `user` identifier is still valid (i.e., the user has not revoked the app's access).  
Generates an event with `"type": "credential_state"`.

### Event Queue

`get_pending_event_count()` — Returns the number of events waiting to be consumed.  
`pop_pending_event()` — Dequeues and returns the oldest pending event as a `Dictionary`.

## Events

### `sign_in`

| Key | Type | Notes |
|---|---|---|
| `type` | String | `"sign_in"` |
| `result` | String | `"ok"` \| `"cancel"` \| `"error"` |
| `user` | String | Stable opaque user identifier — **persist this**; it is always returned on every login |
| `email` | String | Email address — **only on first sign-in**, empty string thereafter |
| `full_name_given` | String | Given / first name — **only on first sign-in** |
| `full_name_family` | String | Family / last name — **only on first sign-in** |
| `full_name_middle` | String | Middle name |
| `full_name_nickname` | String | Nickname |
| `full_name_prefix` | String | Name prefix (e.g. `"Dr."`) |
| `full_name_suffix` | String | Name suffix (e.g. `"Jr."`) |
| `identity_token` | String | Base64-encoded JWT — send to your server via Apple's REST API for verification |
| `authorization_code` | String | Base64-encoded one-time code — exchange on your server for access/refresh tokens |
| `real_user_status` | int | `0`=unsupported, `1`=unknown, `2`=likely a real person |
| `state` | String | Echoed nonce / state string from the original request |
| `error_code` | int | Only when `result == "error"` |
| `error_description` | String | Only when `result == "error"` |

### `credential_state`

| Key | Type | Notes |
|---|---|---|
| `type` | String | `"credential_state"` |
| `user` | String | The user ID that was checked |
| `result` | String | `"authorized"` \| `"revoked"` \| `"not_found"` \| `"transferred"` \| `"error"` |
| `error_code` | int | Only when `result == "error"` |
| `error_description` | String | Only when `result == "error"` |

## Build

```bash
# Single architecture build (development)
scons target=release_debug arch=arm64 simulator=no plugin=apple_signin version=3.x

# Full XCFramework (device + simulator, release + debug)
./scripts/release_apple_signin.sh 3.x
```

Output is placed in `bin/release/apple_signin/`.

## Architecture & Design Notes

### Presentation Context (no UIViewController required)
Apple's `ASAuthorizationController` requires a *presentation context provider* to know which window to anchor the sign-in sheet to. This plugin conforms to `ASAuthorizationControllerPresentationContextProviding` and returns the app's `UIWindow` directly — no dependency on a specific `UIViewController`.

### iOS 13 Availability Guard
All `AuthenticationServices` APIs are wrapped in `@available(iOS 13.0, *)` guards. On older OS versions the method posts an immediate `"error"` event with `error_code = -1` instead of crashing.

### Thread Safety
Apple delivers `ASAuthorizationControllerDelegate` callbacks on the main thread, so `_post_event()` is always called from the main thread — consistent with Godot's event-queue pattern.

### Strong Reference Management
`GodotAppleSignInDelegate` and `ASAuthorizationController` are kept in static variables (`apple_signin_delegate`, `auth_controller`) so they remain alive until the callback fires. Without these strong references the ObjC runtime would deallocate them before completing.

### Credential State: "transferred"
`ASAuthorizationAppleIDProviderCredentialTransferred` is a state added in iOS 14 that indicates a user ID has migrated to a new app (via Universal Links / associated domains). The plugin handles this with an `@available(iOS 14.0, *)` inner guard and maps it to `"transferred"`.

## ⚠️ Critical Notes

1. **Xcode Entitlement is mandatory.** The `AuthenticationServices.framework` system link in the `.gdip` is not enough. You must also add the `com.apple.developer.applesignin` entitlement with value `["Default"]` to your exported Xcode project under **Target → Signing & Capabilities → Sign In with Apple**.

2. **`email` and `full_name_*` are first-login only.** Apple delivers these values exactly once. If your app does not persist them before the user is asked to log in again, this information is **permanently lost**. The GDScript layer (`addons/apple_signin/`) handles caching automatically.

3. **`identity_token` must be verified server-side.** Always send the JWT to your backend and verify it using Apple's public keys before granting access. Do not trust client-side data alone.

4. **`user` identifier scope.** The `user` string is scoped to your *development team* — not just your app. Two apps by the same team will see the same `user` ID for the same Apple account.

5. **RevocationNotification.** Consider observing `ASAuthorizationAppleIDProvider.credentialRevokedNotification` (not exposed as a signal here, as it would require a persistent listener) and calling `check_credential_state` on the next launch.
