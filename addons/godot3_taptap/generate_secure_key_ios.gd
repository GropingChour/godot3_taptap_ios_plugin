tool
extends EditorScript

# TapTap iOS 密钥生成工具
# 生成随机密钥并更新 iOS Info.plist 文件

const PLIST_PATH = "res://ios_plugins/godot3_taptap/info.plist"

func _run():
	print("=".repeat(60))
	print("🔑 TapTap iOS 密钥生成工具")
	print("=".repeat(60))
	
	# 生成随机密钥
	var random_key = _generate_random_key()
	print("生成的随机密钥: ", random_key)
	
	# 保存到 iOS Info.plist
	if _save_key_to_plist(random_key):
		print("\n✅ 成功！")
		print("   密钥已保存到: ", ProjectSettings.globalize_path(PLIST_PATH))
		print("   密钥值: ", random_key)
	else:
		print("\n❌ 失败！")
		print("   请手动将密钥添加到 Info.plist：")
		print("   <key>TapTapDecryptKey</key>")
		print("   <string>", random_key, "</string>")
	
	print("\n🔒 安全提醒:")
	print("• 请妥善保管此密钥，不要泄露")
	print("• 不要将密钥文件提交到公开的版本控制系统")
	print("• 建议在 .gitignore 中添加: ios_plugins/godot3_taptap/info.plist")
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

func _save_key_to_plist(key: String) -> bool:
	# 保存密钥到 iOS Info.plist 文件
	var file = File.new()
	var plist_path = ProjectSettings.globalize_path(PLIST_PATH)
	
	# 确保目录存在
	var dir = Directory.new()
	var dir_path = plist_path.get_base_dir()
	if not dir.dir_exists(dir_path):
		if dir.make_dir_recursive(dir_path) != OK:
			printerr("无法创建目录: ", dir_path)
			return false
	
	var content = ""
	var has_key = false
	
	# 检查文件是否存在
	if file.file_exists(plist_path):
		# 读取现有内容
		if file.open(plist_path, File.READ) == OK:
			content = file.get_as_text()
			file.close()
			
			# 检查是否已有 TapTapDecryptKey
			var regex = RegEx.new()
			regex.compile('<key>TapTapDecryptKey</key>\\s*<string>([^<]+)</string>')
			var result = regex.search(content)
			
			if result:
				# 替换现有密钥
				has_key = true
				content = regex.sub(content, '<key>TapTapDecryptKey</key>\n\t<string>' + key + '</string>')
				print("已更新现有密钥")
		else:
			printerr("无法读取现有 plist 文件")
	
	# 如果文件不存在或没有密钥，需要添加密钥
	if not has_key:
		if content.empty():
			# 创建新的 plist 文件
			content = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>TapTapDecryptKey</key>
	<string>""" + key + """</string>
</dict>
</plist>
"""
			print("已创建新的 Info.plist 文件")
		else:
			# 在现有 plist 中插入密钥（在 </dict> 之前）
			var dict_end_pos = content.rfind("</dict>")
			if dict_end_pos > 0:
				var insert_text = "\t<key>TapTapDecryptKey</key>\n\t<string>" + key + "</string>\n"
				content = content.insert(dict_end_pos, insert_text)
				print("已在现有 plist 中添加密钥")
			else:
				printerr("无法解析 Info.plist 格式")
				return false
	
	# 写入文件
	if file.open(plist_path, File.WRITE) == OK:
		file.store_string(content)
		file.close()
		return true
	else:
		printerr("无法写入 Info.plist 文件")
		return false
