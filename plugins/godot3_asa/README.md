# Godot3 ASA (Apple Search Ads) Attribution Plugin

## 简介

这是一个用于 Godot 3.x 的 iOS ASA（Apple Search Ads）归因插件，基于 Apple 的 AdServices 框架实现客户端归因功能。

## 功能特性

- ✅ 支持 iOS 14.3+ 的 AdServices 归因 API
- ✅ 完全在客户端完成归因（无需服务器端）
- ✅ 自动处理 token 获取和归因数据请求
- ✅ 符合 Apple 最佳实践（自动延迟、重试机制）
- ✅ 完整的错误处理和日志输出

## 系统要求

- iOS 14.3 或更高版本
- Godot 3.x (支持 3.5+)

## API 接口

### 方法

#### `performAttribution()`
**推荐使用** - 一键完成归因（自动获取 token + 请求归因数据）

```gdscript
if Engine.has_singleton("Godot3ASA"):
    var asa = Engine.get_singleton("Godot3ASA")
    asa.performAttribution()
```

#### `requestAttributionToken()`
手动获取 ASA 归因 token

```gdscript
var asa = Engine.get_singleton("Godot3ASA")
asa.requestAttributionToken()
```

#### `requestAttributionData(token: String)`
使用已获取的 token 请求完整归因数据

```gdscript
var asa = Engine.get_singleton("Godot3ASA")
asa.requestAttributionData(your_token)
```

#### `isSupported() -> bool`
检查当前设备是否支持 AdServices（iOS 14.3+）

```gdscript
var asa = Engine.get_singleton("Godot3ASA")
if asa.isSupported():
    print("AdServices is supported")
else:
    print("AdServices not supported on this device")
```

### 信号（Signals）

#### `onASATokenReceived(token: String, error_code: int, error_message: String)`
Token 获取结果回调

**参数:**
- `token`: 获取到的 token（失败时为空字符串）
- `error_code`: 错误码（0 表示成功）
- `error_message`: 错误信息（成功时为空字符串）

**错误码说明:**
- `0`: 成功
- `-1`: Token 为空或其他错误
- `-2`: iOS 版本不支持 AdServices
- `2001`: 网络错误 (AAAttributionErrorcodeNetworkError)
- `2002`: 内部错误 (AAAttributionErrorcodeInternalError)
- `2003`: 平台不支持 (AAAttributionErrorcodePlatformNotSupported)

```gdscript
func _ready():
    var asa = Engine.get_singleton("Godot3ASA")
    asa.connect("onASATokenReceived", self, "_on_asa_token_received")

func _on_asa_token_received(token: String, error_code: int, error_message: String):
    if error_code == 0:
        print("Token received: ", token)
        # 可以使用 token 手动请求归因数据
        asa.requestAttributionData(token)
    else:
        print("Token request failed: ", error_message)
```

#### `onASAAttributionReceived(attribution_data: String, error_code: int, error_message: String)`
归因数据获取结果回调

**参数:**
- `attribution_data`: JSON 格式的归因数据
- `error_code`: HTTP 状态码或错误码
- `error_message`: 错误信息

**状态码说明:**
- `200`: 成功
- `400`: Token 无效
- `404`: 未找到数据（token 可能过期）
- `500`: 服务器错误
- `-1`: 网络错误或其他客户端错误
- `-2`: iOS 版本不支持

**归因数据格式（JSON）:**
```json
{
    "attribution": true,
    "orgId": 40669820,
    "campaignId": 542370539,
    "conversionType": "Download",
    "clickDate": "2024-10-08T17:17Z",
    "claimType": "Click",
    "adGroupId": 542317095,
    "countryOrRegion": "US",
    "keywordId": 87675432,
    "adId": 542317136
}
```

```gdscript
func _ready():
    var asa = Engine.get_singleton("Godot3ASA")
    asa.connect("onASAAttributionReceived", self, "_on_asa_attribution_received")

func _on_asa_attribution_received(attribution_data: String, error_code: int, error_message: String):
    if error_code == 200:
        print("Attribution data: ", attribution_data)
        # 解析 JSON 数据
        var json = JSON.parse(attribution_data)
        if json.error == OK:
            var data = json.result
            if data.attribution:
                print("User came from ASA campaign: ", data.campaignId)
                print("Keyword ID: ", data.keywordId)
    else:
        print("Attribution request failed: ", error_message)
```

## 使用示例

### 完整示例（推荐）

```gdscript
extends Node

var asa = null

func _ready():
    # 检查插件是否可用
    if not Engine.has_singleton("Godot3ASA"):
        print("ASA plugin not available")
        return
    
    asa = Engine.get_singleton("Godot3ASA")
    
    # 检查系统支持
    if not asa.isSupported():
        print("AdServices not supported on this device (requires iOS 14.3+)")
        return
    
    # 连接信号
    asa.connect("onASAAttributionReceived", self, "_on_attribution_received")
    
    # 推荐在获取网络权限后延迟调用（500-1000ms）
    yield(get_tree().create_timer(1.0), "timeout")
    
    # 一键完成归因
    asa.performAttribution()

func _on_attribution_received(attribution_data: String, error_code: int, error_message: String):
    if error_code == 200:
        var json = JSON.parse(attribution_data)
        if json.error == OK:
            var data = json.result
            
            if data.attribution:
                # 用户来自 ASA 广告
                print("=== ASA Attribution Data ===")
                print("Campaign ID: ", data.get("campaignId", "N/A"))
                print("Ad Group ID: ", data.get("adGroupId", "N/A"))
                print("Keyword ID: ", data.get("keywordId", "N/A"))
                print("Country: ", data.get("countryOrRegion", "N/A"))
                print("Conversion Type: ", data.get("conversionType", "N/A"))
                print("Click Date: ", data.get("clickDate", "N/A"))
                
                # 将数据发送到你的分析服务器
                send_attribution_to_server(data)
            else:
                # 用户不是来自 ASA 广告
                print("User is not from ASA")
    else:
        print("Attribution failed: code=", error_code, " message=", error_message)
        
        # 根据错误码处理重试逻辑
        if error_code == 404:
            # Token 可能过期，可以重试
            print("Token expired, consider retrying...")

func send_attribution_to_server(data: Dictionary):
    # 实现你的服务器上报逻辑
    pass
```

### 手动分步获取示例

```gdscript
extends Node

var asa = null
var current_token = ""

func _ready():
    if Engine.has_singleton("Godot3ASA"):
        asa = Engine.get_singleton("Godot3ASA")
        
        # 连接两个信号
        asa.connect("onASATokenReceived", self, "_on_token_received")
        asa.connect("onASAAttributionReceived", self, "_on_attribution_received")
        
        # 延迟后请求 token
        yield(get_tree().create_timer(1.0), "timeout")
        asa.requestAttributionToken()

func _on_token_received(token: String, error_code: int, error_message: String):
    if error_code == 0:
        print("Token received successfully")
        current_token = token
        
        # 延迟后请求归因数据
        yield(get_tree().create_timer(0.5), "timeout")
        asa.requestAttributionData(token)
    else:
        print("Token request failed: ", error_message)

func _on_attribution_received(attribution_data: String, error_code: int, error_message: String):
    if error_code == 200:
        print("Attribution data: ", attribution_data)
    else:
        print("Attribution failed: ", error_message)
```

## 最佳实践

### 1. 调用时机
根据 Apple 官方文档建议：
- ✅ App **首次启动**时调用（不是每次启动）
- ✅ 获取**网络权限后**延迟 500-1000ms 再调用
- ✅ 对于 iOS 14.5+，建议在 ATT 弹窗**之前**请求（可获得 detailed payload）

```gdscript
func _ready():
    # 检查是否首次启动
    if not has_requested_attribution_before():
        # 等待网络权限
        yield(request_network_permission(), "completed")
        
        # 延迟 1 秒
        yield(get_tree().create_timer(1.0), "timeout")
        
        # 执行归因
        var asa = Engine.get_singleton("Godot3ASA")
        asa.performAttribution()
        
        # 标记已请求
        mark_attribution_requested()
```

### 2. 错误处理和重试
根据官方建议实现重试机制：

```gdscript
var retry_count = 0
const MAX_RETRIES = 3
const RETRY_DELAY = 5.0

func _on_attribution_received(attribution_data: String, error_code: int, error_message: String):
    if error_code == 200:
        # 成功
        retry_count = 0
        process_attribution_data(attribution_data)
    elif error_code == 404 or error_code == 500:
        # 404 (未找到) 或 500 (服务器错误) - 可以重试
        if retry_count < MAX_RETRIES:
            retry_count += 1
            print("Retry attempt ", retry_count)
            yield(get_tree().create_timer(RETRY_DELAY), "timeout")
            asa.performAttribution()
        else:
            print("Max retries reached, giving up")
    elif error_code == 400:
        # 400 (Token 无效) - 不应重试
        print("Invalid token, cannot retry")
```

### 3. ATT (App Tracking Transparency) 集成
为获取详细的归因数据（包含 clickDate），需要在请求 ASA token **之前**获得 ATT 授权：

```gdscript
# 伪代码示例
func request_attribution_with_att():
    # 先请求 ATT 授权
    var tracking_status = await request_att_authorization()
    
    # 然后请求 ASA 归因
    if tracking_status == AUTHORIZED:
        # 用户授权，将获得 detailed payload（包含 clickDate）
        asa.performAttribution()
    else:
        # 用户未授权，将获得 standard payload（不含 clickDate）
        asa.performAttribution()
```

### 4. 数据持久化
建议保存归因数据，避免重复请求：

```gdscript
func save_attribution_data(data: Dictionary):
    var file = File.new()
    file.open("user://asa_attribution.json", File.WRITE)
    file.store_string(JSON.print(data))
    file.close()

func load_attribution_data() -> Dictionary:
    var file = File.new()
    if file.file_exists("user://asa_attribution.json"):
        file.open("user://asa_attribution.json", File.READ)
        var json = JSON.parse(file.get_as_text())
        file.close()
        if json.error == OK:
            return json.result
    return {}
```

## 归因数据字段说明

| 字段 | 类型 | 说明 |
|-----|------|------|
| `attribution` | boolean | 是否来自 ASA（true=来自 ASA，false=不来自） |
| `orgId` | long | 广告系列组 ID（账户 ID） |
| `campaignId` | long | 广告系列 ID |
| `adGroupId` | long | 广告组 ID |
| `keywordId` | long | 关键词 ID（可能为空） |
| `adId` | long | 广告对象标识符 |
| `conversionType` | string | 转化类型：`Download`（新下载）、`Redownload`（重新下载）、`PreOrder`（预购） |
| `claimType` | string | 归因类型：`Click`（点击归因）、`Impression`（展示归因） |
| `countryOrRegion` | string | 国家或地区代码（如 "US", "CN"） |
| `clickDate` | string | 广告点击时间（UTC，仅 detailed payload） |
| `impressionDate` | string | 广告展示时间（UTC，仅 detailed payload + view-through） |

## 测试

### 使用 TestFlight 测试
1. 通过 TestFlight 安装 App
2. 联网打开 App
3. 查看日志确认 token 获取和归因请求
4. 测试环境会返回 `attribution: true` 的假数据

### 日志输出
插件会输出详细的调试日志：

```
[ASA] Godot3ASA plugin initialized
[ASA] Token received successfully, length: 512
[ASA] Requesting attribution data...
[ASA] Attribution data received: {"attribution":true,...}
```

## 常见问题

### Q: 为什么总是返回 `attribution: false`？
A: 可能原因：
- 用户最近 30 天内没有点击过 Apple Search Ads
- 在真实环境（非 TestFlight）测试
- Token 获取时机不对

### Q: 什么时候会返回 404 错误？
A: 
- Token 过期（超过 24 小时）
- API 调用太快（建议 500-1000ms 延迟）
- 解决方法：等待 5 秒后重试

### Q: 如何获得包含 clickDate 的详细数据？
A: 
- 在请求 token **之前**通过 ATT 弹窗获得用户授权
- 如果在请求 token 之后才做 ATT 弹窗，无论用户是否授权都只会返回 standard payload

### Q: 可以每次启动都请求吗？
A: 
- 不建议。Apple 建议只在首次启动时请求
- Token 在 24 小时内相同，重复请求无意义
- 建议保存归因数据到本地

## 参考资料

- [Apple Ads Attribution API](https://ads.apple.com/cn/help/advanced/0028-apple-ads-attribution-api/)
- [AdServices Documentation](https://developer.apple.com/documentation/adservices/)
- [App Tracking Transparency](https://developer.apple.com/app-store/user-privacy-and-data-use/)

## 技术支持

如有问题，请查看：
- 插件源码：`plugins/godot3_asa/`
- 编译日志：检查 Xcode 输出
- 网络请求：使用 Charles/Proxyman 抓包分析
