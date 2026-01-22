extends Node

# ASA 归因和 AppSA 上报示例
# 演示如何使用ASA插件进行归因和AppSAReporter进行数据上报

const LOG_PREFIX = "[ASA Example]"
const ASA_REQUESTED_KEY = "asa_attribution_requested"
const REGISTERED_KEY = "asa_user_registered"
const MAX_RETRY_COUNT = 3
const RETRY_DELAY = 5.0

# 配置
export var appsa_from_key: String = "your_from_key_here"
export var auto_attribution: bool = true
export var attribution_delay: float = 1.0
export var auto_report_activation: bool = true
export var save_attribution: bool = true
export var auto_report_register: bool = true
export var auto_report_login: bool = true

# 内部变量
var config_file: ConfigFile
var retry_count: int = 0
var appsa_reporter: HTTPRequest  # AppSAReporter实例

func _ready():
	call_deferred("_ready_late")

func _ready_late():
	if OS.get_name() != "iOS":
		print(LOG_PREFIX, " Not iOS platform")
		return
	
	if not ASA:
		print(LOG_PREFIX, " ASA not available")
		return
	
	# 初始化配置
	config_file = ConfigFile.new()
	config_file.load("user://app_config.cfg")
	
	# 创建AppSA上报器
	var AppSAReporter = load("res://addons/godot3_asa/appsa_reporter.gd")
	appsa_reporter = AppSAReporter.new()
	add_child(appsa_reporter)
	
	if not appsa_from_key.empty() and appsa_from_key != "your_from_key_here":
		appsa_reporter.set_from_key(appsa_from_key)
	else:
		print(LOG_PREFIX, " Warning: from_key not configured")
	
	# 连接信号
	if not ASA.is_connected("onASAAttributionReceived", self, "_on_attribution_received"):
		ASA.connect("onASAAttributionReceived", self, "_on_attribution_received")
	if not appsa_reporter.is_connected("report_success", self, "_on_appsa_success"):
		appsa_reporter.connect("report_success", self, "_on_appsa_success")
	if not appsa_reporter.is_connected("report_failed", self, "_on_appsa_failed"):
		appsa_reporter.connect("report_failed", self, "_on_appsa_failed")
	
	if not ASA.is_supported():
		print(LOG_PREFIX, " AdServices not supported")
		return
	
	# 上报注册/登录（自动排队）
	if auto_report_register and is_first_launch():
		print(LOG_PREFIX, " Reporting register...")
		appsa_reporter.report_event(ASA.get_attribution_data(), "asa_register")
		mark_registered()
	
	if auto_report_login:
		print(LOG_PREFIX, " Reporting login...")
		appsa_reporter.report_event(ASA.get_attribution_data(), "asa_login")
	
	if auto_report_login:
		print(LOG_PREFIX, " Reporting login...")
		appsa_reporter.report_event(ASA.get_attribution_data(), "asa_login")
	
	# 首次启动且开启自动归因
	if auto_attribution and is_first_launch():
		print(LOG_PREFIX, " Starting attribution...")
		start_attribution()
	else:
		ASA.load_attribution_data()

func start_attribution():
	"""开始归因流程"""
	yield(get_tree().create_timer(attribution_delay), "timeout")
	retry_count = 0
	ASA.perform_attribution()

func _on_attribution_received(attribution_data: String, error_code: int, error_message: String):
	"""归因回调"""
	if error_code == 200:
		var json = JSON.parse(attribution_data)
		if json.error == OK:
			var attr = json.result
			print(LOG_PREFIX, " Attribution success - from ASA: ", attr.get("attribution", false))
			
			if save_attribution:
				ASA.save_attribution_data()
			
			mark_attribution_completed()
			retry_count = 0
			
			# 自动上报激活
			if auto_report_activation and attr.get("attribution", false):
				print(LOG_PREFIX, " Reporting activation...")
				yield(get_tree().create_timer(0.5), "timeout")
				appsa_reporter.report_activation(attr)
		else:
			_retry_attribution_if_needed(error_code)
	else:
		_retry_attribution_if_needed(error_code)

func _retry_attribution_if_needed(code: int):
	"""重试归因"""
	var should_retry = code in [404, 500, 502, 503]
	
	if should_retry and retry_count < MAX_RETRY_COUNT:
		retry_count += 1
		print(LOG_PREFIX, " Retrying (%d/%d)..." % [retry_count, MAX_RETRY_COUNT])
		yield(get_tree().create_timer(RETRY_DELAY), "timeout")
		ASA.perform_attribution()
	elif retry_count >= MAX_RETRY_COUNT:
		print(LOG_PREFIX, " Max retries reached")
		retry_count = 0

# 事件上报示例
func report_user_purchase(amount: float, currency: String = "USD"):
	"""上报收入"""
	print(LOG_PREFIX, " Reporting revenue: ", amount, " ", currency)
	var event_values = {"revenue": "%.4f" % amount, "currency": currency}
	appsa_reporter.report_event(ASA.get_attribution_data(), "asa_revenue", event_values)

func report_user_retention_day1():
	"""上报1日留存"""
	print(LOG_PREFIX, " Reporting day1 retention...")
	appsa_reporter.report_event(ASA.get_attribution_data(), "asa_retention_day1")

func _on_appsa_success(response: Dictionary):
	"""上报成功"""
	print(LOG_PREFIX, " AppSA report success: ", response)

func _on_appsa_failed(error_message: String):
	"""上报失败"""
	print(LOG_PREFIX, " AppSA report failed: ", error_message)

# 辅助方法
func is_first_launch() -> bool:
	return not config_file.get_value("asa", ASA_REQUESTED_KEY, false)

func mark_attribution_completed():
	config_file.set_value("asa", ASA_REQUESTED_KEY, true)
	config_file.save("user://app_config.cfg")

func mark_registered():
	config_file.set_value("asa", REGISTERED_KEY, true)
	config_file.save("user://app_config.cfg")

# 测试方法
func test_attribution():
	start_attribution()

func test_activation_report():
	if ASA.has_attribution_data():
		appsa_reporter.report_activation(ASA.get_attribution_data())

func test_event_report():
	var attr = ASA.get_attribution_data()
	appsa_reporter.report_event(attr, "asa_register")
	yield(get_tree().create_timer(0.5), "timeout")
	appsa_reporter.report_event(attr, "asa_login")
	yield(get_tree().create_timer(0.5), "timeout")
	report_user_purchase(99.99, "USD")

func reset_attribution_flag():
	config_file.set_value("asa", ASA_REQUESTED_KEY, false)
	config_file.set_value("asa", REGISTERED_KEY, false)
	config_file.save("user://app_config.cfg")
	print(LOG_PREFIX, " Flags reset")
