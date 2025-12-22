tool
extends EditorScript

# TapTap Token 加密工具
# 用于加密 Client Token 以安全存储在 GDScript 中
# 
# 使用方法：
# 1. 修改下面的 PLAIN_TOKEN 和 ENCRYPTION_KEY
# 2. 在编辑器中：File → Run (Ctrl+Shift+X)
# 3. 复制输出的加密 Token 到你的初始化代码中

# ==================== 配置区域 ====================
# 从 TapTap 开发者中心复制你的 Client Token
const PLAIN_TOKEN = "j25Bb060oycdNPhDyPiMZ708z3KJuQV791prvksR"

# 从 godot3_taptap.gdip 文件的 [plist] 部分复制 TapTapDecryptKey 的值
# 或者你可以使用任意密钥，但必须在 .gdip 中配置相同的密钥
const ENCRYPTION_KEY = "TapTap73sev5b6P5eZxAy2"
# ==================================================

func _run():
	print("=".repeat(70))
	print("🔐 TapTap Token 加密工具")
	print("=".repeat(70))
	
	# 验证输入
	if PLAIN_TOKEN.empty() or PLAIN_TOKEN == "YOUR_CLIENT_TOKEN_HERE":
		printerr("\n❌ 错误：请先修改脚本中的 PLAIN_TOKEN")
		printerr("   从 TapTap 开发者中心复制你的 Client Token")
		return
	
	if ENCRYPTION_KEY.empty() or ENCRYPTION_KEY == "YOUR_ENCRYPTION_KEY":
		printerr("\n❌ 错误：请先修改脚本中的 ENCRYPTION_KEY")
		printerr("   从 godot3_taptap.gdip 的 [plist] 部分复制密钥")
		return
	
	print("\n📋 输入信息:")
	print("  原始 Token: ", PLAIN_TOKEN)
	print("  Token 长度: ", PLAIN_TOKEN.length())
	print("  加密密钥: ", ENCRYPTION_KEY)
	print("  密钥长度: ", ENCRYPTION_KEY.length())
	
	# 执行加密
	var encrypted = encrypt_token(PLAIN_TOKEN, ENCRYPTION_KEY)
	
	print("\n🔒 加密结果:")
	print("  加密 Token: ", encrypted)
	print("  加密 Token 长度: ", encrypted.length())
	
	# 验证：尝试解密
	print("\n✅ 验证解密:")
	var decrypted = decrypt_token(encrypted, ENCRYPTION_KEY)
	print("  解密结果: ", decrypted)
	print("  解密长度: ", decrypted.length())
	
	if decrypted == PLAIN_TOKEN:
		print("  ✅ 加密/解密验证成功！")
	else:
		print("  ❌ 警告：解密结果与原始 Token 不匹配！")
		print("  原始: ", PLAIN_TOKEN)
		print("  解密: ", decrypted)
	
	# 生成使用代码
	print("\n📝 在 GDScript 中使用加密 Token:")
	print("━".repeat(70))
	print("# 初始化 TapTap SDK（使用加密 Token）")
	print("var client_id = \"wpyjvbc5f2jnqqlgfr\"")
	print("var encrypted_token = \"", encrypted, "\"")
	print("TapTap.initSdkWithEncryptedToken(client_id, encrypted_token, true)")
	print("━".repeat(70))
	
	print("\n⚙️  确保 .gdip 文件配置正确:")
	print("━".repeat(70))
	print("[plist]")
	print("TapTapDecryptKey:string_input=\"", ENCRYPTION_KEY, "\"")
	print("━".repeat(70))
	
	print("\n🎯 重要提示:")
	print("• 原始 Token 不要提交到版本控制")
	print("• 只提交加密后的 Token")
	print("• 团队成员各自使用自己的加密密钥")
	print("• iOS 和 Android 可以使用不同的密钥")
	
	print("\n=".repeat(70))

# XOR 加密函数（与 iOS/Android 插件中的解密算法对应）
func encrypt_token(plain_text: String, key: String) -> String:
	if plain_text.empty() or key.empty():
		return ""
	
	var plain_bytes = plain_text.to_utf8()
	var key_bytes = key.to_utf8()
	var encrypted_bytes = PoolByteArray()
	
	# XOR 加密
	for i in range(plain_bytes.size()):
		var plain_byte = plain_bytes[i]
		var key_byte = key_bytes[i % key_bytes.size()]
		var encrypted_byte = plain_byte ^ key_byte
		encrypted_bytes.append(encrypted_byte)
	
	# Base64 编码
	var base64_string = Marshalls.raw_to_base64(encrypted_bytes)
	return base64_string

# XOR 解密函数（用于验证）
func decrypt_token(encrypted_base64: String, key: String) -> String:
	if encrypted_base64.empty() or key.empty():
		return ""
	
	# Base64 解码
	var encrypted_bytes = Marshalls.base64_to_raw(encrypted_base64)
	if encrypted_bytes.size() == 0:
		return ""
	
	var key_bytes = key.to_utf8()
	var decrypted_bytes = PoolByteArray()
	
	# XOR 解密
	for i in range(encrypted_bytes.size()):
		var encrypted_byte = encrypted_bytes[i]
		var key_byte = key_bytes[i % key_bytes.size()]
		var decrypted_byte = encrypted_byte ^ key_byte
		decrypted_bytes.append(decrypted_byte)
	
	# 转换为字符串
	return decrypted_bytes.get_string_from_utf8()
