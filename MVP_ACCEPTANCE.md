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

PR #2 已在 merge commit `cc42e17` 把 v0.3 合入 `main`。2026-07-14 的当前 v0.3.1 修复证据如下。V1 的 367 项、v0.2 的 480 项和 v0.3 的 548 项测试保留为历史基线；v0.3.1 全量为 595/595：

| 检查 | 结果 |
|---|---|
| Swift formatter 严格检查 | 通过 |
| Swift 单元与组合测试 | v0.3.1 全量 595/595 通过，0 failure；其中 actual-Vision 手写识别 focused suite 为 15/15，World 布局 focused suite 为 5/5 |
| Critical XCUITest | iPhone 17 Pro Max 模拟器 7/7 通过：Read/Write 连续反馈、两次删除/Undo、Delete All/完整恢复、Preset 明确批准后才加入、Photos 退出后排序、OCR Review → Add All → Pool → Sort |
| iPhone 17 Pro Max production Vision 真机测试 | iOS 26.5.1 上 2/2 XCTest 通过：`of/go` 六种大小写正例 6/6，错词与 literal `90` 负例 4/4；使用匿名合成 vector 和真实 production service，不使用 mock/demo |
| iPad Air 13-inch (M4) production Vision 真机测试 | iPadOS 26.5 上 2/2 DeviceTests 通过：wrong-word rejection 与 `of/go` case variants；使用真实 production service 与匿名合成 vector |
| iPad Air 13-inch (M4) Critical XCUITest | LocalQA 配置下 7/7 通过：OCR Add All、Delete All/完整恢复、Preset 明确批准、连续删除/排序、Photo picker/排序、Read 与 Write 完成反馈消失 |
| iPhone 17 Pro Max LocalQA 模拟器构建 | v0.3.1 fresh build 通过 |
| iPad Pro 13-inch (M5) LocalQA 模拟器构建 | v0.3.1 fresh build 通过 |
| iPhone 17 Pro Max 真机安装 | `Tada Words QA` v0.3.1 (`2026071402`) 签名构建已覆盖安装并启动；儿童真实书写、发音听感和辅助功能仍需人工验收 |
| iPad Air 13-inch (M4) 真机安装 | Darren iPad、iPadOS 26.5；Team `6S245NCUPQ` 签名的 `Tada Words QA` v0.3.1 (`2026071403`) 已安装并启动；儿童真实书写、发音听感、布局、旋转和辅助功能仍需人工验收 |
| 两个 built product 的方向声明 | v0.2 基线：iPhone 为 Portrait + 两个 Landscape；iPad 为四向；`UIRequiresFullScreen` 为 true；运行时 Parents 可旋转，child route 只允许横屏 |
| 模拟器方向证据 | v0.2 基线：iPad 的 Parent 与 child 窗口形态符合路由策略；iPhone raw framebuffer 截图方向不可靠，仍需真机旋转确认 |
| Release CloudKit 分享声明 | v0.2 基线：iPhone 与 iPad Release built product 的 `CKSharingSupported` 为 true |
| LocalQA 隔离声明 | v0.2 基线：`Tada Words QA` 使用独立 bundle ID、空 iCloud entitlement，且 `CKSharingSupported` 为 false |
| 儿童语音 fixture | v0.2 基线：SHA-256 通过，Apple 转写为 `Bye.`，App policy 对目标 `bye` 判定为匹配 |

`CKSharingSupported` 是构建声明，不代表模拟器正在运行 CloudKit。模拟器刻意使用 local/device-only transport；真实 CloudKit transport 只能在配置 Team、container 与 iCloud 的签名真机上验收。

iPad 的 DeviceTests 与 Critical XCUITest 证明 production 识别链路和七条关键交互能在真机运行。它们不替代儿童真实手写、标准发音听感、各方向布局、Apple Pencil、VoiceOver 或 Dynamic Type 的人工验收。

编号的 `.xcodeproj` 副本已经删除。只打开 `TadaWords.xcodeproj`，也不要使用方向或能力变更之前的 Derived Data。

## 核对关键需求

| 需求 | 当前状态 | 人工验收重点 |
|---|---|---|
| Read 与 Write 两条独立路线 | 代码已完成 | 两个 Today Quest 按钮不合并，数据与设置互不覆盖 |
| Parent Word Manager | v0.2 基础已合并；v0.3/v0.3.1 增强完成，待真机回归 | 单词 Return 即时加入；多照片 Camera/Photo OCR；逐词编号；单图 500 词上限；added/A-Z/most practiced 排序；频次；type-ahead 搜索；Hear/Delete；单删/批删/整组清空；删除确认与 Undo 按 Profile 隔离；两组独立去重 |
| 仅使用家长批准词 | v0.3.1 代码完成 | 无 smart fill / Grade 自动加入；typing、OCR 或 Preset 都必须由家长明确提交，Pool 不足时不补词 |
| 按年龄/年级的 Preset Words | v0.3.1 代码与内容审计完成，待真机布局回归 | 3–8 岁 / Pre-K–Grade 3；34 组、每组 40–45 词；最多 6 组推荐后按层级浏览；搜索、逐词/全选、Read/Write/Both；打开或推荐绝不自动加入 |
| New 与 Review 顺序可交换 | 代码已完成 | 每条路线独立保存顺序 |
| 艾宾浩斯复习与补弱 | 代码已完成 | 到期、错误、相对慢、重播和 Help 影响排序与记忆参数 |
| Write 不预显答案与一次引导重写 | v0.3 代码完成，待真机回归 | 每个词开始时只播发音，不显示拼写；只有点 `?` 才显示答案；第一次真实错答可出现具体词图片按钮 |
| Read 安静首答与两错后 Help | v0.3 代码完成，待真机回归 | 首答前不播答案；两次有效错答后只出现 Hear it；没有图片提示；技术失败不解锁也不耗次数 |
| 真正 Mastered 判定 | 代码已完成 | 三个不同本地日期独立成功，且未来 14 天预计回忆率达标 |
| 分数、宽松三颗星、严格 Guardian 证据 | v0.3 代码完成 | Accuracy 门槛 75%；一次无辅助立即恢复；校准 Pace；慢侧 50% 宽限；完美首答固定 100 分/3 星；技术性 Move On 显示 Not scored |
| 八个独立主题世界 | v0.2 代码完成，待真机视听回归 | 公主、工程车、动物、恐龙、消防救援、原创积木、冰雪与过山车的场景/奖励不混用 |
| 每个世界 20 个小奖励与 5 个里程碑 | v0.2 代码完成，待真机视觉回归 | 共 200 件不同图标；永久收藏品不因 Practice Again 重发 |
| Double Quest 次日 Theme / Icon | v0.2 代码完成，待真机回归 | 同日 Read+Write 的 Today run 次日解锁；partial/replay 不算；My Collection 可选择已获得项目 |
| 多 Kid Profile、年龄与上次 Profile | v0.3.1 代码完成，待真机回归 | 冷启动先到 Picker 并突出上次 Profile；首次/Kid/Parent 新建均采集 3–8 岁年龄；每个 Profile 数据、声纹、设置与 cosmetics 隔离 |
| Profile-first 首次流程 | v0.3.1 代码完成，待真机布局复验 | 无 Profile 直接 New Kid；先录昵称和年龄，首次流程无单词输入 |
| Pre-K 儿童端视觉层级 | v0.2 模拟器已检查，待儿童与辅助功能验收 | 上次 Profile 静态突出；iPhone Lobby 图标 dock 保留 72 pt 触控区；Read 主词与 Result 奖励更醒目；iPad 保留文字工具入口 |
| 自拍、照片、动物头像 | 代码已完成 | 真机检查 Camera 与 Photo Library 权限 |
| 月度打卡 Calendar | 代码已完成 | 每日显示准确 Quest 次数，Practice Again 也计数 |
| 7 日与 30 日报告 | 代码已完成 | 检查趋势、单词详情、识别纠正和 CSV 导出 |
| Crash-resumable Profile 删除 | 代码已完成 | 删除本地资料、单词、历史、奖励、提醒和本机声纹 |
| 本地通知与安静时段 | 代码已完成 | 每日、Pool low、完成、同步失败、周报与时间设置 |
| CloudKit 同步与家庭邀请 | 持久、默认关闭的家长 opt-in 已完成；远端删除未完成 | 用 Developer Team、iCloud container 与两个 Apple 账号验收 opt-in、关闭和邀请；远端擦除完成前不可发布 |
| 1 分钟声纹注册与 Read 匹配 | v0.3 跟读流程完成，需要儿童样本校准 | 随机短句逐句播放、儿童跟读、拒绝样本可重录；声纹只存本机 Keychain，原始录音不保存或同步 |
| Apple Pencil 与掌触过滤 | 代码已完成，需要真机验收 | iPhone 用手指，iPad 分别测试手指与 Pencil |
| VoiceOver、Reduce Motion、动态字体 | 代码已完成，需要真机验收 | 完整走查反馈播报、焦点、横屏紧凑高度 |
| 单一教师契约与主题音乐 | Katie/Aurora 离线包已实现并通过 bundle/转写检查；需要真机人工听感批准 | 不提供 Profile voice style；500 词以 Katie Read 0.90× / Write 0.82× 双版本为 canonical，`bun` 使用 manifest 记录的 Aurora 质量例外，包外词使用 Apple fallback；Aurora 负责连续启动短句 `Ta-dá↗ woooords↘!`、六条答对微庆祝和 Quest 完成；客户端不存 provider key；Moonpetal 彩虹/独角兽与欢快音乐 |
| 八个原创 World | v0.2 代码完成，待真机视听回归 | 新增 Dino、Firehouse、Brickwork、Frostlight、Coaster；每个拥有隔离场景、吉祥物、颜色、奖励与音乐 |
| Write 笔盒与稳定画布 | v0.2 笔盒基础已合并；v0.3 增强完成，待真机书写回归 | Pencil/Chalk/Brush 三种黑色笔、每 Profile 持久化、流畅笔触音效、4× 局部擦除、空白点击恢复原笔、画布加宽 10%；root Quest transition identity 保持稳定，切词/反馈时坐标不移动 |
| 具体词图片提示 | v0.3 代码完成，待真机网络/离线回归 | 入 Pool 后异步缓存固定 Twemoji 资源；Write 首次真实错答显示可点击图片；`the` 等抽象/功能词不请求图片 |
| Parent Gate 与 Lock | v0.3 代码完成，待真机回归 | 输入完整位数后自动判题；错误时立即重置但反馈保持到下一次输入；Parents 的 Lock 直接返回 Kids 页面 |
| Treasure 图标与头像 | v0.2 代码完成，待真机回归 | 8×25 个相关图标；locked 保留灰色图标加锁；collected treasure 可选为头像且保留原照片 |

## 理解分数与单词发音

儿童结果页使用以下规则。Guardian 报告仍显示严格的第一次独立作答，不把补答改写成首答正确。

| 项目 | 规则 |
|---|---|
| Completion Star | 完成计划中的全部单词 |
| Accuracy Star | 第一次独立作答正确率达到 75%，或整轮只错一个词且紧接着在无提示情况下答对 |
| Personal Pace Star | 已获得 Accuracy，且速度落在个人区间、仍处于有效校准期，或整轮完美首答 |
| Points | 正确率最多 80 分，速度最多 20 分 |
| Perfect first try | 无论是否已有速度基线，固定 100 分和 3 星 |

家长可以手输、照片批量导入，或从本地 Preset Catalog 明确选择单词。所有新词统一使用 canonical isolated teacher pronunciation；Parent UI 不提供语境句或多发音编辑入口。年龄/年级只排序推荐，不会自动加入。旧版本中已经保存的 contextual audio metadata 仍可被读取，避免升级时损坏数据。

## 验收 Kid Profile 与 Guardian

1. 清空 LocalQA 数据后启动；第一屏必须是 `New Kid`，且不出现单词输入
2. 阅读并接受版本化隐私说明，创建昵称、3–8 岁年龄、动物头像、Grade 和起始 World
3. 强制退出并重启；Profile Picker 必须突出上次有效 Profile，孩子点击后才进入 Lobby
4. 新建第二个 Profile，为两者输入不同单词与设置，再验证 Picker 和隔离
5. 普通单击 **Parents**，确认随机算术 Parent Gate 立即出现；输入完整位数后无需点 Unlock 即自动判题。错误答案自动清空，但错误提示保持可见，直到家长开始输入下一次答案
6. 让孩子在 Picker 自建第二个 Profile，输入昵称与年龄；确认建议 Grade 合理。再进入 Parents 编辑 Profile，验证家长改变年龄不会静默覆盖明确选择的 Grade，并从 Camera 自拍、Photo Library 和动物图标各测试一次头像来源
7. 从 Parent dashboard 点 **Lock**，确认立即锁定并返回 Kids Profile Picker
8. 删除上次使用的非唯一 Profile；重启后必须回到合法 Picker，不猜测身份或复活数据

通过标准：每个 Profile 隔离单词、设置、学习记录、日历、奖励和声纹。所有新 Profile 都保存有效年龄；旧版缺年龄 Profile 仍可读取。敏感操作需要系统设备认证。App 必须保留至少一个 Profile。Onboarding 不请求麦克风、Speech、Camera、Photo Library 或通知权限；相关权限只在对应功能首次使用时请求。

## 验收 Parent Word Manager

1. 切到 Read Tab，输入 `the` 并按 Return；确认立即保存、输入框清空且 `the` 出现在最顶部
2. 依次输入 `look`、`play`；确认始终 newest-first，同 Pool 再输 `the` 不复制历史而是前移
3. 切到 Write Tab 输入 `the`；确认 Read/Write 两组可以各有同名词
4. 从 Photo Library 一次选择至少两张 school list；再用 **Add photos** 和 **Take another** 追加图片，确认识别结果合并到同一预览
5. 核对每个 OCR 词从 1 开始编号；编辑或删除误识别项，并分别切换 Added order、A-Z、Most practiced
6. 准备一张超过 500 个识别词的单图，确认该图片被明确拒绝并提示更换图片；其他未超限图片的结果不丢失
7. 滚动长预览，验证顶部返回/到顶按钮与到底按钮；点 **Add all N to Read/Write**，确认按钮不会被键盘遮住、只提交一次，并显示保存进度或明确错误
8. 在 Pool 切换 Added order、A-Z、Most practiced，核对每行频次数字；用 type-ahead 搜索并直接点该行的 Hear 与 Delete
9. 第一次删除时确认弹窗出现；确认后继续单删和批删，确认本 Parent session 不再重复弹窗且 Undo 仍可用
10. 分别在 Read 和 Write 点 `Delete all N words`：取消一次，再确认一次；核对明确数量/模式、另一 Pool 不变、学习历史不删，并用 Undo 完整恢复
11. 在 Profile A 删除或清空后切换到 Profile B；确认 B 不继承 A 的首次删除确认状态或 Undo，且 B 的操作不能还原或修改 A 的 Pool
12. 从 Today 打开 Preset Words；核对最多 6 个年龄/年级匹配推荐，再逐层浏览 Sight Words、Phonics、动物/恐龙/车辆/城市/国家、动作和 Emotions。打开列表时 Pool 不变；逐词选择或 Select all，分别提交到 Read、Write、Both 并核对去重
13. 对 Both 导入核对事务边界：正常时两个 Pool 都更新；任一 Pool 保存失败、部分成功或返回数量不符时，只回滚本次插入或重新启用的 membership，既有 active word 与另一 Profile 不变
14. 在 typing、search 和 OCR 文字编辑框中输入文字，再点空白处；确认键盘收起；整个流程不出现 pronunciation/context section
15. 清空或缩小 Pool，重启并准备 Quest；确认不会出现未经家长点击 Add 的 catalog 或 smart-fill 新词

通过标准：所有 Pool 新增项均能追溯到 typing、OCR 或家长明确批准的 Preset selection；原始 school-list 图片只在本机识别且不保存。每张图片独立执行 500 词上限。Preset 与删除操作绑定发起它的 Profile，Both 导入不会留下半完成状态。键盘、OCR sheet、sticky Add All、Preset 层级和选择工具栏在 iPhone/iPad 横竖屏 Parent route 均不裁切。

## 验收 Read Quest

1. 点独立的 **Read Today's Quest**
2. 用全新 Profile/新词进入；确认目标出现时完全不播放发音
3. 首次点 Mic 时允许 Microphone 与 Speech Recognition；权限等待不算孩子速度
4. 读出目标词，确认正确反馈与结果记录
5. 第一次读错后确认 **Hear it** 隐藏；第二次有效读错后确认只出现 **Hear it**，没有图片按钮
6. 点 **Hear it**，确认只因孩子点按才播放；发音必须清晰、连贯且不吃尾音，切换到下一个词后帮助重新隐藏
7. 制造无声、噪声、技术失败，确认不耗有效尝试、不扣正确率、不提前解锁 Help；连续三次技术失败可中性 Move On
8. 测试 `a`、`I`、`go`、`look`、`bye`（包括 Apple 句末标点转写）和 0.8 秒自然停顿
9. 测试目标 `come` 的儿童近音 `kum/cum` 可通过，同时 `some`、`home`、`came`、`cat/cap` 不被误放宽
10. 建立声纹后，让目标儿童和另一位说话者分别测试
11. 连续切换多个词，确认大字始终使用当前 World 对应的同一种深色；只有切换 World 才改变颜色，并始终清晰可读
12. 完成一轮，其中故意答错或使用帮助；在 Result 点 Replay，确认只重练本轮 tricky words。完美一轮不显示空 Replay 按钮

通过标准：技术失败不进入学习证据。声纹不匹配走技术重试，不把另一位说话者记成孩子答错。真实家庭噪声、自动停录、回声消除与识别准确率只能在真机验收。

## 验收 Write Quest

1. 点独立的 **Write Today's Quest**
2. 对 New 与 Review 词都确认只播放发音，不预先显示任何拼写；只有点 `?` 后才显示目标词
3. 试听 Katie Write 版 `of`、`at`、`cat`、`come`、`look`，确认使用 0.82× 离线录音且仍是一段连续、清晰的发音；`f`、`t`、`k` 等尾音没有被背景音乐、外部音频或 audio session 吞掉，播放结束后音乐平滑恢复。再输入一个 500 词 manifest 外的词，确认 Apple fallback 可用
4. 在加宽后的横线区独立手写整个单词，再点 **Done**；确认 App 不会因停笔自动提交
5. 分别写 `i` 的点、三字母词的最后一个字母，以及连笔 `vv`/`w`；确认短点、后续笔画和连笔都留下
6. 分别用首字母大写、全大写和全小写书写同一个词；确认大小写差异不导致失败
7. 测试 **Hear**、单独的 **?**、**Clear** 与 **Done**；`?` 必须立即显示单词且没有三选一，Clear 不弹确认
8. 第一次真实写错 `dog`，确认出现可点击图片按钮且不会自动显示拼写；点图片后显示狗。对 `the` 写错时不显示图片，也不发起图片请求
9. 制造识别不确定和技术失败，确认不计成孩子答错，也不会错误触发图片
10. 在 iPad 分别用手指与 Apple Pencil 书写，并把手掌放到屏幕上
11. 开启 Left-handed writing，确认主操作栏换边
12. 打开笔盒，确认只有 Pencil、Chalk、Brush 与 Eraser；没有 Crayon 或颜色选择，所有新笔画均为黑色
13. 切换到一个 Profile 选择笔型，重启并切换 Profile；确认每个 Profile 保留自己的选择，直到再次修改；旧版 Crayon/彩色设置安全迁移为黑色 Pencil
14. 逐笔书写并试听三种短促书写音；确认快速连续移动没有爆音、卡顿或频繁重启音，发音播放和 Reduced Sound 时不叠加
15. 确认页面没有 Undo；用 Eraser 对每种笔做局部擦除，擦除宽度约为当前笔宽 4 倍。擦完后点旁边空白，确认自动恢复之前的笔
16. 不使用 Help，分别写 `of`、`Of`、`OF`、`go`、`Go`、`GO`，每种写法重复两次并要求 12/12 通过；再确认 `if`、`on`、`or`、`ot`、`off`、`do`、`no` 与数字 `90` 不能误过
17. 在错误反馈出现及切换下一个词时录屏，逐帧确认书写区域的尺寸、中心和坐标不移动；确认整轮 Quest 的 root transition identity 不随 prompt 改变；完成反馈至少停留 830 ms，不再闪过
18. 完成一轮并故意留下 tricky word；在 Result 点 Replay，确认只重练该词

通过标准：Hear、`?`、识别等待和技术重试时间不污染独立作答速度。三种笔的视觉和声音可区分但不盖住发音。图片只服务具体词并使用私有缓存。iPhone 只提示手指，iPad 可以区分 Pencil 与手指，并过滤明显掌触。合成笔画的 production Vision 真机测试只证明修复链路与已知字形，不能替代上述孩子 12 次真实书写。

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
2. 完成一次所有词均首答正确的 Quest；确认结果为 100 分和 3 星，即使 Profile 尚无速度基线
3. 制造 75% 第一次独立正确率，确认仍有 Accuracy Star；再制造整轮仅一次错答并立即无提示答对，确认儿童奖励可获宽限，而 Guardian 仍显示原始首答正确率
4. 在已有个人速度区间后，验证慢侧最多 50% 宽限；过快或超过宽限不获得 Pace Star
5. 确认结果页显示分数、星星、正确率、个人速度和当前世界奖励
6. 完成 Practice Again，确认 Calendar 次数增加，但不重复发当天永久奖励
7. 第一天只完成 Read，确认当天和第二天均不解锁 Theme/Icon
8. 同一本地日完成 Read 与 Write Today Quest；当天仍锁定，跨到第二天或用可控时钟重启后各解锁一个未获得 Theme 与 Icon
9. 完成 Practice Again 与重复完成，确认不触发或重复解锁；测试月末到次月的跨日
10. 打开 My Collection，分别选择已获得 Theme 与 Icon，重启后保留；locked 项只可预览
11. 核对 8 个 World 各自的 20 个小奖励与 5 个里程碑；每件图标相关且同 World 不重复，locked 时仍显示灰色原图标并叠加锁
12. 选择一个已收集 Treasure 作为 Profile 头像，确认 Picker/Lobby 一致；点击未收集 Treasure 不生效
13. 若 Profile 原头像为照片，依次切换动物 Icon、Treasure 头像和原照片，确认照片数据始终保留可恢复
14. 在同一天完成多次 Quest，确认儿童 Calendar 与 Guardian Today 显示相同数量

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

## 验收 Voice setup

1. 在一个 Kid Profile 中打开 **Voice setup**，确认出现一条短英文句子并自动播放，孩子可以再次点 Hear
2. 让孩子跟读并录制；确认成功样本增加进度，再用静音、太短和明显噪声制造拒绝，确认显示可重试原因且已接受进度不丢失
3. 完成至少六个有效片段与最低有效语音时长；确认 **Finish setup** 只在条件满足后可用，并能保存后退出
4. 中断录音、锁屏或切到后台后返回；确认不会出现永久灰色 Finish、零采样率或通用错误循环
5. 新开一次 setup，确认句子顺序会洗牌；在第二个 Profile 独立完成，确认两个声纹互不覆盖
6. 检查 App 沙盒与同步数据，确认不保存原始录音或句子，只在本机 Keychain 保存声纹模板

通过标准：必须用真实儿童声音在真机完成。本机音频 session 应先配置再读取输入格式，并在录音时启用可用的语音处理与降噪；拒绝样本不计入模板。

## 验收声音与辅助功能

1. 在八个 World 中分别预览 Lobby、Read、Write、结果与 Collection；每个至少完成一轮，重点抽查五个新增 World 的两轮 Quest
2. 冷启动试听 Aurora 的单个连续离线短句 `Ta-dá↗ woooords↘!`（近似“它达，沃尔子”）：`da` 略拉长上扬并直接连入明显拉长、下落的 `wor`，不得有刻意逗号停顿或合成接缝；后台短暂返回不重播，Voice 关闭时不播口白。自动转写与连接时序已通过，音高和听感仍需真机人工批准
3. 确认 Parent settings 不再有 voice style picker；所有 Profile 使用同一个 canonical teacher contract
4. 在未配置远端 endpoint 及缺少可选高质量 voice 的设备上测试，确认 App 选用已安装的清晰兼容 fallback 而不是静音；客户端和日志都不得包含 provider API key
5. 在 Write 试听 Katie 0.82× 的 `of`、`at`、`cat`、`come`、`look`；在 Read 两错后点按 Hear 试听 Katie 0.90× 版本。另试听 manifest 记录的 `bun` Aurora quality override。确认每个词只形成一个连续 clip、音高自然、速度不过慢，`f`、`t`、`k`、`n` 等尾音清楚
6. 连续答对至少七个词，确认每次都有当前 World 的即时正确音效，Aurora 六条短庆祝不会连续重复；第七次才循环。完成 Quest 后只追加一次 `Quest complete! Ta-da!`，进入录音时任何未结束口播都会停止
7. 在 Moonpetal 检查两侧彩虹/独角兽；在新增 World 分别检查恐龙、消防救援、原创积木、冰雪极光和过山车元素；确认中央任务安全区清晰且元素不跨主题泄漏
8. 确认语音提示时音乐降低，Read 录音时音乐和非必要音效停止
9. 分别测试 Voice、Music、Sound effects、Reduced Sound 和 Calm Rescue
10. 测试扬声器、耳机、来电打断、后台恢复和音量变化
11. 开启 VoiceOver，走完 Profile、Lobby、Read、Write、结果和 Guardian
12. 开启 Reduce Motion 与较大动态字体，检查横屏紧凑布局

通过标准：Reduced Sound 保留必要的正确、重试和技术非语言提示，但关闭装饰性 click、star、reward 与 Aurora transition 口播；Voice 单独控制 Katie/Aurora/Apple 口播。Calm Rescue 不播放紧急节奏层。人工批准响度、疲劳感、爆音和女声音色。

## 验收方向切换和本地数据

1. 在 iPhone 17 Pro Max 与 iPad 的 Profile、Lobby、Quest、结果和 Collection 测试 Landscape Left 和 Landscape Right
2. 在这些 child route 尝试旋转到 Portrait，确认仍保持横屏全屏
3. 进入 Parents 与首次家长设置：iPhone 验证 Portrait + 两个 Landscape 且拒绝 Upside Down；iPad 验证四向
4. 在家长页面竖持设备后退出，确认 Profile/Lobby 立即恢复横屏，不保留竖屏
5. 完成建档、加词、设置和 Quest 后强制退出
6. 重新打开，确认所有数据与上次 Profile 恢复

当前模拟器证据：iPad 的首次 Parents 页面使用 tall/portrait window，child Read 使用 landscape window；对应截图见 `QAArtifacts/v0.2-2026-07-12/iPadPro13-launch.jpg` 与 `QAArtifacts/v0.2-2026-07-12/iPadPro13-paws-read.jpg`。iPhone Lobby/Read 的最终 JPG 已旋转为可读横屏，只用于 UI 检查；raw framebuffer 的方向仍有歧义，不作为竖屏通过证据。iPhone 与 iPad 的真机旋转仍按上述步骤验收。

`Contents.json` 只描述 Xcode 资产。运行数据位于 App 沙盒的 Application Support 目录。App 没有自建服务器数据库。`TadaWordsLocalQA` 安装为独立的 **Tada Words QA**，没有 iCloud 能力且数据不跨设备；正常 Release 也只有在家长明确开启后才会同步。

具体词图片使用固定版本的 Twemoji 17.0.3 PNG，并缓存到 App 私有目录。请求只包含内置 catalog 的 Unicode asset filename，不包含孩子姓名、Profile ID、学习记录或家长输入的原词。`the`、`come`、`kind` 等不在具体词 catalog 中的词必须直接返回无图片且不联网。许可证与来源记录在 `THIRD_PARTY_NOTICES.md`。

## 完成真机发布验收

最终发布前必须在一台 iPhone 17 Pro Max 与一台 iPad 上通过以下项目：

- 签名安装、冷启动、后台恢复和两个横屏方向
- 真实儿童语音、家庭噪声、自动停录、声纹同人与异人样本
- 手指、Apple Pencil、掌触和四岁儿童字形
- Camera 与 Photo Library 权限
- Camera / Photo Library 的头像与多图片 word-sheet OCR 两种用途，包括单图 500 词上限、编号和 sticky Add All
- VoiceOver、Reduce Motion 与动态字体
- 单一 canonical teacher voice/fallback、每个 World 的音乐、ducking、响度和疲劳感
- Voice setup 的随机句跟读、拒绝样本、完成保存和每设备独立声纹
- Write 的短点/连笔/后续笔画、4× 橡皮、空白点击恢复笔、画布固定坐标和无卡顿笔触音
- `FOLLOWUP_BUGFIXES_AND_IMPROVEMENTS.md` 中 v0.3 全部 device evidence，并保留已合并 v0.2 的未完成真机证据
- 两个 Apple ID 的 CloudKit 邀请、冲突、离线恢复和删除传播
- Family Sync 默认关闭、家长 opt-in 持久化、关闭后停止未来同步
- CloudKit 远端 records 擦除
- 本地通知授权、安静时段与实际投递

只有这些设备项目通过后，才能把 Device Alpha 和家庭同步标记为已验收。
