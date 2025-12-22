tool
extends WindowDialog

# TapTap 简单加密配置工具
# 只需要输入明文 Token，生成加密后的字符串和对应的解密代码

var token_input
var key_input
var encrypt_btn
var encrypted_output
var status_label
var generate_key_btn
var save_key_btn

# 密钥文件路径
const KEY_FILE_PATH_RAW = "res://android/build/Godot3TapTap/src/main/res/raw/taptap_decrypt_key.txt"
const KEY_FILE_PATH_XML = "res://android/build/Godot3TapTap/src/main/res/values/taptap_keys.xml"
# iOS 密钥配置：直接修改 .gdip 文件的 [plist] 部分
const KEY_FILE_PATH_IOS_GDIP = "res://ios/plugins/godot3_taptap/godot3_taptap.gdip"

# 当前加密密钥（从文件读取或默认值）
var current_key = "TapTapz9mdoNZSItSxJOvG"

func _init():
	set_title("TapTap Token 加密配置")
	set_resizable(true)
	rect_min_size = Vector2(700, 500)
	call_deferred("_setup_ui")

func _setup_ui():
	# 先加载密钥
	_load_or_create_key()
	_create_ui()

func _load_or_create_key():
	# 加载密钥文件，如果不存在则使用默认密钥
	# 先尝试从 iOS .gdip 读取
	if _load_key_from_ios_gdip():
		return
	
	# 再尝试从 Android XML 文件读取
	if _load_key_from_xml():
		return
	
	# 最后尝试从 Android RAW 文件读取
	if _load_key_from_raw():
		return
	
	# 如果都不存在，使用默认密钥
	print("使用默认密钥：", current_key)

func _load_key_from_xml() -> bool:
	# 从 XML 文件读取密钥
	var file = File.new()
	var xml_path = ProjectSettings.globalize_path(KEY_FILE_PATH_XML)
	
	if file.file_exists(xml_path):
		if file.open(xml_path, File.READ) == OK:
			var content = file.get_as_text()
			file.close()
			
			# 解析 XML 内容，提取密钥
			var regex = RegEx.new()
			regex.compile('<string name="taptap_decrypt_key">([^<]+)</string>')
			var result = regex.search(content)
			if result:
				current_key = result.get_string(1)
				print("从 XML 文件读取密钥：", current_key)
				return true
	return false

func _load_key_from_raw() -> bool:
	# 从 RAW 文件读取密钥
	var file = File.new()
	var raw_path = ProjectSettings.globalize_path(KEY_FILE_PATH_RAW)
	
	if file.file_exists(raw_path):
		if file.open(raw_path, File.READ) == OK:
			var content = file.get_as_text().strip_edges()
			file.close()
			
			# 解析文件内容，忽略注释行
			var lines = content.split("\n")
			for line in lines:
				line = line.strip_edges()
				if not line.empty() and not line.begins_with("#"):
					current_key = line
					print("从 RAW 文件读取密钥：", current_key)
					return true
	return false

func _load_key_from_ios_gdip() -> bool:
	# 从 iOS .gdip 文件读取密钥
	var gdip_path = ProjectSettings.globalize_path(KEY_FILE_PATH_IOS_GDIP)
	var file = File.new()
	
	if not file.file_exists(gdip_path):
		return false
	
	var config = ConfigFile.new()
	var err = config.load(gdip_path)
	
	if err == OK:
		if config.has_section_key("plist", "TapTapDecryptKey:string_input"):
			current_key = config.get_value("plist", "TapTapDecryptKey:string_input", "")
			if not current_key.empty():
				print("从 iOS .gdip 读取密钥：", current_key)
				return true
	return false

func _create_ui():
	var vbox = VBoxContainer.new()
	add_child(vbox)
	vbox.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	vbox.add_constant_override("separation", 10)
	
	# 标题
	var title = Label.new()
	title.text = "🔐 TapTap Token 加密配置"
	title.align = Label.ALIGN_CENTER
	vbox.add_child(title)
	
	# 密钥配置区域
	var key_group = _create_key_section()
	vbox.add_child(key_group)
	
	# 分隔线
	var separator = HSeparator.new()
	vbox.add_child(separator)
	
	# Token 加密区域
	var token_group = _create_token_section()
	vbox.add_child(token_group)

func _create_key_section():
	# 创建密钥配置区域
	var group = VBoxContainer.new()
	group.add_constant_override("separation", 5)
	
	# 密钥标题
	var key_title = Label.new()
	key_title.text = "🔑 加密密钥配置"
	group.add_child(key_title)
	
	# 密钥输入
	var key_label = Label.new()
	key_label.text = "当前解密密钥："
	group.add_child(key_label)
	
	key_input = LineEdit.new()
	key_input.text = current_key
	key_input.placeholder_text = "输入解密密钥"
	group.add_child(key_input)
	
	# 密钥操作按钮
	var key_buttons = HBoxContainer.new()
	key_buttons.add_constant_override("separation", 10)
	
	generate_key_btn = Button.new()
	generate_key_btn.text = "🎲 生成随机密钥"
	generate_key_btn.connect("pressed", self, "_on_generate_key_pressed")
	key_buttons.add_child(generate_key_btn)
	
	group.add_child(key_buttons)
	
	# 平台保存按钮
	var platform_buttons = HBoxContainer.new()
	platform_buttons.add_constant_override("separation", 10)
	
	var save_ios_btn = Button.new()
	save_ios_btn.text = "💾 保存到 iOS"
	save_ios_btn.connect("pressed", self, "_on_save_ios_pressed")
	platform_buttons.add_child(save_ios_btn)
	
	var save_android_btn = Button.new()
	save_android_btn.text = "💾 保存到 Android"
	save_android_btn.connect("pressed", self, "_on_save_android_pressed")
	platform_buttons.add_child(save_android_btn)
	
	group.add_child(platform_buttons)
	
	# 密钥文件路径显示
	var key_path_label = Label.new()
	key_path_label.text = "密钥文件位置:\n• iOS: " + ProjectSettings.globalize_path(KEY_FILE_PATH_IOS_GDIP) + " ([plist] section)\n• Android XML: " + ProjectSettings.globalize_path(KEY_FILE_PATH_XML) + "\n• Android RAW: " + ProjectSettings.globalize_path(KEY_FILE_PATH_RAW)
	key_path_label.autowrap = true
	group.add_child(key_path_label)
	
	return group

func _create_token_section():
	# 创建 Token 加密区域
	var group = VBoxContainer.new()
	group.add_constant_override("separation", 5)
	
	# Token 标题
	var token_title = Label.new()
	token_title.text = "🛡️ Token 加密"
	group.add_child(token_title)
	
	# 输入区域
	var input_label = Label.new()
	input_label.text = "输入原始 Client Token："
	group.add_child(input_label)
	
	token_input = LineEdit.new()
	token_input.placeholder_text = "例如：U4DSrUu13BB7DX5usnjy7DutaBcEJeh8nLBFcZA2"
	token_input.text = "U4DSrUu13BB7DX5usnjy7DutaBcEJeh8nLBFcZA2"
	group.add_child(token_input)
	
	# 加密按钮
	encrypt_btn = Button.new()
	encrypt_btn.text = "🔐 生成加密 Token"
	encrypt_btn.connect("pressed", self, "_on_encrypt_pressed")
	group.add_child(encrypt_btn)
	
	# 状态
	status_label = Label.new()
	status_label.text = "配置密钥后可进行 Token 加密"
	status_label.align = Label.ALIGN_CENTER
	group.add_child(status_label)
	
	# 加密结果
	var result_label = Label.new()
	result_label.text = "加密后的 Token（用于 GDScript）："
	group.add_child(result_label)
	
	encrypted_output = TextEdit.new()
	encrypted_output.rect_min_size.y = 80
	encrypted_output.readonly = true
	group.add_child(encrypted_output)
	
	# 使用说明
	var usage_label = Label.new()
	usage_label.text = "📝 使用方法：将加密后的 Token 复制到 GDScript 中使用 TapTap.initSdkWithEncryptedToken() 方法"
	usage_label.autowrap = true
	group.add_child(usage_label)
	
	return group

func _on_generate_key_pressed():
	# 生成随机密钥
	var crypto = Crypto.new()
	var random_bytes = crypto.generate_random_bytes(16)
	var new_key = "TapTap" + Marshalls.raw_to_base64(random_bytes).replace("=", "").replace("/", "").replace("+", "").substr(0, 16)
	
	key_input.text = new_key
	status_label.text = "✅ 已生成随机密钥，记得保存！"

func _on_save_ios_pressed():
	# 保存密钥到 iOS .gdip
	var new_key = key_input.text.strip_edges()
	if new_key.empty():
		status_label.text = "❌ 密钥不能为空"
		return
	
	if _save_key_to_ios_gdip(new_key):
		current_key = new_key
		status_label.text = "✅ 密钥已保存到 iOS .gdip"
	else:
		status_label.text = "❌ 保存 iOS 密钥失败"

func _on_save_android_pressed():
	# 保存密钥到 Android
	var new_key = key_input.text.strip_edges()
	if new_key.empty():
		status_label.text = "❌ 密钥不能为空"
		return
	
	var xml_success = _save_key_to_xml(new_key)
	var raw_success = _save_key_to_raw(new_key)
	
	if xml_success or raw_success:
		current_key = new_key
		status_label.text = "✅ 密钥已保存到 Android 资源文件"
	else:
		status_label.text = "❌ 保存 Android 密钥失败"

func _save_key_to_files(key: String) -> bool:
	# 保存密钥到所有平台文件 (内部使用)
	var ios_success = _save_key_to_ios_gdip(key)
	var xml_success = _save_key_to_xml(key)
	var raw_success = _save_key_to_raw(key)
	return ios_success or xml_success or raw_success

func _save_key_to_xml(key: String) -> bool:
	# 保存密钥到 XML 文件
	var file = File.new()
	var xml_path = ProjectSettings.globalize_path(KEY_FILE_PATH_XML)
	
	# 确保目录存在
	var dir = Directory.new()
	var dir_path = xml_path.get_base_dir()
	if not dir.dir_exists(dir_path):
		if dir.make_dir_recursive(dir_path) != OK:
			print("无法创建目录：", dir_path)
			return false
	
	if file.open(xml_path, File.WRITE) == OK:
		var xml_content = """<?xml version="1.0" encoding="utf-8"?>
<resources>
    <!-- TapTap 加密密钥 -->
    <string name="taptap_decrypt_key">""" + key + """</string>
</resources>"""
		file.store_string(xml_content)
		file.close()
		print("密钥已保存到 XML 文件：", xml_path)
		return true
	else:
		print("无法保存 XML 密钥文件")
		return false

func _save_key_to_raw(key: String) -> bool:
	# 保存密钥到 RAW 文件
	var file = File.new()
	var raw_path = ProjectSettings.globalize_path(KEY_FILE_PATH_RAW)
	
	# 确保目录存在
	var dir = Directory.new()
	var dir_path = raw_path.get_base_dir()
	if not dir.dir_exists(dir_path):
		if dir.make_dir_recursive(dir_path) != OK:
			print("无法创建目录：", dir_path)
			return false
	
	if file.open(raw_path, File.WRITE) == OK:
		file.store_string("# TapTap 加密密钥\n")
		file.store_string("# 请妥善保管此密钥\n")
		file.store_string(key)
		file.close()
		print("密钥已保存到 RAW 文件：", raw_path)
		return true
	else:
		print("无法保存 RAW 密钥文件")
		return false

func _save_key_to_ios_gdip(key: String) -> bool:
	# 保存密钥到 iOS .gdip 文件
	var gdip_path = ProjectSettings.globalize_path(KEY_FILE_PATH_IOS_GDIP)
	var file = File.new()
	
	if not file.file_exists(gdip_path):
		print("找不到 .gdip 文件：", gdip_path)
		return false
	
	var config = ConfigFile.new()
	var err = config.load(gdip_path)
	
	if err != OK:
		print("无法加载 .gdip 文件：", err)
		return false
	
	# 更新或添加密钥到 [plist] 部分
	config.set_value("plist", "TapTapDecryptKey:string_input", key)
	
	# 保存回文件
	err = config.save(gdip_path)
	
	if err == OK:
		print("密钥已保存到 iOS .gdip：", gdip_path)
		return true
	else:
		print("无法保存 .gdip 文件：", err)
		return false

func _on_encrypt_pressed():
	var token = token_input.text.strip_edges()
	if token.empty():
		status_label.text = "❌ 请输入 Token"
		return
	
	# 使用当前密钥进行加密
	current_key = key_input.text.strip_edges()
	if current_key.empty():
		status_label.text = "❌ 请先配置密钥"
		return
	
	# 简单的 XOR 加密
	var encrypted = _simple_encrypt(token)
	var encrypted_base64 = Marshalls.raw_to_base64(encrypted)
	
	encrypted_output.text = encrypted_base64
	
	status_label.text = "✅ 加密完成！使用方法：TapTap.initSdkWithEncryptedToken(\"" + encrypted_base64 + "\", clientId, false)"

func _simple_encrypt(text: String) -> PoolByteArray:
	# 简单的 XOR 加密
	var text_bytes = text.to_utf8()
	var key_bytes = current_key.to_utf8()
	var result = PoolByteArray()
	
	for i in range(text_bytes.size()):
		var encrypted_byte = text_bytes[i] ^ key_bytes[i % key_bytes.size()]
		result.append(encrypted_byte)
	
	return result