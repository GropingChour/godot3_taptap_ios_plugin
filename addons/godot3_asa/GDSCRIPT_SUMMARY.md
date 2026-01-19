# ASA 插件 GDScript 层开发完成总结

## 📦 已创建的文件

### 插件核心文件

1. **[plugin.cfg](plugin.cfg)** - 插件配置文件
   - 定义插件名称、版本、描述
   - 指定 `plugin.gd` 为插件脚本

2. **[plugin.gd](plugin.gd)** - 插件注册脚本
   - 注册 `ASA` 全局单例
   - 在编辑器启动时自动加载

3. **[asa.gd](asa.gd)** - 主 API 封装（⭐核心文件）
   - ASA 归因功能封装
   - AppSA 数据上报功能
   - 完整的信号系统
   - 数据持久化支持

### 示例和文档

4. **[example/asa_example.gd](example/asa_example.gd)** - 基础使用示例
   - 配置化的示例节点
   - 演示基础归因和上报流程
   - 包含测试方法

5. **[README_GDSCRIPT.md](README_GDSCRIPT.md)** - GDScript 层完整文档
   - API 详细说明
   - 使用示例
   - 最佳实践
   - 常见问题

6. **[example/FULL_INTEGRATION_EXAMPLE.md](example/FULL_INTEGRATION_EXAMPLE.md)** - 完整集成示例
   - 真实项目集成方案
   - 包含游戏管理器、主菜单、商城、留存统计
   - 完整的代码示例

## 🎯 核心功能

### ASA 归因

```gdscript
# 最简使用
ASA.connect("onASAAttributionReceived", self, "_on_attribution")
yield(get_tree().create_timer(1.0), "timeout")
ASA.perform_attribution()
```

**功能：**
- ✅ 一键归因 `perform_attribution()`
- ✅ 系统支持检查 `is_supported()`
- ✅ 数据缓存 `get_attribution_data()`
- ✅ 用户来源判断 `is_from_asa()`

### AppSA 数据上报

#### 激活上报

```gdscript
ASA.set_appsa_from_key("your_key")
ASA.report_activation("游戏名称")
```

#### 事件上报（按次）

```gdscript
ASA.report_register()                      # 注册
ASA.report_login()                         # 登录
ASA.report_revenue(99.99, "USD")          # 收入
ASA.report_pay_unique_user()              # 付费用户数
ASA.report_retention_day1_instant()       # 1日留存
```

#### 事件上报（汇总）

```gdscript
ASA.report_retention_day1_summary(150, "2026-01-19")  # 1日留存汇总
ASA.report_retention_day3_summary(120, "2026-01-19")  # 3日留存汇总
ASA.report_retention_day7_summary(100, "2026-01-19")  # 7日留存汇总
```

### 数据持久化

```gdscript
ASA.save_attribution_data()               # 保存
ASA.load_attribution_data()               # 加载
ASA.has_attribution_data()                # 检查
```

## 📊 数据流程

### 归因数据流

```
iOS 原生层 (Godot3ASA)
    ↓ emit_signal("onASAAttributionReceived")
GDScript 单例 (ASA)
    ↓ 解析 JSON，缓存数据
    ↓ emit_signal("onASAAttributionReceived")
游戏代码
    ↓ 处理归因结果
    ↓ 调用 ASA.report_activation()
AppSA 服务器
```

### 事件上报流

```
游戏事件发生
    ↓
检查用户来源 (is_from_asa())
    ↓ true
调用 ASA.report_xxx()
    ↓
构建数据 + HTTP 请求
    ↓
AppSA API
    ↓
返回结果
    ↓
emit_signal("onAppSAReportSuccess/Failed")
```

## 🎨 架构设计

### 三层架构

```
┌─────────────────────────────────────┐
│   游戏逻辑层                          │
│   - GameManager (归因管理)           │
│   - MainMenu (注册/登录)             │
│   - Shop (付费)                      │
│   - DailyTaskManager (留存)         │
└────────────┬────────────────────────┘
             │ 调用 ASA.xxx()
┌────────────▼────────────────────────┐
│   GDScript 封装层 (asa.gd)          │
│   - 归因功能封装                      │
│   - AppSA 数据上报                   │
│   - HTTP 请求处理                    │
│   - 信号系统                         │
└────────────┬────────────────────────┘
             │ Engine.get_singleton()
┌────────────▼────────────────────────┐
│   iOS 原生层 (godot3_asa.mm)        │
│   - AdServices 集成                  │
│   - Token 获取                       │
│   - 网络请求                         │
└─────────────────────────────────────┘
```

### 信号系统

```
原生层信号                GDScript 信号
onASAAttributionReceived  →  onASAAttributionReceived
                          ↓  解析数据，缓存
                          
HTTP 请求完成             →  onAppSAReportSuccess
                          →  onAppSAReportFailed
```

## 🔧 关键设计决策

### 1. 单例模式

- 使用 Godot 的 autoload 系统
- 全局访问：`ASA.xxx()`
- 自动初始化，无需手动创建

### 2. 信号驱动

- 异步操作通过信号回调
- 解耦游戏逻辑和插件代码
- 便于错误处理和状态跟踪

### 3. 数据缓存

- 归因数据内存缓存（`attribution_data`）
- 文件持久化（`user://asa_attribution.json`）
- 避免重复网络请求

### 4. 配置管理

- 使用 `ConfigFile` 管理状态
- 标记归因完成、激活上报等
- 支持重置用于测试

### 5. 错误处理

- HTTP 请求错误处理
- JSON 解析错误处理
- 详细的日志输出
- 通过信号反馈错误

## 📝 使用示例对比

### 基础使用（最简）

```gdscript
# 3 行代码完成归因
ASA.set_appsa_from_key("key")
ASA.connect("onASAAttributionReceived", self, "_on_attr")
ASA.perform_attribution()
```

### 标准使用（推荐）

```gdscript
# 带检查和延迟
if ASA.is_supported():
    ASA.set_appsa_from_key("key")
    ASA.connect("onASAAttributionReceived", self, "_on_attr")
    yield(get_tree().create_timer(1.0), "timeout")
    ASA.perform_attribution()
```

### 生产使用（完整）

```gdscript
# 参考 example/FULL_INTEGRATION_EXAMPLE.md
# 包含：
# - 首次启动检查
# - 配置文件管理
# - 错误重试
# - 数据持久化
# - 完整的事件上报
```

## ✅ 与 AppSA 接口文档对照

### 激活回传

| AppSA 字段 | 实现方式 |
|-----------|---------|
| install_time | `OS.get_unix_time() * 1000` |
| device_model | `_get_device_info().model` |
| os_version | `_get_device_info().os_version` |
| app_name | 参数传入或从 ProjectSettings 获取 |
| attribution | 归因数据 `attribution` |
| org_id | 归因数据 `orgId` |
| campaign_id | 归因数据 `campaignId` |
| adgroup_id | 归因数据 `adGroupId` |
| keyword_id | 归因数据 `keywordId` |
| creativeset_id | 归因数据 `adId` |
| conversion_type | 归因数据 `conversionType` |
| country_or_region | 归因数据 `countryOrRegion` |
| click_date | 归因数据 `clickDate` |
| source_from | 固定 `"ads"` |
| claim_type | 归因数据 `claimType` |

### 应用内事件回传

| 事件类型 | 实现方法 |
|---------|---------|
| asa_register | `report_register()` |
| asa_login | `report_login()` |
| asa_revenue | `report_revenue(amount, currency)` |
| asa_pay_unique_user | `report_pay_unique_user()` |
| asa_pay_device | `report_pay_device()` |
| asa_retention_day1 | `report_retention_day1_instant()` |
| asa_retention_day3 | `report_retention_day3_instant()` |
| asa_retention_day7 | `report_retention_day7_instant()` |
| asa_retention_day1 (汇总) | `report_retention_day1_summary(amount, date)` |
| asa_retention_day3 (汇总) | `report_retention_day3_summary(amount, date)` |
| asa_retention_day7 (汇总) | `report_retention_day7_summary(amount, date)` |

## 🎯 最佳实践检查清单

- [x] 仅首次启动时归因
- [x] 延迟 500-1000ms 后归因
- [x] 保存归因数据到本地
- [x] 检查用户来源再上报
- [x] 设置 AppSA from_key
- [x] 实现错误重试机制
- [x] 详细的日志输出
- [x] 信号驱动的异步设计
- [x] 配置文件管理状态
- [x] 完整的文档和示例

## 🚀 下一步

### 开发者需要做的：

1. **配置 from_key**
   ```gdscript
   ASA.set_appsa_from_key("your_key_from_qimai")
   ```

2. **在游戏管理器中集成**
   - 参考 `example/FULL_INTEGRATION_EXAMPLE.md`
   - 复制 `GameManager` 代码
   - 调整为自己的项目结构

3. **在用户行为处中添加上报**
   ```gdscript
   # 注册成功后
   ASA.report_register()
   
   # 登录成功后
   ASA.report_login()
   
   # 付费成功后
   ASA.report_revenue(amount, currency)
   ```

4. **测试**
   - 使用 TestFlight 测试归因
   - 验证 AppSA 后台数据
   - 检查日志输出

## 📚 文档索引

- **插件开发文档**：`plugins/godot3_asa/README.md`
- **GDScript API 文档**：`addons/godot3_asa/README_GDSCRIPT.md`
- **集成指南**：`docs/ASA_INTEGRATION.md`
- **完整示例**：`addons/godot3_asa/example/FULL_INTEGRATION_EXAMPLE.md`
- **快速开始**：`plugins/godot3_asa/QUICKSTART.md`

## 🎉 完成情况

✅ **iOS 原生层**（已完成）
- AdServices 框架集成
- Token 获取和归因数据请求
- 信号系统

✅ **GDScript 封装层**（已完成）
- 归因功能封装
- AppSA 数据上报
- HTTP 请求处理
- 数据持久化

✅ **文档和示例**（已完成）
- 完整的 API 文档
- 基础使用示例
- 完整集成示例
- 最佳实践指南

✅ **AppSA 接口对接**（已完成）
- 激活回传
- 11 种事件上报（按次 + 汇总）
- 完全符合接口文档

---

所有功能已完整实现，可以直接在项目中使用！ 🎊
