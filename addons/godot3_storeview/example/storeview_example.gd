extends Node

# Example usage of Godot3StoreView plugin
#
# This example demonstrates how to request in-app reviews
# and open the App Store review page directly

# Replace with your actual App Store ID
const APP_STORE_ID = "1234567890"

# Track when we last requested a review (persist this in real app)
var last_review_request_time: int = 0
const REVIEW_REQUEST_COOLDOWN = 30 * 24 * 3600  # 30 days in seconds

func _ready():
	if not StoreView.is_supported():
		print("StoreView plugin is not available")
		return
	
	print("StoreView plugin ready!")
	
	# Example 1: Request in-app review (respects iOS rate limits)
	# Call this after positive user interactions, like:
	# - Completing a level
	# - Making a purchase
	# - Achieving a milestone
	request_review_if_appropriate()

func request_review_if_appropriate():
	"""Smart review request with custom rate limiting"""
	
	var current_time = OS.get_unix_time()
	var time_since_last_request = current_time - last_review_request_time
	
	# Custom cooldown to avoid annoying users
	if time_since_last_request < REVIEW_REQUEST_COOLDOWN:
		print("Review request on cooldown")
		return
	
	# Check other conditions (examples):
	# - User has used the app for X days
	# - User has completed Y actions
	# - User hasn't dismissed the review dialog before
	# Add your logic here...
	
	last_review_request_time = current_time
	StoreView.request_review()
	print("Review requested")

func on_review_button_pressed():
	"""Example: Direct user to App Store review page"""
	# This bypasses iOS rate limits and always works
	# Use for explicit "Rate Us" buttons
	StoreView.open_review_page(APP_STORE_ID)

func on_feedback_button_pressed():
	"""Example: Alternative approach - get URL and use it"""
	var review_url = StoreView.get_write_review_url(APP_STORE_ID)
	if not review_url.empty():
		OS.shell_open(review_url)
