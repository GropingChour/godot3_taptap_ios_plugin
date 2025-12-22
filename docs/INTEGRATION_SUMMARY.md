# TapTap iOS SDK 集成总结

## 1. iOS SDK 集成基础知识

### 1.1 SDK 初始化（来自官方文档）
```objective-c
TapTapSdkOptions *options = [[TapTapSdkOptions alloc] init];
options.clientId = @"your_client_id";
options.clientToken = @"your_client_token";
options.region = TapTapRegionTypeCN;  // 中国区
options.enableLog = YES;

[TapTapSDK initWithOptions:options];
```

### 1.2 登录（来自官方文档）
```objective-c
// 定义授权范围
NSArray *scopes = @[@"public_profile"];  // 或 @"basic_info" 无感登录

[TapTapLogin LoginWithScopes:scopes 
                viewController:nil 
                handler:^(BOOL success, NSError *error, TapTapAccount *account) {
    if (success && account) {
        // 登录成功
    }
}];
```

### 1.3 URL Scheme 配置（Info.plist）
```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>open-taptap-{CLIENT_ID}</string>
        </array>
    </dict>
</array>

<key>LSApplicationQueriesSchemes</key>
<array>
    <string>tapiosdk</string>
    <string>tapsdk</string>
    <string>taptap</string>
</array>
```

### 1.4 合规认证
```objective-c
[TapTapCompliance startup:userId];
[TapTapCompliance registerComplianceDelegate:self];
```

## 2. Android 插件实现参考

### 2.1 核心结构
```java
public class Godot3TapTap extends GodotPlugin {
    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    
    private void runOnMainThread(Runnable task) {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            task.run();
        } else {
            mainHandler.post(task);
        }
    }
}
```

### 2.2 Token 加密（Android 使用 res/values/strings.xml）
```java
// 读取密钥
private static String getDecryptKey(Context context) {
    int keyResId = context.getResources().getIdentifier(
        "taptap_decrypt_key", "string", context.getPackageName()
    );
    if (keyResId != 0) {
        return context.getString(keyResId);
    }
    return "TapTapz9mdoNZSItSxJOvG"; // 默认密钥
}

// XOR 解密
private static String decryptToken(String encryptedToken, Context context) {
    String decryptKey = getDecryptKey(context);
    byte[] encryptedBytes = Base64.decode(encryptedToken, Base64.DEFAULT);
    byte[] keyBytes = decryptKey.getBytes(StandardCharsets.UTF_8);
    byte[] decryptedBytes = new byte[encryptedBytes.length];
    
    for (int i = 0; i < encryptedBytes.length; i++) {
        decryptedBytes[i] = (byte) (encryptedBytes[i] ^ keyBytes[i % keyBytes.length]);
    }
    
    return new String(decryptedBytes, StandardCharsets.UTF_8);
}
```

### 2.3 API 方法（与 iOS 必须一致）
```java
@UsedByGodot
public void initSdk(String clientId, String clientToken, boolean enableLog, boolean withIAP);

@UsedByGodot
public void initSdkWithEncryptedToken(String clientId, String encryptedToken, boolean enableLog, boolean withIAP);

@UsedByGodot
public void login(boolean useProfile, boolean useFriends);

@UsedByGodot
public boolean isLogin();

@UsedByGodot
public String getUserProfile(); // 返回 JSON 字符串

@UsedByGodot
public void logout();

@UsedByGodot
public void compliance();

@UsedByGodot
public void checkLicense(boolean forceCheck);

@UsedByGodot
public void queryDLC(String[] skuIds);

@UsedByGodot
public void purchaseDLC(String skuId);
```

### 2.4 信号定义
```java
@Override
public Set<SignalInfo> getPluginSignals() {
    return Set.of(
        new SignalInfo("onLoginSuccess"),
        new SignalInfo("onLoginFail", String.class),
        new SignalInfo("onLoginCancel"),
        new SignalInfo("onComplianceResult", Integer.class, String.class),
        new SignalInfo("onLicenseSuccess"),
        new SignalInfo("onLicenseFailed"),
        new SignalInfo("onDLCQueryResult", String.class),
        new SignalInfo("onDLCPurchaseResult", String.class, Integer.class)
    );
}
```

## 3. 官方 iOS 插件模式

### 3.1 字符串转换（来自 in_app_store.mm）
```objective-c
// NSString → Godot String
String str = String::utf8([nsString UTF8String]);

// Godot String → NSString
NSString *nsStr = [[NSString alloc] initWithUTF8String:godotString.utf8().get_data()];
```

### 3.2 事件队列模式（来自 in_app_store.h）
```objective-c
// 在 .h 中
List<Variant> pending_events;
void _post_event(Variant p_event);

// 在 .mm 中
void InAppStore::_post_event(Variant p_event) {
    pending_events.push_back(p_event);
}

int InAppStore::get_pending_event_count() {
    return pending_events.size();
}

Variant InAppStore::pop_pending_event() {
    Variant front = pending_events.front()->get();
    pending_events.pop_front();
    return front;
}
```

### 3.3 Delegate 模式（来自 in_app_store.mm）
```objective-c
@interface GodotProductsDelegate : NSObject <SKProductsRequestDelegate>
@end

@implementation GodotProductsDelegate
- (void)productsRequest:(SKProductsRequest *)request 
     didReceiveResponse:(SKProductsResponse *)response {
    // 处理回调
    Dictionary ret;
    ret["type"] = "product_info";
    InAppStore::get_singleton()->_post_event(ret);
}
@end

static GodotProductsDelegate *delegate = nil;
```

### 3.4 单例注册（来自 apn_plugin.cpp）
```cpp
#include "core/engine.h"

APNPlugin *plugin;

void godot_apn_init() {
    plugin = memnew(APNPlugin);
    Engine::get_singleton()->add_singleton(Engine::Singleton("APN", plugin));
}

void godot_apn_deinit() {
    if (plugin) {
        memdelete(plugin);
    }
}
```

## 4. iOS 专属特性

### 4.1 Token 存储（Info.plist vs Android strings.xml）
```xml
<!-- iOS: Info.plist -->
<key>TapTapDecryptKey</key>
<string>TapTapz9mdoNZSItSxJOvG</string>
```

```xml
<!-- Android: res/values/strings.xml -->
<string name="taptap_decrypt_key">TapTapz9mdoNZSItSxJOvG</string>
```

### 4.2 主线程检查（iOS 特有）
```objective-c
if (![NSThread isMainThread]) {
    NSLog(@"Error: Must be called on main thread");
    return;
}
```

### 4.3 URL Scheme 处理（官方模式：Service Extension）
不需要 Method Swizzling，应该使用 Godot 官方的 Service Extension 模式。

## 5. 不需要的东西

### ❌ 不需要运行时方法注入
- `injectTapTapEventMethods` - TapTap SDK 不应该需要这个
- `injectNSURLRequestMethods` - 系统类注入是危险的

### ❌ 不需要 Method Swizzling
- `hookAppDelegateURLMethods` - 应该用 AppDelegate Service Extension

### ❌ 不需要 SHA256 签名
- `generateSHA256SignatureWithSecret` - 这不是 TapTap SDK 的标准功能

## 6. 正确的集成方式

### 6.1 简单的桥接结构
```
GDScript (taptap.gd)
    ↓
C++ Singleton (Godot3TapTap)
    ↓
ObjC Delegate (GodotTapTapDelegate)
    ↓
TapTap SDK (原生 API)
```

### 6.2 最小化实现
1. **C++ 单例**: 暴露给 GDScript 的接口
2. **ObjC Delegate**: 处理 SDK 回调
3. **事件队列**: 传递异步结果
4. **线程安全**: 主线程调用 SDK

### 6.3 应该删除的代码
- 所有 `@interface TapTapSDKMethodInjector` 相关代码
- `injectMissingMethods` 全部逻辑
- `hookAppDelegateURLMethods` Method Swizzling
- CommonCrypto/CommonDigest.h 导入（SHA256）

## 7. 推荐实现

参考 Android 插件的 `Godot3TapTap.java`，创建对应的 iOS 版本：
- 相同的方法签名
- 相同的信号名称
- 相同的 Token 加密逻辑（只是存储位置不同）
- 相同的线程处理模式

参考官方 `in_app_store.mm` 的模式：
- Delegate 处理回调
- 事件队列传递结果
- 字符串转换工具
- 单例注册
