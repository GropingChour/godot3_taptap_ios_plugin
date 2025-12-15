tool
extends EditorScript

# TapTap Android 密钥生成工具
# 生成随机密钥并更新 Android 资源文件

const RAW_PATH = "res://android/build/Godot3TapTap/src/main/res/raw/taptap_decrypt_key.txt"
const XML_PATH = "res://android/build/Godot3TapTap/src/main/res/values/taptap_keys.xml"

func _run():
	print("=".repeat(60))
	print("🔑 TapTap Android 密钥生成工具")
	print("=".repeat(60))
	
	# 生成随机密钥
	var random_key = _generate_random_key()
	print("生成的随机密钥: ", random_key)
	
	# 保存到 Android 资源文件
	var raw_success = _save_key_to_raw(random_key)
	var xml_success = _save_key_to_xml(random_key)
	
	if raw_success or xml_success:
		print("\n✅ 成功！")
		if raw_success:
			print("   RAW 文件: ", ProjectSettings.globalize_path(RAW_PATH))
		if xml_success:
			print("   XML 文件: ", ProjectSettings.globalize_path(XML_PATH))
		print("   密钥值: ", random_key)
	else:
		print("\n❌ 失败！")
		print("   请手动创建以下文件：")
		print("   1. ", ProjectSettings.globalize_path(RAW_PATH))
		print("      内容: ", random_key)
		print("   2. ", ProjectSettings.globalize_path(XML_PATH))
		print("      内容: <string name=\"taptap_decrypt_key\">", random_key, "</string>")
	
	print("\n🔒 安全提醒:")
	print("• 请妥善保管此密钥，不要泄露")
	print("• 不要将密钥文件提交到公开的版本控制系统")
	print("• 建议在 .gitignore 中添加:")
	print("  - android/build/Godot3TapTap/src/main/res/raw/taptap_decrypt_key.txt")
	print("  - android/build/Godot3TapTap/src/main/res/values/taptap_keys.xml")
	print("• 团队成员需要单独配置各自的密钥")
	
	print("\n📝 下一步操作:")
	print("1. 打开 Project → Tools → TapTap Token 加密配置")
	print("2. 使用新密钥加密 Client Token")
	print("3. 在 GDScript 中调用 TapTap.initSdkWithEncryptedToken()")
	print("=".repeat(60))

func _generate_random_key() -> String:
	# 生成 22 位随机密钥 (TapTap + 16位随机字符)
	var crypto = Crypto.new()
	var random_bytes = crypto.generate_random_bytes(16)
	var base64 = Marshalls.raw_to_base64(random_bytes)
	# 移除 Base64 中的特殊字符，只保留字母和数字
	var clean = base64.replace("=", "").replace("/", "").replace("+", "")
	return "TapTap" + clean.substr(0, 16)

func _save_key_to_raw(key: String) -> bool:
	# 保存密钥到 RAW 文件
	var file = File.new()
	var raw_path = ProjectSettings.globalize_path(RAW_PATH)
	
	# 确保目录存在
	var dir = Directory.new()
	var dir_path = raw_path.get_base_dir()
	if not dir.dir_exists(dir_path):
		if dir.make_dir_recursive(dir_path) != OK:
			printerr("无法创建目录: ", dir_path)
			return false
	
	if file.open(raw_path, File.WRITE) == OK:
		file.store_string("# TapTap 加密密钥\n")
		file.store_string("# 请妥善保管此密钥，不要提交到版本控制系统\n")
		file.store_string("# 此文件由 generate_secure_key_android.gd 自动生成\n")
		file.store_string(key)
		file.close()
		print("✓ RAW 文件已保存")
		return true
	else:
		printerr("✗ 无法写入 RAW 文件")
		return false

func _save_key_to_xml(key: String) -> bool:
	# 保存密钥到 XML 文件
	var file = File.new()
	var xml_path = ProjectSettings.globalize_path(XML_PATH)
	
	# 确保目录存在
	var dir = Directory.new()
	var dir_path = xml_path.get_base_dir()
	if not dir.dir_exists(dir_path):
		if dir.make_dir_recursive(dir_path) != OK:
			printerr("无法创建目录: ", dir_path)
			return false
	
	if file.open(xml_path, File.WRITE) == OK:
		var xml_content = """<?xml version="1.0" encoding="utf-8"?>
<resources>
    <!-- TapTap 加密密钥 -->
    <!-- 请妥善保管此密钥，不要提交到版本控制系统 -->
    <!-- 此文件由 generate_secure_key_android.gd 自动生成 -->
    <string name="taptap_decrypt_key">""" + key + """</string>
</resources>"""
		file.store_string(xml_content)
		file.close()
		print("✓ XML 文件已保存")
		return true
	else:
		printerr("✗ 无法写入 XML 文件")
		return false
