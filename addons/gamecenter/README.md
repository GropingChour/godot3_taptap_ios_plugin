# Godot iOS GameCenter 插件接入指南 (GDScript 层)

这个文档介绍了如何通过 `addons/gamecenter/GameCenter.gd` 脚本调用 iOS 设备的 GameKit 原生特性。该脚本是 C++ 底层插件的 GDScript 桥接层。

## 一、 App Store Connect 与 Xcode 核心配置

在使用任何 Game Center 接口之前，确保已妥善完成 Apple Developer 的各项配置：

### 1. App Store Connect 配置
登录 [App Store Connect](https://appstoreconnect.apple.com/)：
- **开启服务：** 进入您的应用程序页面，然后在功能 (Features) 面板中开启 Game Center。
- **配置排行榜 (Leaderboards)：** 添加排行榜时，记录所指定的 **排行榜 ID (Leaderboard ID)** (通常是全小写或反向域名)。这对应您调用 `post_score` 接口传入的 `category` 所需的标识符。
- **配置成就 (Achievements)：** 
  添加成就时注意设定它的参数：
  * **成就 ID (Achievement ID)：**  对应 `award_achievement` 传入的 `name` 标识。
  * **达成前说明 (Pre-earn Description)：** 玩家达成前看到的描述。对应接口返回的 `unachieved_descriptions`。
  * **达成后说明 (Earned Description)：** 玩家达成后看到的描述。对应接口返回的 `achieved_descriptions`。
  * **点数 (Points)：** 对应接口返回的 `maximum_points` 参数。上限为 100 分。
  * **隐藏 (Hidden)：** 除非完成，否则对玩家不可见。对应接口返回的 `hidden` 布尔标识。
  * **可重复 (Replayable)：** 该成就能否被多次完成。对应接口返回的 `replayable` 标识。

### 2. Xcode 导出工程配置
完成 Godot 的 iOS 导出后，用 Xcode 打开导出的 `.xcodeproj` 文件：
- 在您的 **App Target -> Signing & Capabilities** 标签页中点击 `+ Capability`。
- 选择添加 **Game Center** Capability 项。

---

## 二、 API 接口字典结构与说明

所有的游戏内调用通过自动加载的单例 `GameCenter` 发出，并通过 Signal 异步接收包含结果的 Dictionary（`event`）。

### 1. 玩家授权 (Authentication)
与 Game Center 交互的 **必经前置步骤**。须在游戏初始化阶段尽早调用。

* **调用**: `GameCenter.authenticate()`
* **响应事件**: `on_authentication`
* **解析 Dictionary (`event`)**:
  ```gdscript
  {
      "type": "authentication",
      "result": "ok" | "error",
      # 当 result == "ok" 时：
      "player_id": "G:1234567890",       # 玩家唯一标识（由于隐私保护，iOS 13+ 返回 TeamPlayerID）
      "alias": "PlayerAlias",            # 玩家的短昵称
      "displayName": "PlayerDisplayName",# 用于 UI 呈现的完整展示名
      # 当 result == "error" 时：
      "error_code": 2,                   # GameKit 原生抛出的 GKError Code
      "error_description": "..."         # 经过本地化翻译的错误详细说明
  }
  ```

### 2. 成就上报 (Award Achievement)
更新单条成就的积累进度。当进度汇报到 100.0 时，GameKit 认为该成就达成。

* **调用**: `GameCenter.award_achievement(achievement_dictionary)`
* **输入传递**:
  ```gdscript
  var achievement_dictionary = {
      "name": "achievement_id_from_app_store_connect",  # String: 成就ID
      "progress": 50.5,                                 # float: 完成进度 0.0 到 100.0
      "show_completion_banner": true                    # bool: (可选)是否在达成 100% 时弹出原生的顶端横幅
  }
  ```
* **响应事件**: `on_award_achievement`
* **解析 Dictionary (`event`)**:
  ```json
  {
      "type": "award_achievement",
      "result": "ok" | "error",
      "error_code": 1 
  }
  ```

### 3. 获取成就基础描述配置 (Achievement Descriptions)
读取您在 App Store Connect 后台专门配置的各条成就的基础静态配置信息（标题、达成前后描述、积分等）。

* **调用**: `GameCenter.request_achievement_descriptions()`
* **响应事件**: `on_achievement_descriptions`
* **解析 Dictionary (`event`)**:
  ```gdscript
  {
      "type": "achievement_descriptions",
      "result": "ok" | "error",
      # ⚠️ 以下全部是相同长度的平行数组(Array) ⚠️
      "names": ["achiev_id_1", "achiev_id_2"],             # String数组: 成就唯一ID集合
      "titles": ["新手上路", "百战百胜"],                      # String数组: 成就配置项的标题
      "unachieved_descriptions": ["获得第一场胜利", "未知条件"],   # String数组: 达成前的配置说明 (若是隐藏成就则文案也隐去)
      "achieved_descriptions": ["恭喜获胜", "你就是战神"],       # String数组: 满进度时的说明 
      "maximum_points": [10, 50],                          # int数组: 可以获得的GameCenter成长积分
      "hidden": [false, true],                             # bool数组: 是否属于隐藏成就
      "replayable": [false, false]                         # bool数组: 是否设计为可被重复达成
  }
  ```

### 4. 读取玩家真实进度 (Request Achievements)
读取该设备当前授权玩家对所有成就的已完成进度（也就是 `award_achievement` 成功提交上去保存在云端的进度）。

* **调用**: `GameCenter.request_achievements()`
* **响应事件**: `on_achievements`
* **解析 Dictionary (`event`)**:
  ```gdscript
  {
      "type": "achievements",
      "result": "ok" | "error",
      # 这两个是长度对齐的数组
      "names": ["achiev_id_1", "achiev_id_2"],   # String数组：有进度的成就ID列表
      "progress": [100.0, 50.5]                  # float数组：对应ID当前的完成百分比
  }
  ```

### 5. 上传排行分数 (Post Score)
* **调用**: `GameCenter.post_score(score_dictionary)`
* **输入传递**:
  ```gdscript
  var score_dictionary = {
      "score": 1050.0,                              # float: 您游戏中对应的数值
      "category": "leaderboard_id_from_app_store"   # String: 对应在后台配置的排行榜ID
  }
  ```
* **响应事件**: `on_post_score`
* **解析 Dictionary (`event`)**: 带有 `result` 与 `error_code`。

### 6. 控制台内嵌 UI 展示 (Show Game Center)
拉起具有系统原生视觉风格的全屏 Game Center Dashbord（玩家可通过面板自我查阅排行、挑战、好友与成就）。

* **调用**: `GameCenter.show_game_center(screen_dictionary)`
* **输入传递**:
  ```gdscript
  var screen_dictionary = {
      "view": "leaderboards",           # String: 可选项 -> "default", "leaderboards", "achievements", "challenges"
      "leaderboard_name": "id_string"   # String(可选): 但凡需要直接跳转到某一个特定排行，填排行 ID
  }
  ```
* **响应事件**: `on_show_game_center` (当玩家点击“完成/关闭”时触发，含带 `"result": "ok"`)

### 7. 数据保护重置 (Reset Achievements)
* **调用**: `GameCenter.reset_achievements()`
* **作用**: 把该开发环境或真实玩家在所有成就的历史记录全部重置为 0，用于测试重置存档，触发事件为 `on_reset_achievements`。

### 8. 自有后端验权加密包 (Identity Verification Signature)
用于确认 Godot 所获取的玩家是否伪造。获取 Apple 的安全加密后发给自有游戏后台进行公钥验证。

* **调用**: `GameCenter.request_identity_verification_signature()`
* **响应事件**: `on_identity_verification_signature`
* **解析 Dictionary (`event`)**:
  ```gdscript
  {
      "type": "identity_verification_signature",
      "result": "ok",
      "public_key_url": "https://...",   # String: Game Center提供的此验证请求对应公钥URL
      "signature": "Base64Str...",       # String: iOS系统签名（Base64编码）
      "salt": "Base64Str...",            # String: 该签名的特有盐值（Base64编码）
      "timestamp": 1690000000,           # int: 签名产生的时间戳
      "player_id": "G:1234567890"        # String: 对齐该签名的玩家ID
  }
  ```

---

## 三、 使用示例汇总

您可以通过如下方式使用这个插件，以便与您的 UI 连接。

```gdscript
extends Node

func _ready():
    if not OS.has_feature("ios") or not Engine.has_singleton("GameCenter"):
        return
    
    # 建立事件总接收管线
    GameCenter.connect("on_authentication", self, "_on_auth_result")
    GameCenter.connect("on_achievement_descriptions", self, "_on_achiev_desc_loaded")
    GameCenter.connect("on_achievements", self, "_on_achiev_progress_loaded")
    
    # 第 1 步：优先要求登录
    GameCenter.authenticate()

func _on_auth_result(event: Dictionary):
    if event.get("result") == "ok":
        print("GameKit 身份验证通过：" + event.get("displayName", ""))
        
        # 登录成功后，接着去拉取目前成就库配置单和存档进度
        GameCenter.request_achievement_descriptions()
        GameCenter.request_achievements()
    else:
        print("禁止使用：Game Center授权失败：" + str(event.get("error_description")))

# 后台配置的静态说明
func _on_achiev_desc_loaded(event: Dictionary):
    if event.result == "ok":
        var count = event.names.size()
        print("查找到后台成就总共 %d 条." % count)
        for i in range(count):
            print("ID:", event.names[i], " -> 标题:", event.titles[i], " -> 达成文案:", event.achieved_descriptions[i])

# 玩家已获得的进度
func _on_achiev_progress_loaded(event: Dictionary):
    if event.result == "ok":
        var i = 0
        for ach_id in event.names:
            print("玩家在成就 [%s] 的当前进度是 %f%%" % [ach_id, event.progress[i]])
            i += 1

# 在游戏内的特定按钮被按下时，解锁或修改成就
func on_kill_boss_clicked():
    print("击杀了首领，为该玩家填加对应成就记录！")
    GameCenter.award_achievement({
        "name": "boss_kill_01",
        "progress": 100.0,
        "show_completion_banner": true
    })
```