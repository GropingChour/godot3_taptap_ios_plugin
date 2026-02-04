# Godot3StoreView Plugin - 重命名完成总结

## 完成的更改

### 1. 文件重命名
- ✅ `plugins/storereview/` → `plugins/godot3_storeview/`
- ✅ `store_review.h` → `godot3_storeview.h`
- ✅ `store_review.mm` → `godot3_storeview.mm`
- ✅ `store_review_module.h` → `godot3_storeview_module.h`
- ✅ `store_review_module.cpp` → `godot3_storeview_module.cpp`
- ✅ `storereview.gdip` → `godot3_storeview.gdip`

### 2. 类名更新
- ✅ `StoreReview` → `Godot3StoreView`
- ✅ 所有方法、构造函数、析构函数已更新
- ✅ 单例名称：`"Godot3StoreView"`
- ✅ 注册函数：`register_godot3_storeview_types()`
- ✅ 注销函数：`unregister_godot3_storeview_types()`

### 3. 日志前缀
- ✅ C++/ObjC层：`[Godot3StoreView]`
- ✅ GDScript层：`[StoreView]`

### 4. 构建配置
- ✅ 在 `SConstruct` 中添加 `godot3_storeview` 到插件列表
- ✅ `.gdip` 文件配置：
  - `name="Godot3StoreView"`
  - `binary="godot3_storeview.a"`
  - `initialization="register_godot3_storeview_types"`
  - `deinitialization="unregister_godot3_storeview_types"`

### 5. GDScript插件层（addons）
创建了完整的 `addons/godot3_storeview/` 结构：

#### 文件列表
- ✅ `plugin.cfg` - 编辑器插件配置
- ✅ `plugin.gd` - 自动加载注册（autoload: `StoreView`）
- ✅ `storeview.gd` - 主GDScript API（120行完整实现）
- ✅ `README.md` - 完整的API文档
- ✅ `example/storeview_example.gd` - 使用示例代码

#### GDScript API
```gdscript
# 自动加载单例：StoreView
StoreView.request_review()                          # 请求应用内评价
StoreView.get_write_review_url(app_store_id)       # 获取App Store评价URL
StoreView.open_review_page(app_store_id)           # 直接打开App Store评价页面
StoreView.is_supported()                            # 检查是否支持
StoreView.should_request_review()                   # 帮助函数
```

## 架构对比

### godot3_asa
```
GDScript: asa.gd (autoload: ASA)
    ↓
C++: Godot3ASA
    ↓
iOS: AdServices API
```

### godot3_taptap
```
GDScript: taptap.gd (autoload: TapTap)
    ↓
C++: Godot3TapTap
    ↓
iOS: TapTap SDK
```

### godot3_storeview（新）
```
GDScript: storeview.gd (autoload: StoreView)
    ↓
C++: Godot3StoreView
    ↓
iOS: SKStoreReviewController
```

## 构建命令

```bash
# 编译设备版本 (arm64)
scons target=release_debug arch=arm64 simulator=no plugin=godot3_storeview version=3.x

# 编译模拟器版本 (x86_64)
scons target=release_debug arch=x86_64 simulator=yes plugin=godot3_storeview version=3.x

# 编译模拟器版本 (arm64, Apple Silicon)
scons target=release_debug arch=arm64 simulator=yes plugin=godot3_storeview version=3.x

# 创建XCFramework
./scripts/release_xcframework.sh 3.x
```

输出文件：`bin/godot3_storeview.arm64-ios.release_debug.a`

## 使用方法

### 1. 启用插件
在 Godot 编辑器中：**项目设置 → 插件 → Godot3StoreView** 启用

### 2. 代码示例
```gdscript
extends Node

const APP_STORE_ID = "1234567890"

func _ready():
    if StoreView.is_supported():
        print("StoreView plugin ready")

func request_review_after_milestone():
    # 在适当的时机请求评价
    StoreView.request_review()

func on_rate_button_pressed():
    # 显式"给我评分"按钮
    StoreView.open_review_page(APP_STORE_ID)
```

## 重要注意事项

### iOS评价限制
- 每个设备每365天最多3次
- 系统可能抑制请求
- 实现自己的冷却时间（建议30+天）

### 最佳实践
**好的时机：**
- 完成关卡/任务后
- 积极的用户交互后
- 达成成就后

**不好的时机：**
- 首次启动
- 游戏过程中
- 错误/崩溃后
- 过于频繁

## 文件清单

### C++/ObjC层 (plugins/godot3_storeview/)
- [x] godot3_storeview.h
- [x] godot3_storeview.mm
- [x] godot3_storeview_module.h
- [x] godot3_storeview_module.cpp
- [x] godot3_storeview.gdip
- [x] README.md

### GDScript层 (addons/godot3_storeview/)
- [x] plugin.cfg
- [x] plugin.gd
- [x] storeview.gd
- [x] README.md
- [x] example/storeview_example.gd

## 验证检查点

- ✅ 文件命名符合 `godot3_*` 规范
- ✅ 类名使用 `Godot3*` 格式
- ✅ 单例名称正确注册
- ✅ `.gdip` 配置与模块函数名匹配
- ✅ 日志前缀统一
- ✅ SConstruct 包含插件选项
- ✅ GDScript API 完整实现
- ✅ 示例代码和文档齐全

## 下一步

1. **测试构建**：
   ```bash
   scons target=release_debug arch=arm64 simulator=no plugin=godot3_storeview version=3.x
   ```

2. **集成测试**：
   - 在Godot项目中启用插件
   - 导出iOS并在Xcode中构建
   - 在真机上测试评价功能

3. **更新CI/CD**（如需要）：
   - 在CI配置中添加 `godot3_storeview` 构建

## 与其他插件的一致性

| 特性 | godot3_asa | godot3_taptap | godot3_storeview |
|------|------------|---------------|------------------|
| C++类名 | Godot3ASA | Godot3TapTap | Godot3StoreView ✅ |
| 单例名 | Godot3ASA | Godot3TapTap | Godot3StoreView ✅ |
| 自动加载 | ASA | TapTap | StoreView ✅ |
| 日志前缀 | [ASA] | [TapTap] | [StoreView] ✅ |
| 目录结构 | plugins/godot3_asa/ | plugins/godot3_taptap/ | plugins/godot3_storeview/ ✅ |
| addons目录 | addons/godot3_asa/ | addons/godot3_taptap/ | addons/godot3_storeview/ ✅ |

所有格式完全一致！ ✨
