/*************************************************************************/
/*  godot3_taptap.mm - 简洁版本                                         */
/*************************************************************************/
/* 参考 Android 版本实现和官方 iOS 插件模式                              */
/*************************************************************************/

#include "godot3_taptap.h"

#if VERSION_MAJOR == 4
#include "core/io/json.h"
#import "platform/ios/app_delegate.h"

#else
#include "core/io/json.h"
#import "platform/iphone/app_delegate.h"

#endif

#import <TapTapComplianceSDK/TapTapCompliance.h>
#import <TapTapComplianceSDK/TapTapComplianceOptions.h>
#import <TapTapCoreSDK/TapTapSDK.h>
#import <TapTapLoginSDK/TapTapLoginSDK-Swift.h>
#import <objc/message.h>
#import <objc/runtime.h>

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
- (void)exitCompliance;

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
	// NSLog(@"[TapTap] Decrypting token with key: %@", decryptKey);
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

	// NSLog(@"[TapTap] SDK init with clientId: %@, clientToken: %@", clientId, clientToken);
	self.clientId = clientId;
	self.clientToken = clientToken;

	TapTapSdkOptions *options = [[TapTapSdkOptions alloc] init];
	options.clientId = clientId;
	options.clientToken = clientToken;
	options.region = TapTapRegionTypeCN;
	options.enableLog = enableLog;

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

	/// 合规认证配置
	TapTapComplianceOptions *complianceOptions = [[TapTapComplianceOptions alloc] init];

	complianceOptions.showSwitchAccount = YES; // 是否显示切换账号按钮
	complianceOptions.useAgeRange = NO; // 游戏是否需要获取真实年龄段信息

	// 其他模块配置项
	NSArray *otherOptions = @[ complianceOptions ];

	// TapSDK 初始化
	[TapTapSDK initWithOptions:options otherOptions:otherOptions];
	self.sdkInitialized = YES;

	NSLog(@"[TapTap] SDK initialized");

	// });
}

- (void)loginWithProfile:(BOOL)useProfile friends:(BOOL)useFriends {
	// dispatch_async(dispatch_get_main_queue(), ^{
	NSMutableArray *scopes = [NSMutableArray array];
	if (useProfile) {
		[scopes addObject:@"public_profile"];
	} else {
		[scopes addObject:@"basic_info"];
	}
	if (useFriends) {
		[scopes addObject:@"user_friends"];
	}

	// 发起 Tap 登录
	[TapTapLogin LoginWithScopes:scopes
						 handler:^(BOOL isCancel, NSError *_Nullable error, TapTapAccount *_Nullable account) {
							 NSLog(@"[TapTap] Login callback, isCancel: %d, error: %@, account: %@", isCancel, error, account);
							 if (isCancel) {
								 Godot3TapTap::get_singleton()->emit_signal("onLoginCancel");
							 } else if (error != nil) {
								 String message = String::utf8([[error localizedDescription] UTF8String]);
								 Godot3TapTap::get_singleton()->emit_signal("onLoginFail", message);
							 } else {
								 Godot3TapTap::get_singleton()->emit_signal("onLoginSuccess");
							 }
						 }];
	// });
}

- (BOOL)isLoggedIn {
	TapTapAccount *account = [TapTapLogin getCurrentTapAccount];
	if (account != nil) {
		AccessToken *token = account.accessToken;
		UserInfo *userInfo = account.userInfo;
		if (token != nil && userInfo != nil) {
			// 用户已登录
			return YES;
		} else {
			// 用户未登录
			return NO;
		}
	} else {
		// 用户未登录
		return NO;
	}
}

- (NSDictionary *)getUserProfile {
	TapTapAccount *account = [TapTapLogin getCurrentTapAccount];

	if (account && account.userInfo) {
		return @{
			@"openId" : account.userInfo.openId ?: @"",
			@"unionId" : account.userInfo.unionId ?: @"",
			@"name" : account.userInfo.name ?: @"",
			@"avatar" : account.userInfo.avatar ?: @""
		};
	}

	return @{ @"error" : @"User not logged in" };
}

- (void)logout {
	[TapTapLogin logout];
}

- (void)startComplianceWithUserId:(NSString *)userId {
	dispatch_async(dispatch_get_main_queue(), ^{
		if (!userId || userId.length == 0) {
			Godot3TapTap::get_singleton()->emit_signal("onComplianceResult", -1, "Invalid user ID");
			return;
		}

		[TapTapCompliance startup:userId];
	});
}

- (void)exitCompliance {
	[TapTapCompliance exit];
}

- (void)complianceCallbackWithCode:(TapComplianceResultHandlerCode)code extra:(NSString *_Nullable)extra {
	String info = String::utf8([extra UTF8String] ?: "");
	Godot3TapTap::get_singleton()->emit_signal("onComplianceResult", (int)code, info);
}

@end

// MARK: - TapTap Injector for OpenURL

@interface TapTapInjector : NSObject
@end

@implementation TapTapInjector

+ (void)load {
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		[self injectAppDelegate];
		if (@available(iOS 13.0, *)) {
			[self injectSceneDelegate];
		}
	});
}

+ (void)injectAppDelegate {
	Class appDelegateClass = NSClassFromString(@"AppDelegate");
	if (!appDelegateClass) {
		appDelegateClass = NSClassFromString(@"GodotApplicalitionDelegate");
	}

	if (appDelegateClass) {
		SEL originalSelector = @selector(application:openURL:options:);
		SEL swizzledSelector = @selector(taptap_application:openURL:options:);

		Method originalMethod = class_getInstanceMethod(appDelegateClass, originalSelector);
		Method swizzledMethod = class_getInstanceMethod([self class], swizzledSelector);

		if (!originalMethod) {
			// Original method doesn't exist, just add our implementation directly
			class_addMethod(appDelegateClass,
					originalSelector,
					imp_implementationWithBlock(^BOOL(id self, UIApplication *app, NSURL *url, NSDictionary *options) {
						return [TapTapLogin openWithUrl:url];
					}),
					"B@:@@@");
		} else if (swizzledMethod) {
			// Original method exists, perform method swizzling
			class_addMethod(appDelegateClass,
					swizzledSelector,
					method_getImplementation(swizzledMethod),
					method_getTypeEncoding(swizzledMethod));

			Method newMethod = class_getInstanceMethod(appDelegateClass, swizzledSelector);
			if (newMethod) {
				method_exchangeImplementations(originalMethod, newMethod);
			}
		}
	}
}

+ (void)injectSceneDelegate {
	Class sceneDelegateClass = NSClassFromString(@"SceneDelegate");
	if (sceneDelegateClass) {
		SEL originalSelector = @selector(scene:openURLContexts:);
		SEL swizzledSelector = @selector(taptap_scene:openURLContexts:);

		Method originalMethod = class_getInstanceMethod(sceneDelegateClass, originalSelector);
		Method swizzledMethod = class_getInstanceMethod([self class], swizzledSelector);

		if (!originalMethod) {
			// Original method doesn't exist, just add our implementation directly
			class_addMethod(sceneDelegateClass,
					originalSelector,
					imp_implementationWithBlock(^(id self, UIScene *scene, NSSet<UIOpenURLContext *> *URLContexts) {
						for (UIOpenURLContext *context in URLContexts) {
							[TapTapLogin openWithUrl:context.URL];
						}
					}),
					"v@:@@");
		} else if (swizzledMethod) {
			// Original method exists, perform method swizzling
			class_addMethod(sceneDelegateClass,
					swizzledSelector,
					method_getImplementation(swizzledMethod),
					method_getTypeEncoding(swizzledMethod));

			Method newMethod = class_getInstanceMethod(sceneDelegateClass, swizzledSelector);
			if (newMethod) {
				method_exchangeImplementations(originalMethod, newMethod);
			}
		}
	}
}

- (BOOL)taptap_application:(UIApplication *)app openURL:(NSURL *)url options:(NSDictionary<UIApplicationOpenURLOptionsKey, id> *)options {
	// Handle TapTap login callback
	if ([TapTapLogin openWithUrl:url]) {
		return YES;
	}

	// Call original implementation (which is now swizzled to taptap_application:openURL:options:)
	return [self taptap_application:app openURL:url options:options];
}

- (void)taptap_scene:(UIScene *)scene openURLContexts:(NSSet<UIOpenURLContext *> *)URLContexts API_AVAILABLE(ios(13.0)) {
	// Handle TapTap login callback
	for (UIOpenURLContext *context in URLContexts) {
		[TapTapLogin openWithUrl:context.URL];
	}

	// Call original implementation (which is now swizzled to taptap_scene:openURLContexts:)
	[self taptap_scene:scene openURLContexts:URLContexts];
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
	ClassDB::bind_method(D_METHOD("complianceExit"), &Godot3TapTap::complianceExit);

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
		emit_signal("onComplianceResult", -1, "Not logged in");
		return;
	}

	TapTapAccount *account = [TapTapLogin getCurrentTapAccount];
	if (account && account.userInfo && account.userInfo.unionId) {
		[taptap_delegate startComplianceWithUserId:account.userInfo.unionId];
	}
}

void Godot3TapTap::complianceExit() {
	[taptap_delegate exitCompliance];
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
	NSString *message = [[NSString alloc] initWithUTF8String:p_text.utf8().get_data()];
	dispatch_async(dispatch_get_main_queue(), ^{
		// 创建 Toast 视图
		UIView *toastView = [[UIView alloc] init];
		toastView.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.8];
		toastView.layer.cornerRadius = 10.0;
		toastView.clipsToBounds = YES;

		// 创建标签
		UILabel *label = [[UILabel alloc] init];
		label.text = message;
		label.textColor = [UIColor whiteColor];
		label.textAlignment = NSTextAlignmentCenter;
		label.font = [UIFont systemFontOfSize:14.0];
		label.numberOfLines = 0;
		[toastView addSubview:label];

		// 计算尺寸
		CGSize screenSize = [UIScreen mainScreen].bounds.size;
		CGFloat maxWidth = screenSize.width * 0.8;
		CGSize textSize = [message boundingRectWithSize:CGSizeMake(maxWidth, CGFLOAT_MAX)
												options:NSStringDrawingUsesLineFragmentOrigin
											 attributes:@{ NSFontAttributeName : label.font }
												context:nil]
								  .size;

		CGFloat padding = 20.0;
		toastView.frame = CGRectMake((screenSize.width - textSize.width - padding * 2) / 2,
				screenSize.height - 150,
				textSize.width + padding * 2,
				textSize.height + padding * 2);
		label.frame = CGRectMake(padding, padding, textSize.width, textSize.height);

		// 添加到窗口
		UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
		[keyWindow addSubview:toastView];

		// 动画显示
		toastView.alpha = 0.0;
		[UIView animateWithDuration:0.3
				animations:^{
					toastView.alpha = 1.0;
				}
				completion:^(BOOL finished) {
					// 延迟消失
					dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
						[UIView animateWithDuration:0.3
								animations:^{
									toastView.alpha = 0.0;
								}
								completion:^(BOOL finished) {
									[toastView removeFromSuperview];
								}];
					});
				}];
	});
}

void Godot3TapTap::restartApp() {
	exit(0);
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
