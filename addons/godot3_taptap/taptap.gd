extends Node

#region 文档说明
# TapTap SDK for Godot 3.x - GDScript封装层
#
# 这个脚本为 Godot 3.x 提供 TapTap SDK 的完整功能封装，包括：
# - TapTap登录系统
# - 正版验证 (License Verification)
# - DLC商品管理
# - 内购(IAP)功能  
# - 合规认证
# - 云存档 (Cloud Save)
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
# - onCloudSaveCallback: 云存档统一状态回调
# - onCreateArchiveSuccess: 创建存档成功
# - onCreateArchiveFailed: 创建存档失败
# - onGetArchiveListSuccess: 获取存档列表成功
# - onGetArchiveListFailed: 获取存档列表失败
# - onDownloadArchiveDataSuccess: 下载并解压存档成功
# - onDownloadArchiveDataFailed: 下载或解压存档失败
# - onUpdateArchiveSuccess: 更新存档成功
# - onUpdateArchiveFailed: 更新存档失败
# - onDeleteArchiveSuccess: 删除存档成功
# - onDeleteArchiveFailed: 删除存档失败
# - onGetArchiveCoverSuccess: 获取存档封面成功
# - onGetArchiveCoverFailed: 获取存档封面失败
#endregion

#region 枚举定义
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

#endregion

#region 类成员变量
const PLUGIN_NAME := "Godot3TapTap"
var singleton

var httpRequest: HTTPRequest

const DEFAULT_NAME = "Nameless"

var userAvatar: ImageTexture
var userName: String = DEFAULT_NAME
var openId: int = -1

var isReady: bool = false

var lastErrorMessage: String = ""
#endregion
#endregion

#region 基础工具方法
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
		# CloudSave 云存档相关信号
		_connect_cloudsave_signal()
		
		print(PLUGIN_NAME, " ready")
	else:
		print(PLUGIN_NAME, " load fail")
		
	isReady = true
	
func _connect_cloudsave_signal():
	if singleton.has_signal("onCloudSaveCallback"):
		singleton.connect("onCloudSaveCallback", self, "_onCloudSaveCallback")
		singleton.connect("onCreateArchiveSuccess", self, "_onCreateArchiveSuccess")
		singleton.connect("onCreateArchiveFailed", self, "_onCreateArchiveFailed")
		singleton.connect("onGetArchiveListSuccess", self, "_onGetArchiveListSuccess")
		singleton.connect("onGetArchiveListFailed", self, "_onGetArchiveListFailed")
		singleton.connect("onDownloadArchiveDataSuccess", self, "_onDownloadArchiveDataSuccess")
		singleton.connect("onDownloadArchiveDataFailed", self, "_onDownloadArchiveDataFailed")
		singleton.connect("onUpdateArchiveSuccess", self, "_onUpdateArchiveSuccess")
		singleton.connect("onUpdateArchiveFailed", self, "_onUpdateArchiveFailed")
		singleton.connect("onDeleteArchiveSuccess", self, "_onDeleteArchiveSuccess")
		singleton.connect("onDeleteArchiveFailed", self, "_onDeleteArchiveFailed")
		singleton.connect("onGetArchiveCoverSuccess", self, "_onGetArchiveCoverSuccess")
		singleton.connect("onGetArchiveCoverFailed", self, "_onGetArchiveCoverFailed")
#endregion

#region SDK初始化
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
#endregion

#region 登录功能
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
#endregion

#region 正版验证相关信号

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
#endregion

#region 用户信息功能
func isLogin() -> bool:
	# 检查用户是否已登录
	#
	# Returns:
	#   bool: true 如果用户已登录，false 如果用户未登录
	if not singleton: return openId != -1
	return singleton.isLogin()

func loadUserInfo(loadAvatar: bool) -> GDScriptFunctionState:
	print("loadUserInfo")
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
#endregion

#region 合规认证功能
func compliance():
	# 启动合规认证流程
	#
	# Triggers:
	#   onComplianceResult: 合规认证结果，参数为合规状态码和详细信息
	if not singleton: 
		yield(get_tree(), "idle_frame")
		emit_signal("onComplianceResult", ComplianceMessage.LOGIN_SUCCESS, "")
		return
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
#endregion

#region 正版验证功能
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
#endregion

#region IAP内购功能
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
#endregion

#region IAP信号处理
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
#endregion

#region 工具方法
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
#endregion

#region 便利方法
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
#endregion

#region 使用示例

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
#endregion

#region 云存档枚举定义
enum CloudSaveResultCode {
	NEED_LOGIN = 300001,  # 需要登录
	INIT_FAILED = 300002  # 初始化失败，需要重新初始化
}

enum CloudSaveErrorCode {
	INVALID_FILE_SIZE = 400000,  # 非法的存档文件/封面大小
	UPLOAD_LIMIT = 400001,  # 存档上传频率超限
	ARCHIVE_NOT_FOUND = 400002,  # 指定的存档不存在
	ARCHIVE_COUNT_LIMIT = 400003,  # 单个应用下存档数量超限
	APP_STORAGE_LIMIT = 400004,  # 单个应用下使用存储空间超限
	TOTAL_STORAGE_LIMIT = 400005,  # 总使用存储空间超限
	INVALID_TOKEN = 400006,  # 非法的操作令牌，通常是由于网络卡顿
	CONCURRENT_CALL = 400007,  # 不允许并发调用
	OSS_PROVIDER_NOT_FOUND = 400008,  # 找不到可用的 OSS 供应商
	INVALID_ARCHIVE_NAME = 400009  # 存档名称不合法
}
#endregion

#region 云存档信号定义
signal onCloudSaveCallback(result_code)
func _onCloudSaveCallback(resultCode: int):
	# 云存档统一状态回调
	emit_signal("onCloudSaveCallback", resultCode)

signal onCreateArchiveSuccess(archive_data)
	# 创建存档成功
	# archive_data: Dictionary 包含存档信息：
	#   - uuid: String - 存档UUID
	#   - name: String - 存档名称
	#   - summary: String - 存档摘要
	#   - extra: String - 额外信息
	#   - playtime: int - 游戏时长（秒）
	#   - fileId: String - 文件ID
	#   - coverSize: int - 封面大小（字节）
	#   - createdTime: int - 创建时间戳
	#   - modifiedTime: int - 修改时间戳
	#   - saveSize: int - 存档大小（字节）
func _onCreateArchiveSuccess(jsonString: String):
	var json = JSON.parse(jsonString)
	if json.error == OK:
		emit_signal("onCreateArchiveSuccess", json.result)
		emit_signal("onCreateArchiveCompleted", json.result, OK)
	else:
		emit_signal("onCreateArchiveSuccess", {"error": json.error_string})
		emit_signal("onCreateArchiveCompleted", null, ERR_BUG)

signal onCreateArchiveFailed(error_data)
func _onCreateArchiveFailed(jsonString: String):
	var json = JSON.parse(jsonString)
	if json.error == OK:
		lastErrorMessage = json.result.get("message", "未知错误")
		emit_signal("onCreateArchiveFailed", json.result)
		emit_signal("onCreateArchiveCompleted", null, ERR_BUG)
	else:
		lastErrorMessage = json.error_string
		emit_signal("onCreateArchiveFailed", {"error": json.error_string})
		emit_signal("onCreateArchiveCompleted", null, ERR_BUG)

signal onCreateArchiveCompleted(result, err)

signal onGetArchiveListSuccess(archives)
	# 获取存档列表成功
	# archives: Dictionary 包含存档列表信息：
	#   - archives: Array - 存档数组，每个元素是一个存档 Dictionary：
	#     - uuid: String - 存档UUID
	#     - name: String - 存档名称
	#     - summary: String - 存档摘要
	#     - extra: String - 额外信息（JSON字符串）
	#     - playtime: int - 游戏时长（秒）
	#     - fileId: String - 文件ID
	#     - coverSize: int - 封面大小（字节）
	#     - createdTime: int - 创建时间戳（毫秒）
	#     - modifiedTime: int - 修改时间戳（毫秒）
	#     - saveSize: int - 存档大小（字节）
	#   - count: int - 存档总数
	#
	# Example:
	#   {
	#     "archives": [
	#       {
	#         "uuid": "abc123",
	#         "name": "save_slot_001",
	#         "summary": "关卡 5",
	#         "extra": "{\"level\": 5, \"timestamp\": 1234567890}",
	#         "playtime": 3600,
	#         "fileId": "file123",
	#         "coverSize": 102400,
	#         "createdTime": 1704614400000,
	#         "modifiedTime": 1704614400000,
	#         "saveSize": 1048576
	#       }
	#     ],
	#     "count": 1
	#   }
func _onGetArchiveListSuccess(jsonString: String):
	var json = JSON.parse(jsonString)
	if json.error == OK:
		emit_signal("onGetArchiveListSuccess", json.result)
		emit_signal("onGetArchiveListCompleted", json.result, OK)
	else:
		emit_signal("onGetArchiveListSuccess", {"archives": [], "count": 0})
		emit_signal("onGetArchiveListCompleted", {"archives": [], "count": 0}, OK)

signal onGetArchiveListFailed(error_data)
func _onGetArchiveListFailed(jsonString: String):
	var json = JSON.parse(jsonString)
	if json.error == OK:
		lastErrorMessage = json.result.get("message", "未知错误")
		emit_signal("onGetArchiveListFailed", json.result)
		emit_signal("onGetArchiveListCompleted", null, ERR_BUG)
	else:
		lastErrorMessage = json.error_string
		emit_signal("onGetArchiveListFailed", {"error": json.error_string})
		emit_signal("onGetArchiveListCompleted", null, ERR_BUG)

signal onGetArchiveListCompleted(result, err)

signal onDownloadArchiveDataSuccess(archive_data)
	# 下载并解压存档成功
	# archive_data: Dictionary 包含存档信息：
	#   - uuid: String - 存档UUID
	#   - name: String - 存档名称
	#   - summary: String - 存档摘要
	#   - extra: String - 额外信息
	#   - playtime: int - 游戏时长（秒）
	#   - fileId: String - 文件ID
	#   - coverSize: int - 封面大小（字节）
	#   - createdTime: int - 创建时间戳
	#   - modifiedTime: int - 修改时间戳
	#   - saveSize: int - 存档大小（字节）
func _onDownloadArchiveDataSuccess(jsonString: String):
	var json = JSON.parse(jsonString)
	if json.error == OK:
		emit_signal("onDownloadArchiveDataSuccess", json.result)
		emit_signal("onDownloadArchiveDataCompleted", json.result, OK)
	else:
		emit_signal("onDownloadArchiveDataSuccess", {"error": json.error_string})
		emit_signal("onDownloadArchiveDataCompleted", null, ERR_BUG)

signal onDownloadArchiveDataFailed(error_data)
func _onDownloadArchiveDataFailed(jsonString: String):
	var json = JSON.parse(jsonString)
	if json.error == OK:
		lastErrorMessage = json.result.get("error", "未知错误")
		emit_signal("onDownloadArchiveDataFailed", json.result)
		emit_signal("onDownloadArchiveDataCompleted", null, ERR_BUG)
	else:
		lastErrorMessage = json.error_string
		emit_signal("onDownloadArchiveDataFailed", {"error": json.error_string})
		emit_signal("onDownloadArchiveDataCompleted", null, ERR_BUG)

signal onDownloadArchiveDataCompleted(result, err)

signal onUpdateArchiveSuccess(archive_data)
	# 更新存档成功
	# archive_data: Dictionary 包含存档信息：
	#   - uuid: String - 存档UUID
	#   - name: String - 存档名称
	#   - summary: String - 存档摘要
	#   - extra: String - 额外信息
	#   - playtime: int - 游戏时长（秒）
	#   - fileId: String - 文件ID
	#   - coverSize: int - 封面大小（字节）
	#   - createdTime: int - 创建时间戳
	#   - modifiedTime: int - 修改时间戳
	#   - saveSize: int - 存档大小（字节）
func _onUpdateArchiveSuccess(jsonString: String):
	var json = JSON.parse(jsonString)
	if json.error == OK:
		emit_signal("onUpdateArchiveSuccess", json.result)
		emit_signal("onUpdateArchiveCompleted", json.result, OK)
	else:
		emit_signal("onUpdateArchiveSuccess", {"error": json.error_string})
		emit_signal("onUpdateArchiveCompleted", null, ERR_BUG)

signal onUpdateArchiveFailed(error_data)
func _onUpdateArchiveFailed(jsonString: String):
	var json = JSON.parse(jsonString)
	if json.error == OK:
		lastErrorMessage = json.result.get("message", "未知错误")
		emit_signal("onUpdateArchiveFailed", json.result)
		emit_signal("onUpdateArchiveCompleted", null, ERR_BUG)
	else:
		lastErrorMessage = json.error_string
		emit_signal("onUpdateArchiveFailed", {"error": json.error_string})
		emit_signal("onUpdateArchiveCompleted", null, ERR_BUG)

signal onUpdateArchiveCompleted(result, err)

signal onDeleteArchiveSuccess(archive_data)
	# 删除存档成功
	# archive_data: Dictionary 包含存档信息：
	#   - uuid: String - 存档UUID
	#   - name: String - 存档名称
	#   - summary: String - 存档摘要
	#   - extra: String - 额外信息
	#   - playtime: int - 游戏时长（秒）
	#   - fileId: String - 文件ID
	#   - coverSize: int - 封面大小（字节）
	#   - createdTime: int - 创建时间戳
	#   - modifiedTime: int - 修改时间戳
	#   - saveSize: int - 存档大小（字节）
func _onDeleteArchiveSuccess(jsonString: String):
	var json = JSON.parse(jsonString)
	if json.error == OK:
		emit_signal("onDeleteArchiveSuccess", json.result)
		emit_signal("onDeleteArchiveCompleted", json.result, OK)
	else:
		emit_signal("onDeleteArchiveSuccess", {"error": json.error_string})
		emit_signal("onDeleteArchiveCompleted", null, ERR_BUG)

signal onDeleteArchiveFailed(error_data)
func _onDeleteArchiveFailed(jsonString: String):
	var json = JSON.parse(jsonString)
	if json.error == OK:
		lastErrorMessage = json.result.get("message", "未知错误")
		emit_signal("onDeleteArchiveFailed", json.result)
		emit_signal("onDeleteArchiveCompleted", null, ERR_BUG)
	else:
		lastErrorMessage = json.error_string
		emit_signal("onDeleteArchiveFailed", {"error": json.error_string})
		emit_signal("onDeleteArchiveCompleted", null, ERR_BUG)

signal onDeleteArchiveCompleted(result, err)

signal onGetArchiveCoverSuccess(cover_data)
func _onGetArchiveCoverSuccess(coverBytes: PoolByteArray):
	# 封面数据直接以 byte[] 形式接收，不再使用 Base64 编码
	emit_signal("onGetArchiveCoverSuccess", coverBytes)
	emit_signal("onGetArchiveCoverCompleted", coverBytes, OK)

signal onGetArchiveCoverFailed(error_data)
func _onGetArchiveCoverFailed(jsonString: String):
	var json = JSON.parse(jsonString)
	if json.error == OK:
		lastErrorMessage = json.result.get("message", "未知错误")
		emit_signal("onGetArchiveCoverFailed", json.result)
		emit_signal("onGetArchiveCoverCompleted", null, ERR_BUG)
	else:
		lastErrorMessage = json.error_string
		emit_signal("onGetArchiveCoverFailed", {"error": json.error_string})
		emit_signal("onGetArchiveCoverCompleted", null, ERR_BUG)

signal onGetArchiveCoverCompleted(result, err)
#endregion

#region 云存档API方法

func createArchive(metadata: Dictionary, archiveFilePath: String, archiveCoverPath: String = "") -> void:
	# 创建游戏存档并上传云端
	#
	# 注意：
	# - 存档名称仅支持【英文/数字/下划线/中划线】，不支持中文
	# - 存档摘要 (summary) 以及额外信息 (extra) 无此限制
	# - 一分钟内仅可调用一次（与更新存档共享冷却时间）
	# - 单个存档文件大小不超过10MB
	# - 封面大小不超过512KB
	#
	# Args:
	#   metadata: 存档元数据 Dictionary，包含字段：
	#     - name: 存档名称（必填，String）
	#     - summary: 存档摘要/描述（可选，String）
	#     - extra: 额外信息（可选，String）
	#     - playtime: 游戏时长/秒（可选，int）
	#   archiveFilePath: 存档文件路径
	#   archiveCoverPath: 存档封面路径（可选）
	#
	# Example:
	#   var metadata = {
	#     "name": "save_slot_001",
	#     "summary": "关卡 5",
	#     "extra": '{"level": 5}',
	#     "playtime": 3600
	#   }
	#   createArchive(metadata, "user://saves/slot1", "user://covers/slot1.png")
	#
	# Triggers:
	#   onCreateArchiveSuccess: 创建成功
	#   onCreateArchiveFailed: 创建失败
	if not singleton: return
	var globalizedFilePath = ProjectSettings.globalize_path(archiveFilePath)
	var coverPath = archiveCoverPath if archiveCoverPath else ""
	var globalizedCoverPath = ProjectSettings.globalize_path(coverPath) if coverPath else ""
	singleton.createArchive(metadata, globalizedFilePath, globalizedCoverPath)

func getArchiveList() -> void:
	# 获取当前用户的存档列表
	#
	# Triggers:
	#   onGetArchiveListSuccess: 获取成功，参数为存档列表数组
	#   onGetArchiveListFailed: 获取失败
	if not singleton: return
	singleton.getArchiveList()

func downloadArchiveData(archiveUuid: String, archiveFileId: String, localArchivePath: String) -> void:
	# 下载存档并自动解压到本地路径（推荐使用）
	#
	# 此方法会下载云端存档，自动解压并覆盖本地指定路径的存档文件或目录
	#
	# Args:
	#   archiveUuid: 存档UUID
	#   archiveFileId: 存档文件ID
	#   localArchivePath: 本地存档路径（文件或目录），使用 res:// 或 user:// 路径
	#
	# Triggers:
	#   onDownloadArchiveDataSuccess: 下载并解压成功，参数为 {"path": String, "size": int}
	#   onDownloadArchiveDataFailed: 下载或解压失败，参数为 {"error": String, "code": int}
	if not singleton: return
	var globalizedPath = ProjectSettings.globalize_path(localArchivePath)
	singleton.downloadArchiveData(archiveUuid, archiveFileId, globalizedPath)

func updateArchive(archiveUuid: String, metadata: Dictionary, archiveFilePath: String, 
				   archiveCoverPath: String = "") -> void:
	# 更新指定的存档文件
	#
	# 注意：
	# - 存档名称仅支持【英文/数字/下划线/中划线】，不支持中文
	# - 存档摘要 (summary) 以及额外信息 (extra) 无此限制
	# - 一分钟内仅可调用一次（与创建存档共享冷却时间）
	# - 单个存档文件大小不超过10MB
	# - 封面大小不超过512KB
	#
	# Args:
	#   archiveUuid: 存档UUID
	#   metadata: 存档元数据 Dictionary，包含字段：
	#     - name: 存档名称（必填，String）
	#     - summary: 存档摘要/描述（可选，String）
	#     - extra: 额外信息（可选，String）
	#     - playtime: 游戏时长/秒（可选，int）
	#   archiveFilePath: 新的存档文件路径
	#   archiveCoverPath: 新的存档封面路径（可选）
	#
	# Example:
	#   var metadata = {
	#     "name": "save_slot_001",
	#     "summary": "关卡 8",
	#     "playtime": 7200
	#   }
	#   updateArchive(uuid, metadata, "user://saves/slot1", null)
	#
	# Triggers:
	#   onUpdateArchiveSuccess: 更新成功
	#   onUpdateArchiveFailed: 更新失败
	if not singleton: return
	var globalizedFilePath = ProjectSettings.globalize_path(archiveFilePath)
	var coverPath = archiveCoverPath if archiveCoverPath else ""
	var globalizedCoverPath = ProjectSettings.globalize_path(coverPath) if coverPath else ""
	singleton.updateArchive(archiveUuid, metadata, globalizedFilePath, globalizedCoverPath)

func deleteArchive(archiveUuid: String) -> void:
	# 删除指定的存档文件
	#
	# Args:
	#   archiveUuid: 存档UUID
	#
	# Triggers:
	#   onDeleteArchiveSuccess: 删除成功
	#   onDeleteArchiveFailed: 删除失败
	if not singleton: return
	singleton.deleteArchive(archiveUuid)

func getArchiveCover(archiveUuid: String, archiveFileId: String) -> void:
	# 获取指定存档的封面图片
	#
	# Args:
	#   archiveUuid: 存档UUID
	#   archiveFileId: 存档文件ID
	#
	# Triggers:
	#   onGetArchiveCoverSuccess: 获取成功，参数包含Base64编码的封面数据
	#   onGetArchiveCoverFailed: 获取失败
	if not singleton: return
	singleton.getArchiveCover(archiveUuid, archiveFileId)
#endregion

