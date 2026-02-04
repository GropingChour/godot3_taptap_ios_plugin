# Godot3StoreView 快速参考

## 基本信息
- **C++ 类名**: `Godot3StoreView`
- **C++ 单例名**: `"Godot3StoreView"`
- **GDScript 自动加载**: `StoreView`
- **iOS 框架**: StoreKit (SKStoreReviewController)

## 文件位置

### C++/ObjC层
```
plugins/godot3_storeview/
├── godot3_storeview.h              # 类声明
├── godot3_storeview.mm             # ObjC++实现
├── godot3_storeview_module.h       # 模块注册头
├── godot3_storeview_module.cpp     # 模块注册实现
└── godot3_storeview.gdip           # 插件清单
```

### GDScript层
```
addons/godot3_storeview/
├── plugin.cfg                      # 编辑器插件配置
├── plugin.gd                       # 注册StoreView自动加载
├── storeview.gd                    # 主API（120行）
├── README.md                       # 完整文档
└── example/
    └── storeview_example.gd        # 使用示例
```

## API速查

### GDScript API（通过 StoreView 自动加载）

```gdscript
# 检查插件是否可用
StoreView.is_supported() -> bool

# 请求应用内评价（iOS 10.3+，系统控制显示）
StoreView.request_review() -> void

# 获取App Store评价URL
StoreView.get_write_review_url(app_store_id: String) -> String

# 直接打开App Store评价页面
StoreView.open_review_page(app_store_id: String) -> void

# 帮助函数：检查是否应该请求评价
StoreView.should_request_review() -> bool
```

### C++ API（内部，GDScript通过单例调用）

```cpp
void request_review();
String get_write_review_url(const String &app_store_id);
static Godot3StoreView *get_singleton();
```

## 使用示例

### 基础使用
```gdscript
# 在适当时机请求评价
func on_level_completed():
    if StoreView.is_supported():
        StoreView.request_review()

# 显式评价按钮
func on_rate_button_pressed():
    StoreView.open_review_page("1234567890")
```

### 智能请求（带冷却时间）
```gdscript
extends Node

var last_request_time: int = 0
const COOLDOWN_DAYS = 30

func request_review_smart():
    var now = OS.get_unix_time()
    var days_passed = (now - last_request_time) / 86400
    
    if days_passed >= COOLDOWN_DAYS:
        last_request_time = now
        StoreView.request_review()
        print("评价已请求")
    else:
        print("冷却中，还需等待 %d 天" % (COOLDOWN_DAYS - days_passed))
```

## 构建命令

```bash
# 单独构建（设备）
scons target=release_debug arch=arm64 simulator=no \
      plugin=godot3_storeview version=3.x

# 单独构建（模拟器 x86_64）
scons target=release_debug arch=x86_64 simulator=yes \
      plugin=godot3_storeview version=3.x

# 单独构建（模拟器 arm64）
scons target=release_debug arch=arm64 simulator=yes \
      plugin=godot3_storeview version=3.x

# 完整XCFramework
./scripts/release_xcframework.sh 3.x
```

## 集成步骤

### 1. 复制插件文件
将 `plugins/godot3_storeview/` 复制到导出模板

### 2. 复制GDScript层
将 `addons/godot3_storeview/` 复制到Godot项目

### 3. 启用插件
**项目设置 → 插件 → Godot3StoreView** ✅

### 4. 配置导出
**项目 → 导出 → iOS → 插件 → Godot3StoreView** ✅

### 5. 使用API
```gdscript
extends Node

func _ready():
    if StoreView.is_supported():
        print("准备就绪")
```

## iOS限制

| 限制 | 说明 |
|------|------|
| 频率 | 每设备每365天最多3次 |
| 控制 | 系统决定是否显示 |
| 测试 | 仅真机有效，模拟器无效 |
| 分发 | 需通过App Store/TestFlight |

## 最佳时机

### ✅ 好的时机
- 完成关卡/任务
- 达成成就
- 购买成功后
- 积极互动后

### ❌ 不好的时机
- App首次启动
- 游戏进行中
- 错误/崩溃后
- 过于频繁（<30天）

## 调试日志

所有操作都会输出日志：

```
[StoreView] Initialized
[StoreView] Requesting review...
[StoreView] Opening review page: https://apps.apple.com/...
[Godot3StoreView] SKStoreReviewController is not available on this iOS version
[Godot3StoreView] No active window scene found
```

- GDScript层：`[StoreView]`
- C++/ObjC层：`[Godot3StoreView]`

## 与其他插件对比

| 插件 | C++类 | 单例名 | 自动加载 | 用途 |
|------|-------|--------|----------|------|
| godot3_asa | Godot3ASA | Godot3ASA | ASA | ASA归因 |
| godot3_taptap | Godot3TapTap | Godot3TapTap | TapTap | TapTap登录 |
| godot3_storeview | Godot3StoreView | Godot3StoreView | StoreView | 评价请求 |

所有插件遵循相同的架构模式！

## 故障排查

### 评价对话框不显示
1. 检查iOS限制（每年3次）
2. 确认在真机测试
3. 验证App Store分发
4. 检查请求频率

### 插件找不到
1. 验证导出设置已启用插件
2. 检查单例：`Engine.has_singleton("Godot3StoreView")`
3. 查看Xcode构建日志

### 构建失败
1. 确认Godot头文件已生成
2. 检查`SConstruct`包含`godot3_storeview`
3. 验证StoreKit框架已链接
