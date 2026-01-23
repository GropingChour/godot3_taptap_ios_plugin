> **警告：** 此项目未经完全验证，请谨慎用于生产环境。

# Godot3 TapTap iOS 插件

TapTap SDK 集成插件，用于 Godot 3.x 在 iOS 平台。此插件将 TapTap 的登录、合规（防沉迷）和核心 SDK 功能包装为 Godot 单例，可从 GDScript 访问。

## 目录

- [功能](#功能)
- [限制](#限制)
- [SDK 组件](#sdk-组件)
- [要求](#要求)
- [快速开始](#快速开始)
  - [1. 安装](#1-安装)
  - [2. 配置](#2-配置)
  - [3. 导出设置](#3-导出设置)
  - [4. 使用示例](#4-使用示例)
- [iOS Swift 配置](#ios-swift-配置)
- [API 参考](#api-参考)
- [故障排除](#故障排除)
- [开发与构建](#开发与构建)
- [许可证](#许可证)
- [致谢](#致谢)

## 功能

- **TapTap 登录**：使用 TapTap 账户进行用户认证
  - 支持个人资料和好友范围授权
  - 检索用户资料（openId、unionId、姓名、头像）
  - 会话管理（登录/登出）

- **合规系统**（防沉迷）：
  - 中国法规要求的实名验证
  - 基于年龄的游戏时间限制
  - 自动合规检查

- **令牌加密**：
  - 基于 XOR 的客户端令牌加密
  - Godot 编辑器中的可视化配置工具
  - 安全密钥存储在 Info.plist 中

- **跨平台 API**：
  - 与 Android 版本统一的 GDScript API
  - 相同的方法签名和信号
  - 平台特定实现

## 限制

⚠️ **iOS 特定说明**：
- 许可证验证 SDK 不可用（使用 Android/服务器端）
- DLC 查询/购买 SDK 不可用（使用 Android/服务器端）
- IAP（应用内购买）不支持（直接使用 iOS StoreKit）

## SDK 组件

该插件包含以下 TapTap SDK 框架（v3.x）：
- TapTapLoginSDK - 用户认证
- TapTapComplianceSDK - 防沉迷系统
- TapTapCoreSDK - 核心功能
- TapTapBasicToolsSDK - 实用工具
- TapTapNetworkSDK - 网络层
- TapTapGidSDK - 全局标识符
- tapsdkcorecpp - C++ 桥接
- TapTapSDKBridgeCore - SDK 桥接
- THEMISLite - 加密库
- 资源包（登录和合规 UI）

## 要求

- iOS 12.0 或更高版本
- Xcode 14.0 或更高版本，支持 Swift
- **必须启用始终嵌入 Swift 标准库**（TapTap SDK 使用 Swift）

**注意：** iOS 插件仅在 iOS 上有效（物理设备或 Xcode 模拟器）。在 Godot 编辑器中运行项目时，其单例将不可用，因此您需要导出项目来测试更改。

## 快速开始

### 1. 安装

从 [Releases](https://github.com/GropingChour/godot3_taptap_ios_plugin/releases) 下载最新版本并解压到您的 Godot 项目中：

```
YourProject/
├── ios/
│   └── plugins/
│       └── godot3_taptap/
│           ├── godot3_taptap.gdip
│           ├── godot3_taptap.release.xcframework
│           ├── godot3_taptap.debug.xcframework
│           └── sdk/  (11 xcframeworks + 2 bundles)
└── addons/
    └── godot3_taptap/
        ├── plugin.cfg
        ├── taptap.gd
        ├── taptap_config_window.gd
        └── ...
```

### 2. 配置

1. 在 Godot 中启用插件：**项目 → 项目设置 → 插件 → Godot3 TapTap** ✓
2. 打开配置工具：**项目 → 工具 → TapTap 配置窗口**
3. 输入您的 TapTap 客户端 ID 和客户端令牌（来自 TapTap 开发者中心）
4. 点击 **生成安全密钥** 创建加密密钥
5. 点击 **保存 iOS 密钥到 .gdip** 将密钥存储在插件配置中

### 3. 导出设置

在 **项目 → 导出 → iOS** 中：
- 添加插件：在插件部分选中 **Godot3 TapTap**
- 加密密钥将自动合并到应用的 Info.plist 中
- **重要**：在 Xcode 项目设置中设置 **始终嵌入 Swift 标准库 = YES**（TapTap SDK 需要 Swift 运行时支持）

### 4. 使用示例

```gdscript
extends Node

func _ready():
    var taptap = Engine.get_singleton("Godot3TapTap")
    if taptap:
        # 使用加密令牌初始化 SDK
        taptap.initSdkWithEncryptedToken(
            "your_client_id", 
            "encrypted_token_from_config_tool",
            true,  # 启用日志
            false  # 无 IAP
        )
        
        # 连接信号
        taptap.connect("onLoginSuccess", self, "_on_login_success")
        taptap.connect("onComplianceResult", self, "_on_compliance_result")
        
        # 登录
        taptap.login(true, false)  # 带个人资料，无好友

func _on_login_success():
    var profile = taptap.getUserProfile()
    print("用户已登录：", profile)
    
    # 开始合规检查
    taptap.compliance()

func _on_compliance_result(code, info):
    print("合规结果：", code, " - ", info)
```

## iOS Swift 配置

基于 TapTap SDK 文档，确保您的 Xcode 项目中的以下 Swift 设置，以避免与 Swift 标准库相关的运行时错误：

### 构建设置配置

1. **始终嵌入 Swift 标准库**：
   - 在 Xcode 中，选择您的项目目标 → **构建设置** 选项卡
   - 搜索 "Always Embed Swift Standard Libraries"
   - 设置为 **YES** 以始终包含 Swift 标准库，防止启动错误如 "Unable to find Swift standard library"

2. **Swift 语言版本**：
   - 在 **构建设置** 中，在 **Swift Compiler - Language** 下，将 **Swift Language Version** 设置为 **Swift 5**

### 替代方案：添加虚拟 Swift 文件

如果上述设置无法解决问题，请添加一个虚拟 Swift 文件以强制正确的 Swift/Objective-C 桥接：

1. 在 Xcode 中：**文件 → 新建 → 文件 → Swift 文件**
2. 命名为 `Dummy.swift`（留空）
3. 提示时，点击 **创建** 以创建桥接头文件
4. 这会自动配置项目以进行 Swift 运行时链接

这些设置确保与 TapTap SDK 的兼容性，该 SDK 包含 Swift 组件。

## API 参考

有关完整的 API 文档，请参见 [addons/godot3_taptap/README.md](addons/godot3_taptap/README.md)。

## 故障排除

### Swift 兼容性库错误

如果您看到链接器错误如：
```
Undefined symbols for architecture arm64:
  "__swift_FORCE_LOAD_$_swiftCompatibility50"
  "__swift_FORCE_LOAD_$_swiftCompatibilityConcurrency"
```

**解决方案**：在您的 Xcode 项目中启用 Swift 支持：

1. 从 Godot 导出后，在 Xcode 中打开 `.xcodeproj`
2. 选择您的项目目标 → **构建设置** 选项卡
3. 搜索 "Always Embed Swift Standard Libraries"
4. 设置为 **YES**
5. 重新构建项目

**替代方案**：向您的项目添加虚拟 Swift 文件：
1. 在 Xcode 中：**文件 → 新建 → 文件 → Swift 文件**
2. 命名为 `Dummy.swift`，添加空内容
3. 提示创建桥接头文件时，点击 **创建**
4. 这会强制 Xcode 链接 Swift 运行时库

### 插件未找到

如果 `Engine.get_singleton("Godot3TapTap")` 返回 `null`：
- 验证插件在 **项目 → 导出 → iOS → 插件** 中已选中
- 确保 `ios/plugins/godot3_taptap/` 目录存在且包含所有文件
- 插件仅在导出版本中有效，不在 Godot 编辑器中

## 开发与构建

### 先决条件

- 使用子模块克隆此仓库：

```bash
git clone --recursive https://github.com/GropingChour/godot3_taptap_ios_plugin.git
```

### 生成 Godot 头文件（Godot 3.x）

```bash
cd godot
scons platform=iphone target=release_debug
```

生成头文件后，您可以停止（<kbd>Ctrl + C</kbd> 当编译开始时）。

### 构建插件二进制文件

- 运行以下命令为选定目标生成 `.a` 静态库：

```bash
scons target=<release_debug|release> arch=arm64 simulator=<no|yes> plugin=godot3_taptap version=3.x
```

**注意：** Godot 的官方 `debug` 导出模板使用 `release_debug`，而不是 `debug` 目标。

### 构建 XCFramework（推荐）

- 运行发布脚本来生成用于分发的 `xcframework`：

```bash
./scripts/release_xcframework.sh 3.x
```

这将：
- 为 arm64 设备 + arm64/x86_64 模拟器构建
- 创建 `.xcframework` 包（发布 + 调试）
- 在 `bin/release/godot3_taptap/` 中打包 SDK 依赖

结果包括：
- `godot3_taptap.release.xcframework`
- `godot3_taptap.debug.xcframework`
- `godot3_taptap.gdip`（插件清单）
- `sdk/` 目录（11 个 TapTap SDK 框架 + 2 个资源包）

## 许可证

MIT 许可证 - 详情请参见 [LICENSE](LICENSE) 文件。

## 致谢

- 基于 [Godot iOS Plugin Template](https://github.com/godotengine/godot-ios-plugins)
- TapTap SDK 由 [TapTap Developer Services](https://developer.taptap.cn/)
- 与 [godot3_taptap_android_plugin](https://github.com/GropingChour/godot3_taptap_android_plugin) 跨平台