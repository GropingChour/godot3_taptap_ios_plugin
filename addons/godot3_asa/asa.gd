extends Node

# Apple Search Ads (ASA) Attribution SDK for Godot 3.x
#
# 提供 ASA 自归因功能（AdServices）
#
# 使用流程：
# 1. App 首次启动时调用 perform_attribution() 进行归因
# 2. 归因成功后通过 onASAAttributionReceived 信号接收数据
# 3. 使用 AppSAReporter 类进行数据上报
#
# 信号列表：
# - onASAAttributionReceived: 归因数据接收完成
# - onASATokenReceived: Token 获取完成

const PLUGIN_NAME := "Godot3ASA"

# 归因数据缓存
var attribution_data: Dictionary = {}
var is_attributed: bool = false
var singleton

# 信号定义
signal onASAAttributionReceived(attribution_data, error_code, error_message)
signal onASATokenReceived(token, error_code, error_message)

func _ready():
	var is_ios = OS.get_name() == "iOS"
	
	if not is_ios:
		return
	
	if Engine.has_singleton(PLUGIN_NAME):
		singleton = Engine.get_singleton(PLUGIN_NAME)
		if singleton:
			if not singleton.is_connected("onASAAttributionReceived", self, "_on_attribution_received"):
				singleton.connect("onASAAttributionReceived", self, "_on_attribution_received")
			if not singleton.is_connected("onASATokenReceived", self, "_on_token_received"):
				singleton.connect("onASATokenReceived", self, "_on_token_received")
			print("[ASA] Initialized")

# ============================================================================
# ASA 归因功能
# ============================================================================

func is_supported() -> bool:
	"""检查当前设备是否支持 ASA 归因（iOS 14.3+）"""
	if not singleton:
		return false
	return singleton.isSupported()

func perform_attribution() -> void:
	"""执行 ASA 归因（推荐使用）"""
	if not singleton:
		return
	
	print("[ASA] Performing attribution...")
	singleton.performAttribution()

func request_attribution_token() -> void:
	"""手动获取 ASA 归因 token"""
	if not singleton:
		return
	
	singleton.requestAttributionToken()

func request_attribution_data(token: String) -> void:
	"""使用 token 手动请求归因数据"""
	if not singleton:
		return
	
	singleton.requestAttributionData(token)

func get_attribution_data() -> Dictionary:
	"""获取缓存的归因数据"""
	return attribution_data

func is_from_asa() -> bool:
	"""检查用户是否来自 ASA 广告"""
	return is_attributed and attribution_data.get("attribution", false)

func has_attribution_data() -> bool:
	"""检查是否已有归因数据"""
	return is_attributed and not attribution_data.empty()

# ============================================================================
# 归因回调
# ============================================================================

func _on_attribution_received(data: String, code: int, message: String) -> void:
	"""归因数据接收回调"""
	if code == 200 and not data.empty():
		var json = JSON.parse(data)
		if json.error == OK:
			attribution_data = json.result
			is_attributed = true
			print("[ASA] Attribution success - from ASA: ", attribution_data.get("attribution", false))
	
	emit_signal("onASAAttributionReceived", data, code, message)

func _on_token_received(token: String, error_code: int, error_message: String) -> void:
	"""Token 接收回调"""
	emit_signal("onASATokenReceived", token, error_code, error_message)

# ============================================================================
# 辅助方法
# ============================================================================

func save_attribution_data(file_path: String = "user://asa_attribution.json") -> bool:
	"""保存归因数据到本地文件"""
	if not is_attributed:
		return false
	
	var file = File.new()
	var err = file.open(file_path, File.WRITE)
	if err != OK:
		return false
	
	file.store_string(to_json(attribution_data))
	file.close()
	return true

func load_attribution_data(file_path: String = "user://asa_attribution.json") -> bool:
	"""从本地文件加载归因数据"""
	var file = File.new()
	if not file.file_exists(file_path):
		return false
	
	var err = file.open(file_path, File.READ)
	if err != OK:
		return false
	
	var json_text = file.get_as_text()
	file.close()
	
	var json = JSON.parse(json_text)
	if json.error != OK:
		return false
	
	attribution_data = json.result
	is_attributed = true
	print("[ASA] Attribution data loaded from cache")
	return true
