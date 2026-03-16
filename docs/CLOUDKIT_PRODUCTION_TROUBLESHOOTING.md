# CloudKit 生产环境跨设备云存档排障手册

## 一、结论先行

从你们的三组现象看，最可能不是单一问题，而是以下几类问题叠加：

1. 账号维度不一致：CloudKit 私有数据库按 Apple ID 隔离，不按游戏内账号隔离。
2. 环境维度不一致：部分包在 Development，部分包在 Production，导致设备间看不到同一批数据。
3. 应用启动同步策略问题：新设备首次拿到空列表后，触发了“空数据上传/覆盖/删除”，导致旧设备重装后也空。
4. 上传调用链缺失或失败未拦截：本地存档成功，但没有成功调用 createArchive 或 updateArchive。

你提到远程已将 schema 从 Development 部署到 Production，这只解决“结构可用”，不保证“数据一定被上传且跨设备可见”。

## 二、针对三组测试现象的原因分析

### 测试1
同ID原设备卸载重装后，成功读取到云存档。

可能说明：
1. 至少该设备对应环境里存在可读云记录。
2. 也可能是同设备上一次流程确实完成了上传。

### 测试2
同ID换新设备下载游戏后，新设备云存档为空，旧设备仍有云存档。

高概率原因：
1. 新旧设备 Apple ID 不同（最常见）。
2. 新旧设备安装包运行在不同 CloudKit 环境（Development 与 Production 不一致）。
3. 新设备 iCloud Drive 或应用 iCloud 权限未开启。
4. 新设备首次拉取时机过早，短时一致性延迟后没有重试。

### 测试3
同ID换新设备下载游戏后，新设备云存档为空；此时旧设备卸载重装后也为空。

高概率原因：
1. 新设备启动后执行了“空列表即上云覆盖/清理”的逻辑，导致云端记录被覆盖或删除。
2. 新设备上传了新空存档并替代了旧存档，旧设备重装后只能读到空结果。
3. 上传失败与重试策略不完善，导致错误状态被当成空状态处理。

## 三、是否缺失“上传 iCloud 云”步骤

结论：有可能缺失，必须按调用链核对。

当前插件不是“自动上传”，只有在业务层明确调用以下接口时才会写云：
1. createArchive
2. updateArchive

只调用 getArchiveList 或 downloadArchiveData 不会触发上传。

因此必须确认：
1. 每次本地存档落盘后，是否一定调用了 createArchive 或 updateArchive。
2. 失败回调是否被正确处理，是否存在“失败也继续当成功流程走”的情况。
3. 是否有任何自动同步逻辑会在空列表时执行 delete 或覆盖上传。

## 四、CloudKit 数据库详细操作流程（Production）

以下流程用于核对“结构、数据、权限、环境”四件事。

### A. 控制台结构核对
1. 打开 CloudKit Console。
2. 选择目标容器。
3. 切到 Production。
4. 在 Schema 确认 Record Type 存在：GameArchive。
5. 确认字段存在：metadata、file、cover。
6. 确认查询相关索引已部署。

### B. 数据存在性核对
1. 切到 Data 页。
2. 选择 Record Type: GameArchive。
3. 直接查看是否有记录。
4. 随机点开记录，核对字段：
   1. recordName
   2. metadata
   3. file 资源是否存在
   4. cover 资源是否存在（若业务要求）
5. 记录最近一次写入时间，用于和客户端日志对时。

### C. 权限与容器核对（Xcode）
1. 打开导出后的 Xcode 工程。
2. Target -> Signing & Capabilities。
3. 确认开启 iCloud。
4. 确认勾选 CloudKit。
5. 确认 Container 与线上容器一致。
6. 确认使用的 Provisioning Profile 包含 iCloud 能力。

### D. 环境一致性核对
1. 明确每台测试设备安装包来源：Xcode Debug、AdHoc、TestFlight、App Store。
2. 确保同一轮对比都使用同一发布渠道。
3. 避免一台跑 Development、一台跑 Production。

### E. 账号一致性核对
1. 两台设备都进入 iOS 设置确认 Apple ID 一致。
2. 两台设备都确认 iCloud Drive 已开启。
3. 两台设备都确认应用 iCloud 权限已允许。

## 五、客户端操作闭环（必须执行）

### 上传闭环
1. 本地保存文件成功。
2. 立即调用 createArchive 或 updateArchive。
3. 等待 onCreateArchiveSuccess 或 onUpdateArchiveSuccess。
4. 若失败，必须重试或告警，不能静默忽略。

### 下载闭环
1. 启动后调用 getArchiveList。
2. 若空列表，不要立刻清云或覆盖写入。
3. 做至少 2 到 3 次延迟重试（例如 2秒、5秒、10秒）。
4. 确认稳定空后，再进入“新档初始化”分支。

## 六、建议立即加的日志点（用于复盘）

每次 create/update/list/delete 都打印：
1. 设备标识（测试编号即可）。
2. Apple ID 是否同一人（脱敏标识）。
3. 当前包渠道与环境标识（Debug/TestFlight 等）。
4. record uuid。
5. 回调类型与错误码。

重点关注：
1. 新设备首次启动后是否触发 deleteArchive。
2. 新设备首次启动后是否触发 createArchive 且 metadata 为空。
3. list 为空后是否直接进入覆盖上传路径。

## 七、给测试同事的最小复现矩阵

1. 同 Apple ID + 同渠道包 + 同环境：验证跨设备可见。
2. 同 Apple ID + 不同渠道包：验证是否环境不一致。
3. 不同 Apple ID + 同游戏账号：验证必然不可见（用于教育用例）。
4. 新设备首次启动禁止写云，只读云：验证是否为“新设备写空覆盖”问题。

## 八、当前最优先排查顺序

1. 先排 Apple ID 与包渠道环境是否一致。
2. 再查新设备首次启动是否触发写云或删云。
3. 最后查上传调用是否有失败但被吞掉。

如果按以上顺序排，通常可以在半天内定位到主因。

## 九、新现象补充：Console 查不到 Record，但单设备可读

现象：
1. 在 iCloud Console 的 Development 和 Production 都看不到记录。
2. 设备端单机仍可读取到“云存档列表”。

这个现象常见有 4 种解释：

1. Console 对 Private 数据可见性有限。
1. 插件写入的是 Private Database，不是 Public Database。
1. 某些情况下 Console 无法像 Public 一样直观看到 Private 用户数据。
1. 所以“Console 看不到”不必然等于“没有写入”。

2. 实际写入了另一个 Container。
1. 插件使用默认容器，取决于签名和 entitlements。
1. 如果包里配置了多个容器或容器名不一致，可能查错容器。

3. 环境/渠道混用。
1. 一台设备可能跑 Development，另一台跑 Production。
1. Console 看的环境与设备实际写入环境不一致时，也会表现为“查不到”。

4. 本地短期一致性缓存导致“看起来像云端有数据”。
1. 当前实现里，create 或 update 成功后会有短期缓存。
1. 在 CloudKit 查询为空时，列表接口会优先返回这份缓存，避免写后读延迟。
1. 所以在同设备短时间内，可能看到列表不为空，但这并不代表云端一定已有记录。

## 十、最小验证路径（强烈建议按顺序做）

1. 确认测试动作只做读取，不做任何 create/update/delete。
1. 冷启动并等待超过 30 秒（当前缓存 TTL），再执行 getArchiveList。
1. 若此时仍有数据，优先怀疑确实已写云或业务层另有本地回填逻辑。
1. 若此时无数据，则之前结果很可能受短期缓存影响。

2. 抓 native 日志，核对三项关键信息：
1. container identifier。
1. createArchive/updateArchive 是否返回 SUCCESS。
1. save 后的 recordName。

3. 在同一构建包、同一 Apple ID、同一环境下做双设备交叉验证。
1. 设备 A 创建存档。
1. 设备 B 仅拉取，不写入。
1. 若 B 为空，继续查环境和容器。

4. 若要确认“不是缓存假象”，建议临时加一个诊断开关：
1. 禁用 getArchiveList 的 recent write fallback。
1. 仅返回 CloudKit 实际查询结果。
1. 用这个诊断包再做一次双设备验证。