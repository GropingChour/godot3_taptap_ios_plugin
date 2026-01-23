# Godot3 ASA 插件集成指南

## 快速开始

### 1. 编译插件

```bash
# 从项目根目录执行
cd godot3_taptap_ios_plugin

# 生成 Godot 头文件（首次需要）
./scripts/generate_headers.sh 3.x

# 编译 godot3_asa 插件
scons target=release_debug arch=arm64 simulator=no plugin=godot3_asa version=3.x

# 生成 XCFramework（包含真机和模拟器）
./scripts/generate_xcframework.sh godot3_asa 3.x
```

### 2. 集成到 Godot 项目

#### 方式一：手动复制
1. 将编译好的 `bin/godot3_asa.xcframework` 复制到你的 Godot 项目
2. 将 `plugins/godot3_asa/godot3_asa.gdip` 复制到项目的 `ios/plugins/` 目录

#### 方式二：使用发布包
```
your_godot_project/
├── ios/
│   └── plugins/
│       ├── godot3_asa.gdip
│       └── godot3_asa.xcframework/
```

### 3. 在 Godot 中启用插件

1. 打开 Godot 编辑器
2. 进入 **项目 → 导出**
3. 选择 iOS 导出预设
4. 在 **插件** 列表中勾选 `Godot3ASA`

### 4. GDScript 使用

```gdscript
extends Node

func _ready():
    # 检查插件可用性
    if not Engine.has_singleton("Godot3ASA"):
        print("ASA plugin not available")
        return
    
    var asa = Engine.get_singleton("Godot3ASA")
    
    # 检查系统支持
    if not asa.isSupported():
        print("AdServices not supported (requires iOS 14.3+)")
        return
    
    # 连接信号
    asa.connect("onASAAttributionReceived", self, "_on_attribution")
    
    # 延迟后执行归因
    yield(get_tree().create_timer(1.0), "timeout")
    asa.performAttribution()

func _on_attribution(data: String, code: int, msg: String):
    if code == 200:
        print("Attribution success: ", data)
    else:
        print("Attribution failed: ", msg)
```

## 调用时机说明

根据 Apple 官方文档和最佳实践：

### 推荐的调用时机

```
App 启动
    ↓
检查是否首次启动 (存储标记)
    ↓ 是
请求网络权限
    ↓
延迟 500-1000ms
    ↓
调用 asa.performAttribution()
    ↓
收到 onASAAttributionReceived 信号
    ↓
解析 JSON 数据
    ↓
发送到分析服务器 / 保存到本地
```

### 实现示例

```gdscript
const ASA_REQUESTED_KEY = "asa_attribution_requested"

func should_request_attribution() -> bool:
    # 检查是否已经请求过
    var config = ConfigFile.new()
    if config.load("user://app_config.cfg") == OK:
        return not config.get_value("attribution", ASA_REQUESTED_KEY, false)
    return true

func mark_attribution_requested():
    var config = ConfigFile.new()
    config.load("user://app_config.cfg")
    config.set_value("attribution", ASA_REQUESTED_KEY, true)
    config.save("user://app_config.cfg")

func _ready():
    if not should_request_attribution():
        print("Attribution already requested, skipping...")
        return
    
    # 首次启动，执行归因
    request_asa_attribution()

func request_asa_attribution():
    # 等待网络权限（根据你的网络请求实现）
    yield(ensure_network_permission(), "completed")
    
    # 延迟 1 秒
    yield(get_tree().create_timer(1.0), "timeout")
    
    # 执行归因
    var asa = Engine.get_singleton("Godot3ASA")
    if asa:
        asa.connect("onASAAttributionReceived", self, "_on_attribution_result")
        asa.performAttribution()

func _on_attribution_result(data: String, code: int, msg: String):
    if code == 200:
        # 保存数据
        save_attribution_data(data)
        
        # 标记已请求
        mark_attribution_requested()
        
        print("Attribution completed and saved")
    else:
        # 失败不标记，下次启动重试
        print("Attribution failed, will retry next launch")
```

### 重要提示

#### ✅ 应该：
1. **仅在首次启动时请求**（后续启动读取本地缓存）
2. **获取网络权限后延迟调用**（500-1000ms）
3. **实现错误重试机制**（404/500 错误可重试，间隔 5 秒）
4. **保存归因数据到本地**（避免重复请求）
5. **如需 clickDate，在请求前弹出 ATT 授权**

#### ❌ 不应该：
1. ❌ 每次启动都请求（浪费资源，token 24 小时内不变）
2. ❌ 立即调用（应延迟 500-1000ms）
3. ❌ 同步阻塞主线程（插件已异步实现）
4. ❌ 400 错误后重试（token 无效，重试无意义）

## 与 ATT (App Tracking Transparency) 集成

如果你需要获得包含 `clickDate` 的详细归因数据：

### 时序要求

```
App 启动
    ↓
请求 ATT 授权 (ATTrackingManager.requestTrackingAuthorization)
    ↓
用户选择 "允许" 或 "拒绝"
    ↓
【此时才能调用 ASA 归因】
    ↓
asa.performAttribution()
    ↓
收到结果:
  - 用户授权 → detailed payload (包含 clickDate)
  - 用户拒绝 → standard payload (不含 clickDate)
```

### 注意事项

如果顺序反了：
```
asa.performAttribution()  ← 先调用 ASA
    ↓
请求 ATT 授权  ← 后请求授权
    ↓
结果：无论用户是否授权，都只能获得 standard payload ❌
```

### 示例伪代码

```gdscript
# 伪代码 - 实际 ATT 实现需要另外的插件或原生代码
func _ready():
    if OS.get_name() == "iOS":
        var att_status = yield(request_att_authorization(), "completed")
        
        # 无论授权与否，都可以请求 ASA
        request_asa_attribution()

func request_att_authorization():
    # 调用 iOS 的 ATTrackingManager
    # 返回: AUTHORIZED, DENIED, RESTRICTED, NOT_DETERMINED
    pass
```

## 数据上报示例

### 上报到自己的服务器

```gdscript
func _on_attribution_result(data: String, code: int, msg: String):
    if code != 200:
        return
    
    var json = JSON.parse(data)
    if json.error != OK:
        return
    
    var attribution = json.result
    
    # 仅当用户来自 ASA 时上报
    if attribution.get("attribution", false):
        send_to_server({
            "campaign_id": attribution.get("campaignId"),
            "ad_group_id": attribution.get("adGroupId"),
            "keyword_id": attribution.get("keywordId"),
            "country": attribution.get("countryOrRegion"),
            "conversion_type": attribution.get("conversionType"),
            "click_date": attribution.get("clickDate", ""),
            "device_id": OS.get_unique_id(),
            "timestamp": OS.get_unix_time()
        })

func send_to_server(data: Dictionary):
    var http = HTTPRequest.new()
    add_child(http)
    
    var headers = ["Content-Type: application/json"]
    var body = JSON.print(data)
    
    http.request("https://your-api.com/asa/attribution", headers, true, HTTPClient.METHOD_POST, body)
```

### 整合到现有分析 SDK

```gdscript
# 假设你有一个现有的分析系统
var Analytics = preload("res://analytics/analytics.gd").new()

func _on_attribution_result(data: String, code: int, msg: String):
    if code == 200:
        var json = JSON.parse(data)
        if json.error == OK:
            var attr = json.result
            
            # 作为用户属性上报
            if attr.get("attribution", false):
                Analytics.set_user_property("asa_campaign", attr.get("campaignId"))
                Analytics.set_user_property("asa_keyword", attr.get("keywordId"))
                Analytics.set_user_property("asa_country", attr.get("countryOrRegion"))
                
                # 作为事件上报
                Analytics.track_event("asa_attribution", {
                    "campaign_id": attr.get("campaignId"),
                    "conversion_type": attr.get("conversionType")
                })
```

## 错误处理完整示例

```gdscript
extends Node

var asa = null
var retry_count = 0
const MAX_RETRIES = 3
const RETRY_DELAY = 5.0

func _ready():
    if not Engine.has_singleton("Godot3ASA"):
        return
    
    asa = Engine.get_singleton("Godot3ASA")
    
    if not asa.isSupported():
        print("AdServices not supported")
        return
    
    asa.connect("onASAAttributionReceived", self, "_on_attribution")
    
    # 延迟后开始
    yield(get_tree().create_timer(1.0), "timeout")
    perform_attribution_with_retry()

func perform_attribution_with_retry():
    print("Requesting attribution (attempt ", retry_count + 1, ")")
    asa.performAttribution()

func _on_attribution(data: String, code: int, msg: String):
    match code:
        200:
            # 成功
            retry_count = 0
            handle_success(data)
        
        400:
            # Token 无效，不重试
            print("Invalid token, cannot retry")
            retry_count = 0
        
        404, 500:
            # 可重试的错误
            if retry_count < MAX_RETRIES:
                retry_count += 1
                print("Retrying after ", RETRY_DELAY, " seconds...")
                yield(get_tree().create_timer(RETRY_DELAY), "timeout")
                perform_attribution_with_retry()
            else:
                print("Max retries reached, giving up")
                retry_count = 0
        
        -1:
            # 网络错误
            print("Network error: ", msg)
            if retry_count < MAX_RETRIES:
                retry_count += 1
                yield(get_tree().create_timer(RETRY_DELAY), "timeout")
                perform_attribution_with_retry()
        
        -2:
            # 系统不支持
            print("System not supported: ", msg)
            retry_count = 0
        
        _:
            # 其他错误
            print("Unknown error: code=", code, " msg=", msg)
            retry_count = 0

func handle_success(data: String):
    var json = JSON.parse(data)
    if json.error != OK:
        print("JSON parse error")
        return
    
    var attribution = json.result
    
    if attribution.get("attribution", false):
        print("=== ASA Attribution Success ===")
        print("Campaign ID: ", attribution.get("campaignId"))
        print("Keyword ID: ", attribution.get("keywordId"))
        
        # 保存到本地
        save_attribution(attribution)
        
        # 上报到服务器
        upload_attribution(attribution)
    else:
        print("User is not from ASA")

func save_attribution(data: Dictionary):
    var file = File.new()
    file.open("user://asa_attribution.json", File.WRITE)
    file.store_string(JSON.print(data))
    file.close()

func upload_attribution(data: Dictionary):
    # 实现上报逻辑
    pass
```

## 测试清单

### 开发测试
- [ ] 插件编译成功
- [ ] Godot 项目能识别插件
- [ ] `isSupported()` 返回正确值
- [ ] 信号能正常触发
- [ ] 日志输出正常

### 功能测试
- [ ] iOS 14.3+ 设备能获取 token
- [ ] 能成功请求归因数据
- [ ] 错误处理正确（404、500 等）
- [ ] 重试机制工作正常
- [ ] 数据格式解析正确

### TestFlight 测试
- [ ] 通过 TestFlight 安装
- [ ] 返回测试数据 (`attribution: true`)
- [ ] 日志输出完整
- [ ] 性能表现良好（无卡顿）

## 常见问题

### Q: 编译失败，找不到 AdServices 框架
A: 确保使用 iOS 14.3+ 的 SDK，检查 Xcode 版本

### Q: 运行时提示 "Godot3ASA" singleton 不存在
A: 检查是否在导出设置中启用了插件

### Q: 一直返回 404 错误
A: 
- 检查网络连接
- 确认延迟时间足够（建议 500-1000ms）
- 查看 token 是否有效
- 实现重试机制（间隔 5 秒）

### Q: 如何在真机上测试？
A: 
1. 真实环境下，只有真正从 ASA 广告点击的用户才会返回 `attribution: true`
2. 建议使用 TestFlight 测试，会返回假数据方便调试
3. 可以通过 Xcode 查看完整日志

## 技术支持

- GitHub Issues: [项目地址]
- 文档: `plugins/godot3_asa/README.md`
- 示例项目: `examples/asa_demo/`
