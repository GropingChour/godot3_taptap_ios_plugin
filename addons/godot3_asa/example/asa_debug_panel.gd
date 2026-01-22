extends Node

# ASA归因调试面板 - 用于可视化测试归因和上报功能

# UI节点
var ui_panel: Panel
var token_label: Label
var attribution_label: TextEdit
var copy_token_btn: Button
var copy_attr_btn: Button
var copy_all_btn: Button
var test_attribution_btn: Button
var fill_mock_btn: Button
var test_report_btn: Button

# 数据缓存
var cached_token: String = ""
var cached_attribution: Dictionary = {}

# AppSA上报器
var appsa_reporter: HTTPRequest
var test_from_key = "debug_test"  # 测试用from参数

# ============================================================================
# 初始化
# ============================================================================

func _ready():
	var is_editor = OS.has_feature("editor")
	var is_ios = OS.get_name() == "iOS"
	
	if not is_ios and not is_editor:
		print("[ASA Debug] Not iOS/editor, disabled")
		queue_free()
		return
	
	# 创建AppSA上报器（测试用）
	var AppSAReporter = load("res://addons/godot3_asa/appsa_reporter.gd")
	appsa_reporter = AppSAReporter.new()
	add_child(appsa_reporter)
	appsa_reporter.set_from_key(test_from_key)
	appsa_reporter.connect("report_success", self, "_on_test_report_success")
	appsa_reporter.connect("report_failed", self, "_on_test_report_failed")
	
	call_deferred("_create_debug_ui")
	
	if is_editor:
		print("[ASA Debug] Editor mode - use buttons to test")
		call_deferred("_setup_editor_mode")
	else:
		call_deferred("_check_asa_support")

func _check_asa_support():
	"""检查ASA支持"""
	if not has_node("/root/ASA"):
		_show_error("ASA autoload not found")
		return
	
	var asa = get_node("/root/ASA")
	if not asa.is_supported():
		_show_error("AdServices not supported (requires iOS 14.3+)")
		return
	
	print("[ASA Debug] Ready - click Test Attribution")
	if token_label:
		token_label.text = "Click 'Test Attribution' to start"
		token_label.add_color_override("font_color", Color(0.5, 0.8, 1.0))
	if attribution_label:
		attribution_label.text = "Click Test Attribution to fetch data"

func _setup_editor_mode():
	"""编辑器模式：显示Mock提示"""
	yield(get_tree(), "idle_frame")
	
	if token_label:
		token_label.text = "[Editor] Click 'Test Attribution' or 'Fill Mock Data'"
		token_label.add_color_override("font_color", Color(0.5, 0.8, 1.0))
	if attribution_label:
		attribution_label.text = "[Editor] Use buttons to load mock data"
	
	print("[ASA Debug] Editor ready - mock data available")

# ============================================================================
# UI 创建
# ============================================================================

func _create_debug_ui():
	# 创建主面板
	ui_panel = Panel.new()
	ui_panel.set_anchors_and_margins_preset(Control.PRESET_TOP_WIDE)
	ui_panel.margin_bottom = 450
	ui_panel.margin_left = 10
	ui_panel.margin_right = -10
	ui_panel.margin_top = 10
	
	# 添加背景样式
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.1, 0.95)
	style.border_color = Color(0.3, 0.3, 0.3, 1.0)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	ui_panel.add_stylebox_override("panel", style)
	
	add_child(ui_panel)
	
	# 创建垂直布局容器
	var margin = MarginContainer.new()
	margin.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	margin.add_constant_override("margin_left", 15)
	margin.add_constant_override("margin_right", 15)
	margin.add_constant_override("margin_top", 15)
	margin.add_constant_override("margin_bottom", 15)
	ui_panel.add_child(margin)
	
	var vbox = VBoxContainer.new()
	vbox.add_constant_override("separation", 15)
	margin.add_child(vbox)
	
	# 标题
	var title = Label.new()
	title.text = "ASA Attribution Debug Panel"
	title.align = Label.ALIGN_CENTER
	title.add_font_override("font", _create_font(18, true))
	title.add_color_override("font_color", Color(0.8, 0.9, 1.0, 1.0))
	vbox.add_child(title)
	
	# 添加分隔线
	vbox.add_child(_create_separator())
	
	# Token 区域
	var token_container = VBoxContainer.new()
	token_container.add_constant_override("separation", 5)
	vbox.add_child(token_container)
	
	var token_title = Label.new()
	token_title.text = "Attribution Token"
	token_title.add_font_override("font", _create_font(14, true))
	token_title.add_color_override("font_color", Color(1.0, 0.9, 0.6, 1.0))
	token_container.add_child(token_title)
	
	token_label = Label.new()
	token_label.text = "Waiting for token..."
	token_label.autowrap = true
	token_label.add_color_override("font_color", Color(0.7, 0.7, 0.7, 1.0))
	token_container.add_child(token_label)
	
	# Token 复制按钮
	copy_token_btn = Button.new()
	copy_token_btn.text = "Copy Token"
	copy_token_btn.disabled = true
	copy_token_btn.connect("pressed", self, "_on_copy_token_pressed")
	token_container.add_child(copy_token_btn)
	
	# 按钮容器
	var btn_row = HBoxContainer.new()
	btn_row.add_constant_override("separation", 5)
	token_container.add_child(btn_row)
	
	# 测试归因按钮
	test_attribution_btn = Button.new()
	test_attribution_btn.text = "Test Attribution"
	test_attribution_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	test_attribution_btn.connect("pressed", self, "_on_test_attribution_pressed")
	btn_row.add_child(test_attribution_btn)
	
	# 填充Mock数据按钮
	fill_mock_btn = Button.new()
	fill_mock_btn.text = "Fill Mock Data"
	fill_mock_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fill_mock_btn.connect("pressed", self, "_on_fill_mock_pressed")
	btn_row.add_child(fill_mock_btn)
	
	# 添加分隔线
	vbox.add_child(_create_separator())
	
	# 归因数据区域
	var attr_container = VBoxContainer.new()
	attr_container.add_constant_override("separation", 5)
	attr_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(attr_container)
	
	var attr_title = Label.new()
	attr_title.text = "Attribution Data"
	attr_title.add_font_override("font", _create_font(14, true))
	attr_title.add_color_override("font_color", Color(1.0, 0.9, 0.6, 1.0))
	attr_container.add_child(attr_title)
	
	attribution_label = TextEdit.new()
	attribution_label.readonly = true
	attribution_label.wrap_enabled = true
	attribution_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	attribution_label.text = "Waiting for attribution data..."
	
	# 添加背景
	var te_style = StyleBoxFlat.new()
	te_style.bg_color = Color(0.05, 0.05, 0.05, 0.8)
	te_style.border_color = Color(0.2, 0.2, 0.2, 1.0)
	te_style.border_width_left = 1
	te_style.border_width_right = 1
	te_style.border_width_top = 1
	te_style.border_width_bottom = 1
	te_style.corner_radius_top_left = 4
	te_style.corner_radius_top_right = 4
	te_style.corner_radius_bottom_left = 4
	te_style.corner_radius_bottom_right = 4
	attribution_label.add_stylebox_override("normal", te_style)
	attribution_label.add_color_override("font_color", Color(0.9, 0.9, 0.9, 1.0))
	
	attr_container.add_child(attribution_label)
	
	# 归因数据复制按钮区域
	var btn_container = HBoxContainer.new()
	btn_container.add_constant_override("separation", 10)
	attr_container.add_child(btn_container)
	
	copy_attr_btn = Button.new()
	copy_attr_btn.text = "Copy Attribution JSON"
	copy_attr_btn.disabled = true
	copy_attr_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy_attr_btn.connect("pressed", self, "_on_copy_attribution_pressed")
	btn_container.add_child(copy_attr_btn)
	
	copy_all_btn = Button.new()
	copy_all_btn.text = "Copy All Data"
	copy_all_btn.disabled = true
	copy_all_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy_all_btn.connect("pressed", self, "_on_copy_all_pressed")
	btn_container.add_child(copy_all_btn)
	
	# 测试上报按钮
	test_report_btn = Button.new()
	test_report_btn.text = "Test Report (Activation)"
	test_report_btn.disabled = true
	test_report_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	test_report_btn.connect("pressed", self, "_on_test_report_pressed")
	btn_container.add_child(test_report_btn)
	
	print("[ASA Debug] Debug panel created")

func _create_font(size: int, bold: bool = false) -> DynamicFont:
	# 创建字体
	var font = DynamicFont.new()
	font.size = size
	# 注意：Godot 3.x 中 DynamicFont 需要 DynamicFontData
	# 这里使用默认字体，如果需要加粗效果，可以通过 outline 模拟
	if bold:
		font.outline_size = 1
		font.outline_color = Color(0, 0, 0, 0.5)
	return font

func _create_separator() -> HSeparator:
	# 创建分隔线
	var separator = HSeparator.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.3, 0.3, 0.3, 0.5)
	separator.add_stylebox_override("separator", style)
	return separator

# ============================================================================
# 信号回调
# ============================================================================

func _on_token_received(token: String, error_code: int, error_message: String):
	# Token 接收回调
	print("[ASA Debug] Token callback: code=", error_code)
	
	# 检查UI节点是否有效
	if not is_instance_valid(token_label) or not is_instance_valid(copy_token_btn):
		print("[ASA Debug] ERROR: UI nodes not ready for token callback")
		return
	
	if error_code == 0 and not token.empty():
		cached_token = token
		var display_token = token.substr(0, 120) + ("..." if token.length() > 120 else "")
		token_label.text = "[SUCCESS] " + display_token
		token_label.add_color_override("font_color", Color(0.4, 1.0, 0.4, 1.0))
		copy_token_btn.disabled = false
		print("[ASA Debug] Token received: ", token.substr(0, 50), "... (length: ", token.length(), ")")
	else:
		cached_token = ""
		var error_text = "[ERROR] (code %d): %s" % [error_code, error_message]
		token_label.text = error_text
		token_label.add_color_override("font_color", Color(1.0, 0.3, 0.3, 1.0))
		copy_token_btn.disabled = true
		print("[ASA Debug] Token failed: ", error_text)
	
	# 重新启用测试按钮
	if is_instance_valid(test_attribution_btn):
		test_attribution_btn.disabled = false

func _on_attribution_received(attribution_data: String, error_code: int, error_message: String):
	# 归因数据接收回调
	print("[ASA Debug] Attribution callback: code=", error_code)
	
	# 检查UI节点是否有效
	if not is_instance_valid(attribution_label) or not is_instance_valid(copy_attr_btn) or not is_instance_valid(copy_all_btn):
		print("[ASA Debug] ERROR: UI nodes not ready for attribution callback")
		return
	
	if error_code == 200 and not attribution_data.empty():
		var json = JSON.parse(attribution_data)
		if json.error == OK:
			var attr = json.result
			cached_attribution = attr
			_update_attribution_ui(attr)
			copy_attr_btn.disabled = false
			copy_all_btn.disabled = false
			print("[ASA Debug] Attribution data displayed")
		else:
			cached_attribution = {}
			_show_attribution_error("Failed to parse JSON data")
			print("[ASA Debug] Failed to parse attribution data")
	else:
		cached_attribution = {}
		_show_attribution_error("[Code: %d] %s" % [error_code, error_message if error_message else "Request failed"])
		print("[ASA Debug] Attribution failed: ", error_message)
	
	# 重新启用测试按钮
	if is_instance_valid(test_attribution_btn):
		test_attribution_btn.disabled = false

func _show_attribution_error(error_text: String):
	# 在归因区域显示错误信息
	if attribution_label:
		attribution_label.text = "[ERROR] " + error_text
	if copy_attr_btn:
		copy_attr_btn.disabled = true
	if copy_all_btn:
		copy_all_btn.disabled = true
	if test_report_btn:
		test_report_btn.disabled = true

func _show_error(error_text: String):
	# 显示通用错误（例如 ASA autoload 未找到）
	if token_label:
		token_label.text = "[ERROR] " + error_text
		token_label.add_color_override("font_color", Color(1.0, 0.3, 0.3, 1.0))
	if attribution_label:
		attribution_label.text = "[ERROR] " + error_text

func _update_attribution_ui(attr: Dictionary):
	# 更新 UI 显示归因数据
	var is_asa = attr.get("attribution", false)
	var status_text = "[SUCCESS] From ASA" if is_asa else "[INFO] Not from ASA"
	
	var text = status_text + "\n\n"
	
	if is_asa:
		# 显示详细归因数据
		text += "Campaign ID: %s\n" % _format_value(attr.get("campaignId"))
		text += "Ad Group ID: %s\n" % _format_value(attr.get("adGroupId"))
		text += "Keyword ID: %s\n" % _format_value(attr.get("keywordId"))
		text += "Creative Set ID: %s\n" % _format_value(attr.get("adId"))
		text += "Org ID: %s\n" % _format_value(attr.get("orgId"))
		text += "Country/Region: %s\n" % _format_value(attr.get("countryOrRegion"))
		text += "Conversion Type: %s\n" % _format_value(attr.get("conversionType"))
		text += "Click Date: %s\n" % _format_value(attr.get("clickDate"))
		
		# 显示原始 JSON（方便调试）
		text += "\n----------------------------------------\n"
		text += "Raw JSON:\n"
		text += JSON.print(attr, "  ")
	else:
		text += "\nUser did not click any ASA ad in the last 30 days."
	
	attribution_label.text = text
	
	# 启用测试上报按钮
	if is_instance_valid(test_report_btn):
		test_report_btn.disabled = false

func _format_value(value) -> String:
	# 格式化值显示
	if value == null or (typeof(value) == TYPE_STRING and value.empty()):
		return "N/A"
	return str(value)

# ============================================================================
# 复制功能
# ============================================================================

func _on_copy_token_pressed():
	# 复制 Token
	if not cached_token.empty():
		OS.set_clipboard(cached_token)
		_show_copy_feedback("Token copied to clipboard!")
		print("[ASA Debug] Token copied to clipboard (", cached_token.length(), " chars)")

func _on_copy_attribution_pressed():
	# 复制归因数据 JSON
	if not cached_attribution.empty():
		var json_text = JSON.print(cached_attribution, "  ")
		OS.set_clipboard(json_text)
		_show_copy_feedback("Attribution JSON copied!")
		print("[ASA Debug] Attribution JSON copied to clipboard")

func _on_copy_all_pressed():
	# 复制所有信息
	var all_data = "=== ASA Attribution Debug Data ===\n\n"
	
	all_data += "[ Token ]\n"
	if not cached_token.empty():
		all_data += cached_token + "\n"
	else:
		all_data += "No token available\n"
	
	all_data += "\n[ Attribution Data ]\n"
	if not cached_attribution.empty():
		all_data += JSON.print(cached_attribution, "  ") + "\n"
	else:
		all_data += "No attribution data available\n"
	
	all_data += "\n[ Summary ]\n"
	if not cached_attribution.empty():
		var is_asa = cached_attribution.get("attribution", false)
		all_data += "From ASA: %s\n" % ("Yes" if is_asa else "No")
		if is_asa:
			all_data += "Campaign ID: %s\n" % str(cached_attribution.get("campaignId", "N/A"))
			all_data += "Ad Group ID: %s\n" % str(cached_attribution.get("adGroupId", "N/A"))
			all_data += "Keyword ID: %s\n" % str(cached_attribution.get("keywordId", "N/A"))
			all_data += "Country: %s\n" % str(cached_attribution.get("countryOrRegion", "N/A"))
	
	OS.set_clipboard(all_data)
	_show_copy_feedback("All data copied!")
	print("[ASA Debug] All debug data copied to clipboard")

func _on_test_attribution_pressed():
	# 强制触发归因测试
	var is_editor = OS.has_feature("editor")
	
	if is_editor:
		# 编辑器模式：模拟网络请求
		print("[ASA Debug] Editor mode: simulating attribution with network delay...")
		_simulate_mock_attribution()
		return
	
	# 真实 iOS 设备模式
	if not has_node("/root/ASA"):
		print("[ASA Debug] ERROR: ASA autoload not found")
		_show_error("ASA autoload not found")
		return
	
	var asa_node = get_node("/root/ASA")
	if not asa_node:
		print("[ASA Debug] ERROR: ASA node is null")
		_show_error("ASA node is null")
		return
	
	# 连接信号（防止重复连接）
	if not asa_node.is_connected("onASATokenReceived", self, "_on_token_received"):
		var err = asa_node.connect("onASATokenReceived", self, "_on_token_received")
		if err != OK:
			print("[ASA Debug] ERROR: Failed to connect onASATokenReceived: ", err)
			return
		print("[ASA Debug] Connected to onASATokenReceived signal")
	
	if not asa_node.is_connected("onASAAttributionReceived", self, "_on_attribution_received"):
		var err = asa_node.connect("onASAAttributionReceived", self, "_on_attribution_received")
		if err != OK:
			print("[ASA Debug] ERROR: Failed to connect onASAAttributionReceived: ", err)
			return
		print("[ASA Debug] Connected to onASAAttributionReceived signal")
	
	# 重置UI状态
	if is_instance_valid(token_label):
		token_label.text = "Requesting attribution token..."
		token_label.add_color_override("font_color", Color(0.7, 0.7, 0.7, 1.0))
	if is_instance_valid(attribution_label):
		attribution_label.text = "Waiting for attribution data..."
	if is_instance_valid(copy_token_btn):
		copy_token_btn.disabled = true
	if is_instance_valid(copy_attr_btn):
		copy_attr_btn.disabled = true
	if is_instance_valid(copy_all_btn):
		copy_all_btn.disabled = true
	if is_instance_valid(test_attribution_btn):
		test_attribution_btn.disabled = true
	if is_instance_valid(test_report_btn):
		test_report_btn.disabled = true
	
	# 清空缓存
	cached_token = ""
	cached_attribution = {}
	
	print("[ASA Debug] Forcing attribution test...")
	asa_node.perform_attribution()
	
	# 10秒后重新启用按钮（防止卡死）
	yield(get_tree().create_timer(10.0), "timeout")
	if is_instance_valid(test_attribution_btn):
		test_attribution_btn.disabled = false

func _show_copy_feedback(message: String):
	# 显示复制反馈（临时修改按钮文本）
	var original_text = copy_all_btn.text
	copy_all_btn.text = message
	
	# 2 秒后恢复
	yield(get_tree().create_timer(2.0), "timeout")
	if is_instance_valid(copy_all_btn):
		copy_all_btn.text = original_text

# ============================================================================
# 编辑器模拟模式
# ============================================================================

func _simulate_mock_attribution():
	"""在编辑器中模拟 ASA 归因请求，带有随机网络延迟"""
	# 重置UI状态
	if is_instance_valid(token_label):
		token_label.text = "[Mock] Requesting token from AdServices..."
		token_label.add_color_override("font_color", Color(0.7, 0.7, 0.7, 1.0))
	if is_instance_valid(attribution_label):
		attribution_label.text = "[Mock] Waiting for server response..."
	if is_instance_valid(copy_token_btn):
		copy_token_btn.disabled = true
	if is_instance_valid(copy_attr_btn):
		copy_attr_btn.disabled = true
	if is_instance_valid(copy_all_btn):
		copy_all_btn.disabled = true
	if is_instance_valid(test_attribution_btn):
		test_attribution_btn.disabled = true
	if is_instance_valid(test_report_btn):
		test_report_btn.disabled = true
	
	# 清空缓存
	cached_token = ""
	cached_attribution = {}
	
	print("[ASA Debug] [Mock] Simulating token request...")
	
	# 模拟 Token 请求延迟 (0.5-1.5秒)
	var token_delay = rand_range(0.5, 1.5)
	yield(get_tree().create_timer(token_delay), "timeout")
	
	# 模拟 Token 数据
	var mock_token = "eyJhbGciOiJFUzI1NiIsInR5cCI6IkpXVCIsImtpZCI6IjEyMzQ1Njc4OTAifQ.eyJhdWQiOiJodHRwczovL2FwaS1hZHNlcnZpY2VzLmFwcGxlLmNvbS9hcGkvdjEiLCJleHAiOjE3MDk5MDAwMDAsImlhdCI6MTcwOTgxMzYwMCwiaXNzIjoiYXBwbGUtYWRzZXJ2aWNlcy1hdHRyaWJ1dGlvbiIsImp0aSI6IjEyMzQ1Njc4LTkwYWItY2RlZi0xMjM0LTU2Nzg5MGFiY2RlZiIsInN1YiI6ImNvbS5leGFtcGxlLmFwcCJ9.dGhpc19pc19hX21vY2tfc2lnbmF0dXJlX2Zvcl9wcmV2aWV3X3B1cnBvc2VzX29ubHk"
	cached_token = mock_token
	
	if is_instance_valid(token_label):
		var display_token = mock_token.substr(0, 120) + "..."
		token_label.text = "[SUCCESS] [Mock] " + display_token
		token_label.add_color_override("font_color", Color(0.4, 1.0, 0.4, 1.0))
	if is_instance_valid(copy_token_btn):
		copy_token_btn.disabled = false
	
	print("[ASA Debug] [Mock] Token received (%.2fs delay)" % token_delay)
	
	# 更新归因状态
	if is_instance_valid(attribution_label):
		attribution_label.text = "[Mock] Fetching attribution data from Apple server..."
	
	# 模拟归因请求延迟 (1.0-3.0秒)
	var attr_delay = rand_range(1.0, 3.0)
	yield(get_tree().create_timer(attr_delay), "timeout")
	
	# 模拟归因数据
	var mock_attribution = {
		"attribution": true,
		"orgId": 40669820,
		"campaignId": 542370539,
		"adGroupId": 542317095,
		"keywordId": 87675432,
		"adId": 542317136,
		"countryOrRegion": "US",
		"conversionType": "Download",
		"clickDate": "2026-01-20T08:30:15Z"
	}
	cached_attribution = mock_attribution
	
	if is_instance_valid(attribution_label):
		_update_attribution_ui(mock_attribution)
	if is_instance_valid(copy_attr_btn):
		copy_attr_btn.disabled = false
	if is_instance_valid(copy_all_btn):
		copy_all_btn.disabled = false
	
	print("[ASA Debug] [Mock] Attribution received (%.2fs delay)" % attr_delay)
	print("[ASA Debug] [Mock] Total time: %.2fs" % (token_delay + attr_delay))
	
	# 重新启用测试按钮
	if is_instance_valid(test_attribution_btn):
		test_attribution_btn.disabled = false

# ============================================================================
# 填充Mock数据（立即加载）
# ============================================================================

func _on_fill_mock_pressed():
	"""立即填充Mock数据，无延迟"""
	print("[ASA Debug] Filling mock data immediately...")
	
	# 禁用按钮防止重复点击
	if is_instance_valid(fill_mock_btn):
		fill_mock_btn.disabled = true
	if is_instance_valid(test_attribution_btn):
		test_attribution_btn.disabled = true
	
	# 生成 Token
	var mock_token = "eyJhbGciOiJFUzI1NiIsInR5cCI6IkpXVCIsImtpZCI6IjEyMzQ1Njc4OTAifQ.eyJhdWQiOiJodHRwczovL2FwaS1hZHNlcnZpY2VzLmFwcGxlLmNvbS9hcGkvdjEiLCJleHAiOjE3MDk5MDAwMDAsImlhdCI6MTcwOTgxMzYwMCwiaXNzIjoiYXBwbGUtYWRzZXJ2aWNlcy1hdHRyaWJ1dGlvbiIsImp0aSI6IjEyMzQ1Njc4LTkwYWItY2RlZi0xMjM0LTU2Nzg5MGFiY2RlZiIsInN1YiI6ImNvbS5leGFtcGxlLmFwcCJ9.dGhpc19pc19hX21vY2tfc2lnbmF0dXJlX2Zvcl9wcmV2aWV3X3B1cnBvc2VzX29ubHk"
	cached_token = mock_token
	
	if is_instance_valid(token_label):
		var display_token = mock_token.substr(0, 120) + "..."
		token_label.text = "[SUCCESS] [Mock] " + display_token
		token_label.add_color_override("font_color", Color(0.4, 1.0, 0.4, 1.0))
	if is_instance_valid(copy_token_btn):
		copy_token_btn.disabled = false
	
	print("[ASA Debug] [Mock] Token filled")
	
	# 生成归因数据
	var mock_attribution = {
		"attribution": true,
		"orgId": 40669820,
		"campaignId": 542370539,
		"adGroupId": 542317095,
		"keywordId": 87675432,
		"adId": 542317136,
		"countryOrRegion": "US",
		"conversionType": "Download",
		"clickDate": "2026-01-20T08:30:15Z"
	}
	cached_attribution = mock_attribution
	
	if is_instance_valid(attribution_label):
		_update_attribution_ui(mock_attribution)
	if is_instance_valid(copy_attr_btn):
		copy_attr_btn.disabled = false
	if is_instance_valid(copy_all_btn):
		copy_all_btn.disabled = false
	
	print("[ASA Debug] [Mock] Attribution filled")
	
	# 重新启用按钮
	if is_instance_valid(fill_mock_btn):
		fill_mock_btn.disabled = false
	if is_instance_valid(test_attribution_btn):
		test_attribution_btn.disabled = false

func _on_test_report_pressed():
	"""测试AppSA上报（独立测试）"""
	print("[ASA Debug] Testing activation report...")
	
	if cached_attribution.empty():
		print("[ASA Debug] No attribution data")
		_show_attribution_error("No attribution data - cannot report")
		return
	
	var is_from_asa = cached_attribution.get("attribution", false)
	if not is_from_asa:
		print("[ASA Debug] Not from ASA, but forcing test...")
	
	print("[ASA Debug] Sending test report - Campaign: ", cached_attribution.get("campaignId", "N/A"))
	appsa_reporter.report_activation(cached_attribution)

func _on_test_report_success(response: Dictionary):
	"""上报成功回调"""
	print("[ASA Debug] Report success: ", response)
	if attribution_label:
		attribution_label.text += "\n\n[Test Report Success]\n" + JSON.print(response, "  ")

func _on_test_report_failed(error_message: String):
	"""上报失败回调"""
	print("[ASA Debug] Report failed: ", error_message)
	if attribution_label:
		attribution_label.text += "\n\n[Test Report Failed] " + error_message

func _exit_tree():
	"""清理资源"""
	if has_node("/root/ASA"):
		var asa = get_node("/root/ASA")
		if asa.is_connected("onASATokenReceived", self, "_on_token_received"):
			asa.disconnect("onASATokenReceived", self, "_on_token_received")
		if asa.is_connected("onASAAttributionReceived", self, "_on_attribution_received"):
			asa.disconnect("onASAAttributionReceived", self, "_on_attribution_received")
	
	if ui_panel:
		ui_panel.queue_free()

