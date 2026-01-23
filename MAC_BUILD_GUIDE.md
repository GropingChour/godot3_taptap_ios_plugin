# Mac 本地编译指南

本指南说明如何在 macOS 上本地编译 godot3_taptap 和 godot3_asa 插件。

## 环境要求

### 必需软件
- **macOS**: 12.0 (Monterey) 或更高版本
- **Xcode**: 14.0 或更高版本
  - 安装完整的 Xcode（不是仅 Command Line Tools）
  - 打开 Xcode 一次以完成组件安装
- **Python**: 3.8-3.11
- **SCons**: 构建工具

### 安装依赖

```bash
# 安装 Xcode Command Line Tools（如果尚未安装）
xcode-select --install

# 安装 Python（使用 Homebrew）
brew install python@3.11

# 安装 SCons
pip3 install scons
```

## 克隆仓库

```bash
# 克隆主仓库（包含子模块）
git clone --recursive https://github.com/GropingChour/godot3_taptap_ios_plugin.git
cd godot3_taptap_ios_plugin

# 如果已克隆但未包含子模块，执行：
git submodule update --init --recursive
```

## 编译步骤

### 1. 生成 Godot 头文件（首次编译必需）

```bash
# 生成 iOS 平台的 Godot 头文件
./scripts/generate_headers.sh 3.x
```

**说明**: 这个脚本会编译 Godot 引擎，并生成插件需要的头文件。这个过程只需执行一次，除非 Godot 版本更新。

### 2. 编译单个插件（开发调试）

#### 编译 godot3_taptap

```bash
# 编译 ARM64 设备版本（真机）
scons target=release_debug arch=arm64 simulator=no plugin=godot3taptap version=3.x

# 编译 ARM64 模拟器版本
scons target=release_debug arch=arm64 simulator=yes plugin=godot3taptap version=3.x

# 编译 x86_64 模拟器版本（Intel Mac 模拟器）
scons target=release_debug arch=x86_64 simulator=yes plugin=godot3taptap version=3.x
```

#### 编译 godot3_asa

```bash
# 编译 ARM64 设备版本（真机）
scons target=release_debug arch=arm64 simulator=no plugin=godot3_asa version=3.x

# 编译 ARM64 模拟器版本
scons target=release_debug arch=arm64 simulator=yes plugin=godot3_asa version=3.x

# 编译 x86_64 模拟器版本
scons target=release_debug arch=x86_64 simulator=yes plugin=godot3_asa version=3.x
```

**构建产物位置**: `bin/lib<plugin>.<arch>-<platform>.<target>.a`

示例:
- `bin/libgodot3taptap.arm64-ios.release_debug.a` (真机)
- `bin/libgodot3_asa.arm64-simulator.release_debug.a` (模拟器)

### 3. 生成 XCFramework（推荐）

XCFramework 包含所有架构的二进制文件，可以同时用于真机和模拟器。

```bash
# 一键构建两个插件的完整 XCFramework（包含所有架构）
./scripts/release_xcframework.sh 3.x
```

这个脚本会：
1. 编译 ARM64 设备版本
2. 编译 ARM64 + x86_64 模拟器版本
3. 使用 `lipo` 合并模拟器架构
4. 使用 `xcodebuild -create-xcframework` 打包
5. 生成两个版本：
   - `.release.xcframework` - 发布版本
   - `.debug.xcframework` - 调试版本（实际也是 release_debug）

**构建产物位置**: 
- `bin/release/godot3_taptap/godot3_taptap.*.xcframework`
- `bin/release/godot3_asa/godot3_asa.*.xcframework`

### 4. 打包分发版本（可选）

```bash
# 手动打包（模拟 CI 流程）
mkdir -p bin/dist/godot3_taptap/ios/plugins/godot3_taptap
mkdir -p bin/dist/godot3_taptap/addons

# 复制 TapTap XCFramework
cp -r bin/release/godot3_taptap/*.xcframework bin/dist/godot3_taptap/ios/plugins/godot3_taptap/
cp bin/release/godot3_taptap/godot3_taptap.gdip bin/dist/godot3_taptap/ios/plugins/godot3_taptap/
cp -r plugins/godot3_taptap/sdk bin/dist/godot3_taptap/ios/plugins/godot3_taptap/
cp -r addons/godot3_taptap bin/dist/godot3_taptap/addons/godot3_taptap

# 打包 ASA（如果需要）
mkdir -p bin/dist/godot3_asa/ios/plugins/godot3_asa
mkdir -p bin/dist/godot3_asa/addons

cp -r bin/release/godot3_asa/*.xcframework bin/dist/godot3_asa/ios/plugins/godot3_asa/
cp bin/release/godot3_asa/godot3_asa.gdip bin/dist/godot3_asa/ios/plugins/godot3_asa/
cp -r addons/godot3_asa bin/dist/godot3_asa/addons/godot3_asa

# 创建压缩包
cd bin/dist
zip -r godot3_taptap-ios-plugin.zip godot3_taptap/
zip -r godot3_asa-ios-plugin.zip godot3_asa/
```

## 在 Godot 项目中使用

### 1. 复制文件到项目

```bash
# 复制到你的 Godot 项目
cp -r bin/dist/godot3_taptap/ios YOUR_PROJECT/ios/
cp -r bin/dist/godot3_taptap/addons YOUR_PROJECT/addons/

# 如果使用 ASA
cp -r bin/dist/godot3_asa/ios YOUR_PROJECT/ios/
cp -r bin/dist/godot3_asa/addons YOUR_PROJECT/addons/
```

### 2. 在 Godot 编辑器中配置

1. 打开你的 Godot 项目
2. 进入 **Project Settings → Plugins**，启用插件
3. 进入 **Project → Export → iOS**
4. 在 **Options → Plugins** 中勾选：
   - `Godot3TapTap` (TapTap 插件)
   - `Godot3ASA` (ASA 插件)

### 3. 导出并测试

1. 导出 iOS 项目
2. 在 Xcode 中打开导出的项目
3. 连接真机或选择模拟器
4. 运行测试

## 常见问题

### 1. 找不到 Godot 头文件

**错误**: `fatal error: 'core/object.h' file not found`

**解决**: 运行 `./scripts/generate_headers.sh 3.x`

### 2. SCons 缓存问题

**错误**: 编译失败或产生错误的二进制文件

**解决**: 清理缓存后重新编译
```bash
rm -rf .scons-cache godot/.scons_cache
rm -rf bin/*.a bin/*.xcframework
```

### 3. Xcode Command Line Tools 版本不匹配

**错误**: `xcrun: error: SDK "iphoneos" cannot be located`

**解决**: 
```bash
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch
```

### 4. Python 版本问题

**错误**: SCons 运行失败

**解决**: 使用 Python 3.8-3.11
```bash
python3 --version  # 检查版本
pip3 install --upgrade scons
```

### 5. 架构不匹配警告

如果在 Xcode 中看到架构警告：
- 确保为 **真机** 使用 `simulator=no`
- 确保为 **模拟器** 使用 `simulator=yes`
- XCFramework 应该包含所有需要的架构

## 调试技巧

### 查看构建产物

```bash
# 列出所有编译的静态库
ls -lh bin/*.a

# 查看 XCFramework 内容
ls -lh bin/release/*/

# 检查架构
lipo -info bin/libgodot3taptap.arm64-ios.release_debug.a
```

### 验证 XCFramework

```bash
# 查看 XCFramework 支持的架构和平台
xcodebuild -showBuildSettings -xcframework bin/release/godot3_taptap/godot3_taptap.release.xcframework
```

### 干净构建

```bash
# 完全清理后重新构建
rm -rf bin/*.a bin/*.xcframework bin/release/
./scripts/generate_headers.sh 3.x
./scripts/release_xcframework.sh 3.x
```

## 构建目标说明

| Target | 用途 | Xcode 配置对应 |
|--------|------|----------------|
| `debug` | 开发调试 | Debug |
| `release_debug` | 发布调试（**推荐**） | Release with debug symbols |
| `release` | 完全发布 | Release |

**注意**: 使用 `release_debug` 以匹配官方 Godot 模板，CI 会将其重命名为 `.debug.xcframework`。

## 参考资源

- [Godot iOS 插件文档](https://docs.godotengine.org/en/3.x/tutorials/platform/ios/ios_plugin.html)
- [官方 iOS 插件示例](https://github.com/godot-sdk-integrations/godot-ios-plugins)
- [SCons 构建系统](https://scons.org/)
- [Apple XCFramework 文档](https://developer.apple.com/documentation/xcode/creating-a-multi-platform-binary-framework-bundle)
