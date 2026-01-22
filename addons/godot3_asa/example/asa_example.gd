extends Node

# ASA 归因和 AppSA 上报示例节点
# 
# 这个节点演示了如何使用 ASA 插件进行归因和数据上报
# 可以直接添加到场景中使用，或参考此代码集成到自己的项目中

# ============================================================================
# 常量配置
# ============================================================================

const LOG_PREFIX = "[ASA Example]"
const ASA_REQUESTED_KEY = "asa_attribution_requested"
const REGISTERED_KEY = "asa_user_registered"
const MAX_RETRY_COUNT = 3
const RETRY_DELAY = 5.0

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

# 是否自动上报注册和登录事件
export var auto_report_register: bool = true
export var auto_report_login: bool = true

# ============================================================================
# 内部变量
# ============================================================================

var config_file: ConfigFile
var retry_count: int = 0

# ============================================================================
# 初始化
# ============================================================================
# 在节点准备好后执行初始化逻辑, 保证ASA的_ready优先执行
func _ready():
	call_deferred("_ready_late")

func _ready_late():
	# 检查是否在 iOS 平台
	if OS.get_name() != "iOS":
		print(LOG_PREFIX, " Not iOS platform, example disabled")
		return
	
	# 检查ASA autoload是否存在
	if not has_node("/root/ASA"):
		print(LOG_PREFIX, " ERROR: ASA autoload not found")
		return
	
	var asa_node = get_node("/root/ASA")
	if not asa_node:
		print(LOG_PREFIX, " ERROR: ASA node is null")
		return
	
	# 初始化配置文件
	config_file = ConfigFile.new()
	config_file.load("user://app_config.cfg")
	
	# 设置 AppSA from 参数
	if not appsa_from_key.empty() and appsa_from_key != "your_from_key_here":
		asa_node.set_appsa_from_key(appsa_from_key)
	else:
		print(LOG_PREFIX, " Warning: AppSA from_key not configured")
	
	# 连接信号（防止重复连接）
	if not asa_node.is_connected("onASAAttributionReceived", self, "_on_attribution_received"):
		asa_node.connect("onASAAttributionReceived", self, "_on_attribution_received")
	if not asa_node.is_connected("onAppSAReportSuccess", self, "_on_appsa_report_success"):
		asa_node.connect("onAppSAReportSuccess", self, "_on_appsa_report_success")
	if not asa_node.is_connected("onAppSAReportFailed", self, "_on_appsa_report_failed"):
		asa_node.connect("onAppSAReportFailed", self, "_on_appsa_report_failed")
	
	# 检查是否支持 ASA
	if not asa_node.is_supported():
		print(LOG_PREFIX, " AdServices not supported on this device (requires iOS 14.3+)")
		return
	
	# 检查并上报注册和登录事件
	# 注意：这些调用是安全的，即使归因还未完成
	# SDK 会自动将事件加入队列，等待归因完成后处理
	if auto_report_register and is_first_launch():
		print(LOG_PREFIX, " First launch - reporting register event...")
		asa_node.report_register()
		mark_registered()
	
	# 上报登录事件
	if auto_report_login:
		print(LOG_PREFIX, " Reporting login event...")
		asa_node.report_login()
	
	# 如果启用自动归因且是首次启动
	if auto_attribution and is_first_launch():
		print(LOG_PREFIX, " First launch detected, starting attribution...")
		start_attribution()
	else:
		print(LOG_PREFIX, " Not first launch or auto attribution disabled")
		# 尝试加载本地缓存的归因数据
		if asa_node.load_attribution_data():
			print(LOG_PREFIX, " Attribution data loaded from cache")

# ============================================================================
# ASA 归因流程
# ============================================================================

func start_attribution():
	# 开始归因流程
	print(LOG_PREFIX, " Waiting ", attribution_delay, " seconds before attribution...")
	
	# 延迟后执行归因（符合 Apple 最佳实践）
	yield(get_tree().create_timer(attribution_delay), "timeout")
	
	print(LOG_PREFIX, " Requesting attribution...")
	retry_count = 0
	ASA.perform_attribution()

func _on_attribution_received(data: String, code: int, message: String):
	# 归因数据接收完成
	print(LOG_PREFIX, " Attribution callback: code=", code)
	
	if code == 200:
		# 归因成功
		var json = JSON.parse(data)
		if json.error == OK:
			var attr = json.result
			
			print(LOG_PREFIX, " Attribution Success!")
			print(LOG_PREFIX, "  - From ASA: ", attr.get("attribution", false))
			print(LOG_PREFIX, "  - Campaign ID: ", attr.get("campaignId", ""))
			print(LOG_PREFIX, "  - Ad Group ID: ", attr.get("adGroupId", ""))
			print(LOG_PREFIX, "  - Keyword ID: ", attr.get("keywordId", ""))
			print(LOG_PREFIX, "  - Country: ", attr.get("countryOrRegion", ""))
			print(LOG_PREFIX, "  - Conversion Type: ", attr.get("conversionType", ""))
			print(LOG_PREFIX, "  - Click Date: ", attr.get("clickDate", ""))
			
			# 保存归因数据
			if save_attribution:
				ASA.save_attribution_data()
			
			# 标记已完成归因
			mark_attribution_completed()
			
			# 重置重试计数
			retry_count = 0
			
			# 自动上报激活
			if auto_report_activation and attr.get("attribution", false):
				print(LOG_PREFIX, " Auto reporting activation...")
				yield(get_tree().create_timer(0.5), "timeout")
				ASA.report_activation()
		else:
			print(LOG_PREFIX, " Failed to parse attribution data")
			_retry_attribution_if_needed(code)
	else:
		# 归因失败
		print(LOG_PREFIX, " Attribution failed: ", message)
		_retry_attribution_if_needed(code)

func _retry_attribution_if_needed(code: int):
	# 检查是否需要重试
	# 对于可重试的错误（404, 500等服务端错误），执行重试逻辑
	var should_retry = false
	
	if code == 404 or code == 500 or code == 502 or code == 503:
		should_retry = true
	
	if should_retry and retry_count < MAX_RETRY_COUNT:
		retry_count += 1
		print(LOG_PREFIX, " Retrying attribution (attempt ", retry_count, "/", MAX_RETRY_COUNT, ")...")
		yield(get_tree().create_timer(RETRY_DELAY), "timeout")
		ASA.perform_attribution()
	elif retry_count >= MAX_RETRY_COUNT:
		print(LOG_PREFIX, " Max retry count reached, giving up")
		retry_count = 0

# ============================================================================
# AppSA 事件上报示例
# ============================================================================

func report_user_register():
	# 用户注册时调用
	print(LOG_PREFIX, " Reporting register event...")
	ASA.report_register()

func report_user_login():
	# 用户登录时调用
	print(LOG_PREFIX, " Reporting login event...")
	ASA.report_login()

func report_user_purchase(amount: float, currency: String = "USD"):
	# 用户付费时调用
	# Args:
	#     amount: 付费金额
	#     currency: 货币类型（USD, RMB 等）
	print(LOG_PREFIX, " Reporting revenue: ", amount, " ", currency)
	ASA.report_revenue(amount, currency)

func report_user_retention_day1():
	# 用户 1 日留存时调用（按次上报）
	print(LOG_PREFIX, " Reporting day1 retention (instant)...")
	ASA.report_retention_day1_instant()

# ============================================================================
# AppSA 上报回调
# ============================================================================

func _on_appsa_report_success(response: Dictionary):
	# AppSA 上报成功
	print(LOG_PREFIX, " AppSA report success: ", response)

func _on_appsa_report_failed(error_message: String):
	# AppSA 上报失败
	print(LOG_PREFIX, " AppSA report failed: ", error_message)

# ============================================================================
# 辅助方法
# ============================================================================

func is_first_launch() -> bool:
	# 检查是否首次启动（是否已完成过归因）
	return not config_file.get_value("asa", ASA_REQUESTED_KEY, false)

func mark_attribution_completed():
	# 标记归因已完成
	config_file.set_value("asa", ASA_REQUESTED_KEY, true)
	config_file.save("user://app_config.cfg")
	print(LOG_PREFIX, " Attribution marked as completed")

func mark_registered():
	# 标记用户已注册
	config_file.set_value("asa", REGISTERED_KEY, true)
	config_file.save("user://app_config.cfg")
	print(LOG_PREFIX, " User marked as registered")

# ============================================================================
# 测试方法（可在编辑器中调用）
# ============================================================================

func test_attribution():
	# 测试归因功能
	print(LOG_PREFIX, " Testing attribution...")
	start_attribution()

func test_activation_report():
	# 测试激活上报
	print(LOG_PREFIX, " Testing activation report...")
	if ASA.has_attribution_data():
		ASA.report_activation()
	else:
		print(LOG_PREFIX, " No attribution data available")

func test_event_report():
	# 测试事件上报
	print(LOG_PREFIX, " Testing event reports...")
	report_user_register()
	yield(get_tree().create_timer(0.5), "timeout")
	report_user_login()
	yield(get_tree().create_timer(0.5), "timeout")
	report_user_purchase(99.99, "USD")

func reset_attribution_flag():
	# 重置归因标记（用于测试）
	config_file.set_value("asa", ASA_REQUESTED_KEY, false)
	config_file.set_value("asa", REGISTERED_KEY, false)
	config_file.save("user://app_config.cfg")
	print(LOG_PREFIX, " Attribution and register flags reset")
