# ASA 插件 GDScript 层使用指南

## 文件结构

```
addons/godot3_asa/
├── plugin.cfg          # 插件配置
├── plugin.gd           # 插件注册脚本
├── asa.gd              # 主要 API 封装（自动加载为 ASA 单例）
├── example/
│   └── asa_example.gd  # 完整使用示例
└── README_GDSCRIPT.md  # 本文档
```

## 快速开始

### 1. 启用插件

在 Godot 编辑器中：
1. **项目 → 项目设置 → 插件**
2. 勾选 **Godot3ASA**

插件会自动注册一个名为 `ASA` 的全局单例。

### 2. 基础使用

```gdscript
extends Node

func _ready():
    # 设置 AppSA from 参数（由七麦提供）
    ASA.set_appsa_from_key("your_from_key")
    
    # 连接信号
    ASA.connect("onASAAttributionReceived", self, "_on_attribution")
    
    # 检查系统支持
    if ASA.is_supported():
        # 延迟后执行归因
        yield(get_tree().create_timer(1.0), "timeout")
        ASA.perform_attribution()

func _on_attribution(data: String, code: int, message: String):
    if code == 200:
        # 归因成功，保存数据
        ASA.save_attribution_data()
        
        # 如果用户来自 ASA，上报激活
        if ASA.is_from_asa():
            ASA.report_activation()
```

## API 文档

### 归因方法

#### `perform_attribution()`
执行 ASA 归因（推荐使用）

**建议调用时机：**
- App 首次启动时
- 获取网络权限后
- 延迟 500-1000ms

```gdscript
# 首次启动检查
if is_first_launch():
    yield(get_tree().create_timer(1.0), "timeout")
    ASA.perform_attribution()
```

#### `is_supported() -> bool`
检查设备是否支持 ASA（iOS 14.3+）

```gdscript
if ASA.is_supported():
    print("ASA is supported")
```

#### `get_attribution_data() -> Dictionary`
获取缓存的归因数据

```gdscript
var data = ASA.get_attribution_data()
print("Campaign ID: ", data.get("campaignId", ""))
```

#### `is_from_asa() -> bool`
检查用户是否来自 ASA 广告

```gdscript
if ASA.is_from_asa():
    print("User came from ASA")
```

### AppSA 上报方法

#### 激活上报

```gdscript
# 设置 from 参数（必须）
ASA.set_appsa_from_key("your_from_key")

# 上报激活
ASA.report_activation("你的应用名称")
```

#### 事件上报（按次）

**注册事件：**
```gdscript
ASA.report_register()
```

**登录事件：**
```gdscript
ASA.report_login()
```

**收入事件：**
```gdscript
# 参数：金额, 货币类型
ASA.report_revenue(99.99, "USD")
ASA.report_revenue(648.0, "RMB")
```

**付费用户数：**
```gdscript
# 注意：需要客户端自己做排重
ASA.report_pay_unique_user()
```

**付费设备数：**
```gdscript
# 注意：需要客户端自己做排重
ASA.report_pay_device()
```

**留存事件（按次）：**
```gdscript
ASA.report_retention_day1_instant()
ASA.report_retention_day3_instant()
ASA.report_retention_day7_instant()
```

#### 事件上报（汇总）

**留存汇总：**
```gdscript
# 参数：用户数量, 日期（YYYY-MM-DD）
ASA.report_retention_day1_summary(150, "2026-01-19")
ASA.report_retention_day3_summary(120, "2026-01-19")
ASA.report_retention_day7_summary(100, "2026-01-19")
```

### 数据持久化

**保存归因数据：**
```gdscript
if ASA.save_attribution_data():
    print("Attribution data saved")
```

**加载归因数据：**
```gdscript
if ASA.load_attribution_data():
    print("Attribution data loaded")
```

**检查是否有数据：**
```gdscript
if ASA.has_attribution_data():
    print("Has attribution data")
```

### 信号

#### `onASAAttributionReceived(data: String, code: int, message: String)`
归因完成信号

**参数：**
- `data`: JSON 格式的归因数据
- `code`: 状态码（200 表示成功）
- `message`: 错误信息（成功时为空）

```gdscript
ASA.connect("onASAAttributionReceived", self, "_on_attribution")

func _on_attribution(data: String, code: int, message: String):
    if code == 200:
        var json = JSON.parse(data)
        if json.error == OK:
            var attr = json.result
            print("Campaign ID: ", attr.campaignId)
```

#### `onAppSAReportSuccess(response: Dictionary)`
AppSA 上报成功信号

```gdscript
ASA.connect("onAppSAReportSuccess", self, "_on_report_success")

func _on_report_success(response: Dictionary):
    print("Report success: ", response)
```

#### `onAppSAReportFailed(error_message: String)`
AppSA 上报失败信号

```gdscript
ASA.connect("onAppSAReportFailed", self, "_on_report_failed")

func _on_report_failed(error: String):
    print("Report failed: ", error)
```

## 完整使用流程

### 1. 首次启动归因和上报

```gdscript
extends Node

const ASA_KEY = "asa_completed"
var config = ConfigFile.new()

func _ready():
    config.load("user://app.cfg")
    
    # 设置 AppSA from 参数
    ASA.set_appsa_from_key("your_from_key")
    
    # 连接信号
    ASA.connect("onASAAttributionReceived", self, "_on_attribution")
    ASA.connect("onAppSAReportSuccess", self, "_on_report_success")
    
    # 检查是否首次启动
    if not config.get_value("app", ASA_KEY, false):
        start_attribution()

func start_attribution():
    if not ASA.is_supported():
        print("ASA not supported")
        return
    
    # 延迟 1 秒后归因
    yield(get_tree().create_timer(1.0), "timeout")
    ASA.perform_attribution()

func _on_attribution(data: String, code: int, msg: String):
    if code == 200:
        # 保存归因数据
        ASA.save_attribution_data()
        
        # 如果来自 ASA，上报激活
        if ASA.is_from_asa():
            ASA.report_activation()
        
        # 标记完成
        config.set_value("app", ASA_KEY, true)
        config.save("user://app.cfg")

func _on_report_success(response: Dictionary):
    print("Activation reported successfully")
```

### 2. 用户行为上报

```gdscript
# 在玩家管理类中
class_name PlayerManager
extends Node

func on_player_register(username: String):
    # 玩家注册成功后
    print("Player registered: ", username)
    ASA.report_register()

func on_player_login(username: String):
    # 玩家登录成功后
    print("Player logged in: ", username)
    ASA.report_login()

func on_player_purchase(item_id: String, price: float, currency: String):
    # 玩家购买成功后
    print("Player purchased: ", item_id, " for ", price, " ", currency)
    ASA.report_revenue(price, currency)
```

### 3. 每日留存统计上报

```gdscript
# 在游戏管理类中
class_name GameManager
extends Node

func calculate_and_report_retention():
    """每日定时任务：计算并上报留存数据"""
    var date = get_today_date()  # "YYYY-MM-DD"
    
    # 统计各天留存用户数（需要自己实现统计逻辑）
    var day1_users = count_day1_retention_users()
    var day3_users = count_day3_retention_users()
    var day7_users = count_day7_retention_users()
    
    # 上报汇总数据
    if day1_users > 0:
        ASA.report_retention_day1_summary(day1_users, date)
    
    if day3_users > 0:
        ASA.report_retention_day3_summary(day3_users, date)
    
    if day7_users > 0:
        ASA.report_retention_day7_summary(day7_users, date)

func get_today_date() -> String:
    var dt = OS.get_datetime()
    return "%04d-%02d-%02d" % [dt.year, dt.month, dt.day]
```

## 使用示例节点

插件提供了完整的示例节点：`addons/godot3_asa/example/asa_example.gd`

**使用方法：**
1. 创建一个新节点
2. 附加 `asa_example.gd` 脚本
3. 在检查器中配置 `appsa_from_key`
4. 运行测试

**配置参数：**
- `appsa_from_key`: AppSA from 参数（必填）
- `auto_attribution`: 是否自动归因
- `attribution_delay`: 归因延迟时间（秒）
- `auto_report_activation`: 是否自动上报激活
- `save_attribution`: 是否保存归因数据

## 注意事项

### ✅ 最佳实践

1. **仅首次启动归因**
   ```gdscript
   if is_first_launch():
       ASA.perform_attribution()
   ```

2. **延迟调用**
   ```gdscript
   yield(get_tree().create_timer(1.0), "timeout")
   ASA.perform_attribution()
   ```

3. **保存归因数据**
   ```gdscript
   ASA.save_attribution_data()
   ```

4. **检查用户来源**
   ```gdscript
   if ASA.is_from_asa():
       # 只有 ASA 用户才上报
   ```

5. **设置 from 参数**
   ```gdscript
   ASA.set_appsa_from_key("your_key")  # 必须在上报前设置
   ```

### ❌ 常见错误

1. ❌ 每次启动都归因
2. ❌ 立即调用（不延迟）
3. ❌ 忘记设置 `from_key`
4. ❌ 在非 ASA 用户上上报
5. ❌ 不保存归因数据

## 调试技巧

### 查看日志

```gdscript
# 启用详细日志
OS.set_debug_generation(true)

# 归因时查看控制台输出
ASA.perform_attribution()
# 输出：
# [ASA] Performing attribution...
# [ASA] Attribution received: code=200
# [ASA] Attribution Success!
```

### 测试归因

```gdscript
# 重置归因标记（用于测试）
func reset_for_testing():
    var config = ConfigFile.new()
    config.load("user://app.cfg")
    config.set_value("app", "asa_completed", false)
    config.save("user://app.cfg")
    
    # 删除缓存数据
    var dir = Directory.new()
    dir.remove("user://asa_attribution.json")
```

### 模拟归因数据

```gdscript
# 用于测试 AppSA 上报（不实际归因）
func simulate_attribution():
    ASA.attribution_data = {
        "attribution": true,
        "orgId": 40669820,
        "campaignId": 542370539,
        "adGroupId": 542317095,
        "keywordId": 87675432,
        "countryOrRegion": "US",
        "conversionType": "Download",
        "claimType": "Click"
    }
    ASA.is_attributed = true
```

## 常见问题

**Q: 如何知道归因是否成功？**

A: 监听 `onASAAttributionReceived` 信号，检查 `code == 200`

**Q: 什么时候上报激活？**

A: 归因成功且 `is_from_asa()` 返回 `true` 时

**Q: 如何避免重复上报？**

A: 保存归因标记，只在首次启动时归因和上报

**Q: 留存事件应该什么时候上报？**

A: 
- 按次上报：用户每次满足留存条件时立即上报
- 汇总上报：每天统计后上报一次（新数据覆盖旧数据）

**Q: 为什么上报失败？**

A: 检查：
1. 是否设置了 `from_key`
2. 用户是否来自 ASA（`is_from_asa()`）
3. 网络连接是否正常
4. 归因数据是否完整

## 技术支持

- 插件文档：`plugins/godot3_asa/README.md`
- 集成指南：`docs/ASA_INTEGRATION.md`
- 示例代码：`addons/godot3_asa/example/asa_example.gd`
