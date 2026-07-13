---
title: 如何验收 Tada Words V1
navLabel: V1 验收
contentType: How-to
category: Delivery
---

# 如何验收 Tada Words V1

这份清单用于验收当前 V1。先运行自动化检查和两种模拟器，再用真实 iPhone 与 iPad 验收麦克风、儿童语音、手写、辅助功能、音频、CloudKit 和通知。

## 先理解验收状态

每个项目使用以下一种状态：

- **代码已完成**：生产路径与自动化测试存在
- **模拟器已检查**：可验证导航、布局、状态和本地持久化
- **需要真机验收**：必须依赖真实硬件、儿童样本、Apple 账号或人工听感

代码或模拟器通过不代表儿童识别准确率、混音质量或 CloudKit 家庭共享已经通过。

## 运行自动化检查

在仓库根目录运行：

```sh
cd /path/to/tadawords
make generate
make check
./Scripts/verify-device-readiness.sh
```

通过标准：格式检查、单元与组合测试、iPhone 17 Pro Max LocalQA 模拟器构建、iPad Pro 13-inch (M5) LocalQA 模拟器构建全部通过。设备准备脚本可以在未配置签名 Team 时报告签名阻塞。

2026-07-13 的 v0.2 自动化证据如下。V1 的 367 项测试只保留为历史基线，已被本轮 479 项全量结果取代：

| 检查 | 结果 |
|---|---|
| Swift formatter 严格检查 | 通过 |
| Swift 单元与组合测试 | v0.2 全量 479/479 通过，0 failure；取代 V1 的 367 项基线 |
| iPhone 17 Pro Max LocalQA 模拟器构建 | 通过 |
| iPad Pro 13-inch (M5) LocalQA 模拟器构建 | 通过 |
| 两个 built product 的方向声明 | iPhone 为 Portrait + 两个 Landscape；iPad 为四向；`UIRequiresFullScreen` 为 true；运行时 Parents 可旋转，child route 只允许横屏 |
| 模拟器方向证据 | iPad 的 Parent 与 child 窗口形态符合路由策略；iPhone raw framebuffer 截图方向不可靠，仍需真机旋转确认 |
| Release CloudKit 分享声明 | iPhone 与 iPad Release built product 的 `CKSharingSupported` 为 true |
| LocalQA 隔离声明 | `Tada Words QA` 使用独立 bundle ID、空 iCloud entitlement，且 `CKSharingSupported` 为 false |
| 儿童语音 fixture | SHA-256 通过，Apple 转写为 `Bye.`，App policy 对目标 `bye` 判定为匹配 |

`CKSharingSupported` 是构建声明，不代表模拟器正在运行 CloudKit。模拟器刻意使用 local/device-only transport；真实 CloudKit transport 只能在配置 Team、container 与 iCloud 的签名真机上验收。

编号的 `.xcodeproj` 副本已经删除。只打开 `TadaWords.xcodeproj`，也不要使用方向或能力变更之前的 Derived Data。

## 核对关键需求

| 需求 | 当前状态 | 人工验收重点 |
|---|---|---|
| Read 与 Write 两条独立路线 | 代码已完成 | 两个 Today Quest 按钮不合并，数据与设置互不覆盖 |
| Parent Word Manager | v0.2 代码完成，待真机回归 | 单词 Return 即时加入、Camera/Photo OCR 预览、newest-first、单删/批删/Undo、两组独立去重 |
| 仅使用家长录入词 | v0.2 代码完成 | 无 smart fill / Grade 自动加入；Pool 不足时不补词 |
| New 与 Review 顺序可交换 | 代码已完成 | 每条路线独立保存顺序 |
| 艾宾浩斯复习与补弱 | 代码已完成 | 到期、错误、相对慢、重播和 Help 影响排序与记忆参数 |
| Write 新词示范与一次引导重写 | 代码已完成 | 先短暂显示答案，错误后显示答案，只提供一次引导重写 |
| Read 安静首答与两错后 Help | v0.2 代码完成，待真机回归 | 首答前不播答案；两次有效错答后才出现 Hear/See；技术失败不解锁也不耗次数 |
| 真正 Mastered 判定 | 代码已完成 | 三个不同本地日期独立成功，且未来 14 天预计回忆率达标 |
| 分数、宽松三颗星、严格 Guardian 证据 | v0.2 代码完成 | 一次无辅助立即恢复、校准 Pace、慢侧 25% 宽限；技术性 Move On 显示 Not scored |
| 八个独立主题世界 | v0.2 代码完成，待真机视听回归 | 公主、工程车、动物、恐龙、消防救援、原创积木、冰雪与过山车的场景/奖励不混用 |
| 每个世界 20 个小奖励与 5 个里程碑 | v0.2 代码完成，待真机视觉回归 | 共 200 件不同图标；永久收藏品不因 Practice Again 重发 |
| Double Quest 次日 Theme / Icon | v0.2 代码完成，待真机回归 | 同日 Read+Write 的 Today run 次日解锁；partial/replay 不算；My Collection 可选择已获得项目 |
| 多 Kid Profile 与上次 Profile | v0.2 代码完成，待真机回归 | 冷启动先到 Picker并突出上次 Profile；每个 Profile 数据、声纹、设置与 cosmetics 隔离 |
| Profile-first 首次流程 | v0.2 代码完成，待真机布局复验 | 无 Profile 直接 New Kid；首次流程无单词输入 |
| 自拍、照片、动物头像 | 代码已完成 | 真机检查 Camera 与 Photo Library 权限 |
| 月度打卡 Calendar | 代码已完成 | 每日显示准确 Quest 次数，Practice Again 也计数 |
| 7 日与 30 日报告 | 代码已完成 | 检查趋势、单词详情、识别纠正和 CSV 导出 |
| Crash-resumable Profile 删除 | 代码已完成 | 删除本地资料、单词、历史、奖励、提醒和本机声纹 |
| 本地通知与安静时段 | 代码已完成 | 每日、Pool low、完成、同步失败、周报与时间设置 |
| CloudKit 同步与家庭邀请 | 持久、默认关闭的家长 opt-in 已完成；远端删除未完成 | 用 Developer Team、iCloud container 与两个 Apple 账号验收 opt-in、关闭和邀请；远端擦除完成前不可发布 |
| 1 分钟声纹注册与 Read 匹配 | Device Alpha 代码已完成，需要儿童样本校准 | 声纹只存本机 Keychain，原始录音不保存或同步 |
| Apple Pencil 与掌触过滤 | 代码已完成，需要真机验收 | iPhone 用手指，iPad 分别测试手指与 Pencil |
| VoiceOver、Reduce Motion、动态字体 | 代码已完成，需要真机验收 | 完整走查反馈播报、焦点、横屏紧凑高度 |
| 年轻、有活力的女声与主题音乐 | v0.2 代码完成，需要人工听感批准 | 优先年轻美式女声；连续 SSML 短句 `tā-'dá, wòrds!`；Write 慢速尾音；Moonpetal 彩虹/独角兽与欢快音乐 |
| 八个原创 World | v0.2 代码完成，待真机视听回归 | 新增 Dino、Firehouse、Brickwork、Frostlight、Coaster；每个拥有隔离场景、吉祥物、颜色、奖励与音乐 |
| Write 笔盒与局部橡皮擦 | v0.2 代码完成，待真机书写回归 | 四种笔、12 色、笔触音效、2.5× 局部擦除；无 Undo；Clear 立即执行；`?` 立即显示词 |
| Treasure 图标与头像 | v0.2 代码完成，待真机回归 | 8×25 个相关图标；locked 保留灰色图标加锁；collected treasure 可选为头像且保留原照片 |

## 验收 Kid Profile 与 Guardian

1. 清空 LocalQA 数据后启动；第一屏必须是 `New Kid`，且不出现单词输入
2. 阅读并接受版本化隐私说明，创建昵称、动物头像、Grade 和起始 World
3. 强制退出并重启；Profile Picker 必须突出上次有效 Profile，孩子点击后才进入 Lobby
4. 新建第二个 Profile，为两者输入不同单词与设置，再验证 Picker 和隔离
5. 普通单击 **Parents**，确认随机算术 Parent Gate 立即出现
6. 进入 Parents 编辑 Profile，再从 Camera 自拍、Photo Library 和动物图标各测试一次头像来源与年龄设置
7. 删除上次使用的非唯一 Profile；重启后必须回到合法 Picker，不猜测身份或复活数据

通过标准：每个 Profile 隔离单词、设置、学习记录、日历、奖励和声纹。孩子可以只输入昵称建档，敏感操作需要系统设备认证。App 必须保留至少一个 Profile。Onboarding 不请求麦克风、Speech、Camera、Photo Library 或通知权限；相关权限只在对应功能首次使用时请求。

## 验收 Parent Word Manager

1. 切到 Read Tab，输入 `the` 并按 Return；确认立即保存、输入框清空且 `the` 出现在最顶部
2. 依次输入 `look`、`play`；确认始终 newest-first，同 Pool 再输 `the` 不复制历史而是前移
3. 切到 Write Tab 输入 `the`；确认 Read/Write 两组可以各有同名词
4. 从 Photo Library 选择一张多词 school list；编辑 OCR 结果、删除误识别项、Add All，并核对批次顺序与去重
5. 用 Camera 拍另一张 word sheet，重复预览与导入
6. 单独删除一个词；进入 Select 后批量删除至少两个词；分别验证确认和 Undo
7. 清空或缩小 Pool，重启并准备 Quest；确认不会出现 Grade、catalog 或 smart-fill 新词

通过标准：所有 Pool 新增项均能追溯到 typing 或 OCR；图片只在本机处理且不保存。键盘、OCR sheet 和选择工具栏在 iPhone/iPad 横屏不裁切。

## 验收 Read Quest

1. 点独立的 **Read Today's Quest**
2. 用全新 Profile/新词进入；确认目标出现时完全不播放发音
3. 首次点 Mic 时允许 Microphone 与 Speech Recognition；权限等待不算孩子速度
4. 读出目标词，确认正确反馈与结果记录
5. 第一次读错后确认 Hear/See 均隐藏；第二次有效读错后确认两个按钮出现
6. 点 Hear，确认只因孩子点按才播放；点 See，确认 `dog` 的图片直接显示在单词旁；未知词不猜图
7. 制造无声、噪声、技术失败，确认不耗有效尝试、不扣正确率、不提前解锁 Help；连续三次技术失败可中性 Move On
8. 测试 `a`、`I`、`go`、`look`、`bye`（包括 Apple 句末标点转写）和 0.8 秒自然停顿
9. 测试目标 `come` 的儿童近音 `kum/cum` 可通过，同时 `some`、`home`、`came`、`cat/cap` 不被误放宽
10. 建立声纹后，让目标儿童和另一位说话者分别测试
11. 连续切换多个词，确认大字颜色来自当前 World 且会适度变化；同一题错误、Help、重绘时颜色不闪变，并始终清晰可读

通过标准：技术失败不进入学习证据。声纹不匹配走技术重试，不把另一位说话者记成孩子答错。真实家庭噪声、自动停录、回声消除与识别准确率只能在真机验收。

## 验收 Write Quest

1. 点独立的 **Write Today's Quest**
2. 对 New 词确认先显示拼写并播放，然后隐藏答案
3. 在横线上独立手写整个单词，再点 **Done**
4. 确认 App 不会因停笔自动提交
5. 测试 **Hear**、单独的 **?**、**Clear** 与 **Done**；`?` 必须立即显示单词且没有三选一，Clear 不弹确认
6. 试听 `at`、`cat` 等短词，确认速度更慢且末尾 `t` 没有被背景音乐或音频 session 吞掉
7. 写错一个词，确认答案立即出现，并且只提供一次引导重写
8. 制造识别不确定，确认不计成孩子答错
9. 在 iPad 分别用手指与 Apple Pencil 书写，并把手掌放到屏幕上
10. 开启 Left-handed writing，确认主操作栏换边
11. 打开笔盒，逐一选择 Pencil、Crayon、Chalk、Brush 与 12 种基础色；换笔/换色后旧笔画保持原来的视觉
12. 逐笔书写并试听四种短促书写音；确认快速移动没有爆音，发音播放和 Reduced Sound 时不叠加
13. 确认页面没有 Undo；用 Eraser 对每种笔做局部擦除，擦除宽度约为当前笔宽 2.5 倍，再确认剩余笔画仍可提交识别

通过标准：Hear、`?`、识别等待和技术重试时间不污染独立作答速度。四种笔的视觉和声音可区分但不盖住发音。iPhone 只提示手指，iPad 可以区分 Pencil 与手指，并过滤明显掌触。

## 验收 Review、Mastered 与今日计划

1. 分别设置 New first 与 Review first
2. 在 New-first 路线故意答错新词，确认它替换最低优先 Review，并保留 Review debt
3. 确认 Review 会补入到期词，也会补入未到期但明显薄弱的词
4. 重复输入一个已学词，确认它在 Review 中前移
5. 跨三个不同日期独立答对同一词
6. 确认只有达到三日成功与 14 日预计回忆率门槛后才显示 Mastered

通过标准：同一天重复成功不能凑满三日条件。Help、重播、错误与相对个人慢会降低稳定度或提高难度。

## 验收奖励、世界与 Calendar

1. 分别完成 Read 与 Write Today Quest
2. 确认结果页显示分数、星星、正确率、个人速度和当前世界奖励
3. 完成 Practice Again，确认 Calendar 次数增加，但不重复发当天永久奖励
4. 第一天只完成 Read，确认当天和第二天均不解锁 Theme/Icon
5. 同一本地日完成 Read 与 Write Today Quest；当天仍锁定，跨到第二天或用可控时钟重启后各解锁一个未获得 Theme 与 Icon
6. 完成 Practice Again 与重复完成，确认不触发或重复解锁；测试月末到次月的跨日
7. 打开 My Collection，分别选择已获得 Theme 与 Icon，重启后保留；locked 项只可预览
8. 核对 8 个 World 各自的 20 个小奖励与 5 个里程碑；每件图标相关且同 World 不重复，locked 时仍显示灰色原图标并叠加锁
9. 选择一个已收集 Treasure 作为 Profile 头像，确认 Picker/Lobby 一致；点击未收集 Treasure 不生效
10. 若 Profile 原头像为照片，依次切换动物 Icon、Treasure 头像和原照片，确认照片数据始终保留可恢复
11. 在同一天完成多次 Quest，确认儿童 Calendar 与 Guardian Today 显示相同数量

通过标准：每个 World 只出现自己的奖励。世界解锁与收藏进度按 Profile 隔离并在重启后保留。

## 验收 Guardian 报告与纠正

1. 打开 Guardian 的 **Reports**
2. 在 7 days 与 30 days 之间切换
3. 检查完成数、正确率、个人速度趋势与单词详情
4. 把一条识别结果从错误改为正确，再改回错误
5. 确认学习进度从事件历史重建，报告与 Needs Attention 同步更新
6. 通过系统认证后导出 CSV，并检查字段和 Profile 范围

通过标准：纠正不直接覆盖汇总快照。App 使用原始 attempt 与 correction event 重建当前进度。

## 验收通知

1. 在 Practice settings 打开每日提醒、Pool low、完成、同步失败和周报
2. 修改每日提醒时间与安静时段起止
3. 允许系统通知权限
4. 确认安静时段内的提醒移动到允许时间
5. 关闭全部通知，确认该 Profile 的待发通知被清除

通过标准：通知文案不包含孩子的单词、分数或敏感学习详情。不同 Profile 的通知使用稳定且互不覆盖的标识符。

## 验收 CloudKit 家庭同步

这部分必须使用已配置 `iCloud.com.tadawords.app` 的 Apple Developer Team。准备两个登录不同 Apple ID 的设备。

Release 的 Family Sync 默认关闭并持久保存。Onboarding 的隐私确认不会开启 CloudKit；只有家长在 Guardian 中明确开启后，启动、生命周期、手动同步和邀请才可以接触 CloudKit。关闭开关会停止未来同步，但不会删除已经上传的 records。Profile 删除会传播 tombstone，但仍不会擦除既有 CloudKit records；完成远端擦除前只能用测试数据执行本节，不能把 Family Sync 作为可发布功能。

1. 首次启动与完成 onboarding 后，确认 **Family sync** 显示关闭，且没有 CloudKit 请求
2. 在设备 A 创建 Profile、单词、设置与学习记录
3. 通过家长认证明确开启 Family Sync，再点 **Sync now**
4. 创建家庭邀请，并通过系统 Share Sheet 发给设备 B
5. 在设备 B 明确开启并接受邀请，然后同步
6. 确认 Profile、Pool、设置、attempt、correction、进度、日计划、完成和奖励一致
7. 关闭 Family Sync，确认后续启动、前后台切换、手动按钮与邀请不再调用 CloudKit，本地 Quest 继续可用
8. 再开启后，两台设备离线修改不同记录，再联网同步
9. 删除一个 Profile，确认 tombstone 防止另一台设备把它恢复，并在远端擦除实现后确认 CloudKit 既有 records 被删除
10. 断网完成 Quest，确认本地学习不受同步失败影响

通过标准：Quest 提交不等待 CloudKit。同步失败显示状态并保留本地数据。声纹模板不进入 CloudKit；每台设备单独注册声纹。

## 验收声音与辅助功能

1. 在八个 World 中分别预览 Lobby、Read、Write、结果与 Collection；每个至少完成一轮，重点抽查五个新增 World 的两轮 Quest
2. 冷启动试听单个连续 SSML 短句 `tā-'dá, wòrds!`（近似“它达，沃尔子”）：按 `tah-DAH` 连读并重读第二音节，逗号停顿约 105ms，`words` 下落；确认没有三段排队造成的接缝。当前只验证了 SSML 构造，真机听感仍需人工批准
3. 确认优先选择年轻美式女声；目标 persona 不可用时仍有自然回退而不是静音
4. 在 Write 试听短词尾音；在 Read 两错后点按 Hear 试听标准发音
5. 在 Moonpetal 检查两侧彩虹/独角兽；在新增 World 分别检查恐龙、消防救援、原创积木、冰雪极光和过山车元素；确认中央任务安全区清晰且元素不跨主题泄漏
6. 确认语音提示时音乐降低，Read 录音时音乐和非必要音效停止
7. 分别测试 Voice、Music、Sound effects、Reduced Sound 和 Calm Rescue
8. 测试扬声器、耳机、来电打断、后台恢复和音量变化
9. 开启 VoiceOver，走完 Profile、Lobby、Read、Write、结果和 Guardian
10. 开启 Reduce Motion 与较大动态字体，检查横屏紧凑布局

通过标准：Reduced Sound 保留正确、重试和技术提示，但关闭装饰性 click、star、reward 与 launch 音。Calm Rescue 不播放紧急节奏层。人工批准响度、疲劳感、爆音和女声音色。

## 验收方向切换和本地数据

1. 在 iPhone 17 Pro Max 与 iPad 的 Profile、Lobby、Quest、结果和 Collection 测试 Landscape Left 和 Landscape Right
2. 在这些 child route 尝试旋转到 Portrait，确认仍保持横屏全屏
3. 进入 Parents 与首次家长设置：iPhone 验证 Portrait + 两个 Landscape 且拒绝 Upside Down；iPad 验证四向
4. 在家长页面竖持设备后退出，确认 Profile/Lobby 立即恢复横屏，不保留竖屏
5. 完成建档、加词、设置和 Quest 后强制退出
6. 重新打开，确认所有数据与上次 Profile 恢复

当前模拟器证据：iPad 的首次 Parents 页面使用 tall/portrait window，child Read 使用 landscape window；对应截图见 `QAArtifacts/v0.2-2026-07-12/iPadPro13-launch.jpg` 与 `QAArtifacts/v0.2-2026-07-12/iPadPro13-paws-read.jpg`。iPhone Lobby/Read 的最终 JPG 已旋转为可读横屏，只用于 UI 检查；raw framebuffer 的方向仍有歧义，不作为竖屏通过证据。iPhone 与 iPad 的真机旋转仍按上述步骤验收。

`Contents.json` 只描述 Xcode 资产。运行数据位于 App 沙盒的 Application Support 目录。App 没有自建服务器数据库。`TadaWordsLocalQA` 安装为独立的 **Tada Words QA**，没有 iCloud 能力且数据不跨设备；正常 Release 也只有在家长明确开启后才会同步。

## 完成真机发布验收

最终发布前必须在一台 iPhone 17 Pro Max 与一台 iPad 上通过以下项目：

- 签名安装、冷启动、后台恢复和两个横屏方向
- 真实儿童语音、家庭噪声、自动停录、声纹同人与异人样本
- 手指、Apple Pencil、掌触和四岁儿童字形
- Camera 与 Photo Library 权限
- Camera / Photo Library 的头像与 word-sheet OCR 两种用途
- VoiceOver、Reduce Motion 与动态字体
- 每个 World 的女声、音乐、ducking、响度和疲劳感
- `FOLLOWUP_BUGFIXES_AND_IMPROVEMENTS.md` 中 v0.2 全部 device evidence
- 两个 Apple ID 的 CloudKit 邀请、冲突、离线恢复和删除传播
- Family Sync 默认关闭、家长 opt-in 持久化、关闭后停止未来同步
- CloudKit 远端 records 擦除
- 本地通知授权、安静时段与实际投递

只有这些设备项目通过后，才能把 Device Alpha 和家庭同步标记为已验收。
