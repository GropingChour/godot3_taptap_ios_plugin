extends Node

# ASA 归因和 AppSA 上报示例节点
# 
# 这个节点演示了如何使用 ASA 插件进行归因和数据上报
# 可以直接添加到场景中使用，或参考此代码集成到自己的项目中

# ============================================================================
# 配置区域 - 根据实际情况修改
# ============================================================================

# AppSA from 参数（由七麦提供）
export var appsa_from_key: String = "your_from_key_here"

# 是否启用自动归因（App 首次启动时）
export var auto_attribution: bool = true

# 归因延迟时间（秒）
export var attribution_delay: float = 1.0

# 是否自动上报激活
export var auto_report_activation: bool = true

# 是否保存归因数据到本地
export var save_attribution: bool = true

# ============================================================================
# 内部变量
# ============================================================================

const ASA_REQUESTED_KEY = "asa_attribution_requested"
var config_file: ConfigFile

# ============================================================================
# 初始化
# ============================================================================

func _ready():
	# 检查是否在 iOS 平台
	if OS.get_name() != "iOS":
		print("[ASA Example] Not iOS platform, example disabled")
		return
	
	# 初始化配置文件
	config_file = ConfigFile.new()
	config_file.load("user://app_config.cfg")
	
	# 设置 AppSA from 参数
	if not appsa_from_key.empty() and appsa_from_key != "your_from_key_here":
		ASA.set_appsa_from_key(appsa_from_key)
	else:
		print("[ASA Example] Warning: AppSA from_key not configured")
	
	# 连接信号
	ASA.connect("onASAAttributionReceived", self, "_on_attribution_received")
	ASA.connect("onAppSAReportSuccess", self, "_on_appsa_report_success")
	ASA.connect("onAppSAReportFailed", self, "_on_appsa_report_failed")
	
	# 检查是否支持 ASA
	if not ASA.is_supported():
		print("[ASA Example] AdServices not supported on this device (requires iOS 14.3+)")
		return
	
	# 如果启用自动归因且是首次启动
	if auto_attribution and is_first_launch():
		print("[ASA Example] First launch detected, starting attribution...")
		start_attribution()
	else:
		print("[ASA Example] Not first launch or auto attribution disabled")
		# 尝试加载本地缓存的归因数据
		if ASA.load_attribution_data():
			print("[ASA Example] Attribution data loaded from cache")

# ============================================================================
# ASA 归因流程
# ============================================================================

func start_attribution():
	"""开始归因流程"""
	print("[ASA Example] Waiting ", attribution_delay, " seconds before attribution...")
	
	# 延迟后执行归因（符合 Apple 最佳实践）
	yield(get_tree().create_timer(attribution_delay), "timeout")
	
	print("[ASA Example] Requesting attribution...")
	ASA.perform_attribution()

func _on_attribution_received(data: String, code: int, message: String):
	"""归因数据接收完成"""
	print("[ASA Example] Attribution callback: code=", code)
	
	if code == 200:
		# 归因成功
		var json = JSON.parse(data)
		if json.error == OK:
			var attr = json.result
			
			print("[ASA Example] Attribution Success!")
			print("  - From ASA: ", attr.get("attribution", false))
			print("  - Campaign ID: ", attr.get("campaignId", ""))
			print("  - Ad Group ID: ", attr.get("adGroupId", ""))
			print("  - Keyword ID: ", attr.get("keywordId", ""))
			print("  - Country: ", attr.get("countryOrRegion", ""))
			print("  - Conversion Type: ", attr.get("conversionType", ""))
			print("  - Click Date: ", attr.get("clickDate", ""))
			
			# 保存归因数据
			if save_attribution:
				ASA.save_attribution_data()
			
			# 标记已完成归因
			mark_attribution_completed()
			
			# 自动上报激活
			if auto_report_activation and attr.get("attribution", false):
				print("[ASA Example] Auto reporting activation...")
				yield(get_tree().create_timer(0.5), "timeout")
				ASA.report_activation()
		else:
			print("[ASA Example] Failed to parse attribution data")
	else:
		# 归因失败
		print("[ASA Example] Attribution failed: ", message)
		
		# 对于可重试的错误，可以在这里实现重试逻辑
		if code == 404 or code == 500:
			print("[ASA Example] This error can be retried")

# ============================================================================
# AppSA 事件上报示例
# ============================================================================

func report_user_register():
	"""用户注册时调用"""
	print("[ASA Example] Reporting register event...")
	ASA.report_register()

func report_user_login():
	"""用户登录时调用"""
	print("[ASA Example] Reporting login event...")
	ASA.report_login()

func report_user_purchase(amount: float, currency: String = "USD"):
	"""
	用户付费时调用
	
	Args:
	    amount: 付费金额
	    currency: 货币类型（USD, RMB 等）
	"""
	print("[ASA Example] Reporting revenue: ", amount, " ", currency)
	ASA.report_revenue(amount, currency)

func report_user_retention_day1():
	"""用户 1 日留存时调用（按次上报）"""
	print("[ASA Example] Reporting day1 retention (instant)...")
	ASA.report_retention_day1_instant()

func report_daily_retention_summary(day: int, amount: int):
	"""
	上报每日留存汇总数据
	
	Args:
	    day: 留存天数（1, 3, 7）
	    amount: 留存用户数量
	"""
	var date = get_date_string()
	print("[ASA Example] Reporting day", day, " retention summary: ", amount, " users on ", date)
	
	match day:
		1:
			ASA.report_retention_day1_summary(amount, date)
		3:
			ASA.report_retention_day3_summary(amount, date)
		7:
			ASA.report_retention_day7_summary(amount, date)
		_:
			push_error("Invalid retention day: ", day)

# ============================================================================
# AppSA 上报回调
# ============================================================================

func _on_appsa_report_success(response: Dictionary):
	"""AppSA 上报成功"""
	print("[ASA Example] AppSA report success: ", response)

func _on_appsa_report_failed(error_message: String):
	"""AppSA 上报失败"""
	print("[ASA Example] AppSA report failed: ", error_message)

# ============================================================================
# 辅助方法
# ============================================================================

func is_first_launch() -> bool:
	"""检查是否首次启动（是否已完成过归因）"""
	return not config_file.get_value("asa", ASA_REQUESTED_KEY, false)

func mark_attribution_completed():
	"""标记归因已完成"""
	config_file.set_value("asa", ASA_REQUESTED_KEY, true)
	config_file.save("user://app_config.cfg")
	print("[ASA Example] Attribution marked as completed")

func get_date_string() -> String:
	"""获取当前日期字符串（YYYY-MM-DD 格式）"""
	var datetime = OS.get_datetime()
	return "%04d-%02d-%02d" % [datetime.year, datetime.month, datetime.day]

# ============================================================================
# 测试方法（可在编辑器中调用）
# ============================================================================

func test_attribution():
	"""测试归因功能"""
	print("[ASA Example] Testing attribution...")
	start_attribution()

func test_activation_report():
	"""测试激活上报"""
	print("[ASA Example] Testing activation report...")
	if ASA.has_attribution_data():
		ASA.report_activation()
	else:
		print("[ASA Example] No attribution data available")

func test_event_report():
	"""测试事件上报"""
	print("[ASA Example] Testing event reports...")
	report_user_register()
	yield(get_tree().create_timer(0.5), "timeout")
	report_user_login()
	yield(get_tree().create_timer(0.5), "timeout")
	report_user_purchase(99.99, "USD")

func reset_attribution_flag():
	"""重置归因标记（用于测试）"""
	config_file.set_value("asa", ASA_REQUESTED_KEY, false)
	config_file.save("user://app_config.cfg")
	print("[ASA Example] Attribution flag reset")
