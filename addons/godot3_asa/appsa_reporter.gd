extends HTTPRequest

# AppSA 数据上报类
# 
# 独立的AppSA上报工具，继承HTTPRequest
# 在需要上报的地方直接new一个实例使用

# AppSA API 地址
const APPSA_ACTIVATION_URL = "https://api.appsa.com/thirdsdk/custom"
const APPSA_EVENT_URL = "https://api.appsa.com/thirdsdk/custom_inapp_event"

# 配置
var from_key: String = ""

# 信号
signal report_success(response)
signal report_failed(error_message)

func _ready():
	connect("request_completed", self, "_on_request_completed")

func set_from_key(key: String) -> void:
	"""设置七麦提供的from参数"""
	from_key = key

func report_activation(attribution_data: Dictionary, app_name: String = "") -> void:
	"""上报激活数据"""
	if from_key.empty():
		push_error("[AppSA] from_key not set")
		emit_signal("report_failed", "from_key not set")
		return
	
	if attribution_data.empty():
		push_error("[AppSA] attribution_data is empty")
		emit_signal("report_failed", "attribution_data is empty")
		return
	
	var device_info = _get_device_info()
	if app_name.empty():
		if ProjectSettings.has_setting("application/config/name"):
			app_name = ProjectSettings.get_setting("application/config/name")
	
	var data = {
		"install_time": str(OS.get_unix_time() * 1000),
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
	
	_send_request(APPSA_ACTIVATION_URL, data, "activation")

func report_event(attribution_data: Dictionary, event_name: String, event_values: Dictionary = {}, is_instant: bool = true, event_date: String = "") -> void:
	"""上报应用内事件"""
	if from_key.empty():
		push_error("[AppSA] from_key not set")
		emit_signal("report_failed", "from_key not set")
		return
	
	if attribution_data.empty():
		push_error("[AppSA] attribution_data is empty")
		emit_signal("report_failed", "attribution_data is empty")
		return
	
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
		data["event_time"] = str(OS.get_unix_time())
	else:
		if event_date.empty():
			push_error("[AppSA] event_date required for summary report")
			emit_signal("report_failed", "event_date required")
			return
		data["event_date"] = event_date
	
	_send_request(APPSA_EVENT_URL, data, "event:%s" % event_name)

func _send_request(url: String, data: Dictionary, request_type: String) -> void:
	"""发送HTTP请求"""
	var full_url = url + "?from=" + from_key
	var json_data = to_json(data)
	
	var headers = [
		"User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
		"Content-Type: application/x-www-form-urlencoded"
	]
	
	var body = "data=" + json_data.percent_encode()
	set_meta("request_type", request_type)
	
	var err = request(full_url, headers, true, HTTPClient.METHOD_POST, body)
	if err != OK:
		var error_msg = "HTTP request failed: %d" % err
		push_error("[AppSA] " + error_msg)
		emit_signal("report_failed", error_msg)

func _on_request_completed(result: int, response_code: int, headers: PoolStringArray, body: PoolByteArray) -> void:
	"""请求完成回调"""
	var request_type = get_meta("request_type") if has_meta("request_type") else "unknown"
	
	if result != HTTPRequest.RESULT_SUCCESS:
		var error_msg = "Request failed (%s): result=%d" % [request_type, result]
		emit_signal("report_failed", error_msg)
		return
	
	if response_code != 200:
		var error_msg = "HTTP error (%s): code=%d" % [request_type, response_code]
		emit_signal("report_failed", error_msg)
		return
	
	var response_text = body.get_string_from_utf8()
	var json = JSON.parse(response_text)
	if json.error != OK:
		emit_signal("report_failed", "Failed to parse response")
		return
	
	var response = json.result
	if response.get("code", -1) == 10000:
		print("[AppSA] Report success: ", request_type)
		emit_signal("report_success", response)
	else:
		var error_msg = "Server error: code=%s, msg=%s" % [response.get("code", ""), response.get("msg", "")]
		emit_signal("report_failed", error_msg)

func _get_device_info() -> Dictionary:
	"""获取设备信息"""
	var model = "iPhone"
	var os_version = "iOS"
	
	# 优先使用ASA singleton的精确方法
	if Engine.has_singleton("Godot3ASA"):
		var singleton = Engine.get_singleton("Godot3ASA")
		if singleton:
			model = singleton.getDeviceModel()
			os_version = singleton.getSystemVersion()
			return {"model": model, "os_version": os_version}
	
	# 后备方案
	var device_name = OS.get_model_name()
	if "iPad" in device_name:
		model = "iPad"
	elif "iPhone" in device_name:
		model = "iPhone"
	
	os_version = OS.get_name()
	
	return {"model": model, "os_version": os_version}
