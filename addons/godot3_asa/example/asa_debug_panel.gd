extends Node

# ASA 归因调试面板
# 
# 显示 ASA 归因过程中的 Token 和归因数据
# 将此节点添加到场景中即可自动显示调试信息

# ============================================================================
# UI 节点
# ============================================================================

var ui_panel: Panel
var token_label: Label
var attribution_label: RichTextLabel
var copy_token_btn: Button
var copy_attr_btn: Button
var copy_all_btn: Button

# 数据缓存
var cached_token: String = ""
var cached_attribution: Dictionary = {}

# ============================================================================
# 初始化
# ============================================================================

func _ready():
	# 在编辑器中也显示布局，用于预览
	var is_editor = OS.has_feature("editor")
	var is_ios = OS.get_name() == "iOS"
	
	# 检查是否在 iOS 平台或编辑器
	if not is_ios and not is_editor:
		print("[ASA Debug] Not iOS platform or editor, debug panel disabled")
		queue_free()
		return
	
	# 创建调试 UI
	call_deferred("_create_debug_ui")
	
	if is_editor:
		# 编辑器模式：填充伪数据用于预览布局
		print("[ASA Debug] Running in editor mode with mock data")
		call_deferred("_fill_mock_data")
	else:
		# 真实运行模式：检查支持情况并连接信号
        var _is_supported = ASA.is_supported() # 预先调用以避免延迟
        print("[ASA Debug] Running on iOS device, checking ASA support: %s" % _is_supported)
		if not _is_supported:
			print("[ASA Debug] ERROR: ASA not supported on this device")
			call_deferred("_show_error", "AdServices not supported (requires iOS 14.3+)")
			return
		print("[ASA Debug] ASA supported, connecting signals")
		ASA.connect("onASATokenReceived", self, "_on_token_received")
		ASA.connect("onASAAttributionReceived", self, "_on_attribution_received")
		print("[ASA Debug] Connected to ASA autoload signals")

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
	title.text = "🔍 ASA Attribution Debug Panel"
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
	token_title.text = "📝 Attribution Token"
	token_title.add_font_override("font", _create_font(14, true))
	token_title.add_color_override("font_color", Color(1.0, 0.9, 0.6, 1.0))
	token_container.add_child(token_title)
	
	token_label = Label.new()
	token_label.text = "⏳ Waiting for token..."
	token_label.autowrap = true
	token_label.add_color_override("font_color", Color(0.7, 0.7, 0.7, 1.0))
	token_container.add_child(token_label)
	
	# Token 复制按钮
	copy_token_btn = Button.new()
	copy_token_btn.text = "📋 Copy Token"
	copy_token_btn.disabled = true
	copy_token_btn.connect("pressed", self, "_on_copy_token_pressed")
	token_container.add_child(copy_token_btn)
	
	# 添加分隔线
	vbox.add_child(_create_separator())
	
	# 归因数据区域
	var attr_container = VBoxContainer.new()
	attr_container.add_constant_override("separation", 5)
	attr_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(attr_container)
	
	var attr_title = Label.new()
	attr_title.text = "📊 Attribution Data"
	attr_title.add_font_override("font", _create_font(14, true))
	attr_title.add_color_override("font_color", Color(1.0, 0.9, 0.6, 1.0))
	attr_container.add_child(attr_title)
	
	attribution_label = RichTextLabel.new()
	attribution_label.bbcode_enabled = true
	attribution_label.scroll_following = true
	attribution_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	attribution_label.bbcode_text = "[color=#aaaaaa]⏳ Waiting for attribution data...[/color]"
	
	# 添加背景
	var rtl_style = StyleBoxFlat.new()
	rtl_style.bg_color = Color(0.05, 0.05, 0.05, 0.8)
	rtl_style.border_color = Color(0.2, 0.2, 0.2, 1.0)
	rtl_style.border_width_left = 1
	rtl_style.border_width_right = 1
	rtl_style.border_width_top = 1
	rtl_style.border_width_bottom = 1
	rtl_style.corner_radius_top_left = 4
	rtl_style.corner_radius_top_right = 4
	rtl_style.corner_radius_bottom_left = 4
	rtl_style.corner_radius_bottom_right = 4
	attribution_label.add_stylebox_override("normal", rtl_style)
	
	attr_container.add_child(attribution_label)
	
	# 归因数据复制按钮区域
	var btn_container = HBoxContainer.new()
	btn_container.add_constant_override("separation", 10)
	attr_container.add_child(btn_container)
	
	copy_attr_btn = Button.new()
	copy_attr_btn.text = "📋 Copy Attribution JSON"
	copy_attr_btn.disabled = true
	copy_attr_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy_attr_btn.connect("pressed", self, "_on_copy_attribution_pressed")
	btn_container.add_child(copy_attr_btn)
	
	copy_all_btn = Button.new()
	copy_all_btn.text = "📋 Copy All Data"
	copy_all_btn.disabled = true
	copy_all_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy_all_btn.connect("pressed", self, "_on_copy_all_pressed")
	btn_container.add_child(copy_all_btn)
	
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
	
	if error_code == 0 and not token.empty():
		cached_token = token
		var display_token = token.substr(0, 120) + ("..." if token.length() > 120 else "")
		token_label.text = "✅ " + display_token
		token_label.add_color_override("font_color", Color(0.4, 1.0, 0.4, 1.0))
		copy_token_btn.disabled = false
		print("[ASA Debug] Token received: ", token.substr(0, 50), "... (length: ", token.length(), ")")
	else:
		cached_token = ""
		var error_text = "❌ Error (code %d): %s" % [error_code, error_message]
		token_label.text = error_text
		token_label.add_color_override("font_color", Color(1.0, 0.3, 0.3, 1.0))
		copy_token_btn.disabled = true
		print("[ASA Debug] Token failed: ", error_text)

func _on_attribution_received(data: String, code: int, message: String):
	# 归因数据接收回调
	print("[ASA Debug] Attribution callback: code=", code)
	
	if code == 200 and not data.empty():
		var json = JSON.parse(data)
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
		_show_attribution_error("[Code: %d] %s" % [code, message if message else "Request failed"])
		print("[ASA Debug] Attribution failed: ", message)

func _show_attribution_error(error_text: String):
	# 在归因区域显示错误信息
	if attribution_label:
		attribution_label.bbcode_text = "[color=#ff5555]❌ %s[/color]" % error_text
	if copy_attr_btn:
		copy_attr_btn.disabled = true
	if copy_all_btn:
		copy_all_btn.disabled = true

func _show_error(error_text: String):
	# 显示通用错误（例如 ASA autoload 未找到）
	if token_label:
		token_label.text = "❌ " + error_text
		token_label.add_color_override("font_color", Color(1.0, 0.3, 0.3, 1.0))
	if attribution_label:
		attribution_label.bbcode_text = "[color=#ff5555]❌ %s[/color]" % error_text

func _update_attribution_ui(attr: Dictionary):
	# 更新 UI 显示归因数据
	var is_asa = attr.get("attribution", false)
	var status_color = "#55ff55" if is_asa else "#ffff55"
	var status_icon = "✅" if is_asa else "⚠️"
	var status_text = "From ASA" if is_asa else "Not from ASA"
	
	var text = "[color=%s]%s %s[/color]\n\n" % [status_color, status_icon, status_text]
	
	if is_asa:
		# 显示详细归因数据
		text += "[b][color=#88ccff]Campaign ID:[/color][/b] %s\n" % _format_value(attr.get("campaignId"))
		text += "[b][color=#88ccff]Ad Group ID:[/color][/b] %s\n" % _format_value(attr.get("adGroupId"))
		text += "[b][color=#88ccff]Keyword ID:[/color][/b] %s\n" % _format_value(attr.get("keywordId"))
		text += "[b][color=#88ccff]Creative Set ID:[/color][/b] %s\n" % _format_value(attr.get("adId"))
		text += "[b][color=#88ccff]Org ID:[/color][/b] %s\n" % _format_value(attr.get("orgId"))
		text += "[b][color=#88ccff]Country/Region:[/color][/b] %s\n" % _format_value(attr.get("countryOrRegion"))
		text += "[b][color=#88ccff]Conversion Type:[/color][/b] %s\n" % _format_value(attr.get("conversionType"))
		text += "[b][color=#88ccff]Click Date:[/color][/b] %s\n" % _format_value(attr.get("clickDate"))
		
		# 显示原始 JSON（方便调试）
		text += "\n[color=#666666]──────────────────────────[/color]\n"
		text += "[color=#999999][b]Raw JSON:[/b][/color]\n"
		text += "[color=#aaaaaa]%s[/color]" % JSON.print(attr, "  ")
	else:
		text += "\n[color=#999999]User did not click any ASA ad in the last 30 days.[/color]"
	
	attribution_label.bbcode_text = text

func _format_value(value) -> String:
	# 格式化值显示
	if value == null or (typeof(value) == TYPE_STRING and value.empty()):
		return "[color=#666666]N/A[/color]"
	return "[color=#ffffff]%s[/color]" % str(value)

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

func _show_copy_feedback(message: String):
	# 显示复制反馈（临时修改按钮文本）
	var original_text = copy_all_btn.text
	copy_all_btn.text = "✅ " + message
	
	# 2 秒后恢复
	yield(get_tree().create_timer(2.0), "timeout")
	if is_instance_valid(copy_all_btn):
		copy_all_btn.text = original_text

# ============================================================================
# 编辑器预览模式
# ============================================================================

func _fill_mock_data():
	# 在编辑器中填充伪数据用于预览布局
	# 等待 UI 创建完成
	yield(get_tree(), "idle_frame")
	
	# 模拟 Token 数据
	var mock_token = "eyJhbGciOiJFUzI1NiIsInR5cCI6IkpXVCIsImtpZCI6IjEyMzQ1Njc4OTAifQ.eyJhdWQiOiJodHRwczovL2FwaS1hZHNlcnZpY2VzLmFwcGxlLmNvbS9hcGkvdjEiLCJleHAiOjE3MDk5MDAwMDAsImlhdCI6MTcwOTgxMzYwMCwiaXNzIjoiYXBwbGUtYWRzZXJ2aWNlcy1hdHRyaWJ1dGlvbiIsImp0aSI6IjEyMzQ1Njc4LTkwYWItY2RlZi0xMjM0LTU2Nzg5MGFiY2RlZiIsInN1YiI6ImNvbS5leGFtcGxlLmFwcCJ9.dGhpc19pc19hX21vY2tfc2lnbmF0dXJlX2Zvcl9wcmV2aWV3X3B1cnBvc2VzX29ubHk"
	cached_token = mock_token
	
	var display_token = mock_token.substr(0, 120) + "..."
	token_label.text = "✅ " + display_token
	token_label.add_color_override("font_color", Color(0.4, 1.0, 0.4, 1.0))
	copy_token_btn.disabled = false
	
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
	
	_update_attribution_ui(mock_attribution)
	copy_attr_btn.disabled = false
	copy_all_btn.disabled = false
	
	print("[ASA Debug] Mock data filled for editor preview")

# ============================================================================
# 清理
# ============================================================================

func _exit_tree():
	# 清理 UI
	if ui_panel and is_instance_valid(ui_panel):
		ui_panel.queue_free()
	print("[ASA Debug] Debug panel removed")
