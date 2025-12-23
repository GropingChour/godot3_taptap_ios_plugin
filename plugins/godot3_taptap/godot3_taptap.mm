/*************************************************************************/
/*  godot3_taptap.mm - 简洁版本                                         */
/*************************************************************************/
/* 参考 Android 版本实现和官方 iOS 插件模式                              */
/*************************************************************************/

#include "godot3_taptap.h"

#if VERSION_MAJOR == 4
#import "platform/ios/app_delegate.h"
#include "core/io/json.h"
#else
#import "platform/iphone/app_delegate.h"
#include "core/io/json.h"
#endif

#import <TapTapCoreSDK/TapTapSDK.h>
#import <TapTapLoginSDK/TapTapLoginSDK-Swift.h>
#import <TapTapComplianceSDK/TapTapComplianceOptions.h>
#import <TapTapComplianceSDK/TapTapCompliance.h>

#if VERSION_MAJOR == 4
typedef PackedStringArray GodotStringArray;
#else
typedef PoolStringArray GodotStringArray;
#endif

// MARK: - Objective-C Delegate

@interface GodotTapTapDelegate : NSObject <TapTapComplianceDelegate>

@property(nonatomic, strong) NSString *clientId;
@property(nonatomic, strong) NSString *clientToken;
@property(nonatomic, assign) BOOL sdkInitialized;

- (NSString *)getDecryptKey;
- (NSString *)decryptToken:(NSString *)encryptedToken;
- (void)initSDKWithClientId:(NSString *)clientId clientToken:(NSString *)clientToken enableLog:(BOOL)enableLog;
- (void)loginWithProfile:(BOOL)useProfile friends:(BOOL)useFriends;
- (BOOL)isLoggedIn;
- (NSDictionary *)getUserProfile;
- (void)logout;
- (void)startComplianceWithUserId:(NSString *)userId;

@end

@implementation GodotTapTapDelegate

- (instancetype)init {
	self = [super init];
	if (self) {
		_sdkInitialized = NO;
		[TapTapCompliance registerComplianceDelegate:self];
	}
	return self;
}

- (NSString *)getDecryptKey {
	NSDictionary *infoPlist = [[NSBundle mainBundle] infoDictionary];
	NSString *key = [infoPlist objectForKey:@"TapTapDecryptKey"];
	return key ?: @"TapTapz9mdoNZSItSxJOvG";
}

- (NSString *)decryptToken:(NSString *)encryptedToken {
	if (!encryptedToken || encryptedToken.length == 0) return @"";
	
	NSString *decryptKey = [self getDecryptKey];
	NSLog(@"[TapTap] Decrypting token with key: %@", decryptKey);
	NSData *encryptedData = [[NSData alloc] initWithBase64EncodedString:encryptedToken options:0];
	if (!encryptedData) return @"";
	
	NSData *keyData = [decryptKey dataUsingEncoding:NSUTF8StringEncoding];
	NSMutableData *decryptedData = [NSMutableData dataWithLength:encryptedData.length];
	
	const uint8_t *encBytes = (const uint8_t *)[encryptedData bytes];
	const uint8_t *keyBytes = (const uint8_t *)[keyData bytes];
	uint8_t *decBytes = (uint8_t *)[decryptedData mutableBytes];
	
	for (NSUInteger i = 0; i < encryptedData.length; i++) {
		decBytes[i] = encBytes[i] ^ keyBytes[i % keyData.length];
	}
	
	return [[NSString alloc] initWithData:decryptedData encoding:NSUTF8StringEncoding] ?: @"";
}

- (void)initSDKWithClientId:(NSString *)clientId clientToken:(NSString *)clientToken enableLog:(BOOL)enableLog {
	// dispatch_async(dispatch_get_main_queue(), ^{

		// Method 1: Direct property (if exists)
		if ([options respondsToSelector:@selector(setEnableAutoReport:)]) {
			[options setValue:@NO forKey:@"enableAutoReport"];
			NSLog(@"[TapTap ObjC] ✓ Disabled auto report via property");
		} else {
			NSLog(@"[TapTap ObjC] ✗ enableAutoReport property not available");
		}

		NSLog(@"[TapTap] SDK init with clientId: %@, clientToken: %@", clientId, clientToken);
		self.clientId = clientId;
		self.clientToken = clientToken;
		
		TapTapSdkOptions *options = [[TapTapSdkOptions alloc] init];
		options.clientId = clientId;
		options.clientToken = clientToken;
		options.region = TapTapRegionTypeCN;
		options.enableLog = enableLog;
		

		[TapTapSDK initWithOptions:options];
		self.sdkInitialized = YES;

		NSLog(@"[TapTap] SDK initialized");

		Dictionary ret;
		ret["type"] = "init";
		ret["result"] = "ok";
		Godot3TapTap::get_singleton()->_post_event(ret);

	// });
}

- (void)loginWithProfile:(BOOL)useProfile friends:(BOOL)useFriends {
	dispatch_async(dispatch_get_main_queue(), ^{
		NSMutableArray *scopes = [NSMutableArray array];
		if (useProfile) {
			[scopes addObject:@"public_profile"];
		} else {
			[scopes addObject:@"basic_info"];
		}
		if (useFriends) {
			[scopes addObject:@"user_friends"];
		}
		
		[TapTapLogin LoginWithScopes:scopes viewController:nil handler:^(BOOL success, NSError *error, TapTapAccount *account) {
			Dictionary ret;
			ret["type"] = "login";
			
			if (success && account) {
				ret["result"] = "success";
				Godot3TapTap::get_singleton()->_post_event(ret);
				Godot3TapTap::get_singleton()->emit_signal("onLoginSuccess");
			} else if (error) {
				if (error.code == 1) {
					ret["result"] = "cancel";
					Godot3TapTap::get_singleton()->_post_event(ret);
					Godot3TapTap::get_singleton()->emit_signal("onLoginCancel");
				} else {
					ret["result"] = "error";
					ret["message"] = String::utf8([[error localizedDescription] UTF8String]);
					Godot3TapTap::get_singleton()->_post_event(ret);
					Godot3TapTap::get_singleton()->emit_signal("onLoginFail", ret["message"]);
				}
			}
		}];
	});
}

- (BOOL)isLoggedIn {
	return [TapTapLogin getCurrentTapAccount] != nil;
}

- (NSDictionary *)getUserProfile {
	TapTapAccount *account = [TapTapLogin getCurrentTapAccount];
	
	if (account && account.userInfo) {
		return @{
			@"openId": account.userInfo.openId ?: @"",
			@"unionId": account.userInfo.unionId ?: @"",
			@"name": account.userInfo.name ?: @"",
			@"avatar": account.userInfo.avatar ?: @""
		};
	}
	
	return @{@"error": @"User not logged in"};
}

- (void)logout {
	[TapTapLogin logout];
	[TapTapCompliance exit];
	
	Dictionary ret;
	ret["type"] = "logout";
	ret["result"] = "ok";
	Godot3TapTap::get_singleton()->_post_event(ret);
}

- (void)startComplianceWithUserId:(NSString *)userId {
	dispatch_async(dispatch_get_main_queue(), ^{
		if (!userId || userId.length == 0) {
			Dictionary ret;
			ret["type"] = "compliance";
			ret["code"] = -1;
			ret["info"] = "Invalid user ID";
			Godot3TapTap::get_singleton()->_post_event(ret);
			return;
		}
		
		[TapTapCompliance startup:userId];
	});
}

- (void)complianceCallbackWithCode:(TapComplianceResultHandlerCode)code extra:(NSString * _Nullable)extra {
	Dictionary ret;
	ret["type"] = "compliance";
	ret["code"] = (int)code;
	ret["info"] = String::utf8([extra UTF8String] ?: "");
	Godot3TapTap::get_singleton()->_post_event(ret);
	Godot3TapTap::get_singleton()->emit_signal("onComplianceResult", (int)code, ret["info"]);
}

@end

// MARK: - Static delegate instance
static GodotTapTapDelegate *taptap_delegate = nil;

// MARK: - C++ Plugin Implementation

Godot3TapTap *Godot3TapTap::instance = NULL;

void Godot3TapTap::_bind_methods() {
	// SDK 初始化
	ClassDB::bind_method(D_METHOD("initSdk"), &Godot3TapTap::initSdk);
	ClassDB::bind_method(D_METHOD("initSdkWithEncryptedToken"), &Godot3TapTap::initSdkWithEncryptedToken);
	
	// 登录
	ClassDB::bind_method(D_METHOD("login"), &Godot3TapTap::login);
	ClassDB::bind_method(D_METHOD("isLogin"), &Godot3TapTap::isLogin);
	ClassDB::bind_method(D_METHOD("getUserProfile"), &Godot3TapTap::getUserProfile);
	ClassDB::bind_method(D_METHOD("logout"), &Godot3TapTap::logout);
	ClassDB::bind_method(D_METHOD("logoutThenRestart"), &Godot3TapTap::logoutThenRestart);
	
	// 合规认证
	ClassDB::bind_method(D_METHOD("compliance"), &Godot3TapTap::compliance);
	
	// License & DLC（iOS 不支持）
	ClassDB::bind_method(D_METHOD("checkLicense"), &Godot3TapTap::checkLicense);
	ClassDB::bind_method(D_METHOD("queryDLC"), &Godot3TapTap::queryDLC);
	ClassDB::bind_method(D_METHOD("purchaseDLC"), &Godot3TapTap::purchaseDLC);
	
	// IAP（iOS 不支持）
	ClassDB::bind_method(D_METHOD("queryProductDetailsAsync"), &Godot3TapTap::queryProductDetailsAsync);
	ClassDB::bind_method(D_METHOD("launchBillingFlow"), &Godot3TapTap::launchBillingFlow);
	ClassDB::bind_method(D_METHOD("finishPurchaseAsync"), &Godot3TapTap::finishPurchaseAsync);
	ClassDB::bind_method(D_METHOD("queryUnfinishedPurchaseAsync"), &Godot3TapTap::queryUnfinishedPurchaseAsync);
	
	// 工具方法
	ClassDB::bind_method(D_METHOD("showTip"), &Godot3TapTap::showTip);
	ClassDB::bind_method(D_METHOD("restartApp"), &Godot3TapTap::restartApp);
	
	// 事件队列
	ClassDB::bind_method(D_METHOD("get_pending_event_count"), &Godot3TapTap::get_pending_event_count);
	ClassDB::bind_method(D_METHOD("pop_pending_event"), &Godot3TapTap::pop_pending_event);
	
	// 信号（与 Android 版本完全一致）
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

void Godot3TapTap::_post_event(Variant p_event) {
	pending_events.push_back(p_event);
}

// SDK 初始化
void Godot3TapTap::initSdk(const String &p_client_id, const String &p_client_token, bool p_enable_log, bool p_with_iap) {
	NSString *clientId = [[NSString alloc] initWithUTF8String:p_client_id.utf8().get_data()];
	NSString *clientToken = [[NSString alloc] initWithUTF8String:p_client_token.utf8().get_data()];
	
	[taptap_delegate initSDKWithClientId:clientId clientToken:clientToken enableLog:p_enable_log];
}

void Godot3TapTap::initSdkWithEncryptedToken(const String &p_client_id, const String &p_encrypted_token, bool p_enable_log, bool p_with_iap) {
	NSString *clientId = [[NSString alloc] initWithUTF8String:p_client_id.utf8().get_data()];
	NSString *encryptedToken = [[NSString alloc] initWithUTF8String:p_encrypted_token.utf8().get_data()];
	
	NSString *decryptedToken = [taptap_delegate decryptToken:encryptedToken];
	[taptap_delegate initSDKWithClientId:clientId clientToken:decryptedToken enableLog:p_enable_log];
}

// 登录
void Godot3TapTap::login(bool p_use_profile, bool p_use_friends) {
	[taptap_delegate loginWithProfile:p_use_profile friends:p_use_friends];
}

bool Godot3TapTap::isLogin() {
	return [taptap_delegate isLoggedIn];
}

String Godot3TapTap::getUserProfile() {
	NSDictionary *profile = [taptap_delegate getUserProfile];
	
	NSError *error = nil;
	NSData *jsonData = [NSJSONSerialization dataWithJSONObject:profile options:0 error:&error];
	if (!jsonData) return "{}";
	
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

// 合规认证
void Godot3TapTap::compliance() {
	if (![taptap_delegate isLoggedIn]) {
		Dictionary ret;
		ret["type"] = "compliance";
		ret["code"] = -1;
		ret["info"] = "Not logged in";
		_post_event(ret);
		return;
	}
	
	TapTapAccount *account = [TapTapLogin getCurrentTapAccount];
	if (account && account.userInfo && account.userInfo.unionId) {
		[taptap_delegate startComplianceWithUserId:account.userInfo.unionId];
	}
}

// License & DLC（iOS 不支持，返回占位）
void Godot3TapTap::checkLicense(bool p_force_check) {
	NSLog(@"[TapTap] License check not supported on iOS");
	emit_signal("onLicenseSuccess");
}

void Godot3TapTap::queryDLC(const Array &p_sku_ids) {
	NSLog(@"[TapTap] DLC query not supported on iOS");
	emit_signal("onDLCQueryResult", "{}");
}

void Godot3TapTap::purchaseDLC(const String &p_sku_id) {
	NSLog(@"[TapTap] DLC purchase not supported on iOS");
	emit_signal("onDLCPurchaseResult", p_sku_id, -1);
}

// IAP（iOS 不支持，返回占位）
void Godot3TapTap::queryProductDetailsAsync(const Array &p_products) {
	NSLog(@"[TapTap] IAP not supported on iOS");
	emit_signal("onProductDetailsResponse", "{}");
}

void Godot3TapTap::launchBillingFlow(const String &p_product_id, const String &p_account_id) {
	NSLog(@"[TapTap] IAP not supported on iOS");
	emit_signal("onLaunchBillingFlowResult", "{}");
}

void Godot3TapTap::finishPurchaseAsync(const String &p_order_id, const String &p_token) {
	NSLog(@"[TapTap] IAP not supported on iOS");
	emit_signal("onFinishPurchaseResponse", "{}");
}

void Godot3TapTap::queryUnfinishedPurchaseAsync() {
	NSLog(@"[TapTap] IAP not supported on iOS");
	emit_signal("onQueryUnfinishedPurchaseResponse", "{}");
}

// 工具方法
void Godot3TapTap::showTip(const String &p_text) {
	dispatch_async(dispatch_get_main_queue(), ^{
		UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"提示"
																	   message:[[NSString alloc] initWithUTF8String:p_text.utf8().get_data()]
																preferredStyle:UIAlertControllerStyleAlert];
		[alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
		
		UIViewController *rootVC = [UIApplication sharedApplication].keyWindow.rootViewController;
		[rootVC presentViewController:alert animated:YES completion:nil];
	});
}

void Godot3TapTap::restartApp() {
	exit(0);
}

int Godot3TapTap::get_pending_event_count() {
	return pending_events.size();
}

Variant Godot3TapTap::pop_pending_event() {
	if (pending_events.size() == 0) {
		return Variant();
	}
	
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
	
	taptap_delegate = [[GodotTapTapDelegate alloc] init];
}

Godot3TapTap::~Godot3TapTap() {
	instance = NULL;
	taptap_delegate = nil;
}
