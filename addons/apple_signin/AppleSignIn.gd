extends Node
## Sign In with Apple — GDScript API wrapper
##
## Autoloaded as "AppleSignIn" when the addon is enabled.
## On iOS the native singleton "AppleSignIn" is polled each _process frame;
## on other platforms every method is a no-op that emits an "error" event.
##
## Required Xcode entitlement (add manually in Capabilities or .entitlements):
##   com.apple.developer.applesignin = ["Default"]
##
## Minimum iOS deployment target: 13.0
##
## --- First-login data caching ---
## Apple only provides email and full-name ONCE (on the very first sign-in).
## This script automatically persists those fields to
##   user://apple_signin_cache/<sanitized_user_id>.json
## on first login, and merges the cached values back into every subsequent
## sign_in event so callers always receive the complete profile.

const PLUGIN_NAME := "AppleSignIn"

## Subdirectory inside user:// where per-account cache files are stored.
const CACHE_DIR := "user://apple_signin_cache"

## Keys that Apple delivers only on first sign-in and that we want to persist.
const _FIRST_LOGIN_KEYS := [
	"email",
	"full_name_given",
	"full_name_family",
	"full_name_middle",
	"full_name_nickname",
	"full_name_prefix",
	"full_name_suffix",
]

var _singleton = null  # native iOS singleton, nil on other platforms

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

## Emitted when sign_in() completes.
##
## event keys (result == "ok"):
##   user               String  — stable opaque user identifier (always present)
##   email              String  — email address; merged from cache if not in current response
##   full_name_given    String  — given / first name; merged from cache if not in current response
##   full_name_family   String  — family / last name; merged from cache if not in current response
##   full_name_middle   String  — middle name; merged from cache
##   full_name_nickname String  — nickname; merged from cache
##   full_name_prefix   String  — name prefix (e.g. "Dr."); merged from cache
##   full_name_suffix   String  — name suffix (e.g. "Jr."); merged from cache
##   identity_token     String  — base64-encoded JWT; verify on your server
##   authorization_code String  — base64-encoded one-time code for token exchange
##   real_user_status   int     — 0=unsupported, 1=unknown, 2=likely_real
##   state              String  — echoed nonce / state (if supplied in request)
##   cached             bool    — true when profile data was merged from the local cache
##
## event keys (result == "cancel"):
##   (no extra keys — user dismissed the dialog)
##
## event keys (result == "error"):
##   error_code         int
##   error_description  String
signal on_sign_in(event)

## Emitted when check_credential_state() completes.
##
## event keys:
##   user    String — the user ID that was checked
##   result  String — "authorized" | "revoked" | "not_found" | "transferred" | "error"
##   error_code / error_description (only when result == "error")
signal on_credential_state(event)

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	pause_mode = Node.PAUSE_MODE_PROCESS
	if Engine.has_singleton(PLUGIN_NAME):
		_singleton = Engine.get_singleton(PLUGIN_NAME)
		print("[AppleSignIn] native singleton ready")
	else:
		print("[AppleSignIn] native singleton not found — running outside iOS or plugin not installed")

func _process(_delta: float) -> void:
	if not _singleton:
		return
	var count: int = _singleton.get_pending_event_count()
	while count > 0:
		var event: Dictionary = _singleton.pop_pending_event()
		_dispatch_event(event)
		count -= 1

func _dispatch_event(event: Dictionary) -> void:
	var type: String = event.get("type", "")
	match type:
		"sign_in":
			_handle_sign_in_event(event)
		"credential_state":
			emit_signal("on_credential_state", event)

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func sign_in(request_email: bool = true, request_name: bool = true) -> int:
	## Initiate the Sign In with Apple flow.
	##
	## Parameters:
	##   request_email — whether to request the user's email address scope.
	##                   Apple only provides this on the VERY FIRST sign-in.
	##   request_name  — whether to request the user's full name scope.
	##                   Apple only provides this on the VERY FIRST sign-in.
	##
	## The result is delivered asynchronously via the on_sign_in signal.
	## Profile data (email, name) is automatically merged from the local cache
	## so subsequent logins also include the full profile.
	##
	## Returns: OK or ERR_UNAVAILABLE (non-iOS platform / iOS < 13)
	if _singleton:
		return _singleton.sign_in(request_email, request_name)
	_emit_unavailable("sign_in")
	return ERR_UNAVAILABLE

func check_credential_state(user_id: String) -> void:
	## Asynchronously check whether a previously-obtained user identifier is
	## still valid (the user has not revoked the app's access).
	##
	## Call this at app launch with the stored user ID before assuming the
	## user is still authenticated.
	##
	## The result is delivered via the on_credential_state signal.
	if _singleton:
		_singleton.check_credential_state(user_id)
	else:
		_emit_unavailable("credential_state")

# ---------------------------------------------------------------------------
# Session state queries
# ---------------------------------------------------------------------------

func is_signed_in() -> bool:
	## Synchronous in-process signed-in check.
	##
	## Returns true when the most recent sign_in() succeeded OR when
	## check_credential_state() last returned "authorized" in this session.
	##
	## IMPORTANT: this state is NOT persistent across app restarts.
	## Always call check_credential_state() at launch to re-establish it.
	if _singleton:
		return _singleton.is_signed_in()
	return false

func get_current_user() -> String:
	## Returns the user identifier from the most recent successful sign-in or
	## authorized credential-state check in this session.
	## Returns an empty String when not signed in.
	if _singleton:
		return _singleton.get_current_user()
	return ""

# ---------------------------------------------------------------------------
# Cache helpers — public for advanced use cases
# ---------------------------------------------------------------------------

func is_available() -> bool:
	## Returns true when the native plugin is present (i.e. running on iOS).
	return _singleton != null

func get_cached_profile(user_id: String) -> Dictionary:
	## Return the cached first-login profile for the given user ID,
	## or an empty Dictionary if no cache exists.
	var path := _cache_path(user_id)
	if not Directory.new().file_exists(path):
		return {}
	var file := File.new()
	if file.open(path, File.READ) != OK:
		return {}
	var text := file.get_as_text()
	file.close()
	var result = JSON.parse(text)
	if result.error != OK:
		return {}
	var data = result.result
	if typeof(data) == TYPE_DICTIONARY:
		return data
	return {}

func clear_cached_profile(user_id: String) -> void:
	## Delete the local cache file for the given user ID.
	## Useful when the user explicitly logs out or revokes access.
	var path := _cache_path(user_id)
	var dir := Directory.new()
	if dir.file_exists(path):
		dir.remove(path)
		print("[AppleSignIn] Cleared cache for user: ", user_id)

# ---------------------------------------------------------------------------
# Internal — sign-in event processing with cache merge
# ---------------------------------------------------------------------------

func _handle_sign_in_event(event: Dictionary) -> void:
	if event.get("result") != "ok":
		emit_signal("on_sign_in", event)
		return

	var user_id: String = event.get("user", "")
	if user_id.empty():
		emit_signal("on_sign_in", event)
		return

	# Determine if Apple sent fresh profile data in this response.
	var has_fresh_data: bool = not event.get("email", "").empty() \
	    or not event.get("full_name_given", "").empty() \
	    or not event.get("full_name_family", "").empty()

	if has_fresh_data:
		# First sign-in (or re-authorization) — save the profile.
		_save_profile(user_id, event)
		event["cached"] = false
	else:
		# Subsequent sign-in — merge from cache (if available).
		event["cached"] = false
		var cached := get_cached_profile(user_id)
		if not cached.empty():
			for key in _FIRST_LOGIN_KEYS:
				if event.get(key, "") == "" and cached.has(key):
					event[key] = cached[key]
			event["cached"] = true

	emit_signal("on_sign_in", event)

func _save_profile(user_id: String, event: Dictionary) -> void:
	_ensure_cache_dir()
	var profile := {}
	for key in _FIRST_LOGIN_KEYS:
		profile[key] = event.get(key, "")

	var path := _cache_path(user_id)
	var file := File.new()
	if file.open(path, File.WRITE) != OK:
		push_error("[AppleSignIn] Failed to write cache file: " + path)
		return
	file.store_string(JSON.print(profile))
	file.close()
	print("[AppleSignIn] Saved profile cache: ", path)

func _ensure_cache_dir() -> void:
	var dir := Directory.new()
	if not dir.dir_exists(CACHE_DIR):
		var err := dir.make_dir_recursive(CACHE_DIR)
		if err != OK:
			push_error("[AppleSignIn] Failed to create cache dir: " + CACHE_DIR)

func _cache_path(user_id: String) -> String:
	# Sanitize the user_id so it is safe to use as a filename.
	# Apple user IDs contain only alphanumeric characters and dots/underscores,
	# but we replace anything outside [A-Za-z0-9._-] with '_' for safety.
	var safe_id := ""
	for ch in user_id:
		if ch.length() == 1 and (ch.is_valid_identifier() or ch == "." or ch == "-"):
			safe_id += ch
		else:
			safe_id += "_"
	return CACHE_DIR + "/" + safe_id + ".json"

func _emit_unavailable(type: String) -> void:
	var event := {
		"type": type,
		"result": "error",
		"error_code": -1,
		"error_description": "AppleSignIn native plugin not available on this platform."
	}
	_dispatch_event(event)
