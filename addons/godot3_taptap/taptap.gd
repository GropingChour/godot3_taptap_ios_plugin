extends Node

# TapTap SDK for Godot 3.x - GDScript封装层
#
# 这个脚本为 Godot 3.x 提供 TapTap SDK 的完整功能封装，包括：
# - TapTap登录系统
# - 正版验证 (License Verification)
# - DLC商品管理
# - 内购(IAP)功能  
# - 合规认证
#
# 使用流程：
# 1. 调用 initSdk() 或 initSdkWithEncryptedToken() 初始化SDK
# 2. 调用 checkLicense() 进行正版验证
# 3. 根据需要调用相应的功能方法
# 4. 连接对应的信号来处理回调
#
# 信号列表：
# - onLoginSuccess: 登录成功
# - onLoginFail: 登录失败
# - onLoginCancel: 登录取消
# - onComplianceResult: 合规认证结果
# - onLicenseSuccess: 正版验证成功
# - onLicenseFailed: 正版验证失败
# - onDLCQueryResult: DLC查询结果
# - onDLCPurchaseResult: DLC购买结果
# - onProductDetailsResponse: 商品详情查询结果
# - onPurchaseUpdated: 购买状态更新
# - onFinishPurchaseResponse: 完成订单结果
# - onQueryUnfinishedPurchaseResponse: 未完成订单查询结果
# - onLaunchBillingFlowResult: 启动购买流程结果

enum ComplianceMessage {
	LOGIN_SUCCESS = 500, ## 玩家未受到限制，正常进入游戏
	EXITED = 1000, ## 退出防沉迷认证及检查，当开发者调用 Exit 接口时或用户认证信息无效时触发，游戏应返回到登录页
	SWITCH_ACCOUNT = 1001, ## 用户点击切换账号，游戏应返回到登录页
	PERIOD_RESTRICT = 1030, ## 用户当前时间无法进行游戏，此时用户只能退出游戏或切换账号
	DURATION_LIMIT = 1050, ## 用户无可玩时长，此时用户只能退出游戏或切换账号
	AGE_LIMIT = 1100, ## 当前用户因触发应用设置的年龄限制无法进入游戏，该回调的优先级高于 1030，触发该回调无弹窗提示
	INVALID_CLIENT_OR_NETWORK_ERROR = 1200, ## 数据请求失败，游戏需检查当前设置的应用信息是否正确及判断当前网络连接是否正常
	REAL_NAME_STOP = 9002, ## 实名过程中点击了关闭实名窗，游戏可重新开始防沉迷认证
}

const PLUGIN_NAME := "Godot3TapTap"
var singleton

var httpRequest: HTTPRequest

const DEFAULT_NAME = "Nameless"

var userAvatar: ImageTexture
var userName: String = DEFAULT_NAME
var openId: int = -1

var isReady: bool = false

func showTip(text: String):
	# 显示Toast提示信息
	#
	# Args:
	#   text: 要显示的文本内容
	if not singleton: return
	singleton.showTip(text)

func _ready():
	var isMobile = OS.has_feature("mobile")
	print("start taptap..., now isMobile: %s" % isMobile)
	
	if not isMobile: return
	
	if Engine.has_singleton(PLUGIN_NAME):
		singleton = Engine.get_singleton(PLUGIN_NAME)
		# 登录相关信号
		singleton.connect("onLoginSuccess", self, "_onLoginSuccess")
		singleton.connect("onLoginFail", self, "_onLoginFail")
		singleton.connect("onLoginCancel", self, "_onLoginCancel")
		# 合规认证信号
		singleton.connect("onComplianceResult", self, "_onComplianceResult")
		# 正版验证相关信号
		singleton.connect("onLicenseSuccess", self, "_onLicenseSuccess")
		singleton.connect("onLicenseFailed", self, "_onLicenseFailed")
		singleton.connect("onDLCQueryResult", self, "_onDLCQueryResult")
		singleton.connect("onDLCPurchaseResult", self, "_onDLCPurchaseResult")
		# IAP 内购相关信号
		singleton.connect("onProductDetailsResponse", self, "_onProductDetailsResponse")
		singleton.connect("onPurchaseUpdated", self, "_onPurchaseUpdated")
		singleton.connect("onFinishPurchaseResponse", self, "_onFinishPurchaseResponse")
		singleton.connect("onQueryUnfinishedPurchaseResponse", self, "_onQueryUnfinishedPurchaseResponse")
		singleton.connect("onLaunchBillingFlowResult", self, "_onLaunchBillingFlowResult")
		print(PLUGIN_NAME, " ready")
	else:
		print(PLUGIN_NAME, " load fail")
		
	isReady = true

func initSdk(clientId: String, clientToken: String, enableLog: bool = false, withIAP: bool = false) -> void:
	# 初始化 TapTap SDK
	#
	# Args:
	#   clientId: 游戏 Client ID，从开发者中心获取
	#   clientToken: 游戏 Client Token，从开发者中心获取
	#   enableLog: 是否启用日志，默认为 false
	#   withIAP: 是否启用内购功能，默认为 false
	if not singleton: return
	singleton.initSdk(clientId, clientToken, enableLog, withIAP)

# 使用加密token初始化SDK（推荐）
func initSdkWithEncryptedToken(clientId: String, encryptedToken: String, enableLog: bool = false, withIAP: bool = false) -> void:
	# 使用加密的token初始化SDK，提高安全性
	# 使用简单加密工具生成的加密token
	#
	# Args:
	#   encryptedToken: 通过简单加密工具生成的加密token
	#   clientId: 游戏 Client ID，从开发者中心获取  
	#   enableLog: 是否启用日志，默认为 false
	if not singleton: return
	singleton.initSdkWithEncryptedToken(clientId, encryptedToken, enableLog, withIAP)

func login(useProfile: bool = false, useFriends: bool = false):
	# TapTap 用户登录
	#
	# Args:
	#   useProfile: 是否请求用户公开资料权限 (public_profile)
	#               - true: 获得 openId、unionId、用户昵称、用户头像
	#               - false: 仅获得 openId 和 unionId (basic_info，支持无感登录)
	#   useFriends: 是否请求好友权限 (user_friends)
	#
	# Triggers:
	#   onLoginSuccess: 登录成功
	#   onLoginFail: 登录失败，参数为错误信息
	#   onLoginCancel: 用户取消登录
	if not singleton:
		yield(get_tree(), "idle_frame")
		_onLoginSuccess()
		return
	singleton.login(useProfile, useFriends)

signal onLoginCompleted(err)

signal onLoginSuccess()
func _onLoginSuccess():
	emit_signal("onLoginSuccess")
	emit_signal("onLoginCompleted", OK)

var login_fail_message: String

signal onLoginFail(message)
func _onLoginFail(message: String):
	login_fail_message = message
	emit_signal("onLoginFail", message)
	emit_signal("onLoginCompleted", ERR_BUG)

signal onLoginCancel()
func _onLoginCancel():
	emit_signal("onLoginCancel")
	emit_signal("onLoginCompleted", ERR_UNAUTHORIZED)

signal onComplianceResult(code, info)
func _onComplianceResult(code: int, info: String):
	emit_signal("onComplianceResult", code, info)

# ==================== 正版验证相关信号 ====================

signal onLicenseSuccess()
func _onLicenseSuccess():
	emit_signal("onLicenseSuccess")

signal onLicenseFailed()
func _onLicenseFailed():
	emit_signal("onLicenseFailed")

signal onDLCQueryResult(query_result)
func _onDLCQueryResult(jsonString: String):
	# DLC查询结果
	var json = JSON.parse(jsonString)
	if json.error == OK:
		emit_signal("onDLCQueryResult", json.result)
	else:
		emit_signal("onDLCQueryResult", {"error": json.error_string})

signal onDLCPurchaseResult(sku_id, status)
func _onDLCPurchaseResult(skuId: String, status: int):
	# DLC购买结果
	emit_signal("onDLCPurchaseResult", skuId, status)

func isLogin() -> bool:
	# 检查用户是否已登录
	#
	# Returns:
	#   bool: true 如果用户已登录，false 如果用户未登录
	if not singleton: return openId != -1
	return singleton.isLogin()

func loadUserInfo(loadAvatar: bool) -> GDScriptFunctionState:
	var needLoadName = userName.empty() or userName == DEFAULT_NAME
	var needLoadAvatar = loadAvatar and not userAvatar
	
	# 加载用户信息和头像
	#
	# 异步方法，加载完成后会设置 userName 和 userAvatar 变量
	if not needLoadName and not needLoadAvatar:
		yield (get_tree(), "idle_frame")
		return
	var profile = getUserProfile()
	if profile.has("error"):
		printerr(profile.error)
		yield (get_tree(), "idle_frame")
		return
	else:
		if needLoadName:
			userName = profile.name
			openId = profile.openId.hash()
			yield (get_tree(), "idle_frame")
		if needLoadAvatar:
			yield (httpDownloadAvatar(profile.avatar), "completed")
		return

func getUserProfile() -> Dictionary:
	# 获取当前登录用户的资料信息
	#
	# Returns:
	#   Dictionary: 包含用户信息的字典：
	#     - avatar: 用户头像URL
	#     - email: 用户邮箱
	#     - name: 用户昵称
	#     - accessToken: 访问令牌
	#     - openId: 用户唯一标识
	#     - unionId: 用户联合标识
	#     如果用户未登录或发生错误则返回包含 error 字段的字典
	if not singleton: 
		if OS.has_feature("editor"):
			return {"name": "test_taptap_name", "openId": "0"}
		else:
			return {"error": "android plugin load failed"}
	var profileText = singleton.getUserProfile()
	var json = JSON.parse(profileText)
	if json.error:
		return {"error": json.error_string, "raw": profileText}
	else:
		return json.result
	
func logout():
	# 登出当前用户
	#
	# 清除登录状态并重置用户信息
	userName = DEFAULT_NAME
	openId = -1
	userAvatar = null
	if not singleton: return
	singleton.logout()

func logoutThenRestart():
	userName = DEFAULT_NAME
	openId = -1
	userAvatar = null
	if not singleton: return
	singleton.logoutThenRestart()

func compliance():
	# 启动合规认证流程
	#
	# Triggers:
	#   onComplianceResult: 合规认证结果，参数为合规状态码和详细信息
	if not singleton: return
	singleton.compliance()

func complianceExit():
	# 退出合规认证
	#
	# 用于主动退出防沉迷认证及检查，通常在用户主动退出登录或切换账号时调用。
	# 调用此接口后会触发 onComplianceResult 信号，code 为 EXITED (1000)
	if not singleton: return
	singleton.complianceExit()

func httpDownloadAvatar(url: String):
	# 创建 HTTP 请求节点并连接完成信号。
	if not httpRequest:
		httpRequest = HTTPRequest.new()
		add_child(httpRequest)

	# 执行 HTTP 请求。截止到文档编写时，下面的 URL 会返回 PNG 图片。
	var error = httpRequest.request(url)
	if error != OK:
		push_error("HTTP 请求发生了错误。%d" % error)
		yield (get_tree(), "idle_frame")
		return
		
	var ret = yield (httpRequest, "request_completed")
	var reuslt = ret[0]
	var response_code = ret[1]
	var headers = ret[2]
	var body = ret[3]
	# 将在 HTTP 请求完成时调用。
	var image = Image.new()
	error = image.load_jpg_from_buffer(body)
	if error != OK:
		push_error("无法加载图片。")

	var texture = ImageTexture.new()
	texture.create_from_image(image)

	userAvatar = texture

# ==================== 版权验证相关方法 ====================

func checkLicense(forceCheck: bool = false):
	# 检查游戏许可证
	#
	# Args:
	#   forceCheck: 是否强制检查，true为强制检查，false为使用缓存
	#
	# Triggers:
	#   onLicenseSuccess: 正版验证成功
	#   onLicenseFailed: 正版验证失败
	if not singleton: return
	singleton.checkLicense(forceCheck)

func queryDLC(skuIds: Array):
	# 查询DLC购买状态
	#
	# 通过商品 skuId 数组批量查询多个商品购买状态，结果通过查询回调返回。
	#
	# Args:
	#   skuIds: 要查询的DLC商品ID数组
	#
	# Triggers:
	#   onDLCQueryResult: DLC查询结果
	#     query_result: Dictionary包含以下字段:
	#       - code: 查询结果代码 (int)
	#       - codeName: 查询结果名称 (String) 
	#       - queryList: Dictionary，key为商品ID，value为购买状态(0未购买，1已购买)
	#
	# 查询结果代码说明：
	#   QUERY_RESULT_OK = 0: 查询成功
	#   QUERY_RESULT_NOT_INSTALL_TAPTAP = 1: 未安装TapTap客户端
	#   QUERY_RESULT_ERR = 2: 查询失败
	#   ERROR_CODE_UNDEFINED = 80000: 未知错误
	if not singleton: return
	singleton.queryDLC(skuIds)

func purchaseDLC(skuId: String):
	# 购买DLC商品
	#
	# 通过商品 skuId 发起购买，结果通过购买回调返回。
	#
	# Args:
	#   skuId: 要购买的DLC商品ID
	#
	# Triggers:
	#   onDLCPurchaseResult: DLC购买结果
	#     sku_id: String - 购买的商品ID
	#     status: String - 购买状态
	#       - DLC_NOT_PURCHASED: 未完成支付
	#       - DLC_PURCHASED: 支付成功  
	#       - DLC_RETURN_ERROR: 支付异常
	if not singleton: return
	singleton.purchaseDLC(skuId)

# ==================== IAP 内购相关方法 ====================

func queryProductDetailsAsync(products: Array):
	# 查询应用内商品详情
	#
	# Args:
	#   products: 要查询的商品ID数组
	#
	# Triggers:
	#   onProductDetailsResponse: 商品详情查询结果
	if not singleton: return
	singleton.queryProductDetailsAsync(products)

func launchBillingFlow(productId: String, obfuscatedAccountId: String):
	# 启动购买流程
	#
	# Args:
	#   productId: 要购买的商品ID，必须先通过 queryProductDetailsAsync 查询过
	#   obfuscatedAccountId: 混淆账户ID，建议使用游戏内的订单ID或用户ID等唯一标识
	#
	# Triggers:
	#   onLaunchBillingFlowResult: 启动购买流程的结果
	#   onPurchaseUpdated: 购买状态更新（在购买过程中会多次触发）
	if not singleton: return
	singleton.launchBillingFlow(productId, obfuscatedAccountId)

func finishPurchaseAsync(orderId: String, purchaseToken: String):
	# 完成订单，确认商品已发放
	#
	# 重要：确认发放商品非常重要，如果您没有调用此方法来完成订单，
	# 用户将无法再次购买该商品，且该订单将会在3天后自动退款。
	#
	# Args:
	#   orderId: 订单ID，从购买回调中获取
	#   purchaseToken: 购买令牌，从购买回调中获取
	#
	# Triggers:
	#   onFinishPurchaseResponse: 完成订单结果
	if not singleton: return
	singleton.finishPurchaseAsync(orderId, purchaseToken)

func queryUnfinishedPurchaseAsync():
	# 查询未完成的订单列表
	#
	# 使用场景：
	# - 在购买过程中出现网络问题，用户成功购买但应用未收到通知
	# - 多设备间同步购买状态
	# - 应用异常崩溃后恢复购买状态
	#
	# 建议在应用的 onResume() 中调用此方法，确保所有购买交易都得到正确处理。
	#
	# Triggers:
	#   onQueryUnfinishedPurchaseResponse: 未完成订单查询结果
	if not singleton: return
	singleton.queryUnfinishedPurchaseAsync()

# ==================== IAP 信号处理 ====================

signal onProductDetailsResponse(response_data)
func _onProductDetailsResponse(jsonString: String):
	# 商品详情查询结果
	var json = JSON.parse(jsonString)
	if json.error == OK:
		emit_signal("onProductDetailsResponse", json.result)
	else:
		emit_signal("onProductDetailsResponse", {"error": json.error_string})

signal onPurchaseUpdated(purchase_data)
func _onPurchaseUpdated(jsonString: String):
	# 购买状态更新
	var json = JSON.parse(jsonString)
	if json.error == OK:
		emit_signal("onPurchaseUpdated", json.result)
	else:
		emit_signal("onPurchaseUpdated", {"error": json.error_string})

signal onFinishPurchaseResponse(response_data)
func _onFinishPurchaseResponse(jsonString: String):
	# 完成订单结果
	var json = JSON.parse(jsonString)
	if json.error == OK:
		emit_signal("onFinishPurchaseResponse", json.result)
	else:
		emit_signal("onFinishPurchaseResponse", {"error": json.error_string})

signal onQueryUnfinishedPurchaseResponse(response_data)
func _onQueryUnfinishedPurchaseResponse(jsonString: String):
	# 未完成订单查询结果
	var json = JSON.parse(jsonString)
	if json.error == OK:
		emit_signal("onQueryUnfinishedPurchaseResponse", json.result)
	else:
		emit_signal("onQueryUnfinishedPurchaseResponse", {"error": json.error_string})

signal onLaunchBillingFlowResult(result_data)
func _onLaunchBillingFlowResult(jsonString: String):
	# 启动购买流程结果
	var json = JSON.parse(jsonString)
	if json.error == OK:
		emit_signal("onLaunchBillingFlowResult", json.result)
	else:
		emit_signal("onLaunchBillingFlowResult", {"error": json.error_string})

# ==================== 工具方法 ====================

# showTip 方法已经在文件开头定义了

func restartApp():
	# 重启应用
	#
	# 完全重启当前应用，适用于需要重新加载配置或重置应用状态的场景。
	# 此方法会关闭当前应用并重新启动主 Activity。
	#
	# 使用场景：
	#   - 切换账号后需要重新初始化
	#   - 更新关键配置后需要重启
	#   - 修复某些状态异常
	#
	# 注意：此方法会立即终止当前进程，请确保在调用前已保存必要的数据。
	if not singleton: return
	singleton.restartApp()

# ==================== 便利方法 ====================

func initAndVerifyLicense(clientId: String, clientToken: String, enableLog: bool = false, withIAP: bool = false):
	# 便利方法：初始化SDK并立即进行正版验证
	#
	# 这是一个封装了SDK初始化和正版验证的便利方法，适合在游戏启动时使用
	#
	# Args:
	#   clientId: 游戏 Client ID
	#   clientToken: 游戏 Client Token  
	#   enableLog: 是否启用日志
	#   withIAP: 是否启用内购功能
	initSdk(clientId, clientToken, enableLog, withIAP)
	# 等待一帧确保SDK初始化完成
	yield(get_tree(), "idle_frame")
	checkLicense(false)

func initWithEncryptedTokenAndVerifyLicense(clientId: String, encryptedToken: String, enableLog: bool = false, withIAP: bool = false):
	# 便利方法：使用加密token初始化SDK并立即进行正版验证
	#
	# Args:
	#   clientId: 游戏 Client ID
	#   encryptedToken: 加密的 Client Token
	#   enableLog: 是否启用日志
	#   withIAP: 是否启用内购功能
	initSdkWithEncryptedToken(clientId, encryptedToken, enableLog, withIAP)
	# 等待一帧确保SDK初始化完成
	yield(get_tree(), "idle_frame")
	checkLicense(false)

func queryAndDisplayDLCStatus(dlcIds: Array):
	# 便利方法：查询并显示DLC状态
	#
	# 查询指定DLC的购买状态，并通过showTip显示结果
	#
	# Args:
	#   dlcIds: 要查询的DLC ID数组
	if dlcIds.empty():
		showTip("没有指定要查询的DLC")
		return
	
	# 连接临时信号处理器
	if not is_connected("onDLCQueryResult", self, "_temp_on_dlc_query_display"):
		connect("onDLCQueryResult", self, "_temp_on_dlc_query_display", [], CONNECT_ONESHOT)
	
	queryDLC(dlcIds)

func _temp_on_dlc_query_display(query_result: Dictionary):
	# 临时的DLC查询结果处理器，用于显示查询结果
	if query_result.has("error"):
		showTip("DLC查询失败: " + str(query_result.error))
		return
	
	if query_result.has("queryList"):
		var status_text = "DLC状态:\n"
		for dlc_id in query_result.queryList:
			var purchased = query_result.queryList[dlc_id]
			status_text += "%s: %s\n" % [dlc_id, "已购买" if purchased == 1 else "未购买"]
		showTip(status_text)
	else:
		showTip("DLC查询结果为空")

func purchaseProduct(productId: String, userOrderId: String = ""):
	# 便利方法：购买商品
	#
	# 这是一个封装了查询和购买流程的便利方法
	#
	# Args:
	#   productId: 要购买的商品ID
	#   userOrderId: 用户订单ID，如果为空则使用当前时间戳
	if userOrderId.empty():
		userOrderId = "order_" + str(OS.get_unix_time())
	
	# 先查询商品详情，然后启动购买
	var temp_product_id = productId
	var temp_order_id = userOrderId
	
	# 连接临时信号处理器
	if not is_connected("onProductDetailsResponse", self, "_temp_on_product_details"):
		connect("onProductDetailsResponse", self, "_temp_on_product_details", [temp_product_id, temp_order_id], CONNECT_ONESHOT)
	
	queryProductDetailsAsync([productId])

func _temp_on_product_details(response_data: Dictionary, product_id: String, order_id: String):
	# 临时的商品详情响应处理器，用于便利购买方法
	if response_data.has("error"):
		showTip("查询商品失败: " + str(response_data.error))
		return
	
	if response_data.has("productDetails") and response_data.productDetails.has(product_id):
		launchBillingFlow(product_id, order_id)
	else:
		showTip("商品不可用: " + product_id)

# ==================== 使用示例 ====================

# 使用示例：
#
# # 1. 初始化 SDK（启用内购功能）
# TapTap.initSdk("your_client_id", "your_client_token", true)
#
# # 2. 连接信号
# TapTap.connect("onLoginSuccess", self, "_on_login_success")
# TapTap.connect("onLicenseSuccess", self, "_on_license_success")
# TapTap.connect("onLicenseFailed", self, "_on_license_failed")
# TapTap.connect("onDLCQueryResult", self, "_on_dlc_query_result")
# TapTap.connect("onDLCPurchaseResult", self, "_on_dlc_purchase_result")
# TapTap.connect("onProductDetailsResponse", self, "_on_product_details")
# TapTap.connect("onPurchaseUpdated", self, "_on_purchase_updated")
#
# # 3. 登录
# TapTap.login(true, false)  # 请求用户资料权限，不请求好友权限
#
# # 4. 正版验证（游戏启动时调用）
# TapTap.checkLicense(false)  # 使用缓存
#
# # 5. 查询DLC状态
# TapTap.queryDLC(["dlc_id_1", "dlc_id_2"])
#
# # 6. 购买DLC
# TapTap.purchaseDLC("dlc_id_1")
#
# # 7. 处理正版验证回调
# func _on_license_success():
# 	print("正版验证成功，可以进入游戏")
# 	
# func _on_license_failed():
# 	print("正版验证失败，需要购买游戏")
#
# # 8. 处理DLC回调
# func _on_dlc_query_result(query_result):
# 	if query_result.has("queryList"):
# 		for dlc_id in query_result.queryList:
# 			var purchased = query_result.queryList[dlc_id]
# 			print("DLC %s 购买状态: %s" % [dlc_id, "已购买" if purchased == 1 else "未购买"])
# 
# func _on_dlc_purchase_result(sku_id, status):
# 	if status == "DLC_PURCHASED":
# 		print("DLC购买成功: " + sku_id)
# 		# 发放DLC内容给用户
# 		unlock_dlc_content(sku_id)
# 	else:
# 		print("DLC购买失败: " + sku_id + " - " + status)
#
# # 9. 查询IAP商品信息
# TapTap.queryProductDetailsAsync(["product_id_1", "product_id_2"])
#
# # 10. 启动IAP购买
# TapTap.launchBillingFlow("product_id_1", "user_order_id_123")
#
# # 11. 处理IAP购买回调
# func _on_purchase_updated(purchase_data):
# 	if purchase_data.has("purchase"):
# 		var purchase = purchase_data.purchase
# 		# 发放商品给用户
# 		give_item_to_user(purchase.productId)
# 		# 确认订单
# 		TapTap.finishPurchaseAsync(purchase.orderId, purchase.purchaseToken)
#
# # 12. 查询未完成订单（建议在游戏启动时调用）
# TapTap.queryUnfinishedPurchaseAsync()
#
# # 13. 合规认证（登录成功后调用）
# TapTap.compliance()
