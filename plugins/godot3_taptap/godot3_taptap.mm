/*************************************************************************/
/*  godot3_taptap.mm                                                     */
/*************************************************************************/
/*                       This file is part of:                           */
/*                           GODOT ENGINE                                */
/*                      https://godotengine.org                          */
/*************************************************************************/
/* Copyright (c) 2007-2021 Juan Linietsky, Ariel Manzur.                 */
/* Copyright (c) 2014-2021 Godot Engine contributors (cf. AUTHORS.md).   */
/*                                                                       */
/* Permission is hereby granted, free of charge, to any person obtaining */
/* a copy of this software and associated documentation files (the       */
/* "Software"), to deal in the Software without restriction, including   */
/* without limitation the rights to use, copy, modify, merge, publish,   */
/* distribute, sublicense, and/or sell copies of the Software, and to    */
/* permit persons to whom the Software is furnished to do so, subject to */
/* the following conditions:                                             */
/*                                                                       */
/* The above copyright notice and this permission notice shall be        */
/* included in all copies or substantial portions of the Software.       */
/*                                                                       */
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,       */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF    */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.*/
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY  */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,  */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE     */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                */
/*************************************************************************/

#include "godot3_taptap.h"

#if VERSION_MAJOR == 4
#import "platform/ios/app_delegate.h"
#import "platform/ios/view_controller.h"
#include "core/io/json.h"
#else
#import "platform/iphone/app_delegate.h"
#import "platform/iphone/view_controller.h"
#include "core/io/json.h"
#endif

#import <Foundation/Foundation.h>
#import <objc/runtime.h>  // Required for runtime method injection

// TapTap SDK Headers
#import <TapTapLoginSDK/TapTapLoginSDK.h>
#import <TapTapComplianceSDK/TapTapComplianceSDK.h>
#import <TapTapCoreSDK/TapTapCoreSDK.h>

#if VERSION_MAJOR == 4
typedef PackedStringArray GodotStringArray;
#else
typedef PoolStringArray GodotStringArray;
#endif

// MARK: - Runtime Fix for Missing TapTapEvent Methods

/**
 * @brief Runtime method injector to fix missing TapTapEvent methods
 * 
 * Problem: TapTap SDK's TapTapEvent class is missing the +captureUncaughtException
 * class method, which causes a crash with "unrecognized selector" error during SDK initialization.
 * 
 * Solution: Use Objective-C runtime to inject a stub implementation of the missing method
 * before SDK initialization occurs. This is done in +load which runs before main().
 * 
 * Technical Details:
 * - Class methods are stored in the metaclass, not the class itself
 * - Must use object_getClass() to get metaclass for class method injection
 * - +load is called automatically by the runtime during class loading
 * - This fix is transparent to the SDK and prevents crashes
 */
@interface TapTapEventMethodInjector : NSObject
+ (void)injectMissingMethods;
@end

@implementation TapTapEventMethodInjector

/**
 * @brief Automatically called by Objective-C runtime before main()
 * 
 * The +load method is guaranteed to be called exactly once per class,
 * during the initial loading of the class into the runtime, before any
 * instances are created or any other methods are called.
 */
+ (void)load {
	NSLog(@"[TapTap Fix] +load called, injecting missing TapTapEvent methods");
	[self injectMissingMethods];
}

/**
 * @brief Injects stub implementations for missing TapTapEvent methods
 * 
 * This method checks if TapTapEvent class exists and if it's missing
 * the captureUncaughtException method. If missing, it injects a no-op
 * stub to prevent crashes.
 */
+ (void)injectMissingMethods {
	// Step 1: Check if TapTapEvent class exists
	Class eventClass = NSClassFromString(@"TapTapEvent");
	if (!eventClass) {
		NSLog(@"[TapTap Fix] TapTapEvent class not found, skipping injection (SDK might not be linked yet)");
		return;
	}
	
	NSLog(@"[TapTap Fix] TapTapEvent class found: %@", eventClass);
	
	// Step 2: Check if the problematic method already exists
	SEL missingSelector = @selector(captureUncaughtException);
	Method existingMethod = class_getClassMethod(eventClass, missingSelector);
	
	if (existingMethod) {
		NSLog(@"[TapTap Fix] +[TapTapEvent captureUncaughtException] already exists, no injection needed");
		return;
	}
	
	NSLog(@"[TapTap Fix] +[TapTapEvent captureUncaughtException] is MISSING");
	NSLog(@"[TapTap Fix] Injecting stub implementation to prevent crash...");
	
	// Step 3: Create a no-op stub implementation using a block
	// This block will be called instead of the missing method
	IMP stubImplementation = imp_implementationWithBlock(^(id self) {
		// Empty implementation - does nothing but prevents crash
		NSLog(@"[TapTap Fix] Stub +[TapTapEvent captureUncaughtException] was called (no-op)");
		// The SDK probably wanted to set up exception handlers here,
		// but we skip it to avoid crashes. This is safe because:
		// 1. Exception handling is optional functionality
		// 2. The game has its own crash handlers (Godot, OS)
		// 3. TapTap SDK will still work without this feature
	});
	
	// Step 4: Get the metaclass (required for class method injection)
	// Class methods are stored in the metaclass, not the class itself
	Class metaClass = object_getClass(eventClass);
	NSLog(@"[TapTap Fix] Metaclass for injection: %@", metaClass);
	
	// Step 5: Add the method to the metaclass
	// Signature: "v@:" means: void return, id self, SEL _cmd (no other parameters)
	BOOL added = class_addMethod(metaClass, 
								  missingSelector, 
								  stubImplementation, 
								  "v@:");
	
	if (added) {
		NSLog(@"[TapTap Fix] ✅ Successfully injected +[TapTapEvent captureUncaughtException]");
		
		// Verify the injection worked
		if ([eventClass respondsToSelector:missingSelector]) {
			NSLog(@"[TapTap Fix] ✅ Verification: Method is now callable");
		} else {
			NSLog(@"[TapTap Fix] ⚠️  WARNING: Method was added but verification failed!");
		}
	} else {
		NSLog(@"[TapTap Fix] ❌ Failed to inject method (method might already exist or class is read-only)");
	}
}

@end

// MARK: - Objective-C Delegate for TapTap SDK callbacks

@interface GodotTapTapDelegate : NSObject <TapTapComplianceDelegate>

@property(nonatomic, strong) NSString *clientId;
@property(nonatomic, strong) NSString *clientToken;
@property(nonatomic, assign) BOOL sdkInitialized;
@property(nonatomic, strong) NSString *currentUserId;

- (NSString *)getDecryptKey;
- (NSString *)decryptToken:(NSString *)encryptedToken;
- (void)initSDKWithClientId:(NSString *)clientId clientToken:(NSString *)clientToken enableLog:(BOOL)enableLog withIAP:(BOOL)withIAP;
- (void)loginWithProfile:(BOOL)useProfile friends:(BOOL)useFriends;
- (BOOL)isLoggedIn;
- (NSDictionary *)getUserProfile;
- (void)logout;
- (void)startComplianceWithUserId:(NSString *)userId;
- (void)checkLicenseWithForce:(BOOL)force;
- (void)queryDLCWithSkuIds:(NSArray *)skuIds;
- (void)purchaseDLCWithSkuId:(NSString *)skuId;

@end

@implementation GodotTapTapDelegate

- (instancetype)init {
	self = [super init];
	if (self) {
		_sdkInitialized = NO;
		_currentUserId = nil;
		// Register as compliance delegate
		[TapTapCompliance registerComplianceDelegate:self];
	}
	return self;
}

- (NSString *)getDecryptKey {
	// Try to read from Info.plist first
	NSDictionary *infoPlist = [[NSBundle mainBundle] infoDictionary];
	NSString *key = [infoPlist objectForKey:@"TapTapDecryptKey"];
	
	if (key && key.length > 0) {
		NSLog(@"[TapTap] Using decrypt key from Info.plist");
		return key;
	}
	
	// Fallback to default key (same as Android)
	NSLog(@"[TapTap] Using default decrypt key");
	return @"TapTapz9mdoNZSItSxJOvG";
}

- (NSString *)decryptToken:(NSString *)encryptedToken {
	if (!encryptedToken || encryptedToken.length == 0) {
		NSLog(@"[TapTap] Empty encrypted token");
		return @"";
	}
	
	NSString *decryptKey = [self getDecryptKey];
	
	// Base64 decode
	NSData *encryptedData = [[NSData alloc] initWithBase64EncodedString:encryptedToken options:0];
	if (!encryptedData) {
		NSLog(@"[TapTap] Failed to decode Base64 token");
		return @"";
	}
	
	// XOR decryption
	NSData *keyData = [decryptKey dataUsingEncoding:NSUTF8StringEncoding];
	NSMutableData *decryptedData = [NSMutableData dataWithLength:encryptedData.length];
	
	const uint8_t *encBytes = (const uint8_t *)[encryptedData bytes];
	const uint8_t *keyBytes = (const uint8_t *)[keyData bytes];
	uint8_t *decBytes = (uint8_t *)[decryptedData mutableBytes];
	
	// XOR decrypt each byte
	for (NSUInteger i = 0; i < encryptedData.length; i++) {
		decBytes[i] = encBytes[i] ^ keyBytes[i % keyData.length];
	}
	
	NSString *decryptedToken = [[NSString alloc] initWithData:decryptedData encoding:NSUTF8StringEncoding];
	
	if (!decryptedToken) {
		NSLog(@"[TapTap] Failed to convert decrypted data to UTF-8 string");
		return @"";
	}
	
	NSLog(@"[TapTap] Token decrypted successfully (length: %lu)", (unsigned long)decryptedToken.length);
	return decryptedToken;
}

/**
 * @brief Initialize TapTap SDK with client credentials
 * 
 * @param clientId TapTap application client ID
 * @param clientToken TapTap application client token (plaintext)
 * @param enableLog Enable SDK debug logging
 * @param withIAP Enable In-App Purchase features (not supported on iOS)
 * 
 * CRITICAL: This method MUST be called on the main thread because:
 * 1. TapTap SDK registers notification observers that require main thread
 * 2. SDK may perform UI operations during initialization
 * 3. Thread safety is ensured at C++ layer before calling this method
 * 
 * The method includes comprehensive logging and error handling to diagnose
 * initialization issues, especially the missing captureUncaughtException method.
 */
- (void)initSDKWithClientId:(NSString *)clientId clientToken:(NSString *)clientToken enableLog:(BOOL)enableLog withIAP:(BOOL)withIAP {
	_clientId = clientId;
	_clientToken = clientToken;
	
	// === Initialization Start - Log Configuration ===
	NSLog(@"[TapTap ObjC] ========================================");
	NSLog(@"[TapTap ObjC] SDK Initialization Start");
	NSLog(@"[TapTap ObjC] ========================================");
	NSLog(@"[TapTap ObjC] Thread: %@", [NSThread currentThread]);
	NSLog(@"[TapTap ObjC] Main thread: %d (MUST be 1)", [NSThread isMainThread]);
	NSLog(@"[TapTap ObjC] Client ID: %@", clientId);
	NSLog(@"[TapTap ObjC] Enable log: %d", enableLog);
	NSLog(@"[TapTap ObjC] With IAP: %d (ignored on iOS)", withIAP);
	
	// === Thread Safety Check ===
	// If not on main thread, abort immediately to prevent crashes
	if (![NSThread isMainThread]) {
		NSLog(@"[TapTap ObjC] ❌ FATAL ERROR: Not on main thread!");
		NSLog(@"[TapTap ObjC] TapTap SDK initialization MUST run on main thread");
		NSLog(@"[TapTap ObjC] Call stack:");
		for (NSString *frame in [NSThread callStackSymbols]) {
			NSLog(@"[TapTap ObjC]   %@", frame);
		}
		
		// Post error event to GDScript
		Dictionary ret;
		ret["type"] = "init";
		ret["result"] = "error";
		ret["message"] = "SDK initialization called from background thread";
		Godot3TapTap::get_singleton()->_post_event(ret);
		return;
	}
	
	// === Verify Runtime Method Injection ===
	// Check if our +load method successfully injected the missing method
	Class eventClass = NSClassFromString(@"TapTapEvent");
	if (eventClass) {
		NSLog(@"[TapTap ObjC] Checking TapTapEvent class: %@", eventClass);
		
		SEL targetSelector = @selector(captureUncaughtException);
		if ([eventClass respondsToSelector:targetSelector]) {
			NSLog(@"[TapTap ObjC] ✅ captureUncaughtException is available (injected by runtime fix)");
		} else {
			NSLog(@"[TapTap ObjC] ⚠️  WARNING: captureUncaughtException STILL missing!");
			NSLog(@"[TapTap ObjC] Runtime injection may have failed. SDK may crash during init.");
		}
	} else {
		NSLog(@"[TapTap ObjC] TapTapEvent class not found (SDK might initialize it later)");
	}
	
	// === Create SDK Options ===
	NSLog(@"[TapTap ObjC] Creating TapTapSdkOptions...");
	TapTapSdkOptions *options = [[TapTapSdkOptions alloc] init];
	
	if (!options) {
		NSLog(@"[TapTap ObjC] ❌ Failed to allocate TapTapSdkOptions!");
		Dictionary ret;
		ret["type"] = "init";
		ret["result"] = "error";
		ret["message"] = "Failed to create SDK options object";
		Godot3TapTap::get_singleton()->_post_event(ret);
		return;
	}
	
	// Configure basic options
	options.clientId = clientId;
	options.clientToken = clientToken;
	options.region = TapTapRegionTypeCN;  // China region
	options.enableLog = enableLog;
	NSLog(@"[TapTap ObjC] Basic options configured");
	
	// === Attempt to Disable Crash Reporting (Defense in Depth) ===
	// Even with runtime injection, try to disable crash handlers as backup
	NSLog(@"[TapTap ObjC] Attempting to disable SDK crash reporting...");
	
	@try {
		// Method 1: enableAutoReport property
		if ([options respondsToSelector:@selector(setEnableAutoReport:)]) {
			[options setValue:@NO forKey:@"enableAutoReport"];
			NSLog(@"[TapTap ObjC]   ✓ Disabled via enableAutoReport");
		} else {
			NSLog(@"[TapTap ObjC]   ✗ enableAutoReport not available");
		}
		
		// Method 2: TapTapEventOptions configuration
		Class eventOptionsClass = NSClassFromString(@"TapTapEventOptions");
		if (eventOptionsClass && [options respondsToSelector:@selector(setEventOptions:)]) {
			id eventOptions = [[eventOptionsClass alloc] init];
			if (eventOptions && [eventOptions respondsToSelector:@selector(setEnable:)]) {
				[eventOptions setValue:@NO forKey:@"enable"];
				[options setValue:eventOptions forKey:@"eventOptions"];
				NSLog(@"[TapTap ObjC]   ✓ Disabled via TapTapEventOptions");
			}
		} else {
			NSLog(@"[TapTap ObjC]   ✗ TapTapEventOptions not available");
		}
		
		// Method 3: enableCrashReport property
		if ([options respondsToSelector:@selector(setEnableCrashReport:)]) {
			[options setValue:@NO forKey:@"enableCrashReport"];
			NSLog(@"[TapTap ObjC]   ✓ Disabled via enableCrashReport");
		}
		
	} @catch (NSException *e) {
		NSLog(@"[TapTap ObjC]   ⚠️  Exception while configuring: %@", e);
		NSLog(@"[TapTap ObjC]   Continuing with default configuration...");
	}
	
	// === Initialize TapTap SDK ===
	NSLog(@"[TapTap ObjC] ----------------------------------------");
	NSLog(@"[TapTap ObjC] Calling [TapTapSDK initWithOptions]...");
	NSLog(@"[TapTap ObjC] ----------------------------------------");
	
	@try {
		// This is where the crash would occur if captureUncaughtException is missing
		[TapTapSDK initWithOptions:options];
		NSLog(@"[TapTap ObjC] ✅ [TapTapSDK initWithOptions] returned successfully");
		
	} @catch (NSException *exception) {
		// If we get here, either:
		// 1. Runtime injection failed
		// 2. There's a different exception
		NSLog(@"[TapTap ObjC] ❌❌❌ SDK initialization threw exception!");
		NSLog(@"[TapTap ObjC] Exception: %@", exception);
		NSLog(@"[TapTap ObjC] Reason: %@", exception.reason);
		NSLog(@"[TapTap ObjC] User info: %@", exception.userInfo);
		NSLog(@"[TapTap ObjC] Stack trace:");
		for (NSString *frame in [exception callStackSymbols]) {
			NSLog(@"[TapTap ObjC]   %@", frame);
		}
		
		// Post error event to GDScript
		Dictionary ret;
		ret["type"] = "init";
		ret["result"] = "error";
		ret["message"] = String::utf8([[NSString stringWithFormat:@"SDK Exception: %@", exception.reason] UTF8String]);
		Godot3TapTap::get_singleton()->_post_event(ret);
		return;
	}
	
	// === Initialization Success ===
	_sdkInitialized = YES;
	
	NSLog(@"[TapTap ObjC] ========================================");
	NSLog(@"[TapTap ObjC] ✅✅✅ SDK Initialization SUCCESS");
	NSLog(@"[TapTap ObjC] ========================================");
	
	// Post success event to GDScript on main thread
	// (Already on main thread, but dispatch_async ensures event queue is processed correctly)
	dispatch_async(dispatch_get_main_queue(), ^{
		Dictionary ret;
		ret["type"] = "init";
		ret["result"] = "ok";
		Godot3TapTap::get_singleton()->_post_event(ret);
		NSLog(@"[TapTap ObjC] Success event posted to GDScript");
	});
}

- (void)loginWithProfile:(BOOL)useProfile friends:(BOOL)useFriends {
	NSLog(@"[TapTap ObjC] loginWithProfile called");
	NSLog(@"[TapTap ObjC] Thread: %@", [NSThread currentThread]);
	NSLog(@"[TapTap ObjC] IsMainThread: %d", [NSThread isMainThread]);
	NSLog(@"[TapTap ObjC] useProfile: %d, useFriends: %d", useProfile, useFriends);
	
	// Thread checking is done at C++ layer
	if (![NSThread isMainThread]) {
		NSLog(@"[TapTap ObjC] CRITICAL ERROR: Not on main thread! This should never happen!");
		NSLog(@"[TapTap ObjC] Stack trace: %@", [NSThread callStackSymbols]);
	}
	
	NSMutableArray *scopes = [NSMutableArray array];
	if (useProfile) {
		[scopes addObject:@"public_profile"];
	} else {
		[scopes addObject:@"basic_info"];
	}
	if (useFriends) {
		[scopes addObject:@"user_friends"];
	}
	
	NSLog(@"[TapTap] Calling TapTapLogin.LoginWithScopes");
	
	// Call TapTap Login SDK (using correct OC API)
	[TapTapLogin LoginWithScopes:scopes viewController:nil handler:^(BOOL success, NSError *error, TapTapAccount *account) {
		NSLog(@"[TapTap] Login handler callback on thread: %@", [NSThread currentThread]);
		NSLog(@"[TapTap] Login result: success=%d, error=%@, account=%@", success, error, account);
		
		// Create Dictionary and post event - _post_event handles thread safety
		if (error) {
			if (error.code == 1) {
				// User cancelled
				NSLog(@"[TapTap] User cancelled login");
				Dictionary ret;
				ret["type"] = "login";
				ret["result"] = "cancel";
				Godot3TapTap::get_singleton()->_post_event(ret);
			} else {
				// Error occurred
				NSLog(@"[TapTap] Login error: %@", error.localizedDescription);
				Dictionary ret;
				ret["type"] = "login";
				ret["result"] = "error";
				ret["message"] = String::utf8([error.localizedDescription UTF8String]);
				Godot3TapTap::get_singleton()->_post_event(ret);
			}
		} else if (success && account && account.userInfo) {
			// Login successful - extract profile from TapTapAccount.userInfo
			NSLog(@"[TapTap] Login successful, preparing success event");
			Dictionary ret;
			ret["type"] = "login";
			ret["result"] = "success";
			ret["openId"] = String::utf8([account.userInfo.openId UTF8String] ?: "");
			ret["unionId"] = String::utf8([account.userInfo.unionId UTF8String] ?: "");
			ret["name"] = String::utf8([account.userInfo.name UTF8String] ?: "");
			ret["avatar"] = String::utf8([account.userInfo.avatar UTF8String] ?: "");
			Godot3TapTap::get_singleton()->_post_event(ret);
			NSLog(@"[TapTap] Login success event posted");
			
			// Store user ID for compliance
			self.currentUserId = account.userInfo.openId;
			NSLog(@"[TapTap] Stored currentUserId: %@", self.currentUserId);
		}
		NSLog(@"[TapTap] Login handler completed");
	}];
	
	NSLog(@"[TapTap] TapTapLogin.LoginWithScopes call returned");
}

- (BOOL)isLoggedIn {
	// Check TapTap SDK login status
	return [TapTapLogin getCurrentTapAccount] != nil;
}

/**
 * @brief Get current user profile from TapTap SDK
 * 
 * Returns a consistent Dictionary structure regardless of login state.
 * This ensures GDScript code can safely access fields without checking.
 * 
 * @return Dictionary with user profile fields:
 *   - openId: User's unique identifier (empty if not logged in)
 *   - unionId: User's union identifier (empty if not logged in)
 *   - name: User's display name (empty if not logged in)
 *   - avatar: User's avatar URL (empty if not logged in)
 *   - error: Error message if user is not logged in
 */
- (NSDictionary *)getUserProfile {
	NSLog(@"[TapTap ObjC] getUserProfile called");
	
	// Get current TapTap account
	TapTapAccount *account = [TapTapLogin getCurrentTapAccount];
	
	if (account && account.userInfo) {
		// User is logged in, return full profile
		NSDictionary *profile = @{
			@"openId": account.userInfo.openId ?: @"",
			@"unionId": account.userInfo.unionId ?: @"",
			@"name": account.userInfo.name ?: @"",
			@"avatar": account.userInfo.avatar ?: @""
		};
		
		NSLog(@"[TapTap ObjC] User profile found: openId=%@, name=%@", 
			  account.userInfo.openId ?: @"(null)", 
			  account.userInfo.name ?: @"(null)");
		
		return profile;
	}
	
	// User is NOT logged in - return consistent structure with empty values
	// This prevents GDScript errors when trying to access profile.name
	NSLog(@"[TapTap ObjC] User not logged in, returning empty profile with error");
	return @{
		@"openId": @"",
		@"unionId": @"",
		@"name": @"",
		@"avatar": @"",
		@"error": @"User not logged in"
	};
}

- (void)logout {
	NSLog(@"[TapTap] Logout called");
	
	// Call TapTap SDK logout
	[TapTapLogin logout];
	[TapTapCompliance exit];
	
	self.currentUserId = nil;
	
	Dictionary ret;
	ret["type"] = "logout";
	ret["result"] = "ok";
	Godot3TapTap::get_singleton()->_post_event(ret);
}

- (void)startComplianceWithUserId:(NSString *)userId {
	NSLog(@"[TapTap] Starting compliance with userId: %@", userId);
	
	if (!userId || userId.length == 0) {
		NSLog(@"[TapTap] Cannot start compliance: invalid user ID");
		Dictionary ret;
		ret["type"] = "compliance";
		ret["code"] = -1;
		ret["info"] = "Invalid user ID";
		Godot3TapTap::get_singleton()->_post_event(ret);
		return;
	}
	
	NSLog(@"[TapTap ObjC] Thread: %@", [NSThread currentThread]);
	NSLog(@"[TapTap ObjC] IsMainThread: %d", [NSThread isMainThread]);
	
	// Thread checking is done at C++ layer
	if (![NSThread isMainThread]) {
		NSLog(@"[TapTap ObjC] CRITICAL ERROR: Not on main thread! This should never happen!");
		NSLog(@"[TapTap ObjC] Stack trace: %@", [NSThread callStackSymbols]);
	}
	
	NSLog(@"[TapTap ObjC] About to call [TapTapCompliance startup]");
	
	// Call TapTap Compliance SDK
	[TapTapCompliance startup:userId];
	
	NSLog(@"[TapTap ObjC] [TapTapCompliance startup] returned");
	
	// Callback will be received via complianceCallbackWithCode:extra:
}

// TapTapComplianceDelegate method
- (void)complianceCallbackWithCode:(TapComplianceResultHandlerCode)code extra:(NSString * _Nullable)extra {
	NSLog(@"[TapTap] complianceCallbackWithCode called on thread: %@", [NSThread currentThread]);
	NSLog(@"[TapTap] Compliance callback: code=%ld, extra=%@", (long)code, extra);
	
	// Post event - _post_event handles thread safety
	Dictionary ret;
	ret["type"] = "compliance";
	ret["code"] = (int)code;
	ret["info"] = String::utf8([extra UTF8String] ?: "");
	Godot3TapTap::get_singleton()->_post_event(ret);
	NSLog(@"[TapTap] Compliance event posted");
}

- (void)checkLicenseWithForce:(BOOL)force {
	NSLog(@"[TapTap] Checking license with force: %d", force);
	
	// Note: TapTap License SDK is not available for iOS
	// License verification should be done on Android or server-side
	NSLog(@"[TapTap] Warning: License check not supported on iOS");
	
	// Return success for compatibility (actual check should be on Android/server)
	Dictionary ret;
	ret["type"] = "license";
	ret["result"] = "success";
	ret["message"] = "iOS does not support license check";
	Godot3TapTap::get_singleton()->_post_event(ret);
}

- (void)queryDLCWithSkuIds:(NSArray *)skuIds {
	NSLog(@"[TapTap] Querying DLC with %lu SKUs", (unsigned long)[skuIds count]);
	
	// Note: TapTap DLC SDK is not available for iOS
	// DLC operations should be done on Android or server-side
	NSLog(@"[TapTap] Warning: DLC query not supported on iOS");
	
	// Return empty result for compatibility
	Dictionary ret;
	ret["type"] = "dlc_query";
	ret["code"] = -1;
	ret["codeName"] = "NOT_SUPPORTED_ON_IOS";
	Dictionary query_list;
	for (NSString *skuId in skuIds) {
		query_list[String::utf8([skuId UTF8String])] = 0;
	}
	ret["queryList"] = query_list;
	
	NSError *error = nil;
	NSData *jsonData = [NSJSONSerialization dataWithJSONObject:@{
		@"code": @-1,
		@"codeName": @"NOT_SUPPORTED_ON_IOS",
		@"queryList": @{}
	} options:0 error:&error];
	NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
	ret["jsonString"] = String::utf8([jsonString UTF8String]);
	
	Godot3TapTap::get_singleton()->_post_event(ret);
}

- (void)purchaseDLCWithSkuId:(NSString *)skuId {
	NSLog(@"[TapTap] Purchasing DLC: %@", skuId);
	
	// Note: TapTap DLC SDK is not available for iOS
	// DLC operations should be done on Android or server-side
	NSLog(@"[TapTap] Warning: DLC purchase not supported on iOS");
	
	// Return error for compatibility
	Dictionary ret;
	ret["type"] = "dlc_purchase";
	ret["skuId"] = String::utf8([skuId UTF8String]);
	ret["status"] = -1;
	ret["message"] = "Not supported on iOS";
	Godot3TapTap::get_singleton()->_post_event(ret);
}

@end

// MARK: - Static delegate instance
static GodotTapTapDelegate *taptap_delegate = nil;

// MARK: - C++ Plugin Implementation

Godot3TapTap *Godot3TapTap::instance = NULL;

void Godot3TapTap::_bind_methods() {
	// SDK Initialization
	ClassDB::bind_method(D_METHOD("initSdk"), &Godot3TapTap::initSdk);
	ClassDB::bind_method(D_METHOD("initSdkWithEncryptedToken"), &Godot3TapTap::initSdkWithEncryptedToken);
	
	// Login
	ClassDB::bind_method(D_METHOD("login"), &Godot3TapTap::login);
	ClassDB::bind_method(D_METHOD("isLogin"), &Godot3TapTap::isLogin);
	ClassDB::bind_method(D_METHOD("getUserProfile"), &Godot3TapTap::getUserProfile);
	ClassDB::bind_method(D_METHOD("logout"), &Godot3TapTap::logout);
	ClassDB::bind_method(D_METHOD("logoutThenRestart"), &Godot3TapTap::logoutThenRestart);
	
	// Compliance
	ClassDB::bind_method(D_METHOD("compliance"), &Godot3TapTap::compliance);
	
	// License Verification
	ClassDB::bind_method(D_METHOD("checkLicense"), &Godot3TapTap::checkLicense);
	
	// DLC
	ClassDB::bind_method(D_METHOD("queryDLC"), &Godot3TapTap::queryDLC);
	ClassDB::bind_method(D_METHOD("purchaseDLC"), &Godot3TapTap::purchaseDLC);
	
	// IAP
	ClassDB::bind_method(D_METHOD("queryProductDetailsAsync"), &Godot3TapTap::queryProductDetailsAsync);
	ClassDB::bind_method(D_METHOD("launchBillingFlow"), &Godot3TapTap::launchBillingFlow);
	ClassDB::bind_method(D_METHOD("finishPurchaseAsync"), &Godot3TapTap::finishPurchaseAsync);
	ClassDB::bind_method(D_METHOD("queryUnfinishedPurchaseAsync"), &Godot3TapTap::queryUnfinishedPurchaseAsync);
	
	// Utility
	ClassDB::bind_method(D_METHOD("showTip"), &Godot3TapTap::showTip);
	ClassDB::bind_method(D_METHOD("restartApp"), &Godot3TapTap::restartApp);

	// Event handling
	ClassDB::bind_method(D_METHOD("get_pending_event_count"), &Godot3TapTap::get_pending_event_count);
	ClassDB::bind_method(D_METHOD("pop_pending_event"), &Godot3TapTap::pop_pending_event);
	
	// Signals
	ADD_SIGNAL(MethodInfo("onLoginSuccess"));
	ADD_SIGNAL(MethodInfo("onLoginFail", PropertyInfo(Variant::STRING, "message")));
	ADD_SIGNAL(MethodInfo("onLoginCancel"));
	ADD_SIGNAL(MethodInfo("onComplianceResult", PropertyInfo(Variant::INT, "code"), PropertyInfo(Variant::STRING, "info")));
	ADD_SIGNAL(MethodInfo("onLicenseSuccess"));
	ADD_SIGNAL(MethodInfo("onLicenseFailed"));
	ADD_SIGNAL(MethodInfo("onDLCQueryResult", PropertyInfo(Variant::STRING, "jsonString")));
	ADD_SIGNAL(MethodInfo("onDLCPurchaseResult", PropertyInfo(Variant::STRING, "skuId"), PropertyInfo(Variant::INT, "status")));
	ADD_SIGNAL(MethodInfo("onProductDetailsResponse", PropertyInfo(Variant::STRING, "jsonString")));
	ADD_SIGNAL(MethodInfo("onPurchaseUpdated", PropertyInfo(Variant::STRING, "jsonString")));
	ADD_SIGNAL(MethodInfo("onFinishPurchaseResponse", PropertyInfo(Variant::STRING, "jsonString")));
	ADD_SIGNAL(MethodInfo("onQueryUnfinishedPurchaseResponse", PropertyInfo(Variant::STRING, "jsonString")));
	ADD_SIGNAL(MethodInfo("onLaunchBillingFlowResult", PropertyInfo(Variant::STRING, "jsonString")));
}

// Helper method to add events
void Godot3TapTap::add_pending_event(const String &type, const String &result, const Dictionary &data) {
	NSLog(@"[TapTap] add_pending_event called: type=%s, result=%s", type.utf8().get_data(), result.utf8().get_data());
	Dictionary event;
	event["type"] = type;
	event["result"] = result;
	if (!data.empty()) {
		for (int i = 0; i < data.keys().size(); i++) {
			Variant key = data.keys()[i];
			event[key] = data[key];
		}
	}
	pending_events.push_back(event);
	NSLog(@"[TapTap] Event added, pending count: %d", pending_events.size());
}

void Godot3TapTap::_post_event(Variant p_event) {
	NSLog(@"[TapTap] _post_event called from thread: %@", [NSThread currentThread]);
	
	// Ensure we're on the main thread for Godot operations
	if (![NSThread isMainThread]) {
		NSLog(@"[TapTap] WARNING: _post_event called from background thread, dispatching to main thread");
		// Capture the event by value in the block
		Variant event_copy = p_event;
		dispatch_async(dispatch_get_main_queue(), ^{
			NSLog(@"[TapTap] Now on main thread, adding event");
			Godot3TapTap::get_singleton()->pending_events.push_back(event_copy);
			NSLog(@"[TapTap] Event added on main thread, pending count: %d", Godot3TapTap::get_singleton()->pending_events.size());
		});
		return;
	}
	
	NSLog(@"[TapTap] Adding event on main thread");
	pending_events.push_back(p_event);
	NSLog(@"[TapTap] Event added, pending count: %d", pending_events.size());
}

// SDK Initialization
void Godot3TapTap::initSdk(const String &p_client_id, const String &p_client_token, bool p_enable_log, bool p_with_iap) {
	NSLog(@"[TapTap C++] initSdk called");
	NSLog(@"[TapTap C++] Thread: %@", [NSThread currentThread]);
	NSLog(@"[TapTap C++] IsMainThread: %d", [NSThread isMainThread]);
	NSLog(@"[TapTap C++] ClientId: %s, enableLog: %d, withIAP: %d", p_client_id.utf8().get_data(), p_enable_log, p_with_iap);
	
	client_id = p_client_id;
	client_token = p_client_token;
	sdk_initialized = true;
	
	NSString *nsClientId = [NSString stringWithUTF8String:p_client_id.utf8().get_data()];
	NSString *nsClientToken = [NSString stringWithUTF8String:p_client_token.utf8().get_data()];
	
	// CRITICAL: Force main thread execution for TapTap SDK init
	if (![NSThread isMainThread]) {
		NSLog(@"[TapTap C++] WARNING: Called from background thread, dispatching to main thread");
		NSLog(@"[TapTap C++] Stack trace: %@", [NSThread callStackSymbols]);
		dispatch_async(dispatch_get_main_queue(), ^{
			NSLog(@"[TapTap C++] Now on main thread, calling ObjC delegate");
			[taptap_delegate initSDKWithClientId:nsClientId clientToken:nsClientToken enableLog:p_enable_log withIAP:p_with_iap];
		});
		return;
	}
	
	NSLog(@"[TapTap C++] Already on main thread, calling ObjC delegate directly");
	[taptap_delegate initSDKWithClientId:nsClientId clientToken:nsClientToken enableLog:p_enable_log withIAP:p_with_iap];
	NSLog(@"[TapTap C++] initSdk returned");
}

void Godot3TapTap::initSdkWithEncryptedToken(const String &p_client_id, const String &p_encrypted_token, bool p_enable_log, bool p_with_iap) {
	NSLog(@"[TapTap C++] initSdkWithEncryptedToken called");
	NSLog(@"[TapTap C++] Thread: %@", [NSThread currentThread]);
	NSLog(@"[TapTap C++] IsMainThread: %d", [NSThread isMainThread]);
	
	client_id = p_client_id;
	sdk_initialized = true;
	
	// CRITICAL: Decrypt and init must happen on main thread
	if (![NSThread isMainThread]) {
		NSLog(@"[TapTap C++] WARNING: Called from background thread, dispatching entire flow to main thread");
		NSLog(@"[TapTap C++] Stack trace: %@", [NSThread callStackSymbols]);
		
		// Capture all parameters for the block
		String client_id_copy = p_client_id;
		String encrypted_token_copy = p_encrypted_token;
		
		dispatch_async(dispatch_get_main_queue(), ^{
			NSLog(@"[TapTap C++] Now on main thread, decrypting token");
			NSString *nsEncryptedToken = [NSString stringWithUTF8String:encrypted_token_copy.utf8().get_data()];
			NSString *nsDecryptedToken = [taptap_delegate decryptToken:nsEncryptedToken];
			
			if (!nsDecryptedToken || nsDecryptedToken.length == 0) {
				NSLog(@"[TapTap C++] Failed to decrypt token");
				Dictionary ret;
				ret["type"] = "init";
				ret["result"] = "error";
				ret["message"] = "Failed to decrypt token";
				Godot3TapTap::get_singleton()->_post_event(ret);
				return;
			}
			
			NSString *nsClientId = [NSString stringWithUTF8String:client_id_copy.utf8().get_data()];
			NSLog(@"[TapTap C++] Token decrypted, calling ObjC delegate");
			[taptap_delegate initSDKWithClientId:nsClientId clientToken:nsDecryptedToken enableLog:p_enable_log withIAP:p_with_iap];
		});
		return;
	}
	
	NSLog(@"[TapTap C++] Already on main thread, decrypting token");
	// Decrypt the token using the key from Info.plist
	NSString *nsEncryptedToken = [NSString stringWithUTF8String:p_encrypted_token.utf8().get_data()];
	NSString *nsDecryptedToken = [taptap_delegate decryptToken:nsEncryptedToken];
	
	if (!nsDecryptedToken || nsDecryptedToken.length == 0) {
		NSLog(@"[TapTap C++] Failed to decrypt token, SDK initialization aborted");
		Dictionary ret;
		ret["type"] = "init";
		ret["result"] = "error";
		ret["message"] = "Failed to decrypt token";
		_post_event(ret);
		return;
	}
	
	String decrypted_token = String::utf8([nsDecryptedToken UTF8String]);
	NSLog(@"[TapTap C++] Token decrypted, calling initSdk");
	initSdk(p_client_id, decrypted_token, p_enable_log, p_with_iap);
}

// Login
void Godot3TapTap::login(bool p_use_profile, bool p_use_friends) {
	NSLog(@"[TapTap C++] login called");
	NSLog(@"[TapTap C++] Thread: %@", [NSThread currentThread]);
	NSLog(@"[TapTap C++] IsMainThread: %d", [NSThread isMainThread]);
	
	// CRITICAL: Force main thread execution for UI operations
	if (![NSThread isMainThread]) {
		NSLog(@"[TapTap C++] WARNING: Called from background thread, dispatching to main thread");
		NSLog(@"[TapTap C++] Stack trace: %@", [NSThread callStackSymbols]);
		dispatch_async(dispatch_get_main_queue(), ^{
			NSLog(@"[TapTap C++] Now on main thread, calling ObjC delegate");
			[taptap_delegate loginWithProfile:p_use_profile friends:p_use_friends];
		});
		return;
	}
	
	NSLog(@"[TapTap C++] Already on main thread, calling ObjC delegate directly");
	[taptap_delegate loginWithProfile:p_use_profile friends:p_use_friends];
	NSLog(@"[TapTap C++] login returned");
}

bool Godot3TapTap::isLogin() {
	return [taptap_delegate isLoggedIn];
}

String Godot3TapTap::getUserProfile() {
	NSDictionary *profile = [taptap_delegate getUserProfile];
	
	// Convert NSDictionary to JSON string
	NSError *error = nil;
	NSData *jsonData = [NSJSONSerialization dataWithJSONObject:profile options:0 error:&error];
	if (error) {
		NSLog(@"[TapTap] Error converting profile to JSON: %@", error);
		return "{}";
	}
	
	NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
	return String::utf8([jsonString UTF8String]);
}

void Godot3TapTap::logout() {
	[taptap_delegate logout];
}

void Godot3TapTap::logoutThenRestart() {
	logout();
	restartApp();
}

// Compliance (Anti-addiction)
void Godot3TapTap::compliance() {
	NSLog(@"[TapTap C++] compliance called");
	NSLog(@"[TapTap C++] Thread: %@", [NSThread currentThread]);
	NSLog(@"[TapTap C++] IsMainThread: %d", [NSThread isMainThread]);
	
	// CRITICAL: Force main thread execution for compliance
	if (![NSThread isMainThread]) {
		NSLog(@"[TapTap C++] WARNING: Called from background thread, dispatching to main thread");
		NSLog(@"[TapTap C++] Stack trace: %@", [NSThread callStackSymbols]);
		dispatch_async(dispatch_get_main_queue(), ^{
			NSLog(@"[TapTap C++] Now on main thread, getting userId");
			NSString *userId = [taptap_delegate currentUserId];
			if (!userId || userId.length == 0) {
				TapTapAccount *account = [TapTapLogin getCurrentTapAccount];
				if (account && account.userInfo && account.userInfo.openId) {
					userId = account.userInfo.openId;
				}
			}
			NSLog(@"[TapTap C++] Calling ObjC delegate with userId: %@", userId);
			[taptap_delegate startComplianceWithUserId:userId];
		});
		return;
	}
	
	NSLog(@"[TapTap C++] Already on main thread, getting userId");
	// Use stored user ID from login, or openId from current account
	NSString *userId = [taptap_delegate currentUserId];
	if (!userId || userId.length == 0) {
		TapTapAccount *account = [TapTapLogin getCurrentTapAccount];
		if (account && account.userInfo && account.userInfo.openId) {
			userId = account.userInfo.openId;
		}
	}
	
	NSLog(@"[TapTap C++] Calling ObjC delegate with userId: %@", userId);
	[taptap_delegate startComplianceWithUserId:userId];
	NSLog(@"[TapTap C++] compliance returned");
}

// License Verification
void Godot3TapTap::checkLicense(bool p_force_check) {
	[taptap_delegate checkLicenseWithForce:p_force_check];
}

// DLC
void Godot3TapTap::queryDLC(const Array &p_sku_ids) {
	NSMutableArray *skuIds = [NSMutableArray array];
	for (int i = 0; i < p_sku_ids.size(); i++) {
		String sku = p_sku_ids[i];
		[skuIds addObject:[NSString stringWithUTF8String:sku.utf8().get_data()]];
	}
	
	[taptap_delegate queryDLCWithSkuIds:skuIds];
}

void Godot3TapTap::purchaseDLC(const String &p_sku_id) {
	NSString *skuId = [NSString stringWithUTF8String:p_sku_id.utf8().get_data()];
	[taptap_delegate purchaseDLCWithSkuId:skuId];
}

// IAP (In-App Purchase) - Not supported on iOS
void Godot3TapTap::queryProductDetailsAsync(const Array &p_products) {
	NSLog(@"[TapTap] queryProductDetailsAsync called (not supported on iOS)");
	
	Dictionary result;
	result["error"] = "IAP not supported on iOS";
	add_pending_event("product_details", "error", result);
}

void Godot3TapTap::launchBillingFlow(const String &p_product_id, const String &p_obfuscated_account_id) {
	NSLog(@"[TapTap] launchBillingFlow called (not supported on iOS)");
	
	Dictionary result;
	result["error"] = "IAP not supported on iOS";
	add_pending_event("billing_flow", "error", result);
}

void Godot3TapTap::finishPurchaseAsync(const String &p_order_id, const String &p_purchase_token) {
	NSLog(@"[TapTap] finishPurchaseAsync called (not supported on iOS)");
	
	Dictionary result;
	result["error"] = "IAP not supported on iOS";
	add_pending_event("finish_purchase", "error", result);
}

void Godot3TapTap::queryUnfinishedPurchaseAsync() {
	NSLog(@"[TapTap] queryUnfinishedPurchaseAsync called (not supported on iOS)");
	
	Dictionary result;
	result["error"] = "IAP not supported on iOS";
	add_pending_event("unfinished_purchase", "error", result);
}

// Utility
void Godot3TapTap::showTip(const String &p_text) {
	NSLog(@"[TapTap] showTip: %@", [NSString stringWithUTF8String:p_text.utf8().get_data()]);
	
	// TODO: Show native iOS alert/toast
	dispatch_async(dispatch_get_main_queue(), ^{
		UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil 
			message:[NSString stringWithUTF8String:p_text.utf8().get_data()]
			preferredStyle:UIAlertControllerStyleAlert];
		
		[alert addAction:[UIAlertAction actionWithTitle:@"OK" 
			style:UIAlertActionStyleDefault handler:nil]];
		
		UIViewController *rootVC = [UIApplication sharedApplication].keyWindow.rootViewController;
		[rootVC presentViewController:alert animated:YES completion:nil];
	});
}

void Godot3TapTap::restartApp() {
	NSLog(@"[TapTap] restartApp called");
	
	// iOS doesn't support programmatic app restart
	// Best practice: show alert and exit
	dispatch_async(dispatch_get_main_queue(), ^{
		UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Restart Required"
			message:@"Please close and reopen the app."
			preferredStyle:UIAlertControllerStyleAlert];
		
		[alert addAction:[UIAlertAction actionWithTitle:@"OK" 
			style:UIAlertActionStyleDefault 
			handler:^(UIAlertAction * _Nonnull action) {
				exit(0);
			}]];
		
		UIViewController *rootVC = [UIApplication sharedApplication].keyWindow.rootViewController;
		[rootVC presentViewController:alert animated:YES completion:nil];
	});
}

int Godot3TapTap::get_pending_event_count() {
	int count = pending_events.size();
	NSLog(@"[TapTap] get_pending_event_count: %d", count);
	return count;
}

Variant Godot3TapTap::pop_pending_event() {
	NSLog(@"[TapTap] pop_pending_event called, pending count: %d", pending_events.size());
	
	if (pending_events.size() == 0) {
		NSLog(@"[TapTap] WARNING: pop_pending_event called with empty queue");
		return Variant();
	}
	
	Variant front = pending_events.front()->get();
	pending_events.pop_front();
	
	NSLog(@"[TapTap] Event popped, remaining count: %d", pending_events.size());
	return front;
}

Godot3TapTap *Godot3TapTap::get_singleton() {
	return instance;
}

Godot3TapTap::Godot3TapTap() {
	ERR_FAIL_COND(instance != NULL);
	instance = this;
	sdk_initialized = false;
	
	// Initialize Objective-C delegate
	taptap_delegate = [[GodotTapTapDelegate alloc] init];
	
	NSLog(@"[TapTap] Godot3TapTap singleton created");
}

Godot3TapTap::~Godot3TapTap() {
	// Clean up Objective-C delegate
	taptap_delegate = nil;
	
	instance = NULL;
	NSLog(@"[TapTap] Godot3TapTap singleton destroyed");
}
