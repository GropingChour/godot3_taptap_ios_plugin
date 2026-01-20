extends Node

# Apple Search Ads (ASA) Attribution SDK for Godot 3.x
#
# 这个脚本为 Godot 3.x 提供 ASA 归因和 AppSA 数据上报功能，包括：
# - ASA 自归因（AdServices）
# - AppSA 激活数据上报
# - AppSA 应用内事件上报（注册、登录、付费、留存等）
#
# 使用流程：
# 1. App 首次启动时调用 performAttribution() 进行归因
# 2. 归因成功后通过 onASAAttributionReceived 信号接收数据
# 3. 调用 report_activation() 上报激活数据到 AppSA
# 4. 在用户行为发生时调用相应的事件上报方法
#
# 信号列表：
# - onASAAttributionReceived: 归因数据接收完成
# - onASATokenReceived: Token 获取完成
# - onAppSAReportSuccess: AppSA 上报成功
# - onAppSAReportFailed: AppSA 上报失败

const PLUGIN_NAME := "Godot3ASA"

# AppSA API 配置
var appsa_from_key: String = ""  # 由七麦提供的 from 参数
const APPSA_ACTIVATION_URL = "https://api.appsa.com/thirdsdk/custom"
const APPSA_EVENT_URL = "https://api.appsa.com/thirdsdk/custom_inapp_event"

# 归因数据缓存
var attribution_data: Dictionary = {}
var is_attributed: bool = false
var singleton

# HTTP 请求节点
var http_request: HTTPRequest

# 待处理的上报请求队列（归因完成前暂存）
var pending_reports: Array = []
var is_attribution_pending: bool = false

# 信号定义
signal onASAAttributionReceived(data, code, message)
signal onASATokenReceived(token, code, message)
signal onAppSAReportSuccess(response)
signal onAppSAReportFailed(error_message)

func _ready():
	var is_ios = OS.get_name() == "iOS"
	print("[ASA] Initializing... iOS: %s" % is_ios)
	
	if not is_ios:
		print("[ASA] Not iOS platform, plugin disabled")
		return
	
	if Engine.has_singleton(PLUGIN_NAME):
		singleton = Engine.get_singleton(PLUGIN_NAME)
		singleton.connect("onASAAttributionReceived", self, "_on_attribution_received")
		singleton.connect("onASATokenReceived", self, "_on_token_received")
		print("[ASA] ", PLUGIN_NAME, " singleton ready")
	else:
		print("[ASA] ", PLUGIN_NAME, " singleton not found")
	
	# 创建 HTTP 请求节点
	http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.connect("request_completed", self, "_on_http_request_completed")

# ============================================================================
# ASA 归因功能
# ============================================================================

func is_supported() -> bool:
	"""检查当前设备是否支持 ASA 归因（iOS 14.3+）"""
	if not singleton:
		return false
	return singleton.isSupported()

func perform_attribution() -> void:
	# 执行 ASA 归因（推荐使用）
	# 一键完成 token 获取和归因数据请求
	# 建议在 App 首次启动时，获取网络权限后延迟 500-1000ms 调用
	if not singleton:
		push_error("[ASA] Singleton not available")
		return
	
	print("[ASA] Performing attribution...")
	is_attribution_pending = true
	singleton.performAttribution()

func request_attribution_token() -> void:
	"""
	手动获取 ASA 归因 token
	一般情况下使用 perform_attribution() 即可，无需单独调用此方法
	"""
	if not singleton:
		push_error("[ASA] Singleton not available")
		return
	
	singleton.requestAttributionToken()

func request_attribution_data(token: String) -> void:
	"""
	使用 token 手动请求归因数据
	一般情况下使用 perform_attribution() 即可，无需单独调用此方法
	
	Args:
	    token: 通过 request_attribution_token() 获取的 token
	"""
	if not singleton:
		push_error("[ASA] Singleton not available")
		return
	
	singleton.requestAttributionData(token)

func get_attribution_data() -> Dictionary:
	"""
	获取缓存的归因数据
	
	Returns:
	    Dictionary: 归因数据，如果未归因则返回空字典
	"""
	return attribution_data

func is_from_asa() -> bool:
	"""
	检查用户是否来自 ASA 广告
	
	Returns:
	    bool: true 表示来自 ASA，false 表示不来自或未归因
	"""
	return is_attributed and attribution_data.get("attribution", false)

# ============================================================================
# AppSA 数据上报功能
# ============================================================================

func set_appsa_from_key(from_key: String) -> void:
	"""
	设置 AppSA 的 from 参数
	此参数由七麦提供，必须在上报前设置
	
	Args:
	    from_key: 七麦提供的 from 参数
	"""
	appsa_from_key = from_key
	print("[ASA] AppSA from key set: ", from_key)

func report_activation(app_name: String = "") -> void:
	# 上报激活数据到 AppSA
	# 应在归因成功后调用，且仅在首次激活时上报一次
	# Args:
	#     app_name: 应用名称（可选，默认从 ProjectSettings 获取）
	
	# 如果归因正在进行中，加入队列等待
	if is_attribution_pending:
		print("[ASA] Attribution pending, queueing activation report...")
		pending_reports.append({"type": "activation", "app_name": app_name})
		return
	
	# 归因未完成，直接返回
	if not is_attributed:
		print("[ASA] ERROR: Cannot report activation: attribution data not available")
		return
	
	if not attribution_data.get("attribution", false):
		print("[ASA] User is not from ASA, skip activation report")
		return
	
	if appsa_from_key.empty():
		print("[ASA] ERROR: AppSA from_key not set, call set_appsa_from_key() first")
		return
	
	_do_report_activation(app_name)

func _do_report_activation(app_name: String) -> void:
	# 实际执行激活上报的内部方法
	var device_info = _get_device_info()
	if app_name.empty():
		if ProjectSettings.has_setting("application/config/name"):
			app_name = ProjectSettings.get_setting("application/config/name")
		else:
			app_name = ""
	
	var data = {
		"install_time": str(OS.get_unix_time() * 1000),  # 毫秒时间戳
		"device_model": device_info.model,
		"os_version": device_info.os_version,
		"app_name": app_name,
		"attribution": attribution_data.get("attribution", false),
		"org_id": str(attribution_data.get("orgId", "")),
		"campaign_id": str(attribution_data.get("campaignId", "")),
		"adgroup_id": str(attribution_data.get("adGroupId", "")),
		"keyword_id": str(attribution_data.get("keywordId", "")),
		"creativeset_id": str(attribution_data.get("adId", "")),
		"conversion_type": attribution_data.get("conversionType", ""),
		"country_or_region": attribution_data.get("countryOrRegion", ""),
		"click_date": attribution_data.get("clickDate", ""),
		"source_from": "ads",
		"claim_type": attribution_data.get("claimType", "Click")
	}
	
	_send_appsa_request(APPSA_ACTIVATION_URL, data, "activation")

func report_register() -> void:
	"""上报注册事件（按次上报）"""
	_report_event("asa_register", {}, true)

func report_login() -> void:
	"""上报登录事件（按次上报）"""
	_report_event("asa_login", {}, true)

func report_revenue(amount: float, currency: String = "USD") -> void:
	"""
	上报收入事件（按次上报）
	
	Args:
	    amount: 订单金额，支持小数点后四位
	    currency: 货币符号，如 "USD", "RMB"
	"""
	var event_values = {
		"revenue": "%.4f" % amount,
		"currency": currency
	}
	_report_event("asa_revenue", event_values, true)

func report_pay_unique_user() -> void:
	"""上报付费用户数（按次上报，需客户端排重）"""
	_report_event("asa_pay_unique_user", {}, true)

func report_pay_device() -> void:
	"""上报付费设备数（按次上报，需客户端排重）"""
	_report_event("asa_pay_device", {}, true)

func report_retention_day1_instant() -> void:
	"""上报 1 日留存（按次上报）"""
	_report_event("asa_retention_day1", {}, true)

func report_retention_day3_instant() -> void:
	"""上报 3 日留存（按次上报）"""
	_report_event("asa_retention_day3", {}, true)

func report_retention_day7_instant() -> void:
	"""上报 7 日留存（按次上报）"""
	_report_event("asa_retention_day7", {}, true)

func report_retention_day1_summary(amount: int, date: String) -> void:
	"""
	上报 1 日留存汇总数据（汇总上报）
	一天只上报一次，新数据会覆盖旧数据
	
	Args:
	    amount: 留存用户数量
	    date: 事件发生日期，格式 "YYYY-MM-DD"
	"""
	var event_values = {"amount": str(amount)}
	_report_event("asa_retention_day1", event_values, false, date)

func report_retention_day3_summary(amount: int, date: String) -> void:
	"""
	上报 3 日留存汇总数据（汇总上报）
	
	Args:
	    amount: 留存用户数量
	    date: 事件发生日期，格式 "YYYY-MM-DD"
	"""
	var event_values = {"amount": str(amount)}
	_report_event("asa_retention_day3", event_values, false, date)

func report_retention_day7_summary(amount: int, date: String) -> void:
	"""
	上报 7 日留存汇总数据（汇总上报）
	
	Args:
	    amount: 留存用户数量
	    date: 事件发生日期，格式 "YYYY-MM-DD"
	"""
	var event_values = {"amount": str(amount)}
	_report_event("asa_retention_day7", event_values, false, date)

# ============================================================================
# 内部方法
# ============================================================================

func _report_event(event_name: String, event_values: Dictionary, is_instant: bool, event_date: String = "") -> void:
	"""
	内部方法：上报事件到 AppSA
	
	Args:
	    event_name: 事件名称
	    event_values: 事件值
	    is_instant: true=按次上报, false=汇总上报
	    event_date: 事件日期（仅汇总上报需要），格式 "YYYY-MM-DD"
	"""
	# 如果归因正在进行中，加入队列等待
	if is_attribution_pending:
		print("[ASA] Attribution pending, queueing event: ", event_name)
		pending_reports.append({
			"type": "event",
			"event_name": event_name,
			"event_values": event_values,
			"is_instant": is_instant,
			"event_date": event_date
		})
		return
	
	# 归因已完成，但用户不是来自 ASA，跳过上报
	if not is_attributed or not attribution_data.get("attribution", false):
		print("[ASA] User is not from ASA, skip event report: ", event_name)
		return
	
	if appsa_from_key.empty():
		push_error("[ASA] AppSA from_key not set")
		return
	
	_do_report_event(event_name, event_values, is_instant, event_date)

func _do_report_event(event_name: String, event_values: Dictionary, is_instant: bool, event_date: String = "") -> void:
	"""
	实际执行事件上报的内部方法
	"""
	var data = {
		"org_id": str(attribution_data.get("orgId", "")),
		"campaign_id": str(attribution_data.get("campaignId", "")),
		"adgroup_id": str(attribution_data.get("adGroupId", "")),
		"keyword_id": str(attribution_data.get("keywordId", "")),
		"creativeset_id": str(attribution_data.get("adId", "")),
		"country_or_region": attribution_data.get("countryOrRegion", ""),
		"event_name": event_name,
		"claim_type": attribution_data.get("claimType", "Click")
	}
	
	if not event_values.empty():
		data["event_values"] = event_values
	
	if is_instant:
		# 按次上报：传 event_time
		data["event_time"] = str(OS.get_unix_time())
	else:
		# 汇总上报：传 event_date
		if event_date.empty():
			print("[ASA] ERROR: event_date is required for summary report")
			return
		data["event_date"] = event_date
	
	_send_appsa_request(APPSA_EVENT_URL, data, "event:%s" % event_name)

func _send_appsa_request(url: String, data: Dictionary, request_type: String) -> void:
	"""
	内部方法：发送 AppSA HTTP 请求
	"""
	var full_url = url + "?from=" + appsa_from_key
	var json_data = to_json(data)
	
	print("[ASA] Sending AppSA request: ", request_type)
	print("[ASA] URL: ", full_url)
	print("[ASA] Data: ", json_data)
	
	var headers = [
		"User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
		"Content-Type: application/x-www-form-urlencoded"
	]
	
	var body = "data=" + json_data.percent_encode()
	
	# 保存请求类型到 meta，用于回调识别
	http_request.set_meta("request_type", request_type)
	
	var err = http_request.request(full_url, headers, true, HTTPClient.METHOD_POST, body)
	if err != OK:
		var error_msg = "[ASA] HTTP request failed: %d" % err
		print("[ASA] ERROR: ", error_msg)
		emit_signal("onAppSAReportFailed", error_msg)

func _on_http_request_completed(result: int, response_code: int, headers: PoolStringArray, body: PoolByteArray) -> void:
	"""HTTP 请求完成回调"""
	var request_type = http_request.get_meta("request_type") if http_request.has_meta("request_type") else "unknown"
	
	if result != HTTPRequest.RESULT_SUCCESS:
		var error_msg = "[ASA] AppSA request failed (%s): result=%d" % [request_type, result]
		print("[ASA] ERROR: ", error_msg)
		emit_signal("onAppSAReportFailed", error_msg)
		return
	
	var response_text = body.get_string_from_utf8()
	print("[ASA] AppSA response (%s): code=%d, body=%s" % [request_type, response_code, response_text])
	
	if response_code != 200:
		var error_msg = "[ASA] AppSA returned error code: %d" % response_code
		print("[ASA] ERROR: ", error_msg)
		emit_signal("onAppSAReportFailed", error_msg)
		return
	
	# 解析响应
	var json = JSON.parse(response_text)
	if json.error != OK:
		var error_msg = "[ASA] Failed to parse AppSA response"
		print("[ASA] ERROR: ", error_msg)
		emit_signal("onAppSAReportFailed", error_msg)
		return
	
	var response = json.result
	if response.get("code", -1) == 10000:
		print("[ASA] AppSA report success: ", request_type)
		emit_signal("onAppSAReportSuccess", response)
	else:
		var error_msg = "[ASA] AppSA returned error: code=%s, msg=%s" % [response.get("code", ""), response.get("msg", "")]
		print("[ASA] ERROR: ", error_msg)
		emit_signal("onAppSAReportFailed", error_msg)

func _on_attribution_received(data: String, code: int, message: String) -> void:
	"""归因数据接收回调"""
	print("[ASA] Attribution received: code=", code)
	
	if code == 200 and not data.empty():
		var json = JSON.parse(data)
		if json.error == OK:
			attribution_data = json.result
			is_attributed = true
			is_attribution_pending = false  # 归因完成，清除待处理标志
			print("[ASA] Attribution data parsed successfully")
			print("[ASA] Attribution: ", attribution_data.get("attribution", false))
			print("[ASA] Campaign ID: ", attribution_data.get("campaignId", ""))
			
			# 处理队列中的待处理上报
			_process_pending_reports()
		else:
			print("[ASA] ERROR: Failed to parse attribution data")
			is_attribution_pending = false  # 解析失败也清除标志
	else:
		is_attribution_pending = false  # 归因失败，清除标志
	
	emit_signal("onASAAttributionReceived", data, code, message)

func _on_token_received(token: String, code: int, message: String) -> void:
	"""Token 接收回调"""
	print("[ASA] Token received: code=", code)
	emit_signal("onASATokenReceived", token, code, message)

func _process_pending_reports() -> void:
	"""处理队列中的待处理上报"""
	if pending_reports.empty():
		return
	
	print("[ASA] Processing %d pending reports..." % pending_reports.size())
	
	for report in pending_reports:
		if report["type"] == "activation":
			_do_report_activation(report["app_name"])
		elif report["type"] == "event":
			_do_report_event(
				report["event_name"],
				report["event_values"],
				report["is_instant"],
				report["event_date"]
			)
	
	pending_reports.clear()
	print("[ASA] All pending reports processed")

func _get_device_info() -> Dictionary:
	"""获取设备信息"""
	var model = "iPhone"  # 默认值
	var os_version = ""
	
	# 尝试获取设备型号
	if OS.has_feature("iOS"):
		# iOS 设备
		var device_name = OS.get_model_name()
		if "iPad" in device_name:
			model = "iPad"
		else:
			model = "iPhone"
		
		# 获取系统版本
		os_version = OS.get_name() # 可能返回 "iOS"
		# 尝试获取更详细的版本信息
		var sys_info = OS.get_system_info()
		if sys_info.has("version"):
			os_version = sys_info.version
	
	return {
		"model": model,
		"os_version": os_version
	}

# ============================================================================
# 辅助方法
# ============================================================================

func save_attribution_data(file_path: String = "user://asa_attribution.json") -> bool:
	"""
	保存归因数据到本地文件
	
	Args:
	    file_path: 保存路径，默认 "user://asa_attribution.json"
	    
	Returns:
	    bool: 保存是否成功
	"""
	if not is_attributed:
		return false
	
	var file = File.new()
	var err = file.open(file_path, File.WRITE)
	if err != OK:
		print("[ASA] ERROR: Failed to open file for writing: ", file_path)
		return false
	
	file.store_string(to_json(attribution_data))
	file.close()
	print("[ASA] Attribution data saved to: ", file_path)
	return true

func load_attribution_data(file_path: String = "user://asa_attribution.json") -> bool:
	"""
	从本地文件加载归因数据
	
	Args:
	    file_path: 文件路径，默认 "user://asa_attribution.json"
	    
	Returns:
	    bool: 加载是否成功
	"""
	var file = File.new()
	if not file.file_exists(file_path):
		return false
	
	var err = file.open(file_path, File.READ)
	if err != OK:
		print("[ASA] ERROR: Failed to open file for reading: ", file_path)
		return false
	
	var json_text = file.get_as_text()
	file.close()
	
	var json = JSON.parse(json_text)
	if json.error != OK:
		print("[ASA] ERROR: Failed to parse saved attribution data")
		return false
	
	attribution_data = json.result
	is_attributed = true
	print("[ASA] Attribution data loaded from: ", file_path)
	return true

func has_attribution_data() -> bool:
	"""检查是否已有归因数据"""
	return is_attributed and not attribution_data.empty()
