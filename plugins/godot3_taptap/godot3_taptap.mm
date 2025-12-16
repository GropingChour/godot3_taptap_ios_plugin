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

// TapTap SDK Headers
#import <TapTapLoginSDK/TapTapLoginSDK.h>
#import <TapTapComplianceSDK/TapTapComplianceSDK.h>
#import <TapTapCoreSDK/TapTapCoreSDK.h>

#if VERSION_MAJOR == 4
typedef PackedStringArray GodotStringArray;
#else
typedef PoolStringArray GodotStringArray;
#endif

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
	
	for (NSUInteger i = 0; i < encryptedData.length; i++) {
		decBytes[i] = encBytes[i] ^ keyBytes[i % keyData.length];
	}
	
	NSString *decryptedToken = [[NSString alloc] initWithData:decryptedData encoding:NSUTF8StringEncoding];
	
	if (!decryptedToken) {
		NSLog(@"[TapTap] Failed to decrypt token");
		return @"";
	}
	
	NSLog(@"[TapTap] Token decrypted successfully");
	return decryptedToken;
}

- (void)initSDKWithClientId:(NSString *)clientId clientToken:(NSString *)clientToken enableLog:(BOOL)enableLog withIAP:(BOOL)withIAP {
	_clientId = clientId;
	_clientToken = clientToken;
	
	NSLog(@"[TapTap] Initializing SDK with clientId: %@, enableLog: %d, withIAP: %d", clientId, enableLog, withIAP);
	
	// Initialize TapTap SDK
	TapTapSdkOptions *options = [[TapTapSdkOptions alloc] init];
	options.clientId = clientId;
	options.clientToken = clientToken;
	options.region = TapTapRegionTypeCN;
	options.enableLog = enableLog;
	
	[TapTapSDK initWithOptions:options];
	
	_sdkInitialized = YES;
	
	// Post init success event
	Dictionary ret;
	ret["type"] = "init";
	ret["result"] = "ok";
	Godot3TapTap::get_singleton()->_post_event(ret);
}

- (void)loginWithProfile:(BOOL)useProfile friends:(BOOL)useFriends {
	NSLog(@"[TapTap] Login called with useProfile: %d, useFriends: %d", useProfile, useFriends);
	
	NSMutableArray *scopes = [NSMutableArray array];
	if (useProfile) {
		[scopes addObject:@"public_profile"];
	} else {
		[scopes addObject:@"basic_info"];
	}
	if (useFriends) {
		[scopes addObject:@"user_friends"];
	}
	
	// Call TapTap Login SDK (using correct OC API)
	[TapTapLogin LoginWithScopes:scopes viewController:nil handler:^(BOOL success, NSError *error, TapTapAccount *account) {
		if (error) {
			if (error.code == 1) {
				// User cancelled
				Dictionary ret;
				ret["type"] = "login";
				ret["result"] = "cancel";
				Godot3TapTap::get_singleton()->_post_event(ret);
			} else {
				// Error occurred
				Dictionary ret;
				ret["type"] = "login";
				ret["result"] = "error";
				ret["message"] = String::utf8([error.localizedDescription UTF8String]);
				Godot3TapTap::get_singleton()->_post_event(ret);
			}
		} else if (success && account) {
			// Login successful - extract profile from TapTapAccount
			Dictionary ret;
			ret["type"] = "login";
			ret["result"] = "success";
			ret["openId"] = String::utf8([account.openid UTF8String] ?: "");
			ret["unionId"] = String::utf8([account.unionid UTF8String] ?: "");
			ret["name"] = String::utf8([account.name UTF8String] ?: "");
			ret["avatar"] = String::utf8([account.avatar UTF8String] ?: "");
			Godot3TapTap::get_singleton()->_post_event(ret);
			
			// Store user ID for compliance
			self.currentUserId = account.openid;
		}
	}];
}

- (BOOL)isLoggedIn {
	// Check TapTap SDK login status
	return [TapTapLogin getCurrentTapAccount] != nil;
}

- (NSDictionary *)getUserProfile {
	// Get user profile from TapTap SDK
	TapTapAccount *account = [TapTapLogin getCurrentTapAccount];
	if (account) {
		return @{
			@"openId": account.openid ?: @"",
			@"unionId": account.unionid ?: @"",
			@"name": account.name ?: @"",
			@"avatar": account.avatar ?: @""
		};
	}
	return @{};
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
	
	// Call TapTap Compliance SDK
	[TapTapCompliance startup:userId];
	
	// Callback will be received via complianceCallbackWithCode:extra:
}

// TapTapComplianceDelegate method
- (void)complianceCallbackWithCode:(TapComplianceResultHandlerCode)code extra:(NSString * _Nullable)extra {
	NSLog(@"[TapTap] Compliance callback: code=%ld, extra=%@", (long)code, extra);
	
	Dictionary ret;
	ret["type"] = "compliance";
	ret["code"] = (int)code;
	ret["info"] = String::utf8([extra UTF8String] ?: "");
	Godot3TapTap::get_singleton()->_post_event(ret);
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
}

void Godot3TapTap::_post_event(Variant p_event) {
	pending_events.push_back(p_event);
}

// SDK Initialization
void Godot3TapTap::initSdk(const String &p_client_id, const String &p_client_token, bool p_enable_log, bool p_with_iap) {
	client_id = p_client_id;
	client_token = p_client_token;
	sdk_initialized = true;
	
	NSString *nsClientId = [NSString stringWithUTF8String:p_client_id.utf8().get_data()];
	NSString *nsClientToken = [NSString stringWithUTF8String:p_client_token.utf8().get_data()];
	
	[taptap_delegate initSDKWithClientId:nsClientId clientToken:nsClientToken enableLog:p_enable_log withIAP:p_with_iap];
}

void Godot3TapTap::initSdkWithEncryptedToken(const String &p_client_id, const String &p_encrypted_token, bool p_enable_log, bool p_with_iap) {
	client_id = p_client_id;
	sdk_initialized = true;
	
	// Decrypt the token using the key from Info.plist
	NSString *nsEncryptedToken = [NSString stringWithUTF8String:p_encrypted_token.utf8().get_data()];
	NSString *nsDecryptedToken = [taptap_delegate decryptToken:nsEncryptedToken];
	
	if (!nsDecryptedToken || nsDecryptedToken.length == 0) {
		NSLog(@"[TapTap] Failed to decrypt token, SDK initialization aborted");
		Dictionary ret;
		ret["type"] = "init";
		ret["result"] = "error";
		ret["message"] = "Failed to decrypt token";
		_post_event(ret);
		return;
	}
	
	String decrypted_token = String::utf8([nsDecryptedToken UTF8String]);
	initSdk(p_client_id, decrypted_token, p_enable_log, p_with_iap);
}

// Login
void Godot3TapTap::login(bool p_use_profile, bool p_use_friends) {
	[taptap_delegate loginWithProfile:p_use_profile friends:p_use_friends];
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
	// Use stored user ID from login, or openid from current account
	NSString *userId = [taptap_delegate currentUserId];
	if (!userId || userId.length == 0) {
		TapTapAccount *account = [TapTapLogin getCurrentTapAccount];
		if (account && account.openid) {
			userId = account.openid;
		}
	}
	
	[taptap_delegate startComplianceWithUserId:userId];
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
	return pending_events.size();
}

Variant Godot3TapTap::pop_pending_event() {
	Variant front = pending_events.front()->get();
	pending_events.pop_front();
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
