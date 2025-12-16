tool
extends EditorScript

# TapTap iOS 密钥生成工具
# 生成随机密钥并更新 iOS .gdip 文件

const GDIP_PATH = "res://ios_plugins/godot3_taptap/godot3_taptap.gdip"

func _run():
	print("=".repeat(60))
	print("🔑 TapTap iOS 密钥生成工具")
	print("=".repeat(60))
	
	# 生成随机密钥
	var random_key = _generate_random_key()
	print("生成的随机密钥: ", random_key)
	
	# 保存到 iOS .gdip
	if _save_key_to_gdip(random_key):
		print("\n✅ 成功！")
		print("   密钥已保存到: ", ProjectSettings.globalize_path(GDIP_PATH))
		print("   密钥值: ", random_key)
	else:
		print("\n❌ 失败！")
		print("   无法保存到 .gdip 文件")
		print("   请手动编辑 godot3_taptap.gdip 的 [plist] 部分：")
		print("   TapTapDecryptKey:string_input=\"", random_key, "\"")
	
	print("\n🔒 安全提醒:")
	print("• 请妥善保管此密钥，不要泄露")
	print("• 密钥已保存在 .gdip 文件的 [plist] 部分")
	print("• 团队成员可以各自修改 .gdip 使用不同密钥")
	print("• 或在导出时在 iOS → Options → Plugins → TapTapLogin 中输入")
	
	print("\n📝 下一步操作:")
	print("1. 打开 Project → Tools → TapTap Token 加密配置")
	print("2. 使用新密钥加密 Client Token")
	print("3. 在 GDScript 中调用 TapTap.initSdkWithEncryptedToken()")
	print("\n📱 iOS 密钥使用:")
	print("• 密钥已保存在 .gdip 文件，导出时自动读取")
	print("• 也可在导出窗口修改：iOS → Options → Plugins → TapTapLogin → TapTapDecryptKey")
	print("=".repeat(60))

func _generate_random_key() -> String:
	# 生成 22 位随机密钥 (TapTap + 16位随机字符)
	var crypto = Crypto.new()
	var random_bytes = crypto.generate_random_bytes(16)
	var base64 = Marshalls.raw_to_base64(random_bytes)
	# 移除 Base64 中的特殊字符，只保留字母和数字
	var clean = base64.replace("=", "").replace("/", "").replace("+", "")
	return "TapTap" + clean.substr(0, 16)

func _save_key_to_gdip(key: String) -> bool:
	# 保存密钥到 iOS .gdip 文件
	var gdip_path = ProjectSettings.globalize_path(GDIP_PATH)
	var file = File.new()
	
	if not file.file_exists(gdip_path):
		printerr("找不到 .gdip 文件: ", gdip_path)
		return false
	
	var config = ConfigFile.new()
	var err = config.load(gdip_path)
	
	if err != OK:
		printerr("无法加载 .gdip 文件: ", err)
		return false
	
	# 更新或添加密钥到 [plist] 部分
	config.set_value("plist", "TapTapDecryptKey:string_input", key)
	
	# 保存回文件
	err = config.save(gdip_path)
	
	if err == OK:
		print("已更新 .gdip 文件中的密钥")
		return true
	else:
		printerr("无法保存 .gdip 文件: ", err)
		return false
