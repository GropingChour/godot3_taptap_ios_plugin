extends Node

const PLUGIN_NAME := "GameCenter"
var singleton

#region Signals
signal on_authentication(event)
signal on_post_score(event)
signal on_award_achievement(event)
signal on_achievement_descriptions(event)
signal on_achievements(event)
signal on_reset_achievements(event)
signal on_show_game_center(event)
signal on_identity_verification_signature(event)
#endregion

func _ready():
	pause_mode = Node.PAUSE_MODE_PROCESS
	if Engine.has_singleton(PLUGIN_NAME):
		singleton = Engine.get_singleton(PLUGIN_NAME)
		print(PLUGIN_NAME + " initialized")
	else:
		print(PLUGIN_NAME + " singleton not found")

func _process(delta):
	if not singleton:
		return
		
	var count = singleton.get_pending_event_count()
	while count > 0:
		var event = singleton.pop_pending_event()
		_dispatch_event(event)
		count -= 1

func _dispatch_event(event: Dictionary):
	var type = event.get("type", "")
	match type:
		"authentication":
			emit_signal("on_authentication", event)
		"post_score":
			emit_signal("on_post_score", event)
		"award_achievement":
			emit_signal("on_award_achievement", event)
		"achievement_descriptions":
			emit_signal("on_achievement_descriptions", event)
		"achievements":
			emit_signal("on_achievements", event)
		"reset_achievements":
			emit_signal("on_reset_achievements", event)
		"show_game_center":
			emit_signal("on_show_game_center", event)
		"identity_verification_signature":
			emit_signal("on_identity_verification_signature", event)

#region Public API
func authenticate():
	# 验证玩家授权
	#
	# 初始化并验证本地玩家的 Game Center 账号登录状态。
	# 必须在调用其它 Game Center 接口前优先调用该方法以确保用户已登录。
	#
	# Triggers:
	#   on_authentication: 授权回调
	#     - result: "ok" 或 "error"
	#     - player_id: 玩家唯一标识（iOS 13+ 返回 teamPlayerID，否则返回 playerID）
	#     - alias: 玩家昵称
	#     - displayName: 玩家显示名称
	#     - error_code / error_description: result为error时返回错误信息
	if singleton:
		return singleton.authenticate()
	return ERR_UNAVAILABLE

func is_authenticated() -> bool:
	# 检查玩家是否已授权登录
	#
	# Returns:
	#   bool: true 表示玩家已登录 Game Center，false 表示未登录
	if singleton:
		return singleton.is_authenticated()
	return false

func post_score(score_dictionary: Dictionary):
	# 提交分数到排行榜 (Leaderboard)
	#
	# Args:
	#   score_dictionary: 包含分数信息的字典：
	#     - score: (float) 玩家的分数
	#     - category: (String) 排行榜的 ID (Leaderboard Identifier)
	#
	# Triggers:
	#   on_post_score: 提交结果回调
	#     - result: "ok" 或 "error"
	#     - error_code / error_description: 错误信息
	if singleton:
		return singleton.post_score(score_dictionary)
	return ERR_UNAVAILABLE

func award_achievement(achievement_dictionary: Dictionary):
	# 报告成就进度 (Achievement)
	#
	# Args:
	#   achievement_dictionary: 包含成就信息的字典：
	#     - name: (String) 成就的 ID (Achievement Identifier)
	#     - progress: (float) 成就完成百分比 (0.0 到 100.0)
	#     - show_completion_banner: (bool, 可选) 是否在成就完成时展示系统横幅，默认为 false
	#
	# Triggers:
	#   on_award_achievement: 汇报结果回调
	#     - result: "ok" 或 "error"
	#     - error_code: 错误码
	if singleton:
		return singleton.award_achievement(achievement_dictionary)
	return ERR_UNAVAILABLE

func reset_achievements():
	# 重置当前玩家的所有成就进度
	#
	# 通常用于游戏测试或玩家要求重置存档数据时。
	#
	# Triggers:
	#   on_reset_achievements: 重置结果回调
	#     - result: "ok" 或 "error"
	#     - error_code: 错误码
	if singleton:
		singleton.reset_achievements()

func request_achievements():
	# 请求当前玩家已获得的成就及其进度
	#
	# Triggers:
	#   on_achievements: 获取结果回调
	#     - result: "ok" 或 "error"
	#     - names: (Array) 已获得的成就 ID 列表
	#     - progress: (Array) 对应成就的完成进度列表 (0.0 - 100.0)
	if singleton:
		singleton.request_achievements()

func request_achievement_descriptions():
	# 请求游戏中所有成就的配置描述（标题、说明等）
	#
	# 需要在 App Store Connect 中预先配置好成就的详细信息。
	#
	# Triggers:
	#   on_achievement_descriptions: 获取结果回调
	#     - result: "ok" 或 "error"
	#     - names: (Array) 成就 ID 列表
	#     - titles: (Array) 成就标题列表
	#     - unachieved_descriptions: (Array) 未达成时的描述列表
	#     - achieved_descriptions: (Array) 已达成时的描述列表
	#     - maximum_points: (Array) 成就点数列表
	#     - hidden: (Array) 是否为隐藏成就列表
	#     - replayable: (Array) 是否可重复完成列表
	if singleton:
		singleton.request_achievement_descriptions()

func show_game_center(screen_dictionary: Dictionary):
	# 调起并展现系统原生的 Game Center 界面 (Dashboard)
	#
	# Args:
	#   screen_dictionary: 界面参数字典：
	#     - view: (String) 需要展示的特定页面，可选值：
	#       "default" (默认界面), "leaderboards" (排行榜), "achievements" (成就), "challenges" (挑战)
	#     - leaderboard_name: (String, 可选) 当 view 为 "leaderboards" 时，特定拉起的排行榜 ID
	#
	# Triggers:
	#   on_show_game_center: 界面关闭后的回调
	#     - result: "ok"
	if singleton:
		return singleton.show_game_center(screen_dictionary)
	return ERR_UNAVAILABLE

func request_identity_verification_signature():
	# 请求第三方服务器验证本地玩家身份所需的安全签名数据
	#
	# 要求玩家当前必须是已授权登录状态。
	# 生成的签名用于发送给游戏自有服务端，经过 App Developer 秘钥验证玩家真实身份。
	#
	# Triggers:
	#   on_identity_verification_signature: 获取签名回调
	#     - result: "ok" 或 "error"
	#     - public_key_url: (String) 公钥地址 URL
	#     - signature: (String) Base64 编码的安全签名
	#     - salt: (String) Base64 编码的盐值
	#     - timestamp: (int) 签名时间戳
	#     - player_id: (String) 玩家 ID
	if singleton:
		return singleton.request_identity_verification_signature()
	return ERR_UNAVAILABLE
#endregion
