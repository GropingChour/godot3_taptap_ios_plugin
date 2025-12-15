# TapTap iOS SDK 放置说明

## 目录结构
将从 TapTap 开发者中心下载的 iOS SDK 框架文件放置在此目录下。

## 下载地址
https://developer.taptap.cn/docs/tap-download/

## 所需框架列表（v4.9.2）

### 核心模块框架
```
sdk/
├── THEMISLite.xcframework              # 加密库
├── TapTapBasicToolsSDK.xcframework     # 基础工具
├── TapTapCoreSDK.xcframework           # 核心 SDK
├── TapTapGidSDK.xcframework            # 游戏 ID
├── TapTapNetworkSDK.xcframework        # 网络层
├── tapsdkcorecpp.xcframework           # C++ 核心
└── TapTapSDKBridgeCore.xcframework     # 桥接核心
```

### 登录模块
```
sdk/
├── TapTapLoginSDK.xcframework          # 登录功能
└── TapTapLoginResource.bundle          # 登录资源包
```

### 防沉迷模块
```
sdk/
├── TapTapComplianceSDK.xcframework     # 防沉迷功能
└── TapTapComplianceResource.bundle     # 防沉迷资源包
```

### 正版验证模块
```
sdk/
└── TapTapLicenseSDK.xcframework        # 正版验证
```

## 下载步骤

1. 访问 TapTap 开发者中心：https://developer.taptap.cn/docs/tap-download/
2. 找到 **iOS SDK v4.9.2** 部分
3. 下载以下模块：
   - 基础库（必需）：包含 7 个核心 xcframework
   - 内建账户（必需）：包含 TapTapLoginSDK + 资源包
   - 合规认证（可选）：包含 TapTapComplianceSDK + 资源包
   - 正版验证（可选）：包含 TapTapLicenseSDK
4. 解压后将所有 `.xcframework` 和 `.bundle` 文件复制到本目录

## 验证
确保以下文件存在：
- [ ] THEMISLite.xcframework
- [ ] TapTapBasicToolsSDK.xcframework
- [ ] TapTapCoreSDK.xcframework
- [ ] TapTapGidSDK.xcframework
- [ ] TapTapNetworkSDK.xcframework
- [ ] tapsdkcorecpp.xcframework
- [ ] TapTapSDKBridgeCore.xcframework
- [ ] TapTapLoginSDK.xcframework
- [ ] TapTapLoginResource.bundle
- [ ] TapTapComplianceSDK.xcframework
- [ ] TapTapComplianceResource.bundle
- [ ] TapTapLicenseSDK.xcframework

## 构建说明
放置完成后，可以使用以下命令构建插件：
```bash
scons target=release_debug arch=arm64 simulator=no plugin=godot3taptap version=3.x
```

## 注意事项
- 确保下载的 SDK 版本为 **v4.9.2** 或兼容版本
- xcframework 包含多架构支持（arm64, x86_64）
- bundle 文件包含 UI 资源，不可缺少
- 如果不需要某些功能（如防沉迷、正版验证），可以不下载对应模块，但需要修改 `godot3taptap.gdip` 配置
