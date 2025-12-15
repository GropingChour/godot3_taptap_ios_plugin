/*************************************************************************/
/*  taptap_login.mm                                                      */
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
/* CLAIM, DAMAGES OR OTHER HOLDERS BE LIABLE FOR ANY  */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,  */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE     */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                */
/*************************************************************************/

#include "taptap_login.h"

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

#if VERSION_MAJOR == 4
typedef PackedStringArray GodotStringArray;
#else
typedef PoolStringArray GodotStringArray;
#endif

TapTapLogin *TapTapLogin::instance = NULL;

void TapTapLogin::_bind_methods() {
	// SDK Initialization
	ClassDB::bind_method(D_METHOD("initSdk"), &TapTapLogin::initSdk);
	ClassDB::bind_method(D_METHOD("initSdkWithEncryptedToken"), &TapTapLogin::initSdkWithEncryptedToken);
	
	// Login
	ClassDB::bind_method(D_METHOD("login"), &TapTapLogin::login);
	ClassDB::bind_method(D_METHOD("isLogin"), &TapTapLogin::isLogin);
	ClassDB::bind_method(D_METHOD("getUserProfile"), &TapTapLogin::getUserProfile);
	ClassDB::bind_method(D_METHOD("logout"), &TapTapLogin::logout);
	ClassDB::bind_method(D_METHOD("logoutThenRestart"), &TapTapLogin::logoutThenRestart);
	
	// Compliance
	ClassDB::bind_method(D_METHOD("compliance"), &TapTapLogin::compliance);
	
	// License Verification
	ClassDB::bind_method(D_METHOD("checkLicense"), &TapTapLogin::checkLicense);
	
	// DLC
	ClassDB::bind_method(D_METHOD("queryDLC"), &TapTapLogin::queryDLC);
	ClassDB::bind_method(D_METHOD("purchaseDLC"), &TapTapLogin::purchaseDLC);
	
	// IAP
	ClassDB::bind_method(D_METHOD("queryProductDetailsAsync"), &TapTapLogin::queryProductDetailsAsync);
	ClassDB::bind_method(D_METHOD("launchBillingFlow"), &TapTapLogin::launchBillingFlow);
	ClassDB::bind_method(D_METHOD("finishPurchaseAsync"), &TapTapLogin::finishPurchaseAsync);
	ClassDB::bind_method(D_METHOD("queryUnfinishedPurchaseAsync"), &TapTapLogin::queryUnfinishedPurchaseAsync);
	
	// Utility
	ClassDB::bind_method(D_METHOD("showTip"), &TapTapLogin::showTip);
	ClassDB::bind_method(D_METHOD("restartApp"), &TapTapLogin::restartApp);

	// Event handling
	ClassDB::bind_method(D_METHOD("get_pending_event_count"), &TapTapLogin::get_pending_event_count);
	ClassDB::bind_method(D_METHOD("pop_pending_event"), &TapTapLogin::pop_pending_event);
	
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
void TapTapLogin::add_pending_event(const String &type, const String &result, const Dictionary &data) {
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

// SDK Initialization
void TapTapLogin::initSdk(const String &p_client_id, const String &p_client_token, bool p_enable_log, bool p_with_iap) {
	client_id = p_client_id;
	client_token = p_client_token;
	sdk_initialized = true;
	
	NSLog(@"[TapTap] initSdk called with clientId: %@, enableLog: %d, withIAP: %d", 
		[NSString stringWithUTF8String:p_client_id.utf8().get_data()], p_enable_log, p_with_iap);
	
	// TODO: Initialize real TapTap SDK here
	// [TapTapSDK initWithConfig:config];
	
	Dictionary ret_data;
	add_pending_event("init", "ok", ret_data);
}

void TapTapLogin::initSdkWithEncryptedToken(const String &p_client_id, const String &p_encrypted_token, bool p_enable_log, bool p_with_iap) {
	client_id = p_client_id;
	sdk_initialized = true;
	
	NSLog(@"[TapTap] initSdkWithEncryptedToken called with clientId: %@", [NSString stringWithUTF8String:p_client_id.utf8().get_data()]);
	
	// TODO: Decrypt token and initialize SDK
	// String decrypted_token = decrypt(p_encrypted_token);
	// [TapTapSDK initWithConfig:config];
	
	Dictionary ret_data;
	add_pending_event("init", "ok", ret_data);
}

// Login
void TapTapLogin::login(bool p_use_profile, bool p_use_friends) {
	NSLog(@"[TapTap] login called with useProfile: %d, useFriends: %d", p_use_profile, p_use_friends);
	
	// Build scopes array
	NSMutableArray *scopes = [NSMutableArray array];
	if (p_use_profile) {
		[scopes addObject:@"public_profile"];
	} else {
		[scopes addObject:@"basic_info"];
	}
	if (p_use_friends) {
		[scopes addObject:@"user_friends"];
	}
	
	// TODO: Call real TapTap SDK login
	// [TapTapLogin loginWithScopes:scopes completion:^(TapTapAccount *account, NSError *error) { ... }];
	
	// Simulate async login response
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		// Emit signal directly for iOS
		emit_signal("onLoginSuccess");
	});
}

bool TapTapLogin::isLogin() {
	// TODO: Check real TapTap SDK login status
	// return [TapTapLogin isLoggedIn];
	NSLog(@"[TapTap] isLogin called");
	return false;
}

String TapTapLogin::getUserProfile() {
	NSLog(@"[TapTap] getUserProfile called");
	
	// TODO: Get real user profile from TapTap SDK
	// TapTapAccount *account = [TapTapLogin getCurrentAccount];
	// return convert_to_json(account);
	
	// Return mock JSON string
	Dictionary profile;
	profile["name"] = "TapTap User";
	profile["avatar"] = "https://example.com/avatar.png";
	profile["openId"] = "mock_open_id";
	profile["unionId"] = "mock_union_id";
	
	return JSON::print(profile);
}

void TapTapLogin::logout() {
	NSLog(@"[TapTap] logout called");
	
	// TODO: Call real TapTap SDK logout
	// [TapTapLogin logout];
	
	Dictionary ret_data;
	add_pending_event("logout", "ok", ret_data);
}

void TapTapLogin::logoutThenRestart() {
	NSLog(@"[TapTap] logoutThenRestart called");
	logout();
	// TODO: Restart app logic
	// exit(0); // Not recommended, find proper iOS restart method
}

// Compliance (Anti-addiction)
void TapTapLogin::compliance() {
	NSLog(@"[TapTap] compliance called");
	
	// TODO: Start compliance check
	// [TapTapCompliance startup:userId callback:^(int code, NSString *message) { ... }];
	
	// Simulate compliance success
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		emit_signal(\"onComplianceResult\", 500, \"LOGIN_SUCCESS\");
	});
}

// License Verification
void TapTapLogin::checkLicense(bool p_force_check) {
	NSLog(@"[TapTap] checkLicense called with forceCheck: %d", p_force_check);
	
	// TODO: Call real TapTap SDK license check
	// [TapTapLicense checkLicense:p_force_check callback:^(BOOL success) { ... }];
	
	// Simulate license check
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		emit_signal(\"onLicenseSuccess\");
	});
}

// DLC
void TapTapLogin::queryDLC(const Array &p_sku_ids) {
	NSLog(@"[TapTap] queryDLC called with %d SKUs", p_sku_ids.size());
	
	// Convert Array to NSArray
	NSMutableArray *skuIds = [NSMutableArray array];
	for (int i = 0; i < p_sku_ids.size(); i++) {
		String sku = p_sku_ids[i];
		[skuIds addObject:[NSString stringWithUTF8String:sku.utf8().get_data()]];
	}
	
	// TODO: Call real TapTap SDK DLC query
	// [TapTapLicense queryDLC:skuIds callback:^(TapLicenseQueryCode code, NSDictionary *queryList) { ... }];
	
	// Simulate query result
	Dictionary result;
	result[\"code\"] = 0;
	result[\"codeName\"] = \"QUERY_RESULT_OK\";
	Dictionary query_list;
	for (int i = 0; i < p_sku_ids.size(); i++) {
		query_list[p_sku_ids[i]] = 0; // 0 = not purchased
	}
	result[\"queryList\"] = query_list;
	
	emit_signal(\"onDLCQueryResult\", JSON::print(result));
}

void TapTapLogin::purchaseDLC(const String &p_sku_id) {
	NSLog(@"[TapTap] purchaseDLC called with SKU: %@", [NSString stringWithUTF8String:p_sku_id.utf8().get_data()]);
	
	// TODO: Call real TapTap SDK DLC purchase
	// [TapTapLicense purchaseDLC:skuId callback:^(NSString *sku, TapLicensePurchaseCode status) { ... }];
	
	// Simulate purchase (DLC_NOT_PURCHASED = 0, DLC_PURCHASED = 1, DLC_RETURN_ERROR = -1)
	emit_signal(\"onDLCPurchaseResult\", p_sku_id, 0);
}

// IAP (In-App Purchase)
void TapTapLogin::queryProductDetailsAsync(const Array &p_products) {
	NSLog(@"[TapTap] queryProductDetailsAsync called with %d products", p_products.size());
	
	// TODO: Query product details
	// iOS doesn't have IAP in TapTap SDK (Android only feature)
	// Log and skip
	
	Dictionary result;
	result[\"error\"] = \"IAP not supported on iOS\";
	emit_signal(\"onProductDetailsResponse\", JSON::print(result));
}

void TapTapLogin::launchBillingFlow(const String &p_product_id, const String &p_obfuscated_account_id) {
	NSLog(@"[TapTap] launchBillingFlow called (not supported on iOS)");
	
	Dictionary result;
	result[\"error\"] = \"IAP not supported on iOS\";
	emit_signal(\"onLaunchBillingFlowResult\", JSON::print(result));
}

void TapTapLogin::finishPurchaseAsync(const String &p_order_id, const String &p_purchase_token) {
	NSLog(@"[TapTap] finishPurchaseAsync called (not supported on iOS)");
	
	Dictionary result;
	result[\"error\"] = \"IAP not supported on iOS\";
	emit_signal(\"onFinishPurchaseResponse\", JSON::print(result));
}

void TapTapLogin::queryUnfinishedPurchaseAsync() {
	NSLog(@"[TapTap] queryUnfinishedPurchaseAsync called (not supported on iOS)");
	
	Dictionary result;
	result[\"error\"] = \"IAP not supported on iOS\";
	emit_signal(\"onQueryUnfinishedPurchaseResponse\", JSON::print(result));
}

// Utility
void TapTapLogin::showTip(const String &p_text) {
	NSLog(@"[TapTap] showTip: %@", [NSString stringWithUTF8String:p_text.utf8().get_data()]);
	
	// TODO: Show native iOS toast/alert
	// On iOS, you might want to use UIAlertController or a custom toast view
}

void TapTapLogin::restartApp() {
	NSLog(@"[TapTap] restartApp called");
	
	// TODO: Implement app restart on iOS
	// iOS doesn't have a direct restart API, might need to exit and let user reopen
	// exit(0); // Not recommended
}

int TapTapLogin::get_pending_event_count() {
	return pending_events.size();
}

Variant TapTapLogin::pop_pending_event() {
	Variant front = pending_events.front()->get();
	pending_events.pop_front();
	return front;
}

TapTapLogin *TapTapLogin::get_singleton() {
	return instance;
}

TapTapLogin::TapTapLogin() {
	ERR_FAIL_COND(instance != NULL);
	instance = this;
	sdk_initialized = false;
	NSLog(@"[TapTap] TapTapLogin singleton created");
}

TapTapLogin::~TapTapLogin() {
	instance = NULL;
	NSLog(@"[TapTap] TapTapLogin singleton destroyed");
}
