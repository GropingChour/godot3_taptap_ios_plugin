# ASA 插件完整集成示例

这个文档提供了一个真实项目中如何集成和使用 ASA 插件的完整示例。

## 项目结构

```
your_game_project/
├── autoload/
│   └── game_manager.gd     # 游戏管理器（处理归因）
├── scenes/
│   ├── main_menu/
│   │   └── main_menu.gd    # 主菜单（处理登录/注册）
│   └── shop/
│       └── shop.gd         # 商城（处理付费）
└── addons/
    └── godot3_asa/         # ASA 插件
```

## 1. 游戏管理器（autoload/game_manager.gd）

```gdscript
extends Node

# 游戏管理器 - 处理 ASA 归因和基础上报

# ============================================================================
# 配置
# ============================================================================

# AppSA from 参数（从项目设置或配置文件读取）
const APPSA_FROM_KEY = "your_appsa_from_key"
const APP_NAME = "你的游戏名称"

# 配置文件路径
const CONFIG_PATH = "user://game_config.cfg"
const ASA_DATA_PATH = "user://asa_attribution.json"

# 配置键名
const CONFIG_SECTION_ASA = "asa"
const KEY_ASA_COMPLETED = "attribution_completed"
const KEY_ACTIVATION_REPORTED = "activation_reported"

# ============================================================================
# 变量
# ============================================================================

var config: ConfigFile
var attribution_retry_count: int = 0
const MAX_RETRY = 3

# ============================================================================
# 初始化
# ============================================================================

func _ready():
	print("=== Game Manager Initializing ===")
	
	# 加载配置
	config = ConfigFile.new()
	var err = config.load(CONFIG_PATH)
	if err != OK and err != ERR_FILE_NOT_FOUND:
		push_error("Failed to load config: ", err)
	
	# 只在 iOS 平台处理 ASA
	if OS.get_name() != "iOS":
		print("Not iOS platform, ASA disabled")
		return
	
	# 设置 AppSA from 参数
	ASA.set_appsa_from_key(APPSA_FROM_KEY)
	
	# 连接 ASA 信号
	ASA.connect("onASAAttributionReceived", self, "_on_asa_attribution")
	ASA.connect("onAppSAReportSuccess", self, "_on_appsa_success")
	ASA.connect("onAppSAReportFailed", self, "_on_appsa_failed")
	
	# 检查归因状态
	check_and_perform_attribution()

# ============================================================================
# ASA 归因
# ============================================================================

func check_and_perform_attribution():
	"""检查并执行归因"""
	
	# 检查是否已完成归因
	if is_attribution_completed():
		print("[GameManager] Attribution already completed")
		# 尝试加载缓存的归因数据
		if ASA.load_attribution_data(ASA_DATA_PATH):
			print("[GameManager] Attribution data loaded from cache")
		return
	
	# 检查系统支持
	if not ASA.is_supported():
		print("[GameManager] AdServices not supported (iOS 14.3+ required)")
		return
	
	# 延迟后执行归因（等待网络初始化）
	print("[GameManager] Scheduling attribution in 1 second...")
	yield(get_tree().create_timer(1.0), "timeout")
	
	print("[GameManager] Starting attribution...")
	ASA.perform_attribution()

func _on_asa_attribution(data: String, code: int, message: String):
	"""归因完成回调"""
	print("[GameManager] Attribution callback: code=%d" % code)
	
	if code == 200:
		# 归因成功
		print("[GameManager] ✅ Attribution SUCCESS")
		
		# 解析数据
		var json = JSON.parse(data)
		if json.error == OK:
			var attr = json.result
			
			# 打印关键信息
			print("  From ASA: ", attr.get("attribution", false))
			if attr.get("attribution", false):
				print("  Campaign: ", attr.get("campaignId", ""))
				print("  AdGroup: ", attr.get("adGroupId", ""))
				print("  Keyword: ", attr.get("keywordId", ""))
				print("  Country: ", attr.get("countryOrRegion", ""))
			
			# 保存归因数据
			ASA.save_attribution_data(ASA_DATA_PATH)
			
			# 标记归因完成
			mark_attribution_completed()
			
			# 重置重试计数
			attribution_retry_count = 0
			
			# 上报激活（如果用户来自 ASA）
			if not is_activation_reported() and ASA.is_from_asa():
				print("[GameManager] Reporting activation...")
				yield(get_tree().create_timer(0.5), "timeout")
				report_activation()
	
	elif code == 404 or code == 500:
		# 可重试的错误
		if attribution_retry_count < MAX_RETRY:
			attribution_retry_count += 1
			print("[GameManager] Attribution failed (code=%d), retrying... (%d/%d)" % [code, attribution_retry_count, MAX_RETRY])
			yield(get_tree().create_timer(5.0), "timeout")
			ASA.perform_attribution()
		else:
			print("[GameManager] Attribution failed after %d retries" % MAX_RETRY)
	
	else:
		# 其他错误，不重试
		print("[GameManager] ❌ Attribution FAILED: %s (code=%d)" % [message, code])

func report_activation():
	"""上报激活到 AppSA"""
	ASA.report_activation(APP_NAME)

# ============================================================================
# 配置管理
# ============================================================================

func is_attribution_completed() -> bool:
	"""检查是否已完成归因"""
	return config.get_value(CONFIG_SECTION_ASA, KEY_ASA_COMPLETED, false)

func mark_attribution_completed():
	"""标记归因已完成"""
	config.set_value(CONFIG_SECTION_ASA, KEY_ASA_COMPLETED, true)
	config.save(CONFIG_PATH)
	print("[GameManager] Attribution marked as completed")

func is_activation_reported() -> bool:
	"""检查激活是否已上报"""
	return config.get_value(CONFIG_SECTION_ASA, KEY_ACTIVATION_REPORTED, false)

func mark_activation_reported():
	"""标记激活已上报"""
	config.set_value(CONFIG_SECTION_ASA, KEY_ACTIVATION_REPORTED, true)
	config.save(CONFIG_PATH)

# ============================================================================
# AppSA 上报回调
# ============================================================================

func _on_appsa_success(response: Dictionary):
	"""AppSA 上报成功"""
	print("[GameManager] ✅ AppSA report success: ", response.get("msg", ""))
	
	# 如果是激活上报，标记已完成
	mark_activation_reported()

func _on_appsa_failed(error_message: String):
	"""AppSA 上报失败"""
	push_error("[GameManager] ❌ AppSA report failed: " + error_message)

# ============================================================================
# 公共接口 - 供其他模块调用
# ============================================================================

func is_asa_user() -> bool:
	"""检查当前用户是否来自 ASA"""
	return ASA.is_from_asa()

func get_asa_campaign_id() -> String:
	"""获取 ASA 广告系列 ID"""
	var data = ASA.get_attribution_data()
	return str(data.get("campaignId", ""))
```

## 2. 主菜单场景（scenes/main_menu/main_menu.gd）

```gdscript
extends Control

# 主菜单 - 处理用户注册和登录

# ============================================================================
# UI 节点引用
# ============================================================================

onready var login_panel = $LoginPanel
onready var username_input = $LoginPanel/UsernameInput
onready var register_button = $LoginPanel/RegisterButton
onready var login_button = $LoginPanel/LoginButton

# ============================================================================
# 初始化
# ============================================================================

func _ready():
	# 连接按钮信号
	register_button.connect("pressed", self, "_on_register_pressed")
	login_button.connect("pressed", self, "_on_login_pressed")

# ============================================================================
# 用户操作
# ============================================================================

func _on_register_pressed():
	"""注册按钮点击"""
	var username = username_input.text.strip_edges()
	
	if username.empty():
		show_message("请输入用户名")
		return
	
	# 执行注册逻辑（调用后端 API 等）
	var success = perform_register(username)
	
	if success:
		show_message("注册成功！")
		
		# 上报注册事件到 AppSA
		if OS.get_name() == "iOS" and GameManager.is_asa_user():
			print("[MainMenu] Reporting register event to AppSA")
			ASA.report_register()
		
		# 自动登录
		on_login_success(username)

func _on_login_pressed():
	"""登录按钮点击"""
	var username = username_input.text.strip_edges()
	
	if username.empty():
		show_message("请输入用户名")
		return
	
	# 执行登录逻辑
	var success = perform_login(username)
	
	if success:
		on_login_success(username)

func on_login_success(username: String):
	"""登录成功处理"""
	print("[MainMenu] Login success: ", username)
	
	# 上报登录事件到 AppSA
	if OS.get_name() == "iOS" and GameManager.is_asa_user():
		print("[MainMenu] Reporting login event to AppSA")
		ASA.report_login()
	
	# 进入游戏主界面
	get_tree().change_scene("res://scenes/game/game.tscn")

# ============================================================================
# 后端交互（示例）
# ============================================================================

func perform_register(username: String) -> bool:
	"""执行注册（示例，需要实现实际逻辑）"""
	# TODO: 调用后端注册 API
	return true

func perform_login(username: String) -> bool:
	"""执行登录（示例，需要实现实际逻辑）"""
	# TODO: 调用后端登录 API
	return true

func show_message(text: String):
	"""显示提示消息"""
	# TODO: 显示 Toast 或对话框
	print("[MainMenu] ", text)
```

## 3. 商城场景（scenes/shop/shop.gd）

```gdscript
extends Control

# 商城 - 处理用户付费

# ============================================================================
# 商品数据
# ============================================================================

const PRODUCTS = [
	{
		"id": "coin_pack_small",
		"name": "小金币包",
		"price": 6.0,
		"currency": "USD"
	},
	{
		"id": "coin_pack_medium",
		"name": "中金币包",
		"price": 30.0,
		"currency": "USD"
	},
	{
		"id": "coin_pack_large",
		"name": "大金币包",
		"price": 99.0,
		"currency": "USD"
	}
]

# ============================================================================
# UI
# ============================================================================

onready var product_list = $ProductList

func _ready():
	setup_products()

func setup_products():
	"""设置商品列表"""
	for product in PRODUCTS:
		var button = Button.new()
		button.text = "%s - $%.2f" % [product.name, product.price]
		button.connect("pressed", self, "_on_product_pressed", [product])
		product_list.add_child(button)

# ============================================================================
# 购买处理
# ============================================================================

func _on_product_pressed(product: Dictionary):
	"""商品按钮点击"""
	print("[Shop] Product clicked: ", product.name)
	
	# 显示确认对话框
	show_purchase_confirmation(product)

func show_purchase_confirmation(product: Dictionary):
	"""显示购买确认对话框（示例）"""
	# TODO: 显示确认对话框
	# 用户确认后调用 process_purchase
	process_purchase(product)

func process_purchase(product: Dictionary):
	"""处理购买"""
	print("[Shop] Processing purchase: ", product.name)
	
	# 1. 调用支付接口（IAP、支付宝等）
	var success = perform_payment(product)
	
	if success:
		# 2. 支付成功，发放商品
		deliver_product(product)
		
		# 3. 上报收入事件到 AppSA
		if OS.get_name() == "iOS" and GameManager.is_asa_user():
			print("[Shop] Reporting revenue to AppSA")
			ASA.report_revenue(product.price, product.currency)
		
		# 4. 如果是首次付费，上报付费用户数
		if is_first_purchase():
			if OS.get_name() == "iOS" and GameManager.is_asa_user():
				print("[Shop] Reporting first purchase")
				ASA.report_pay_unique_user()
			mark_first_purchase()
		
		show_message("购买成功！")

func perform_payment(product: Dictionary) -> bool:
	"""执行支付（示例）"""
	# TODO: 调用实际支付 API
	return true

func deliver_product(product: Dictionary):
	"""发放商品"""
	# TODO: 给玩家添加对应的金币/道具
	print("[Shop] Product delivered: ", product.name)

# ============================================================================
# 辅助方法
# ============================================================================

func is_first_purchase() -> bool:
	"""检查是否首次付费"""
	var config = ConfigFile.new()
	config.load("user://game_config.cfg")
	return not config.get_value("player", "has_purchased", false)

func mark_first_purchase():
	"""标记已付费"""
	var config = ConfigFile.new()
	config.load("user://game_config.cfg")
	config.set_value("player", "has_purchased", true)
	config.save("user://game_config.cfg")

func show_message(text: String):
	"""显示消息"""
	print("[Shop] ", text)
```

## 4. 每日任务管理器（autoload/daily_task_manager.gd）

```gdscript
extends Node

# 每日任务管理器 - 处理留存统计和上报

# ============================================================================
# 配置
# ============================================================================

const CONFIG_PATH = "user://game_config.cfg"
const CONFIG_SECTION = "daily_tasks"
const KEY_LAST_LOGIN_DATE = "last_login_date"
const KEY_INSTALL_DATE = "install_date"

var config: ConfigFile

# ============================================================================
# 初始化
# ============================================================================

func _ready():
	config = ConfigFile.new()
	config.load(CONFIG_PATH)
	
	# 检查是否首次启动
	if not config.has_section_key(CONFIG_SECTION, KEY_INSTALL_DATE):
		on_first_install()
	
	# 每日登录检查
	check_daily_login()

# ============================================================================
# 首次安装
# ============================================================================

func on_first_install():
	"""首次安装时调用"""
	var today = get_today_date()
	config.set_value(CONFIG_SECTION, KEY_INSTALL_DATE, today)
	config.set_value(CONFIG_SECTION, KEY_LAST_LOGIN_DATE, today)
	config.save(CONFIG_PATH)
	print("[DailyTask] First install on: ", today)

# ============================================================================
# 每日登录检查
# ============================================================================

func check_daily_login():
	"""检查每日登录，判断留存"""
	var today = get_today_date()
	var last_login = config.get_value(CONFIG_SECTION, KEY_LAST_LOGIN_DATE, "")
	
	if last_login == today:
		print("[DailyTask] Already logged in today")
		return
	
	# 更新最后登录日期
	config.set_value(CONFIG_SECTION, KEY_LAST_LOGIN_DATE, today)
	config.save(CONFIG_PATH)
	
	print("[DailyTask] Daily login on: ", today)
	
	# 检查留存
	check_retention()

func check_retention():
	"""检查并上报留存"""
	if OS.get_name() != "iOS" or not GameManager.is_asa_user():
		return
	
	var install_date = config.get_value(CONFIG_SECTION, KEY_INSTALL_DATE, "")
	if install_date.empty():
		return
	
	var days_since_install = get_days_between(install_date, get_today_date())
	
	print("[DailyTask] Days since install: ", days_since_install)
	
	# 上报留存事件（按次上报）
	match days_since_install:
		1:
			print("[DailyTask] Day 1 retention")
			ASA.report_retention_day1_instant()
		3:
			print("[DailyTask] Day 3 retention")
			ASA.report_retention_day3_instant()
		7:
			print("[DailyTask] Day 7 retention")
			ASA.report_retention_day7_instant()

# ============================================================================
# 定时任务（每天凌晨执行）
# ============================================================================

func run_daily_summary_task():
	"""
	每日汇总任务（需要后台统计留存用户数）
	建议在服务器端统计后调用此方法
	"""
	if OS.get_name() != "iOS":
		return
	
	var today = get_today_date()
	
	# 从服务器获取今日留存数据（示例）
	var day1_count = get_day1_retention_count_from_server()
	var day3_count = get_day3_retention_count_from_server()
	var day7_count = get_day7_retention_count_from_server()
	
	# 上报汇总数据
	if day1_count > 0:
		ASA.report_retention_day1_summary(day1_count, today)
	
	if day3_count > 0:
		ASA.report_retention_day3_summary(day3_count, today)
	
	if day7_count > 0:
		ASA.report_retention_day7_summary(day7_count, today)

# ============================================================================
# 辅助方法
# ============================================================================

func get_today_date() -> String:
	"""获取今日日期字符串（YYYY-MM-DD）"""
	var dt = OS.get_datetime()
	return "%04d-%02d-%02d" % [dt.year, dt.month, dt.day]

func get_days_between(date1: String, date2: String) -> int:
	"""计算两个日期之间的天数"""
	# 简化实现，实际项目可能需要更精确的日期计算
	var d1_parts = date1.split("-")
	var d2_parts = date2.split("-")
	
	if d1_parts.size() != 3 or d2_parts.size() != 3:
		return 0
	
	var d1_dict = {
		"year": int(d1_parts[0]),
		"month": int(d1_parts[1]),
		"day": int(d1_parts[2])
	}
	
	var d2_dict = {
		"year": int(d2_parts[0]),
		"month": int(d2_parts[1]),
		"day": int(d2_parts[2])
	}
	
	# 使用 OS.get_unix_time_from_datetime
	var time1 = OS.get_unix_time_from_datetime(d1_dict)
	var time2 = OS.get_unix_time_from_datetime(d2_dict)
	
	var days = (time2 - time1) / 86400
	return int(days)

func get_day1_retention_count_from_server() -> int:
	"""从服务器获取 1 日留存用户数（示例）"""
	# TODO: 实现服务器 API 调用
	return 0

func get_day3_retention_count_from_server() -> int:
	"""从服务器获取 3 日留存用户数（示例）"""
	# TODO: 实现服务器 API 调用
	return 0

func get_day7_retention_count_from_server() -> int:
	"""从服务器获取 7 日留存用户数（示例）"""
	# TODO: 实现服务器 API 调用
	return 0
```

## 5. 项目设置（project.godot）

在 `project.godot` 中添加 autoload：

```ini
[autoload]

GameManager="*res://autoload/game_manager.gd"
DailyTaskManager="*res://autoload/daily_task_manager.gd"
ASA="*res://addons/godot3_asa/asa.gd"
```

## 使用流程总结

### 应用启动流程

```
1. App 启动
   ↓
2. GameManager._ready()
   ↓
3. 检查是否首次启动
   ↓
4. 是 → 延迟 1 秒 → ASA.perform_attribution()
   否 → 加载缓存数据
   ↓
5. 归因完成
   ↓
6. 保存归因数据
   ↓
7. 如果来自 ASA → 上报激活
   ↓
8. DailyTaskManager 检查每日登录
   ↓
9. 如果是留存日（1/3/7天） → 上报留存事件
```

### 用户行为上报流程

```
用户行为发生
   ↓
检查是否 iOS 平台
   ↓
检查是否 ASA 用户（GameManager.is_asa_user()）
   ↓
是 → 调用对应的 ASA.report_xxx() 方法
   ↓
AppSA 接收数据
   ↓
通过信号反馈上报结果
```

## 关键点总结

1. **归因只做一次**：使用配置文件标记
2. **延迟执行**：等待网络初始化后再归因
3. **检查用户来源**：只为 ASA 用户上报
4. **保存归因数据**：避免重复请求
5. **错误重试**：404/500 错误可重试
6. **事件即时上报**：用户行为发生时立即上报
7. **留存按需上报**：按次或汇总根据需求选择

## 测试建议

1. **使用 TestFlight 测试**：可获得测试归因数据
2. **添加调试开关**：方便重置归因状态
3. **监控日志输出**：确认各步骤执行正常
4. **验证 AppSA 数据**：在 AppSA 后台查看上报结果

这套代码提供了完整的 ASA 集成方案，可以直接在实际项目中使用！
