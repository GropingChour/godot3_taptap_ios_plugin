tool
extends EditorPlugin

# TapTap RSA 密钥配置窗口
var config_window

func _enter_tree() -> void:
	add_autoload_singleton("TapTap", "res://addons/godot3_taptap/taptap.gd")
	
	# 添加工具菜单项
	add_tool_menu_item("TapTap RSA 密钥配置", self, "_open_config_window")

func _exit_tree() -> void:
	remove_autoload_singleton("TapTap")
	
	# 移除工具菜单项
	remove_tool_menu_item("TapTap RSA 密钥配置")
	
	# 清理配置窗口
	if config_window:
		config_window.queue_free()

func _open_config_window(user_data = null) -> void:
	# 打开 TapTap RSA 密钥配置窗口
	if config_window and is_instance_valid(config_window):
		config_window.popup_centered()
		return
	
	# 创建配置窗口
	var config_script = load("res://addons/godot3_taptap/taptap_config_window.gd")
	config_window = config_script.new()
	if not config_window:
		print("❌ 无法创建配置窗口")
		return
	
	# 添加到编辑器界面
	get_editor_interface().get_base_control().add_child(config_window)
	
	# 设置窗口大小并居中显示
	config_window.rect_size = Vector2(900, 700)
	config_window.popup_centered()
	
	# 连接关闭信号
	if not config_window.is_connected("popup_hide", self, "_on_config_window_closed"):
		config_window.connect("popup_hide", self, "_on_config_window_closed")

func _on_config_window_closed() -> void:
	# 配置窗口关闭时的处理
	if config_window:
		config_window.queue_free()
		config_window = null
