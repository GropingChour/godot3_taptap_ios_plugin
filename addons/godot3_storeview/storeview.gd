extends Node

# iOS App Store Review Plugin for Godot 3.x
#
# This plugin wraps iOS SKStoreReviewController API to request in-app reviews
# and provides App Store review URL generation.
#
# Usage:
# 1. Request in-app review (system controlled):
#    StoreView.request_review()
#
# 2. Get App Store review URL (opens directly in App Store):
#    var url = StoreView.get_write_review_url("YOUR_APP_STORE_ID")
#    OS.shell_open(url)
#
# Notes:
# - In-app review requests are rate-limited by iOS (max 3 times per year)
# - System decides whether to show the dialog based on Apple's policies
# - Only works on iOS devices, not simulators or other platforms

const PLUGIN_NAME := "Godot3StoreView"

var singleton

func _ready():
	var is_ios = OS.get_name() == "iOS"
	
	if not is_ios:
		print("[StoreView] Not running on iOS platform")
		return
	
	if Engine.has_singleton(PLUGIN_NAME):
		singleton = Engine.get_singleton(PLUGIN_NAME)
		if singleton:
			print("[StoreView] Initialized")
		else:
			push_error("[StoreView] Failed to get singleton")
	else:
		push_error("[StoreView] Singleton not found - make sure plugin is properly installed")

# ============================================================================
# Core Functions
# ============================================================================

func is_supported() -> bool:
	"""Check if the plugin is available (iOS platform with singleton)"""
	return singleton != null

func request_review() -> void:
	"""
	Request in-app review dialog (iOS 10.3+)
	
	Note: System will decide whether to show the dialog based on:
	- Request frequency (max 3 times per 365 days)
	- User interaction patterns
	- Apple's internal policies
	
	No callback is provided - the dialog may or may not appear
	"""
	if not singleton:
		push_warning("[StoreView] Cannot request review - singleton not available")
		return
	
	print("[StoreView] Requesting review...")
	singleton.request_review()

func get_write_review_url(app_store_id: String) -> String:
	"""
	Get App Store URL with write-review action
	
	Args:
		app_store_id: Your app's App Store ID (numeric string)
	
	Returns:
		App Store URL that directly opens the review writing page
		
	Usage:
		var url = StoreView.get_write_review_url("1234567890")
		OS.shell_open(url)
	"""
	if app_store_id.empty():
		push_error("[StoreView] App Store ID cannot be empty")
		return ""
	
	if not singleton:
		push_warning("[StoreView] Singleton not available - generating URL manually")
		return "https://apps.apple.com/app/id%s?action=write-review" % app_store_id
	
	return singleton.get_write_review_url(app_store_id)

# ============================================================================
# Helper Functions
# ============================================================================

func open_review_page(app_store_id: String) -> void:
	"""
	Convenience function to directly open App Store review page
	
	Args:
		app_store_id: Your app's App Store ID (numeric string)
	"""
	var url = get_write_review_url(app_store_id)
	if not url.empty():
		print("[StoreView] Opening review page: ", url)
		OS.shell_open(url)

func should_request_review() -> bool:
	"""
	Helper to check if it's appropriate to request review
	
	Returns:
		true if on iOS platform with singleton available
		
	Note: This only checks plugin availability, not iOS rate limits.
	You should implement your own logic to track review requests
	and avoid requesting too frequently.
	"""
	return singleton != null
