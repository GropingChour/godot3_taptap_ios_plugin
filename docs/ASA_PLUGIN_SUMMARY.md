# Godot3 ASA 插件开发总结

## 插件概述

基于 Apple AdServices 框架实现的 Godot 3.x iOS ASA（Apple Search Ads）归因插件，完全在客户端完成归因，无需服务器端支持。

## 已完成的文件

### 核心插件文件

1. **godot3_asa.h** - C++ 头文件
   - 定义 `Godot3ASA` 类（继承自 `Object`）
   - 声明 4 个公共方法：
     - `requestAttributionToken()` - 获取 token
     - `requestAttributionData(token)` - 请求归因数据
     - `performAttribution()` - 一键完成归因（推荐）
     - `isSupported()` - 检查系统支持

2. **godot3_asa.mm** - Objective-C++ 实现文件
   - 实现 `GodotASADelegate` ObjC 类
   - 集成 AdServices 框架
   - 实现网络请求归因数据
   - 自动延迟处理（500ms）
   - 完整的错误处理
   - 通过信号异步返回结果

3. **godot3_asa_module.h/cpp** - 模块注册
   - 实现 `register_godot3_asa_types()` 函数
   - 实现 `unregister_godot3_asa_types()` 函数
   - 将插件注册为 Godot singleton

4. **godot3_asa.gdip** - 插件配置
   - 指定二进制文件：`godot3_asa.xcframework`
   - 链接系统框架：`AdServices.framework`
   - 指定初始化/反初始化函数

### 文档文件

5. **README.md** - 完整的使用文档（plugins/godot3_asa/）
   - API 接口说明
   - 信号详解
   - 使用示例
   - 最佳实践
   - 常见问题

6. **ASA_INTEGRATION.md** - 集成指南（docs/）
   - 编译步骤
   - 集成方法
   - 调用时机详解
   - ATT 集成说明
   - 数据上报示例
   - 错误处理完整示例
   - 测试清单

## 技术实现要点

### 1. 双层架构（ObjC + C++）

```
GDScript → Godot3ASA (C++) → GodotASADelegate (ObjC) → AdServices Framework
            ↓                        ↓
        emit_signal() ← 异步回调 ← NSURLSession
```

### 2. 符合 Apple 最佳实践

- ✅ 自动延迟 500ms（获取 token 和请求数据时）
- ✅ 异步网络请求（不阻塞主线程）
- ✅ 5 秒超时设置
- ✅ 详细的错误码处理
- ✅ 完整的日志输出

### 3. 简化的 API 设计

提供三种使用方式：
- **简单模式**（推荐）：`performAttribution()` 一键完成
- **手动模式**：分别调用 `requestAttributionToken()` + `requestAttributionData(token)`
- **检查模式**：`isSupported()` 检测系统支持

### 4. 信号机制

```gdscript
# Token 信号
onASATokenReceived(token: String, error_code: int, error_message: String)

# 归因数据信号
onASAAttributionReceived(attribution_data: String, error_code: int, error_message: String)
```

### 5. 完整的错误处理

| 错误码 | 说明 | 处理建议 |
|-------|------|---------|
| 0 | 成功 | 继续处理 |
| 200 | HTTP 成功 | 解析数据 |
| 400 | Token 无效 | 不重试 |
| 404 | 未找到/Token 过期 | 可重试（5秒间隔） |
| 500 | 服务器错误 | 可重试（5秒间隔） |
| -1 | 客户端错误 | 检查网络 |
| -2 | 系统不支持 | 不处理 |
| 2001 | 网络错误 | 可重试 |
| 2002 | 内部错误 | 可重试 |
| 2003 | 平台不支持 | 不处理 |

## 使用流程

### 最简使用（3 行代码）

```gdscript
var asa = Engine.get_singleton("Godot3ASA")
asa.connect("onASAAttributionReceived", self, "_on_attribution")
asa.performAttribution()
```

### 完整使用（含错误处理）

```gdscript
extends Node

func _ready():
    if Engine.has_singleton("Godot3ASA"):
        var asa = Engine.get_singleton("Godot3ASA")
        
        if asa.isSupported():
            asa.connect("onASAAttributionReceived", self, "_on_attribution")
            yield(get_tree().create_timer(1.0), "timeout")
            asa.performAttribution()

func _on_attribution(data: String, code: int, msg: String):
    if code == 200:
        var json = JSON.parse(data)
        if json.error == OK and json.result.get("attribution"):
            print("User from ASA campaign: ", json.result.get("campaignId"))
```

## 调用时机建议

根据 Apple 官方文档：

### ✅ 推荐时机
1. **App 首次启动时**（不是每次启动）
2. **获取网络权限后**延迟 500-1000ms
3. **如需 clickDate**：在 ATT 弹窗授权之后

### ❌ 不推荐
1. 每次启动都请求（浪费资源）
2. 立即调用（不符合最佳实践）
3. 同步阻塞（已异步实现）

## 编译说明

### 前提条件
- macOS 系统
- Xcode 12+（支持 iOS 14.3+ SDK）
- Python 3.x
- SCons 构建工具

### 编译步骤

```bash
# 1. 生成 Godot 头文件（首次）
./scripts/generate_headers.sh 3.x

# 2. 编译真机版本
scons target=release_debug arch=arm64 simulator=no plugin=godot3_asa version=3.x

# 3. 编译模拟器版本
scons target=release_debug arch=x86_64 simulator=yes plugin=godot3_asa version=3.x
scons target=release_debug arch=arm64 simulator=yes plugin=godot3_asa version=3.x

# 4. 生成 XCFramework
./scripts/generate_xcframework.sh godot3_asa 3.x
```

### 输出文件
```
bin/
├── godot3_asa.xcframework/
│   ├── Info.plist
│   ├── ios-arm64/              # 真机
│   │   └── godot3_asa.framework
│   └── ios-arm64_x86_64-simulator/  # 模拟器
│       └── godot3_asa.framework
```

## 与 Android 版本对比

| 特性 | iOS (本插件) | Android (参考) |
|-----|-------------|---------------|
| 框架 | AdServices | Google Play Billing / 自定义 |
| 归因方式 | 客户端 | 客户端/服务端 |
| 系统要求 | iOS 14.3+ | Android 5.0+ |
| 隐私 | 高（无需 IDFA） | 中等 |
| SDK 依赖 | 无（系统框架） | 需要第三方 SDK |
| Token 有效期 | 24 小时 | N/A |
| 数据详细度 | 取决于 ATT | 完整 |

## 已知限制

1. **仅支持 iOS 14.3+**
   - 低版本系统 `isSupported()` 返回 `false`
   - 不会影响 App 稳定性

2. **Token 有效期 24 小时**
   - 超过 24 小时会返回 404
   - 建议保存归因数据，避免重复请求

3. **ATT 授权影响数据详细度**
   - 授权前请求：可获得 `clickDate`
   - 授权后请求：无法获得 `clickDate`

4. **测试环境限制**
   - 真实环境下只有 ASA 广告用户才返回 `attribution: true`
   - TestFlight 会返回假数据方便测试

## 测试建议

### 开发阶段
- 使用 iOS 模拟器快速验证
- 通过日志检查流程
- 单元测试错误处理

### 集成测试
- 使用 TestFlight 分发
- 真机测试网络请求
- 验证数据格式

### 生产环境
- 监控成功率
- 实现降级策略
- 定期检查日志

## 后续优化方向

### 功能增强
- [ ] 添加本地缓存机制
- [ ] 自动重试配置选项
- [ ] 支持批量上报到服务器
- [ ] 提供 GDScript 包装类

### 性能优化
- [ ] 优化网络请求超时时间
- [ ] 减少内存占用
- [ ] 改进错误恢复机制

### 文档完善
- [ ] 添加视频教程
- [ ] 提供示例项目
- [ ] 多语言文档支持

## 参考资料

### Apple 官方文档
- [AdServices Framework](https://developer.apple.com/documentation/adservices/)
- [Apple Ads Attribution API](https://ads.apple.com/cn/help/advanced/0028-apple-ads-attribution-api/)
- [App Tracking Transparency](https://developer.apple.com/app-store/user-privacy-and-data-use/)

### Godot 插件开发
- [iOS Plugins Guide](https://docs.godotengine.org/en/stable/tutorials/platform/ios/plugins_for_ios.html)
- [官方插件示例](https://github.com/godot-sdk-integrations/godot-ios-plugins)

### 相关项目
- [godot3_taptap_ios_plugin](https://github.com/GropingChour/godot3_taptap_ios_plugin)（本项目）
- [godot3_taptap_android_plugin](https://github.com/GropingChour/godot3_taptap_android_plugin)（Android 版本）

## 总结

本插件完全遵循：
- ✅ Godot iOS 插件架构模式
- ✅ Apple ASA 归因最佳实践
- ✅ 客户端归因实现方案
- ✅ 完整的错误处理机制
- ✅ 详细的使用文档

所有接口都已实现并可直接使用，无需服务器端支持即可完成 ASA 归因。
