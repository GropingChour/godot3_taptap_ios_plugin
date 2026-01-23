# 编译问题诊断与解决方案

## 问题现象

在 Apple Silicon Mac 上编译 Godot iOS 项目时出现链接错误：

```
Undefined symbols for architecture arm64:
  "StringName::StringName(char const*)"
  "StringName::~StringName()"
  "Memory::free_static(void*, bool)"
  "Object::emit_signal(...)"
  "String::utf8(char const*, int)"
  "Variant::clear()"
```

同时伴随大量警告：
```
ld: warning: ignoring file .../libgodot.a(...): found architecture 'x86_64', required architecture 'arm64'
```

## 根本原因

### 1. **libgodot.a 架构不匹配**

**问题：** Godot 导出的 `libgodot.a` 不是 Fat Binary，只包含单一架构

- **声称的架构**（Info.plist）：arm64 + x86_64
- **实际包含的架构**：仅 x86_64
- **导致的问题**：
  - Apple Silicon Mac 上 Xcode 默认构建 arm64 架构
  - libgodot.a 中的 x86_64 目标文件全部被忽略
  - libgodot3_asa.a 依赖的 Godot 符号找不到 arm64 版本
  - 链接失败

### 2. **验证方法（在 Mac 上执行）**

```bash
# 检查 libgodot.a 的实际架构
cd <项目路径>/BackpackBattles_GB.xcframework/ios-arm64_x86_64-simulator
lipo -info libgodot.a

# 预期输出（正确）：
# Architectures in the fat file: libgodot.a are: arm64 x86_64

# 实际输出（错误）：
# Non-fat file: libgodot.a is architecture: x86_64
```

```bash
# 检查 libgodot3_asa.a 的架构（对比）
cd <项目路径>/dylibs/ios/plugins/godot3_asa/godot3_asa.xcframework/ios-arm64_x86_64-simulator
lipo -info libgodot3_asa.a

# 正确输出：
# Architectures in the fat file: libgodot3_asa.a are: arm64 x86_64
```

## 解决方案

### 方案 1：使用正确的 Godot 导出模板（推荐）

**步骤：**

1. **升级 Godot 版本**
   - 使用 Godot 3.5+ 或最新的 3.x 版本
   - 早期版本可能不支持 arm64-simulator

2. **重新下载/安装 iOS 导出模板**
   ```bash
   # 在 Godot Editor 中
   编辑器 → 管理导出模板 → 下载并安装
   ```

3. **重新导出 iOS 项目**
   - 项目 → 导出
   - 选择 iOS 平台
   - 确保勾选 "Export With Debug" 和 "Export With Release"
   - 点击 "Export Project"

4. **验证导出的 XCFramework**
   ```bash
   cd <导出路径>/<项目名>.xcframework/ios-arm64_x86_64-simulator
   lipo -info libgodot.a
   # 应该显示：Architectures in the fat file: libgodot.a are: arm64 x86_64
   ```

### 方案 2：临时解决 - 强制使用 x86_64（仅用于测试）

**适用场景：** 快速测试，不关心性能

**步骤：**

1. 打开 Xcode 项目：
   ```bash
   open <项目路径>/<项目名>.xcodeproj
   ```

2. 修改 Build Settings：
   ```
   Project → Build Settings → Architectures
   → 设置为：x86_64（删除 arm64）
   ```

3. 编译运行：
   - 会在 Rosetta 2 模式下运行模拟器
   - 性能较差，但可以测试功能

**注意：** 此方案不解决根本问题，无法用于正式发布

### 方案 3：手动重建 Godot 导出模板（高级）

**适用场景：** 使用自定义 Godot 版本或需要特殊配置

**步骤：**

1. **编译 Godot iOS 模板**
   ```bash
   cd <godot-source>
   
   # 编译真机版本
   scons platform=iphone target=release arch=arm64
   
   # 编译模拟器版本（两个架构）
   scons platform=iphone target=release arch=x86_64 simulator=yes
   scons platform=iphone target=release arch=arm64 simulator=yes
   
   # 合并为 Fat Binary
   lipo -create \
     bin/libgodot.iphone.opt.x86_64.simulator.a \
     bin/libgodot.iphone.opt.arm64.simulator.a \
     -output bin/libgodot.simulator.a
   ```

2. **创建 XCFramework**
   ```bash
   xcodebuild -create-xcframework \
     -library bin/libgodot.iphone.opt.arm64.a \
     -library bin/libgodot.simulator.a \
     -output <项目名>.xcframework
   ```

3. **替换导出项目中的 libgodot.a**

## SConstruct 配置检查

### godot3_taptap vs godot3_asa 差异

| 配置项 | godot3_taptap | godot3_asa |
|--------|---------------|------------|
| 框架搜索路径 | ✅ 配置了 TapTap SDK 路径 | ❌ 无（使用系统框架） |
| 编译标志 | 标准 + `-F <sdk_path>` | 仅标准 |
| 依赖框架 | 第三方 XCFrameworks | AdServices.framework（系统） |

**结论：** SConstruct 配置差异不是问题根源，因为：
- godot3_asa 使用系统框架，不需要额外的 `-F` 路径
- 两个插件的编译标志基本一致
- 问题出在 libgodot.a 本身

## 预防措施

### 1. 使用 CI/CD 自动验证

在 GitHub Actions 中添加架构检查：

```yaml
- name: Verify XCFramework architectures
  run: |
    echo "Checking godot3_asa simulator binary:"
    lipo -info bin/simulator/libgodot3_asa.a
    
    echo "Checking godot3_asa device binary:"
    lipo -info bin/device/libgodot3_asa.a
    
    # 验证模拟器版本包含两个架构
    if ! lipo -info bin/simulator/libgodot3_asa.a | grep -q "arm64.*x86_64\|x86_64.*arm64"; then
      echo "ERROR: Simulator binary missing required architectures!"
      exit 1
    fi
```

### 2. 版本兼容性矩阵

| Godot 版本 | iOS SDK | arm64-simulator 支持 | 推荐状态 |
|-----------|---------|---------------------|---------|
| 3.5.x | iOS 12+ | ✅ 完整支持 | ✅ 推荐 |
| 3.4.x | iOS 11+ | ⚠️ 部分支持 | ⚠️ 需验证 |
| 3.3.x 及更早 | iOS 10+ | ❌ 不支持 | ❌ 不推荐 |

### 3. 本地开发验证清单

构建插件前：
- [ ] 确认 Godot 版本 ≥ 3.5
- [ ] 验证 iOS 导出模板已更新
- [ ] 检查 Xcode 版本 ≥ 12.0（支持 arm64-simulator）
- [ ] 运行 `lipo -info` 验证所有库文件

构建插件后：
- [ ] 验证 XCFramework 包含正确架构
- [ ] 测试在 Apple Silicon Mac 模拟器上运行
- [ ] 测试在真机上运行

## 常见问题

### Q: 为什么 godot3_taptap 能编译成功？

**A:** 可能的原因：
1. 在不同的测试环境（可能使用了正确的 libgodot.a）
2. Xcode 配置强制使用了 x86_64 架构
3. 在 Intel Mac 上编译（没有 arm64 架构问题）
4. 使用了不同版本的 Godot 导出模板

### Q: 可以只保留 x86_64 吗？

**A:** 可以，但不推荐：
- 在 Apple Silicon Mac 上需要 Rosetta 2
- 性能降低约 20-30%
- Apple 未来可能停止支持 Rosetta 2
- 无法充分利用 M 系列芯片性能

### Q: 如何判断是 libgodot.a 还是 libgodot3_asa.a 的问题？

**A:** 运行以下命令：
```bash
# 检查 libgodot.a
lipo -info <项目>/<项目>.xcframework/ios-arm64_x86_64-simulator/libgodot.a

# 检查 libgodot3_asa.a
lipo -info <项目>/dylibs/ios/plugins/godot3_asa/godot3_asa.xcframework/ios-arm64_x86_64-simulator/libgodot3_asa.a
```

如果 libgodot.a 不是 Fat Binary → **问题在 Godot 导出**
如果 libgodot3_asa.a 不是 Fat Binary → **问题在插件编译**

## 参考资料

- [Godot iOS 导出文档](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_ios.html)
- [Apple - Building Apple Silicon Apps](https://developer.apple.com/documentation/xcode/building-a-universal-macos-binary)
- [Creating XCFrameworks](https://developer.apple.com/documentation/xcode/creating-a-multi-platform-binary-framework-bundle)
- [lipo 命令文档](https://ss64.com/osx/lipo.html)

## 更新日志

- 2026-01-19: 初始版本，记录 libgodot.a 架构问题及解决方案
