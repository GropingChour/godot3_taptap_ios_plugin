# Godot3 ASA 插件 - 快速开始

## 概述

本插件为 Godot 3.x iOS 平台提供 Apple Search Ads (ASA) 归因功能，基于 AdServices 框架实现客户端归因。

## 核心功能

✅ **自动化归因** - 一键完成 token 获取和数据请求  
✅ **客户端实现** - 无需服务器端支持  
✅ **完整错误处理** - 详细的错误码和重试机制  
✅ **符合最佳实践** - 遵循 Apple 官方建议  

## 快速使用（3 步）

### 1. 在 Godot 中启用插件

导出设置 → iOS → 插件 → 勾选 `Godot3ASA`

### 2. 添加代码

```gdscript
extends Node

func _ready():
    var asa = Engine.get_singleton("Godot3ASA")
    if asa and asa.isSupported():
        asa.connect("onASAAttributionReceived", self, "_on_attribution")
        # 延迟 1 秒后执行
        yield(get_tree().create_timer(1.0), "timeout")
        asa.performAttribution()

func _on_attribution(data: String, code: int, msg: String):
    if code == 200:
        print("归因成功: ", data)
        # 解析和处理数据
        var json = JSON.parse(data)
        if json.error == OK:
            var attr = json.result
            if attr.get("attribution"):
                print("用户来自 ASA 广告")
                print("广告系列 ID: ", attr.get("campaignId"))
    else:
        print("归因失败: ", msg)
```

### 3. 导出并测试

通过 Xcode 或 TestFlight 安装到设备上测试。

## 完整 API

### 方法

| 方法 | 说明 |
|-----|------|
| `performAttribution()` | **推荐** - 一键完成归因 |
| `requestAttributionToken()` | 手动获取 token |
| `requestAttributionData(token)` | 手动请求归因数据 |
| `isSupported()` | 检查系统是否支持（iOS 14.3+） |

### 信号

**onASAAttributionReceived(data: String, code: int, msg: String)**

| 参数 | 说明 |
|-----|------|
| `data` | JSON 格式的归因数据 |
| `code` | 状态码（200=成功） |
| `msg` | 错误信息 |

**归因数据示例：**
```json
{
  "attribution": true,
  "campaignId": 542370539,
  "adGroupId": 542317095,
  "keywordId": 87675432,
  "countryOrRegion": "US",
  "conversionType": "Download",
  "clickDate": "2024-10-08T17:17Z"
}
```

## 重要提示

### ✅ 应该这样做

1. **仅首次启动时请求**（不是每次启动）
2. **延迟 500-1000ms** 后调用
3. **保存结果到本地**，避免重复请求
4. **实现重试机制**（404/500 错误）

### ❌ 不要这样做

1. ❌ 每次启动都请求
2. ❌ 立即调用（应延迟）
3. ❌ 400 错误后重试（token 无效）

## 调用时机

```
App 启动
    ↓
检查是否首次启动？
    ↓ 是
获取网络权限
    ↓
延迟 1 秒
    ↓
asa.performAttribution()
    ↓
收到信号
    ↓
保存数据
    ↓
标记已完成
```

## 示例：仅首次启动时请求

```gdscript
const ASA_KEY = "asa_requested"

func _ready():
    if not has_asa_requested():
        request_asa_attribution()

func has_asa_requested() -> bool:
    var config = ConfigFile.new()
    config.load("user://app_config.cfg")
    return config.get_value("app", ASA_KEY, false)

func mark_asa_requested():
    var config = ConfigFile.new()
    config.load("user://app_config.cfg")
    config.set_value("app", ASA_KEY, true)
    config.save("user://app_config.cfg")

func request_asa_attribution():
    var asa = Engine.get_singleton("Godot3ASA")
    if asa and asa.isSupported():
        asa.connect("onASAAttributionReceived", self, "_on_asa_result")
        yield(get_tree().create_timer(1.0), "timeout")
        asa.performAttribution()

func _on_asa_result(data: String, code: int, msg: String):
    if code == 200:
        save_attribution_data(data)
        mark_asa_requested()
        print("ASA 归因完成")
```

## 错误处理示例

```gdscript
var retry_count = 0
const MAX_RETRIES = 3

func _on_asa_result(data: String, code: int, msg: String):
    match code:
        200:
            # 成功
            handle_success(data)
            retry_count = 0
        
        404, 500:
            # 可重试
            if retry_count < MAX_RETRIES:
                retry_count += 1
                print("重试中... (", retry_count, "/", MAX_RETRIES, ")")
                yield(get_tree().create_timer(5.0), "timeout")
                asa.performAttribution()
            else:
                print("达到最大重试次数")
        
        400:
            # Token 无效，不重试
            print("Token 无效")
        
        _:
            print("其他错误: ", msg)
```

## 测试方法

### 开发测试
1. 使用 iOS 模拟器
2. 检查日志输出
3. 验证信号触发

### TestFlight 测试
1. 通过 TestFlight 安装
2. 会返回测试数据 (`attribution: true`)
3. 验证完整流程

### 真实环境
只有从 ASA 广告点击的用户才会返回 `attribution: true`

## 常见问题

**Q: 如何检查插件是否正常工作？**

A: 查看 Xcode 控制台日志：
```
[ASA] Godot3ASA plugin initialized
[ASA] Token received successfully, length: 512
[ASA] Requesting attribution data...
[ASA] Attribution data received: {...}
```

**Q: 一直返回 404 错误？**

A: 
- 确保延迟足够（建议 1 秒）
- 实现重试机制（间隔 5 秒）
- 检查网络连接

**Q: 如何获得包含 clickDate 的详细数据？**

A: 在调用 ASA 归因之前，先通过 ATT 弹窗获得用户授权

**Q: 可以在编辑器中测试吗？**

A: 不可以，必须在 iOS 设备或模拟器上测试

## 更多信息

- 📖 **完整文档**: `plugins/godot3_asa/README.md`
- 🔧 **集成指南**: `docs/ASA_INTEGRATION.md`
- 📝 **开发总结**: `docs/ASA_PLUGIN_SUMMARY.md`

## 技术支持

如遇问题：
1. 检查 Xcode 日志
2. 查看完整文档
3. 提交 GitHub Issue

---

**最简示例（3 行代码）：**

```gdscript
var asa = Engine.get_singleton("Godot3ASA")
asa.connect("onASAAttributionReceived", self, "_on_attribution")
yield(get_tree().create_timer(1.0), "timeout"); asa.performAttribution()
```

就这么简单！🎉
