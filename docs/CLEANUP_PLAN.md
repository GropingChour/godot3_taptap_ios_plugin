# 代码清理计划

## 问题分析

当前代码有太多不必要的复杂性：
1. 运行时方法注入（Runtime Method Injection）
2. Method Swizzling
3. SHA256 签名生成
4. 混乱的日志和调试代码

这些都不是标准 TapTap SDK 集成需要的！

## 清理步骤

### 第一步：删除所有运行时注入代码

删除以下内容：
- `@interface TapTapSDKMethodInjector`
- `+ (void)injectMissingMethods`
- `+ (void)injectTapTapEventMethods`
- `+ (void)injectNSURLRequestMethods`
- `+ (void)hookAppDelegateURLMethods`
- `#import <objc/runtime.h>`
- `#import <CommonCrypto/CommonDigest.h>`

### 第二步：简化 GodotTapTapDelegate

保留以下核心方法：
- `- (void)initSDKWithClientId:clientToken:enableLog:withIAP:`
- `- (void)loginWithProfile:friends:`
- `- (BOOL)isLoggedIn`
- `- (NSDictionary *)getUserProfile`
- `- (void)logout`
- `- (void)startComplianceWithUserId:`
- `- (NSString *)decryptToken:` (Token 解密)
- `- (NSString *)getDecryptKey` (从 Info.plist 读取)

### 第三步：重写主线程处理

使用标准 dispatch_async：
```objective-c
- (void)initSDKWithClientId:(NSString *)clientId 
               clientToken:(NSString *)clientToken 
                enableLog:(BOOL)enableLog 
                  withIAP:(BOOL)withIAP {
    dispatch_async(dispatch_get_main_queue(), ^{
        TapTapSdkOptions *options = [[TapTapSdkOptions alloc] init];
        options.clientId = clientId;
        options.clientToken = clientToken;
        options.region = TapTapRegionTypeCN;
        options.enableLog = enableLog;
        
        [TapTapSDK initWithOptions:options];
    });
}
```

### 第四步：简化日志

只保留关键日志：
- SDK 初始化成功/失败
- 登录成功/失败/取消
- 合规认证结果

删除所有：
- Thread 检查日志
- Token 完整内容日志（安全风险）
- 调试用的 "===" 分隔线

### 第五步：URL Scheme 处理

**不使用 Method Swizzling！**

选项 A：让用户手动添加到 AppDelegate（文档说明）
选项 B：使用 Godot 官方 Service Extension 模式（推荐）

在 .gdip 中配置：
```ini
[plist]
CFBundleURLTypes = [{
    "CFBundleURLSchemes": ["ttwpyjvbc5f2jnqqlgfr"]
}]
LSApplicationQueriesSchemes = ["tapiosdk", "tapsdk", "taptap"]
```

### 第六步：统一 API 与 Android 版本

确保方法签名完全一致：
```cpp
// C++ 层
void initSdk(String p_client_id, String p_client_token, bool p_enable_log, bool p_with_iap);
void initSdkWithEncryptedToken(String p_client_id, String p_encrypted_token, bool p_enable_log, bool p_with_iap);
void login(bool p_use_profile, bool p_use_friends);
bool isLogin();
String getUserProfile();
void logout();
void logoutThenRestart();
void compliance();
void checkLicense(bool p_force_check);
void queryDLC(const Array &p_sku_ids);
void purchaseDLC(const String &p_sku_id);
void showTip(const String &p_text);
void restartApp();
```

## 新文件结构

### godot3_taptap.h（简化）
```cpp
#include "core/object.h"
#include "core/reference.h"

class Godot3TapTap : public Object {
    GDCLASS(Godot3TapTap, Object);
    
    static void _bind_methods();
    static Godot3TapTap *instance;
    
    List<Variant> pending_events;
    
public:
    // SDK 初始化
    void initSdk(String p_client_id, String p_client_token, bool p_enable_log, bool p_with_iap);
    void initSdkWithEncryptedToken(String p_client_id, String p_encrypted_token, bool p_enable_log, bool p_with_iap);
    
    // 登录
    void login(bool p_use_profile, bool p_use_friends);
    bool isLogin();
    String getUserProfile();
    void logout();
    void logoutThenRestart();
    
    // 合规认证
    void compliance();
    
    // License & DLC（iOS 不支持，返回占位）
    void checkLicense(bool p_force_check);
    void queryDLC(const Array &p_sku_ids);
    void purchaseDLC(const String &p_sku_id);
    
    // IAP（iOS 不支持，返回占位）
    void queryProductDetailsAsync(const Array &p_products);
    void launchBillingFlow(const String &p_product_id, const String &p_account_id);
    void finishPurchaseAsync(const String &p_order_id, const String &p_token);
    void queryUnfinishedPurchaseAsync();
    
    // 工具方法
    void showTip(const String &p_text);
    void restartApp();
    
    // 事件队列
    void _post_event(Variant p_event);
    int get_pending_event_count();
    Variant pop_pending_event();
    
    static Godot3TapTap *get_singleton();
    
    Godot3TapTap();
    ~Godot3TapTap();
};
```

### godot3_taptap.mm（核心逻辑）
```objective-c
#include "godot3_taptap.h"
#import <Foundation/Foundation.h>
#import <TapTapLoginSDK/TapTapLoginSDK.h>
#import <TapTapComplianceSDK/TapTapComplianceSDK.h>
#import <TapTapCoreSDK/TapTapCoreSDK.h>

@interface GodotTapTapDelegate : NSObject <TapTapComplianceDelegate>
@property(nonatomic, strong) NSString *clientId;
@property(nonatomic, strong) NSString *clientToken;

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
// 实现代码...
@end

static GodotTapTapDelegate *taptap_delegate = nil;

// C++ 方法实现...
```

## 预期效果

- 代码行数减少 50%+
- 移除所有运行时黑科技
- 与 Android 版本 API 完全一致
- 遵循官方 iOS 插件模式
- 易于维护和调试
