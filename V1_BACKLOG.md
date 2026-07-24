<!-- TADA_BILINGUAL_DOC: English is the default reading language. The original source text is preserved for verification. -->
<a id="english-default"></a>

> **Languages / 语言：** **English (default) / 英文（默认）** · [简体中文](#简体中文版)

# Tada Words V1 backlog

This backlog tracks release acceptance and external configuration. Physical-device feedback and all subsequent iterations are versioned in `FOLLOWUP_BUGFIXES_AND_IMPROVEMENTS.md`; the active source batch is `v0.7.0`. Use `MVP_ACCEPTANCE.md` for the executable checklist.

## Release blockers

### DEVICE-01: Sign and install on physical devices

**Status:** Earlier LocalQA installs exist; the exact-HEAD v0.7.0 signed iPhone/iPad regression and production Family Sync acceptance are required

- Select an Apple development Team in Xcode
- Confirm a valid signing identity
- Enable Developer Mode on the test iPhone and iPad
- Install the canonical `TadaWords.xcodeproj` build
- Complete one Read and one Write quest on each device

### DEVICE-02: Re-test physical-device follow-ups

**Status:** Automated implementation pass complete; fresh physical-device regression required

- Single-tap `Parents` and Results Replay
- Profile-first clean/returning launch
- Read silence before first response and Hear/See only after two valid errors
- Silence/noise/short-word speech behavior and child voiceprint samples
- Relaxed star recovery, calibration, and slow-side cases
- Parent Word Manager typing, Camera OCR, Photo OCR, newest-first, delete/Undo, and no automatic words
- Write final consonants and the continuous `tā-'dá, wòrds!` / `它达，沃尔子` launch phrase: `tah-DAH`, 105ms pause, lower `words`
- Moonpetal rainbow/unicorn visuals and upbeat score
- Double-Quest next-day Theme/Icon unlock and My Collection persistence
- Rotate all Parents routes in portrait/landscape, then confirm every child route restores landscape; simulator policy passes, but physical iPhone/iPad checks remain
- Tap the upper-right `Badge` on phone and tablet; simulator layout evidence passes, but physical navigation confirmation remains

### CLOUD-01: Add consent and erasure, then validate CloudKit

**Status:** v0.7.0 source implementation complete; production schema, destructive test-only erasure, and physical-device acceptance remain privacy release blockers

- [x] Add a persisted, default-off Family Sync choice
- [x] Block launch, onboarding-completion, lifecycle, manual, and invitation synchronization until the guardian opts in
- [x] Let the guardian disable future sync without blocking local quests
- [x] Keep LocalQA visibly device-only with a separate bundle ID and no iCloud entitlement
- [x] Implement ledger-before-purge deletion, owner remote erasure, participant leave/revocation, restart retry, and unconditional stale-device non-resurrection
- Create or attach `iCloud.com.tadawords.app` under the selected Team
- Deploy the CloudKit development schema
- Validate private-database sync on two devices using one Apple ID
- Validate a CloudKit share between two Apple IDs
- [x] Add production-only Apple `CKShare` access-management UI routed to the persisted private-owner or shared-participant root/share
- Validate owner removal, participant leave, and revocation on signed iPhone/iPad builds
- [x] Cover offline edits, conflict resolution, retry, corrupt data, account changes, invitation routing, deletion dominance, crash replay, and two-device arrival permutations with deterministic source harnesses
- [x] Confirm child Quest commits never wait for CloudKit

Voiceprint templates remain device-scoped and do not sync through CloudKit.

Simulator and LocalQA builds intentionally use a local/device-only sync transport. The real CloudKit transport runs only in a normal signed physical-device build with the configured Team, container, iCloud account, and explicit guardian opt-in.

### VOICE-01: Calibrate child voiceprints

**Status:** Device Alpha code complete; representative accuracy evidence open

- Enroll the target child on each test device
- Collect same-child and different-speaker trials across multiple rooms and distances
- Measure false accept, false reject, and uncertain rates
- Tune thresholds only from representative child samples
- Confirm no raw enrollment or quest recording persists or uploads

The current on-device acoustic signature and conservative uncertain band improve routing. They do not prove that the microphone recorded only the selected child.

### AUDIO-01: Approve voice and music on device

**Status:** Code complete; listening approval open

- Complete two Read and two Write quests in every World
- Approve the young, energetic female voice on supported device voices
- Check pronunciation, loudness, fatigue, clipping, ducking, interruptions, and headphone changes
- Verify Reduced Sound and Calm Rescue preserve essential feedback

The shipping soundscape synthesizes original procedural music and cues. It does not bundle the downloaded child-speech test fixture or copied Todo Math assets.

### INPUT-01: Validate handwriting and Pencil behavior

**Status:** Code complete; child and device acceptance open

- Test four-year-old handwriting on iPhone and iPad
- Compare finger and Apple Pencil samples on iPad
- Place a palm on the screen while writing and check accidental-touch filtering
- Verify Left-handed writing keeps the primary controls reachable
- Calibrate recognition from real samples before changing thresholds

### ACCESS-01: Complete the physical accessibility pass

**Status:** Code complete; device acceptance open

- Walk through every child and Guardian route with VoiceOver
- Verify transient feedback and result summaries announce once
- Test larger Dynamic Type in compact landscape height
- Verify Reduce Motion removes repeating travel while preserving visible state changes
- Check Camera and Photo Library permission copy for both avatars and word-sheet OCR

### PRODUCT-01: Run the real-child usability session

**Status:** Human acceptance required

- Confirm a pre-reader can distinguish Read and Write without help
- Confirm the child can switch Profile, World, Calendar, and Badge/Collection
- Observe whether rewards remain motivating after several sessions
- Check that Rescue feedback helps without creating pressure

## Final repository cleanup

### REPO-01: Remove stale generated Xcode artifacts

**Status:** V1 baseline cleanup completed; canonical LocalQA files retained; the current v0.7.0 batch passes 814 Swift and 14 Issue Agent tests, and the exact committed-HEAD simulator reruns plus final artifact scan must be recorded at merge time

Keep:

- `TadaWords.xcodeproj`
- `Apps/TadaWordsApp/Info.plist`
- `Apps/TadaWordsApp/InfoLocalQA.plist`
- `Apps/TadaWordsApp/TadaWordsLocalQA.entitlements`
- `TadaWords.xcodeproj/xcshareddata/xcschemes/TadaWordsLocalQA.xcscheme`
- `project.yml`

Removed stale artifacts:

- `TadaWords 2.xcodeproj`
- `TadaWords 3.xcodeproj`
- `TadaWords 4.xcodeproj`
- `TadaWords 5.xcodeproj`
- `Apps/TadaWordsApp/Info 2.plist`

The numbered projects were generated snapshots, not source inputs. A repository scan now finds only the canonical `TadaWords.xcodeproj`; removing the duplicates prevents opening an obsolete target or shipping stale privacy and orientation settings.

## Completed V1 scope

- Two independent Today Quest routes, guided retry rules, timing isolation, Ebbinghaus review, and true mastery
- Profile-first onboarding with versioned consent, Profile setup, no starter-word form, and deferred system permissions
- Parent-only words via typing or local Camera/Photo OCR, normalization, newest-first queues, de-duplication, and delete/Undo
- Multiple Profiles, child nickname creation, last-profile highlight, photo/animal/earned icons, grade, age, and world settings
- Eight separate original worlds, 20 small rewards and five milestones each,
  distinct locked/earned treasure icons, treasure avatars, world unlocks,
  Collection, and monthly Calendar
- Guardian Today, Needs Attention, 7-day and 30-day reports, corrections, and CSV export
- Crash-resumable profile deletion, local notifications, sensitive-action authentication, and device-local voice setup
- Versioned private/shared CKSyncEngine transport, durable outbox/inbox/apply, full Profile/settings/pool/photo/event coverage, derived progress/rewards, default-off guardian opt-in, family invitations, and source-side remote erasure/non-resurrection; production schema and physical acceptance remain open
- Light-mode V1 visual system, compact landscape layouts, 44-point targets, VoiceOver announcements, Reduce Motion, and left-handed writing controls
<!-- TADA_BILINGUAL_ZH_START -->

---

<a id="简体中文版"></a>

> **翻译说明：** 英文为默认阅读语言；本文同时保留原始语言文本。如中英文内容存在差异，请以原始语言文本为准。

# Tada Words V1积压

此待办事项跟踪发布接受和外部配置。物理设备反馈和所有后续迭代都在`FOLLOWUP_BUGFIXES_AND_IMPROVEMENTS.md`中版本化；活跃源批次是`v0.7.0`。使用`MVP_ACCEPTANCE.md`进行可执行检查清单。

## 释放阻塞器

### 设备-01：在物理设备上签名并安装

**状态：**早期的LocalQA安装存在；需要确切的HEAD v0.7.0签名的iPhone/iPad回归和生产家庭同步接受

- 在 Xcode 中选择一个 Apple 开发团队
- 确认有效的签名身份
- 在测试iPhone和iPad上启用开发者模式
- 安装规范的`TadaWords.xcodeproj`构建
- 在每个设备上完成一个Read和一个Write任务

### 设备-02：重新测试物理设备后续检查

**状态：**自动实施通过完成；需要新的物理设备回归

- 单击`Parents`和结果Replay
- Profile-第一次清洁/返回发射
- Read在第一次回复之前保持沉默，并在两次有效错误后才听/看
- 沉默/噪音/短词语音行为和儿童语音指纹样本
- 放松的星级恢复、校准和慢侧案例
- 父词汇管理器键入，相机OCR，照片OCR，最新优先，删除/撤销，以及无自动词汇
- Write 最终辅音和连续的`tā-'dá, wòrds!` / `它达，沃尔子` 启动短语：`tah-DAH`，105毫秒暂停，降低`words`
- Moonpetal彩虹/独角兽视觉效果和欢快的配乐
- 双任务第二天主题/图标解锁和我的收藏品持久性
- 将所有Parents路线在纵向/横向旋转，然后确认每个子路线恢复了横向；模拟器政策通过，但物理iPhone/iPad检查仍然存在
- 在手机和平板电脑上轻点右上角的`Badge`；模拟器布局证据通过，但物理导航确认仍然存在

### CLOUD-01：添加同意和删除，然后验证CloudKit

**状态：** v0.7.0源代码实现完成；生产模式、仅破坏性测试擦除和物理设备接受仍是隐私发布障碍。

- [x] 添加一个保留的默认关闭的“家庭同步”选项
- [x] 阻止启动、入职完成、生命周期、手动和邀请同步，直到监护人选择加入。
- [x] 让守护者禁用未来的同步，而不阻碍本地任务
- [x] 保留LocalQA，明显只适用于设备，具有单独的捆绑ID，且无iCloud权利
- [x] 实施清理前日志删除、所有者远程抹除、参与者离开/撤销、重新启动重试和无条件过期设备无复活
- 在所选团队下创建或附加 `iCloud.com.tadawords.app`
- 部署CloudKit开发模式
- 使用一个Apple ID验证在两个设备上进行私人数据库同步的有效性
- 验证两个Apple ID之间的CloudKit份额
- [x] 添加仅限生产的 Apple `CKShare` 访问管理 UI，该 UI 路由至持久化的私人所有者或共享参与者根/共享文件夹。
- 验证签署的iPhone/iPad版本上的所有者删除、参与者休假和撤销
- [x] 涵盖离线编辑、冲突解决、重试、损坏数据、帐户更改、邀请路由、删除主导权、崩溃重播以及使用确定性源束的两个设备到达排列
- [x] 确认儿童 Quest 的提交永远不会等待 CloudKit

语音指纹模板仍然保持在设备范围内，不会通过CloudKit同步。

模拟器和LocalQA构建故意使用本地/仅限设备同步传输。真正的CloudKit传输仅在配置的团队、容器、iCloud帐户和明确的监护人选择加入的情况下在正常签名的物理设备构建中运行。

### 语音-01：校准儿童语音指纹

**状态：**设备Alpha代码已完成；代表性准确性证据已打开

- 在每个测试设备上注册目标儿童
- 在多个房间和不同距离收集相同孩子和不同扬声器试验
- 测量错误接受率、错误拒绝率和不确定率
- 仅从代表性儿童样本中调整阈值
- 确认没有原始注册或任务记录持续存在或上传

当前的设备上的声学特征和保守的不确定频段提高了路由。它们不能证明麦克风只录制了所选的子频段。

### 音频-01：批准设备上的语音和音乐

**状态：**代码完成；听证会审批开放

- 在每个世界完成两个Read和两个Write任务
- 批准支持设备语音上的年轻、充满活力的女性语音
- 检查发音、音量、疲劳、剪切、低音、中断和耳机更换情况
- 验证 Reduced Sound 和 Calm Rescue 是否保留了重要的反馈。

运输声音景观合成了原始程序音乐和提示。它不打包下载的儿童语音测试固定装置或复制好的Todo Math资产。

### 输入-01：验证手写和铅笔行为

**状态：**代码完成；儿童和设备接受开放

- 测试四岁儿童在iPhone和iPad上的手写字迹
- 比较iPad上的手指和Apple Pencil样本
- 在书写时将手掌放在屏幕上，并检查意外触摸过滤功能。
- 验证左撇子书写时，主要控制按钮仍然可以触及
- 在更改阈值之前，从真实样本中校准识别

### ACCESS-01：完成物理无障碍通行证

**状态：** 代码完成；设备接受开放

- 用VoiceOver穿过每个孩子和Guardian路线
- 验证瞬态反馈和结果摘要公告一次
- 在紧凑的景观高度中测试更大的Dynamic Type
- 验证Reduce Motion可以删除重复的旅行，同时保留可见的状态变化
- 检查头像和单词表OCR的相机和照片库权限副本

### PR产品-01：运行真实儿童可用性会议

**状态：**需要人类接受

- 确认预读器可以在没有帮助的情况下区分Read和Write
- 确认孩子可以切换 Profile、世界、日历和徽章/收藏
- 观察奖励在几次会议后是否仍然具有激励作用
- 检查“救援”反馈是否有助于帮助，而不会造成压力。

## 最终存储库清理

### REPO-01：删除过期的已生成 Xcode 工件

**状态：**V1基线清理完成；保留规范化LocalQA文件；当前v0.7.0批次通过了814 Swift和14 Issue代理测试，在合并时必须记录确切的提交的HEAD模拟器重运行以及最终人工制品扫描。

Keep:

- `TadaWords.xcodeproj`
- `Apps/TadaWordsApp/Info.plist`
- `Apps/TadaWordsApp/InfoLocalQA.plist`
- `Apps/TadaWordsApp/TadaWordsLocalQA.entitlements`
- `TadaWords.xcodeproj/xcshareddata/xcschemes/TadaWordsLocalQA.xcscheme`
- `project.yml`

移除了过期的工件：

- `TadaWords 2.xcodeproj`
- `TadaWords 3.xcodeproj`
- `TadaWords 4.xcodeproj`
- `TadaWords 5.xcodeproj`
- `Apps/TadaWordsApp/Info 2.plist`

编号项目是生成的快照，而不是源输入。存储库扫描现在只找到规范的`TadaWords.xcodeproj`；删除重复项可以防止打开过时的目标或发布过时的隐私和方向设置。

## 完成V1范围

- 两个独立的Today Quest路线，引导重试规则，时间隔离，Ebbinghaus审查和真正的掌握
- Profile-首次入职时需要获得版本同意，Profile设置，没有启动词表单，并且系统权限需要推迟
- 仅限家长的通过键入或本地相机/照片OCR、归一化、最新优先队列、去重和删除/撤销的单词
- 多个Profiles，儿童昵称创建，最后个人资料亮点，照片/动物/获得图标，年级，年龄和世界设置
- 八个独立的原始世界，20个小奖励和每个五个里程碑，
独特的锁定/获得的宝藏图标、宝藏头像、世界解锁、收藏和每月日历
- Guardian Today，需要注意，7天和30天的报告、更正和CSV导出
- 重启后可恢复的个人资料删除、本地通知、敏感操作认证和设备本地语音设置
- 版本化的私人/共享CKSyncEngine传输，持久的外箱/收件箱/应用，完整的Profile/设置/池/照片/事件覆盖，衍生的进度/奖励，默认关闭监护人选择加入，家庭邀请，以及源侧远程擦除/非复活；生产模式和物理接受仍然开放
- 光线模式V1视觉系统，紧凑的景观布局，44点目标，VoiceOver公告，Reduce Motion，以及左撇子书写控制
