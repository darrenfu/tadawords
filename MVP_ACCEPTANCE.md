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

通过标准：格式检查、单元与组合测试、iPhone 17 Pro Max Release 模拟器构建、iPad Pro 13-inch Release 模拟器构建全部通过。设备准备脚本可以在未配置签名 Team 时报告签名阻塞。

2026-07-12 最终整合证据：

| 检查 | 结果 |
|---|---|
| Swift formatter 严格检查 | 通过 |
| Swift 单元与组合测试 | 367 项通过，0 失败 |
| iPhone 17 Pro Max Release 模拟器构建 | 通过 |
| iPad Pro 13-inch Release 模拟器构建 | 通过 |
| 两个 built product 的横屏声明 | 只包含 Landscape Left 与 Landscape Right；`UIRequiresFullScreen` 为 true |
| CloudKit 分享声明 | 两个 built product 的 `CKSharingSupported` 为 true |
| 儿童语音 fixture | SHA-256 通过，Apple 转写为 `Bye.`，App policy 对目标 `bye` 判定为匹配 |

`CKSharingSupported` 是构建声明，不代表模拟器正在运行 CloudKit。模拟器刻意使用 local/device-only transport；真实 CloudKit transport 只能在配置 Team、container 与 iCloud 的签名真机上验收。

编号的 `.xcodeproj` 副本已经删除。只打开 `TadaWords.xcodeproj`，也不要使用方向或能力变更之前的 Derived Data。

## 核对关键需求

| 需求 | 当前状态 | 人工验收重点 |
|---|---|---|
| Read 与 Write 两条独立路线 | 代码已完成 | 两个 Today Quest 按钮不合并，数据与设置互不覆盖 |
| 家长手动输入与自动去重 | 代码已完成 | 同一组忽略大小写去重，两组可以包含同一个词 |
| 家长优先、智能补足、Grade 自动推荐 | 代码已完成 | 今日新词优先，Pool 不足时按已选难度或 Grade 补足 |
| New 与 Review 顺序可交换 | 代码已完成 | 每条路线独立保存顺序 |
| 艾宾浩斯复习与补弱 | 代码已完成 | 到期、错误、相对慢、重播和 Help 影响排序与记忆参数 |
| Write 新词示范与一次引导重写 | 代码已完成 | 先短暂显示答案，错误后显示答案，只提供一次引导重写 |
| Read 首次加两次有效重试 | 代码已完成 | 技术失败不耗次数、不扣正确率 |
| 真正 Mastered 判定 | 代码已完成 | 三个不同本地日期独立成功，且未来 14 天预计回忆率达标 |
| 分数、三颗星、正确率和个人速度 | 代码已完成 | 技术性 Move On 显示 Not scored |
| 三个独立主题世界 | 代码已完成 | 公主、工程车和动物奖励不混用 |
| 每个世界 20 个小奖励与 5 个里程碑 | 代码已完成 | 3 与 8 个 Today Quest 解锁世界，Collection 状态持久化 |
| 多 Kid Profile 与上次 Profile 恢复 | 代码已完成 | 每个 Profile 的数据、声纹和设置隔离 |
| 首次家长 Onboarding | 代码已完成，需要真机布局复验 | 版本化 consent、昵称、动物头像、Grade、起始 World 和两组可选首批单词 |
| 自拍、照片、动物头像 | 代码已完成 | 真机检查 Camera 与 Photo Library 权限 |
| 月度打卡 Calendar | 代码已完成 | 每日显示准确 Quest 次数，Practice Again 也计数 |
| 7 日与 30 日报告 | 代码已完成 | 检查趋势、单词详情、识别纠正和 CSV 导出 |
| Crash-resumable Profile 删除 | 代码已完成 | 删除本地资料、单词、历史、奖励、提醒和本机声纹 |
| 本地通知与安静时段 | 代码已完成 | 每日、Pool low、完成、同步失败、周报与时间设置 |
| CloudKit 同步与家庭邀请 | 代码已完成，需要 Apple 环境验收 | 需要 Developer Team、iCloud container 与两个 Apple 账号 |
| 1 分钟声纹注册与 Read 匹配 | Device Alpha 代码已完成，需要儿童样本校准 | 声纹只存本机 Keychain，原始录音不保存或同步 |
| Apple Pencil 与掌触过滤 | 代码已完成，需要真机验收 | iPhone 用手指，iPad 分别测试手指与 Pencil |
| VoiceOver、Reduce Motion、动态字体 | 代码已完成，需要真机验收 | 完整走查反馈播报、焦点、横屏紧凑高度 |
| 年轻、有活力的女声与主题音乐 | 代码已完成，需要人工听感批准 | 系统已安装的英文 voice 会影响最终音色 |

## 验收 Kid Profile 与 Guardian

1. 用 Production 启动 App
2. 阅读并接受版本化的家长 consent，确认完成时间会写入本地 Onboarding 状态
3. 创建孩子昵称、动物头像、Grade 和起始 World
4. 可选输入 Read 与 Write 的首批单词，确认两组分别去重；也可以留空以后再填
5. 进入 Grown-ups 编辑 Profile，再从 Camera 自拍、Photo Library 和动物图标各测试一次头像来源与年龄设置
6. 新建第二个 Profile，并为两个 Profile 输入不同单词与设置
7. 从儿童区使用 **New Player**，只输入昵称创建 Profile
8. 强制退出并重新启动，确认恢复最后使用的有效 Profile，且首次 Onboarding 不再出现
9. 长按家长入口 1 秒，完成乘法 Parent Gate
10. 删除一个非唯一 Profile，并确认 App 重启后没有残留或复活

通过标准：每个 Profile 隔离单词、设置、学习记录、日历、奖励和声纹。孩子可以只输入昵称建档，敏感操作需要系统设备认证。App 必须保留至少一个 Profile。Onboarding 不请求麦克风、Speech、Camera、Photo Library 或通知权限；相关权限只在对应功能首次使用时请求。

## 验收单词 Pool 与自动推荐

1. 在 Read Pool 输入 `the, look, play, the`
2. 确认导入报告单独列出重复的 `the`
3. 在 Write Pool 输入 `the, see, go`
4. 确认 `the` 可以同时存在于两个 Pool
5. 分别测试 **Parent words only**、**Parent + smart fill** 和 **Grade automatic**
6. 删除或停用一个词，再次输入它，确认重新排入练习且不复制历史
7. 输入包含自定义大小写的词，确认显示形式保留但去重仍规范化

通过标准：家长当天输入的词优先。Pool 数量不足时才自动补足。推荐词不会与手动词或当天计划重复。

## 验收 Read Quest

1. 点独立的 **Read Today's Quest**
2. 首次使用时允许 Microphone 与 Speech Recognition
3. 读出目标词，确认正确反馈与结果记录
4. 故意读错并重试，确认最多三次有效尝试
5. 制造一次无声或技术失败，确认它不耗有效尝试、不扣正确率
6. 连续三次技术失败，确认可以中性 **Move On**
7. 测试带 Apple 句末标点的识别结果，例如目标 `bye` 与转写 `Bye.`
8. 建立声纹后，让目标儿童和另一位说话者分别测试

通过标准：技术失败不进入学习证据。声纹不匹配走技术重试，不把另一位说话者记成孩子答错。真实家庭噪声、自动停录、回声消除与识别准确率只能在真机验收。

## 验收 Write Quest

1. 点独立的 **Write Today's Quest**
2. 对 New 词确认先显示拼写并播放，然后隐藏答案
3. 在横线上独立手写整个单词，再点 **Done**
4. 确认 App 不会因停笔自动提交
5. 测试 **Hear**、**Help**、**Undo**、**Clear** 与 **Done**
6. 写错一个词，确认答案立即出现，并且只提供一次引导重写
7. 制造识别不确定，确认不计成孩子答错
8. 在 iPad 分别用手指与 Apple Pencil 书写，并把手掌放到屏幕上
9. 开启 Left-handed writing，确认主操作栏换边

通过标准：Hear、Help、识别等待和技术重试时间不污染独立作答速度。iPhone 只提示手指，iPad 可以区分 Pencil 与手指，并过滤明显掌触。

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
4. 累计完成 3 与 8 个 Today Quest，确认解锁第二与第三个 World
5. 打开 Collection，核对每个 World 的 20 个小奖励与 5 个里程碑
6. 在同一天完成多次 Quest，确认儿童 Calendar 与 Guardian Today 显示相同数量

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

1. 在设备 A 创建 Profile、单词、设置与学习记录
2. 在 **Family sync** 点 **Sync now**
3. 创建家庭邀请，并通过系统 Share Sheet 发给设备 B
4. 在设备 B 接受邀请并同步
5. 确认 Profile、Pool、设置、attempt、correction、进度、日计划、完成和奖励一致
6. 两台设备离线修改不同记录，再联网同步
7. 删除一个 Profile，确认 tombstone 防止另一台设备把它恢复
8. 断网完成 Quest，确认本地学习不受同步失败影响

通过标准：Quest 提交不等待 CloudKit。同步失败显示状态并保留本地数据。声纹模板不进入 CloudKit；每台设备单独注册声纹。

## 验收声音与辅助功能

1. 每个 World 完成两轮 Read 与 Write Quest
2. 检查启动口播、女声发音、主题音乐、正确、重试、星星和奖励提示
3. 确认读词时音乐降低，录音时音乐和非必要音效停止
4. 分别测试 Voice、Music、Sound effects、Reduced Sound 和 Calm Rescue
5. 测试扬声器、耳机、来电打断、后台恢复和音量变化
6. 开启 VoiceOver，走完 Profile、Lobby、Read、Write、结果和 Guardian
7. 开启 Reduce Motion 与较大动态字体，检查横屏紧凑布局

通过标准：Reduced Sound 保留正确、重试和技术提示，但关闭装饰性 click、star、reward 与 launch 音。Calm Rescue 不播放紧急节奏层。人工批准响度、疲劳感、爆音和女声音色。

## 验收横屏和本地数据

1. 在 iPhone 17 Pro Max 与 iPad 上测试 Landscape Left 和 Landscape Right
2. 尝试旋转到 Portrait，确认所有页面仍保持横屏全屏
3. 完成建档、加词、设置和 Quest 后强制退出
4. 重新打开，确认所有数据与上次 Profile 恢复

`Contents.json` 只描述 Xcode 资产。运行数据位于 App 沙盒的 Application Support 目录。App 没有自建服务器数据库；CloudKit 只在启用 Family Sync 后复制支持的记录。

## 完成真机发布验收

最终发布前必须在一台 iPhone 17 Pro Max 与一台 iPad 上通过以下项目：

- 签名安装、冷启动、后台恢复和两个横屏方向
- 真实儿童语音、家庭噪声、自动停录、声纹同人与异人样本
- 手指、Apple Pencil、掌触和四岁儿童字形
- Camera 与 Photo Library 权限
- VoiceOver、Reduce Motion 与动态字体
- 每个 World 的女声、音乐、ducking、响度和疲劳感
- 两个 Apple ID 的 CloudKit 邀请、冲突、离线恢复和删除传播
- 本地通知授权、安静时段与实际投递

只有这些设备项目通过后，才能把 Device Alpha 和家庭同步标记为已验收。
