# Sign In with Apple — GDScript 层接入指南

本文档介绍如何通过 `addons/apple_signin/AppleSignIn.gd` 脚本在 Godot 3 iOS 项目中集成苹果账号认证（Sign In with Apple）。该脚本是 C++ 底层插件 (`plugins/apple_signin`) 的 GDScript 桥接层，并内置了**首次登录数据缓存**机制。

---

## 一、前置配置（必须完成）

### 1. Apple Developer 后台

1. 登录 [Apple Developer](https://developer.apple.com/)，进入 **Certificates, IDs & Profiles → Identifiers**。
2. 找到你的 App ID（Bundle ID），勾选 **Sign In with Apple** 能力并保存。

### 2. Xcode 工程配置

将 Godot 项目导出为 iOS 后，用 Xcode 打开 `.xcodeproj`：

1. 选中 App Target → **Signing & Capabilities** 标签页。
2. 点击 **`+ Capability`**，添加 **Sign In with Apple**。
3. 这会在 `.entitlements` 文件里自动写入：
   ```xml
   <key>com.apple.developer.applesignin</key>
   <array>
       <string>Default</string>
   </array>
   ```

> ⚠️ **如果缺少此权限，调用 `sign_in()` 时会收到 `result: "error"`，且不会弹出任何系统对话框。**

### 3. 启用插件

在 Godot 编辑器的 **Project → Project Settings → Plugins** 中启用 `AppleSignIn`。  
插件会将 `AppleSignIn.gd` 注册为 Autoload 单例，游戏中任意脚本均可直接调用 `AppleSignIn.*`。

---

## 二、关键机制说明

### 苹果账号数据"只给一次"

苹果的安全策略规定：**email 和姓名（full_name_*）只在用户第一次授权登录时提供**。  
之后每次调用 `sign_in()`，这些字段将为空字符串。

### 自动缓存（本插件核心特性）

本 GDScript 层在首次登录成功后，会自动将 email 和姓名等字段写入：

```
user://apple_signin_cache/<sanitized_user_id>.json
```

**后续每次登录成功时**，若苹果返回的字段为空，脚本会自动从本地缓存中取值并合并到事件 Dictionary 里，`on_sign_in` 信号收到的 `event` 始终包含完整的用户资料。

合并时会在 `event` 中加入 `"cached": true` 标志，方便调试。

---

## 三、API 接口说明

### `sign_in(request_email: bool = true, request_name: bool = true) -> int`

发起苹果登录弹窗。

| 参数 | 说明 |
|---|---|
| `request_email` | 是否申请 email 授权范围（仅首次有效） |
| `request_name` | 是否申请姓名授权范围（仅首次有效） |

- 返回值：`OK` 或 `ERR_UNAVAILABLE`（非 iOS / iOS < 13）
- 结果通过 `on_sign_in` 信号异步返回

### `check_credential_state(user_id: String) -> void`

检查已存储的 `user` ID 是否仍然有效（未被用户撤销）。  
建议在**每次游戏启动时**调用，以确认帐号状态，避免使用失效的凭据。  
结果通过 `on_credential_state` 信号返回。

### `get_cached_profile(user_id: String) -> Dictionary`

直接读取某个账号的本地缓存资料，无需登录。  
若无缓存则返回空 Dictionary。

### `clear_cached_profile(user_id: String) -> void`

删除指定账号的本地缓存文件。  
适用于玩家手动登出或检测到凭据被撤销（`result == "revoked"`）等场景。

### `is_available() -> bool`

检查原生插件是否加载成功（仅在真实 iOS 上运行时返回 `true`）。

---

## 四、信号与事件 Dictionary 结构

### `on_sign_in(event: Dictionary)`

#### result == `"ok"`

```gdscript
{
    "type": "sign_in",
    "result": "ok",

    # 账号标识 — 每次登录均返回，请持久化存储以便后续调用 check_credential_state
    "user": "000343.a1b2c3...",

    # 以下字段首次登录时由苹果提供；之后从本地缓存合并
    "email":              "user@privaterelay.appleid.com",  # 可能是苹果私信邮件中继地址
    "full_name_given":    "三",
    "full_name_family":   "张",
    "full_name_middle":   "",
    "full_name_nickname": "",
    "full_name_prefix":   "",
    "full_name_suffix":   "",

    # 服务端验签所需
    "identity_token":     "eyJhbGci...",  # Base64 编码的 JWT；发给后端验证
    "authorization_code": "c1a2b3...",    # Base64 编码的一次性码；用于服务端换取 token

    # 真实用户指标
    "real_user_status": 2,  # 0=不支持, 1=未知, 2=可信真实用户

    # 其它
    "state":  "",    # 如调用时设置了 nonce/state 则此处有值
    "cached": false  # true = 本次 email/name 来自本地缓存（非首次登录）
}
```

#### result == `"cancel"`

用户关闭了苹果弹窗，无额外字段。

```gdscript
{
    "type": "sign_in",
    "result": "cancel"
}
```

#### result == `"error"`

```gdscript
{
    "type": "sign_in",
    "result": "error",
    "error_code": 1001,
    "error_description": "The operation couldn't be completed."
}
```

### `on_credential_state(event: Dictionary)`

```gdscript
{
    "type": "credential_state",
    "user": "000343.a1b2c3...",
    "result": "authorized"    # "authorized" | "revoked" | "not_found" | "transferred" | "error"
    # 当 result == "error" 时附带：
    # "error_code": ...,
    # "error_description": "..."
}
```

| result | 含义 |
|---|---|
| `authorized` | 凭据有效，用户仍已授权 |
| `revoked` | 用户已在苹果设备的「设置 → 隐私 → 账号」中撤销了授权，应引导用户重新登录 |
| `not_found` | 该设备从未使用苹果账号登录过此应用 |
| `transferred` | 用于 App Group 账号迁移场景（iOS 14+） |

---

## 五、推荐使用流程

```
游戏启动
    │
    ├─ 读取本地存储的 user_id（如果有）
    │       ├─ 有 → check_credential_state(user_id)
    │       │           ├─ authorized → 跳过登录，直接进入游戏
    │       │           ├─ revoked / not_found → 引导用户重新登录
    │       │           └─ error → 视情况处理
    │       └─ 无 → 展示「Sign In with Apple」按钮（自行实现 UI）
    │
    └─ 用户点击登录按钮 → sign_in()
            └─ on_sign_in 事件
                    ├─ ok     → 持久化 user_id；使用 email/name 展示欢迎界面
                    ├─ cancel → 忽略，保持登录页面
                    └─ error  → 提示用户错误信息
```

---

## 六、完整示例代码

```gdscript
extends Node

const USER_ID_SAVE_PATH := "user://apple_user_id.txt"

func _ready() -> void:
    if not AppleSignIn.is_available():
        print("不在 iOS 上运行，跳过苹果登录")
        return

    AppleSignIn.connect("on_sign_in", self, "_on_sign_in")
    AppleSignIn.connect("on_credential_state", self, "_on_credential_state")

    # 启动时检查已存储的账号状态
    var saved_uid := _load_user_id()
    if saved_uid != "":
        AppleSignIn.check_credential_state(saved_uid)
    else:
        _show_sign_in_button()

# ---------- 登录按钮回调（由你的 UI 调用）----------
func _on_sign_in_button_pressed() -> void:
    AppleSignIn.sign_in(true, true)

# ---------- 信号处理 ----------
func _on_sign_in(event: Dictionary) -> void:
    match event.get("result"):
        "ok":
            var uid: String = event["user"]
            _save_user_id(uid)

            # email 和名字：首次登录时由苹果提供，之后由缓存补全
            var display_name := event.get("full_name_given", "") \
                + " " + event.get("full_name_family", "")
            display_name = display_name.strip_edges()

            print("登录成功！")
            print("  用户 ID：", uid)
            print("  显示名称：", display_name if display_name != "" else "（未提供姓名）")
            print("  邮箱：", event.get("email", "（未提供）"))
            print("  数据来自缓存：", event.get("cached", false))

            # 将 identity_token 发送到服务端进行验证
            # _send_to_server(uid, event["identity_token"], event["authorization_code"])

            _enter_game()

        "cancel":
            print("用户取消了登录")

        "error":
            print("登录失败：%s (code %d)" % [
                event.get("error_description", "未知错误"),
                event.get("error_code", -1)
            ])

func _on_credential_state(event: Dictionary) -> void:
    match event.get("result"):
        "authorized":
            print("凭据有效，直接进入游戏")
            _enter_game()

        "revoked":
            print("苹果账号授权已被用户撤销，需要重新登录")
            _save_user_id("")
            AppleSignIn.clear_cached_profile(event.get("user", ""))
            _show_sign_in_button()

        "not_found":
            print("未找到登录记录，展示登录界面")
            _show_sign_in_button()

        "error":
            print("检查凭据状态失败：", event.get("error_description", ""))
            # 网络问题等临时错误，可以选择允许进入游戏
            _enter_game()

# ---------- 辅助方法 ----------
func _save_user_id(uid: String) -> void:
    var file := File.new()
    file.open(USER_ID_SAVE_PATH, File.WRITE)
    file.store_string(uid)
    file.close()

func _load_user_id() -> String:
    var file := File.new()
    if not file.file_exists(USER_ID_SAVE_PATH):
        return ""
    file.open(USER_ID_SAVE_PATH, File.READ)
    var uid := file.get_as_text().strip_edges()
    file.close()
    return uid

func _show_sign_in_button() -> void:
    pass  # TODO: 显示你的登录 UI

func _enter_game() -> void:
    pass  # TODO: 跳转到游戏主场景
```

---

## 七、注意事项汇总

| # | 注意事项 |
|---|---|
| 1 | **Xcode Capability 必须手动添加**，`.gdip` 中的 `AuthenticationServices.framework` 仅负责链接，不会自动写入 entitlement |
| 2 | **email / 姓名只在首次登录时提供**，本脚本已自动缓存，但若用户卸载重装应用，缓存会丢失 |
| 3 | **`identity_token` 必须在服务端用苹果公钥验证**，不可仅凭客户端返回的数据判断登录合法性 |
| 4 | **`user` ID 应持久化存储**（如 `user://` 文件或加密存档），它是后续 `check_credential_state` 的唯一输入 |
| 5 | 苹果私信邮件中继 `@privaterelay.appleid.com` 是正常现象；用户可在苹果设置中转为真实邮箱 |
| 6 | 若 `result == "revoked"`，应主动调用 `clear_cached_profile(user_id)` 删除本地缓存，并引导用户重新登录 |
| 7 | 在 Godot 编辑器中运行或在 Android 上运行时，所有调用均返回 `result: "error"` 并附带说明信息，不会崩溃 |
| 8 | 该插件最低支持 iOS 13.0，低于此版本的设备会收到 `error_code: -1` 的错误事件 |
