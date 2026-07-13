# Tada Words — V1 产品与交互设计

> 状态：需求与产品设计已确认，可进入视觉原型与技术验证
>
> 项目名称：**Tada Words**
>
> 目标版本：家庭私有测试版 / TestFlight V1

## 1. 产品定义

Tada Words 是一款面向学前儿童的英语 sight-word 学习 App。Guardian 每天分别输入需要“会读”和“会写”的单词；孩子通过两个彼此独立的主题闯关，最终做到：

- **Read**：看见单词后，可以独立读出来。
- **Write**：只听见标准发音，可以独立手写完整单词。

首位目标用户是 4 岁、即将进入 Pre-K、中文母语、生活在美国英语教学环境中的孩子。她已经认识并会写大小写字母，正在开始 phonics 和 sight words。

### V1 产品承诺

- Read 和 Write 是两条独立学习路线，不合并成一轮任务。
- V1 的 Kid 与 Guardian 界面都只使用英文；本文档使用中文仅便于设计沟通。
- Kid Quest 主要依靠图形、声音和动画引导，不提供中文提示。
- 学习以真实回忆为核心：Read 必须开口，Write 必须落笔。
- App 可以识别和安排练习，但不能因为识别不确定而惩罚孩子。
- 游戏奖励增强持续练习，不替代学习目标。
- 多个 Kid Profile、多个 Guardian 和多设备数据保持一致。

### V1 不做

- 不内置 Pre-K / Kindergarten / Grade 1 自动课程词库；该功能进入 V2。
- 不做 Read 配对、听音找词等额外小游戏。
- 不做社交、儿童排行榜、广告、抽卡或随机宝箱。
- 不保存或上传任何原始练习录音。
- 不承诺专业的 phoneme-level 发音评分；V1 判断的是孩子是否独立读出了目标词。
- 不复制 Todo Math 或其他产品的旋律、音效、角色口播、采样和声音资产。

## 2. 用户与权限

| 角色 | 能力 |
|---|---|
| Owner Guardian | 创建家庭、邀请 Guardian、创建和删除 Kid Profile、管理所有数据 |
| Guardian | 输入单词、调整设置、查看报告、管理声纹与主题 |
| Kid Profile | 选择自己的头像、完成 Quest、查看收藏与世界 |

V1 的 Kid 是 App 内 Profile，而不是必须拥有独立 Apple ID 的 CloudKit 成员。孩子在 Guardian 已登录 iCloud 的设备上使用；不同 Guardian 可以通过邀请共享同一个 Kid Profile。

### Kid Profile 最小资料

- 昵称
- 头像
- 当前年级
- 可选年龄
- 儿童声纹模板

不收集真实姓名、完整生日、学校或老师信息。

头像来源：

- 前置摄像头自拍
- 从相册选择已有照片
- 内置的可爱动物图标

## 3. 平台与屏幕方向

V1 是 Universal iOS App。

### 必须验收

- iPad
- iPhone 17 Pro Max

其他 iPhone 使用响应式布局尽力兼容，但不作为 V1 发布阻塞项。

### 方向规则

- iPad 和 iPhone 的整个 App 只支持 `Landscape Left` 与 `Landscape Right`。
- Profile Picker、World Lobby、Kid Quest、Guardian 和结果页都不支持竖屏。
- Guardian 在 iPhone 使用横屏自适应布局，在 iPad 使用横屏侧边栏或多栏布局。
- App 从设备竖持状态启动时也必须进入横屏；左右两个横屏方向都要验收。
- iPhone Kid Quest 会减少背景装饰，优先保证大单词、麦克风和完整书写区。

Write 支持手指；Apple Pencil 仅在兼容设备上启用，并使用防误触。Apple 官方当前的 Pencil 兼容设备为 iPad，因此 iPhone 17 Pro Max 的 Write 输入使用手指。[Apple Pencil compatibility](https://support.apple.com/en-am/108937)

## 4. 信息架构

```text
App Launch
├── Profile Picker
│   ├── New Player（孩子只输入昵称）
│   └── World Lobby
│       ├── Read Today’s Quest
│       ├── Write Today’s Quest
│       ├── Practice Again
│       ├── Quest Calendar
│       ├── World Picker
│       └── Collection
└── Parent Gate
    ├── Today
    ├── Words
    │   ├── Read Pool
    │   └── Write Pool
    ├── Reports
    ├── Profiles & Family
    ├── Worlds
    └── Settings
```

儿童端的固定心智模型只有三个选择：

1. 我是谁？
2. 今天 Read 还是 Write？
3. 在哪个已解锁世界冒险？

选词、复习、难词回流、计时和同步全部由 App 处理。

## 5. 首次设置

Guardian 首次启动依次完成：

1. 阅读并同意儿童声纹、同步与删除规则。
2. 创建 Kid Profile。
3. 选择或拍摄头像。
4. 完成约 1 分钟声纹注册。
5. 分别输入首批 Read Words 和 Write Words。
6. 从三个首发 World Pack 中选择 Starter World。
7. 设置可选通知时间。
8. 进入 Profile Picker。

### 一分钟声纹注册

- App 依次播放 8–10 个非常简单的词。
- 孩子只需跟读，不要求自己认识这些词。
- 在安静与轻微家庭背景声下采集多个特征样本。
- 原始注册音频生成特征后立即删除。
- 只保存加密的声纹特征模板和模型版本。
- Guardian 可以删除或重新注册。
- 感冒、成长或置信度下降时，App 提醒 Guardian 重新注册，但不会锁住学习。

声纹只用于过滤“当前是不是这个孩子在说话”，不作为安全登录或身份认证。

## 6. Profile Picker

```text
┌──────────────────────────────────────────────────────────┐
│ Tada Words                                       Parent  │
│                                                          │
│       ( Panda )        ( Bunny )        ( Photo )         │
│         Mia              Leo              Addy            │
│                                                          │
│                    “Who’s playing?”                       │
└──────────────────────────────────────────────────────────┘
```

- 每个 Profile 使用 96 pt 以上的大头像卡片。
- 孩子先点击自己的头像；App 不依赖声纹自动切换 Profile。
- App 记住最后使用的有效 Profile；下次冷启动直接进入该 Profile 的 Lobby。若该 Profile 已不存在，则回到 Picker，不猜测其他身份。
- Picker 提供 `New Player` 卡片。孩子只输入昵称，App 自动分配内置动物头像与 Starter World；完整编辑仍由 Guardian 完成。
- Read 录音时，才用选中 Profile 的声纹过滤其他说话人。
- Parent 入口放在稳定的右上角，不与 Quest 主入口争夺注意力。

## 7. World Lobby

```text
┌──────────────────────────────────────────────────────────┐
│ (Mia)      Moonpetal Kingdom              Worlds  Parent │
│                                                          │
│                 [ 当前世界互动场景 ]                       │
│                                                          │
│   ┌────────────────────┐  ┌────────────────────┐         │
│   │  Read Today’s      │  │  Write Today’s     │         │
│   │      Quest         │  │       Quest        │         │
│   │   ☆  ☆  ☆          │  │    ☆  ☆  ☆         │         │
│   └────────────────────┘  └────────────────────┘         │
└──────────────────────────────────────────────────────────┘
```

硬性规则：

- 必须始终显示两个独立的大入口。
- 不提供把 Read 与 Write 合并的“综合 Today’s Quest”。
- 当前 World 是全屏背景，但 Quest 卡片位置不随主题改变。
- 已完成的入口显示当日分数和星星，并提供 `Practice Again`。
- Practice Again 会更新记忆模型，但不重复发放当日永久收藏品，也不计入世界解锁次数。
- `Quest Calendar` 展示当前月每天实际完成的 Quest 次数；Read、Write 和 Practice Again 都按一次完成记录计数，并严格按 Profile 隔离。

## 8. 单词池与每日编排

Guardian 每天直接向两个独立 Pool 输入：

- `Read New Words Pool`
- `Write New Words Pool`

### 输入规则

- 支持逐行或用逗号批量输入。
- 自动去掉首尾空格、统一 Unicode 形式并忽略大小写去重。
- 默认显示为小写；Guardian 可为个别单词保留指定大小写。
- Read 与 Write 之间不跨组去重；同一个词可以拥有两套独立记录。
- 重复输入尚未学习的词时，把它移动到当天队列前部。
- 重复输入已学习的词时，保留历史，并把它提高到 Review 优先级。
- 自动生成标准美式英语发音，允许 Guardian 试听。
- 不提供多读音选择，也不要求 Guardian 自己录音。

### 默认题量

| 路线 | New | Review | 紧急状态 |
|---|---:|---:|---:|
| Read | 5 | 5 | 3 分钟 |
| Write | 3 | 3 | 5 分钟 |

四个数量、New/Review 顺序和两个时间阈值都可按 Profile 配置。

### New 选择顺序

1. 优先当天刚输入的词。
2. 不足时，从 Pool 中更早输入、尚未开始的词补足。
3. 超出当日上限的词留在 Pool，下一天优先。
4. Pool 本身不足时就练现有数量，不复制词来凑数。

### New 与 Review 关系

- 默认 `New → Review`，Guardian 可改为 `Review → New`。
- `New → Review` 时，刚才答错、使用 Help、识别不确定或明显偏慢的新词，可以替换 Review 中优先级较低的词；不增加整轮题量。
- `Review → New` 时，New 中的问题词进入下一次 Review，不在本轮末尾追加 Retry。
- 完成的定义是“孩子已经尝试所有安排题目”，不是“必须全部答对”。

## 9. Read Today’s Quest

### 核心状态机

```text
Show Word
  → Tap Mic
  → Listening
  → Speaker Check
  → Word Recognition
      ├── Correct → score + micro reward
      ├── Technical Retry → neutral retry
      └── Valid Incorrect → retry, at most 2 retries
```

### 界面

```text
┌──────────────────────────────────────────────────────────┐
│  01:42          ● ● ● ○ ○ ○ ○ ○ ○ ○             Pause  │
│                                                          │
│                         because                          │
│                                                          │
│                    ┌──────────────┐                      │
│                    │      🎙      │                      │
│                    │     Read     │                      │
│                    └──────────────┘                      │
│                                                          │
│                         +100                             │
└──────────────────────────────────────────────────────────┘
```

### 行为

- 每题只显示一个大号单词。
- 新词首次出现可以进行一次明确的发音示范；该示范轮不计独立掌握。
- 正式判断前不播放答案。
- 孩子点击一次大麦克风，App 自动开始并检测说完。
- 进行降噪、回声消除、语音活动检测、静音裁剪和声纹匹配。
- 原始音频只在本机短暂处理，完成后立即删除。
- App 判断“识别为目标词”，不显示专业发音分数。

### 重试规则

- 首次有效尝试＋最多两次有效重试，共 3 次。
- 无语音、噪声过强、其他人说话、多人重叠、声纹不足或引擎故障属于 `technicalRetry`。
- `technicalRetry` 不消耗重试次数、不进入正确率、不影响遗忘曲线或速度。
- 三次有效尝试仍未通过：播放标准美式发音，标记为问题词，然后继续。

### 用时

- 主要记录从单词出现到孩子开始说话的有效等待时间。
- 扣除技术重试、系统中断和后台等待。
- 只与该 Profile、Read 模式、相近词长的历史基线比较。

## 10. Write Today’s Quest

### 界面

```text
┌──────────────────────────────────────────────────────────┐
│  03:18          ● ● ○ ○ ○ ○                     Pause   │
│                                                          │
│                         🔊                               │
│                                                          │
│             _ _ _ _ _ _ _                               │
│             ─────────────────────────                    │
│             - - - - - - - - - - - -                    │
│             ─────────────────────────                    │
│                                                          │
│   Help      Undo       Clear                 [ Done ]     │
└──────────────────────────────────────────────────────────┘
```

### 行为

- 新词第一次出现时，短暂显示完整拼写并播放发音；随后隐藏。
- 不建立“拼字 → 描写 → 抄写 → 默写”的强制渐进路线。
- 正式题目只给发音、三线练字区域和按字母数量显示的淡色空位。
- 发音按钮可以无限重播；重播不算 Help，但记录次数。
- `Help` 显示正确拼写；使用后仍可完成，但不计独立成功。
- 支持手指和兼容设备上的 Apple Pencil。
- 提供固定位置的 `Undo`、`Clear`、`Help` 和大号 `Done`。
- 不因停笔自动提交。

### 识别结果

- `confidentCorrect`：计分并触发奖励。
- `confidentIncorrect`：显示正确词供对照，然后允许重写一次。
- `uncertain`：不直接判错；显示正确词并允许重写一次。
- 第二次仍不能确认：标记为需要复习并继续，不让识别引擎阻塞 Quest。
- 只保存笔画/识别结果所需的数据；Guardian 报告不展示孩子原始手写轨迹回放。

### 用时

- 从最后一次发音播放结束后开始。
- 发音播放、Help 展示和技术识别等待不计入速度。
- 按单词长度校正，并只与该孩子自己的 Write 历史比较。

PencilKit 用于手指/Pencil 采集；低系统版本可使用 Vision 的目标词约束识别，未来系统可升级为 PencilKit 原生手写识别。[PencilKit drawing policy](https://developer.apple.com/documentation/pencilkit/pkcanvasviewdrawingpolicy/anyinput) · [Vision text recognition](https://developer.apple.com/documentation/vision/recognizing-text-in-images)

## 11. 分数与三颗星

孩子端同时保留数字分数、星星和故事奖励。

### 每轮最多三颗星

1. **Completion Star**：尝试完所有安排题目即可获得。
2. **Accuracy Star**：独立正确率达到默认 80%。
3. **Personal Pace Star**：在正确率达到门槛的前提下，有效中位用时达到该孩子的个人目标。

### 分数默认公式

- 总分 0–100。
- Accuracy 占 80 分，Personal Pace 占 20 分。
- Help 后答对可获得完成分，但不算独立正确。
- 不倒扣、不出现负分、不做跨儿童排名。
- 技术重试和模型不确定完全排除在分母之外。
- 前 3 次有效 Quest 用来建立个人速度基线；在此之前第三颗星显示为“Learning your pace”，不会显示为失败。

速度星不直接使用整轮紧急时间，而是使用逐词、按词长校正后的个人基线，避免鼓励抢答或潦草书写。

## 12. Timer 与紧急状态

- Timer 是正向计时，不是倒计时。
- Quest 按题目完成，不因时间结束。
- 超过默认阈值后，进入当前 World 的故事化紧急状态。
- 只改变音乐、环境颜色和场景动画。
- 不扣分、不倒计时失败、不提高难度、不增加提示。
- 不闪烁、不突然提高音量。
- `Reduce Motion` 或 `Calm Emergency` 开启时，只保留温和的颜色和节奏变化。

## 13. World Pack 与奖励系统

### 内容结构

```text
Theme Category
└── World Pack
    ├── 独立美术方向
    ├── 独立音乐和紧急状态
    ├── 20 个小收藏品
    └── 5 个大型场景里程碑
```

V1 首发三个完整 World Pack：

| World | 类别 | 美术方向 | 示例奖励 |
|---|---|---|---|
| Moonpetal Kingdom | Princess | 温暖手绘森林童话 | 皇冠、礼服、宠物、城堡房间 |
| Build-It Bay | Construction | 明快立体绘本城市 | 工程车、工具、桥梁、城市建筑 |
| Paws & Pines | Animals | 自然探索与照料 | 动物伙伴、食物、玩具、栖息地 |

同一类别未来可以拥有多个完全不同画风的 World Pack，例如水彩森林童话、冰晶音乐剧或星空舞会。美术只借鉴抽象的情绪和媒介语言，不复刻 Disney、Ghibli、《冰雪奇缘》的角色、服装、场景和标志性造型。

### 奖励节奏

- 每个正确答案触发 1–2 秒主题微动画。
- 完成一轮 Today’s Quest 获得一个明确可见的永久收藏品。
- 多轮共同推进大型场景。
- 分数与星星推进当前 World 的成就轨道。
- 不使用随机宝箱或概率奖励。
- 在哪个 World 完成，就只获得该 World 的奖励。

### 世界解锁

- 首次从三个世界中选择一个 Starter World。
- 完成 3 次 Today’s Quest 解锁第二个世界。
- 累计完成 8 次 Today’s Quest 解锁第三个世界。
- Read 或 Write 均计数；Practice Again 不计数。
- Guardian 可以更换 Starter World 或直接解锁。
- 未解锁世界允许预览，但不允许进入 Quest。

## 14. Guardian 端

### Today

每个 Kid Profile 显示：

- Read / Write 今天新输入的数量
- Pool 中等待的新词
- 当前到期 Review
- Today’s Quest 完成状态、分数和星星
- 当前月 Quest Calendar（每天精确完成次数）
- 需要关注的词
- 同步状态
- `Quick Add Words`

### Words

- Read / Write 两个 Tab。
- 大型批量输入框和 `Add to Pool`。
- 保存前显示自动去重结果与发音预览。
- 状态：`Queued`、`Learning`、`Review Due`、`Strong`。
- 单词详情：编辑大小写、试听、查看历史、删除。

### Reports

概览：

- 7 / 30 日完成趋势
- 正确率趋势
- 个人有效用时趋势
- Read / Write 对比
- 星星与世界进度

词级报告：

- 当前记忆状态
- 独立正确率与错误率
- 平均 / 中位有效用时
- 重试、Help 与发音重播次数
- 最近练习时间
- 预计下次 Review
- “Why this word is recommended now”

Guardian 可以纠正一次明显的语音或手写误判。系统修正该 AttemptEvent 并重算状态，不清空整个单词历史。

### Profiles & Family

- 创建、编辑、删除 Kid Profile。
- 邀请或移除 Guardian。
- 查看每台设备的同步与声纹模型版本。
- 重新注册或删除声纹。
- 删除 Profile 时向所有设备传播 tombstone，防止离线旧设备把资料重新上传。

### Settings

- Quest：四个题量、New/Review 顺序、紧急阈值
- Audio & Voice：麦克风测试、声纹重新注册、发音预览
- Worlds：Starter World、手动解锁
- Notifications：按 Profile 设置时间与免打扰
- Accessibility：Reduce Motion、Calm Emergency、左手布局
- Family & Sync：成员、权限、同步状态
- Privacy & Data：导出、删除、声纹说明

## 15. 遗忘曲线与 Review 调度

每个 `Kid Profile × Word × Mode` 独立维护：

- `difficulty`
- `stabilityDays`
- `lastIndependentSuccessAt`
- `predictedRecall`
- `nextDueAt`
- `lapseCount`

以艾宾浩斯遗忘曲线形式作为核心：

```text
R(t) = exp(-t / stability)
```

正确、错误、Help、有效反应时间和发音重播次数会改变 `stability` 与 `difficulty`；不会把 1、3、7 天写死为固定日历。

### Review 排序

1. 已越过预计遗忘点的词
2. 有效错误率高的词
3. 相对个人基线明显偏慢的词
4. 使用 Help、重试或发音重播较多的词
5. 接触次数不足的词
6. 当前 New 阶段刚出现问题的词

`Mastered` 是展示标签，不是永久毕业。默认要求至少三次跨日独立成功，并且模型预计未来 14 天仍能保持目标记忆率；之后仍会根据预测重新进入 Review。

## 16. 事件、计分与可重算状态

每次有效或技术尝试写入不可变 `AttemptEvent`：

```text
eventID, profileID, questID, wordID
mode: read | write
phase: new | review
result: correct | incorrect | helped | technicalRetry
technicalReason
validRetryIndex
promptAt, validInputAt, submittedAt
technicalHoldMs, scoreEligibleMs
speakerConfidence, recognitionConfidence
modelVersion, schedulerVersion, deviceID
```

硬性不变量：

- `technicalRetry` 不消耗有效重试。
- 不进入正确率或速度分母。
- 不更新遗忘曲线。
- 不减少分数或星星。
- 同步、算法和报告都从不可变事件重算，避免版本升级破坏历史。

## 17. 离线、同步与家庭共享

### 本地优先

- Quest 永远先写本地，CloudKit 不得阻塞孩子答题。
- 离线时可以完成全部核心功能。
- 恢复网络后增量同步。
- Attempt、QuestCompletion、RewardGrant 使用不可变 UUID 事件。
- Settings 使用字段级时间戳和设备 ID 做确定性合并。
- 重复 Word 在同步后由标准化 key 合并，并迁移关联事件。

推荐 SwiftUI + Core Data + `NSPersistentCloudKitContainer`；Apple 提供了跨 iCloud 用户共享 Core Data 对象的官方路径。[Sharing Core Data objects between iCloud users](https://developer.apple.com/documentation/coredata/sharing-core-data-objects-between-icloud-users)

### 同一 Apple ID

- 使用 CloudKit private database 自动同步 Profile 数据。
- 同步单词、事件、设置、奖励、头像和加密声纹模板。

### 不同 Apple ID

- 通过 `CKShare` 明确邀请和接受；属于 Apple Family 不会自动获得 App 数据。
- 一名 Kid Profile 对应一个共享对象图。
- Owner Guardian 拥有根 Profile；其他 Guardian 获得读写权限。
- CloudKit 的原生 participant 权限只有只读/读写，因此 V1 不把独立儿童 Apple ID 加入为可写 participant。[CloudKit sharing](https://developer.apple.com/documentation/cloudkit/sharing-cloudkit-data-with-other-icloud-users)

## 18. 声纹端到端加密

跨账号同步只包含声纹特征模板，不包含原始录音。

推荐流程：

1. 每个 Kid Profile 生成独立 `ProfileKey`。
2. 声纹模板使用 AES-GCM 加密。
3. 同 Apple ID 的设备通过可同步 Keychain 获得密钥。
4. 不同 Guardian 接受共享后生成设备公钥。
5. Owner 使用 HPKE 为新 Guardian 包装 `ProfileKey`。
6. 私钥只保存在设备 Keychain。
7. 移除 Guardian 后轮换 `ProfileKey`。
8. 所有密钥都丢失时，声纹不可恢复，需要重新做 1 分钟注册；学习历史不能因此丢失。

仅依赖 CloudKit encrypted fields 不能在所有家庭配置下保证严格 E2EE，因为共享数据的端到端保护与 Advanced Data Protection 状态有关。[iCloud data security overview](https://support.apple.com/en-lamr/102651) · [CryptoKit HPKE](https://developer.apple.com/documentation/cryptokit/hpke)

## 19. 通知

Guardian 可按 Profile 开启：

- 每日学习提醒
- Read / Write Pool 即将为空
- 当天 Quest 完成状态
- 同步失败
- 长期问题词的每周摘要

默认规则：

- 不向 Kid 发送催促通知。
- 锁屏不显示儿童昵称、具体单词、分数或声纹信息。
- 支持免打扰时段和全部关闭。

## 20. 设计系统

### 三层 Token

```text
Primitive → Semantic → Component
```

- Primitive：颜色、间距、字号、圆角、阴影、动效时间。
- Semantic：Read、Write、Success、Attention、Surface、Ink。
- Component：Quest Card、Mic Button、Writing Canvas、Timer、Star Rail、Reward Card。
- World Pack 只覆盖 theme semantic tokens，不改变组件结构和功能颜色。

### 核心视觉 Token

| Token | 默认用途 |
|---|---|
| `surface.canvas` | 温暖的浅奶油背景 |
| `ink.primary` | 深蓝灰文字 |
| `action.read` | 清晰蓝色 |
| `action.write` | 柔和紫色 |
| `feedback.correct` | 青绿色 |
| `feedback.attention` | 琥珀色，不使用刺眼红色 |
| `radius.child` | 24–32 pt 大圆角 |
| `touch.child` | 至少 72 × 72 pt |
| `touch.guardian` | 至少 44 × 44 pt |

### 字体与文字

- Kid UI 使用清晰、圆润但不过度卡通的系统字体。
- 目标单词使用最高对比度和稳定字形，不使用装饰字体。
- iPad Read 单词建议 96–128 pt；iPhone 横屏建议 64–88 pt。
- Guardian 支持 Dynamic Type。

### 动效

- 点按反馈：约 120–180 ms。
- 正确答案微动画：1–2 秒。
- 永久收藏品揭晓：不超过 3 秒，可跳过。
- 紧急状态不使用闪烁或强烈屏幕抖动。
- 支持 Reduce Motion。

### 音效与背景乐

Todo Math 仅作为“儿童可以独立理解、游戏反馈即时、背景音乐可由家长关闭”的交互参考；Tada Words 的旋律、音色组合、口播、音效与录音均须原创。[Todo Math 官方介绍](https://todomath.com/) · [Todo Math 背景音乐设置](https://todomath.zendesk.com/hc/en-us/articles/360022343054-I-can-t-hear-any-sound)

#### 启动声音标识

- 每次冷启动播放约 1–1.5 秒的原创 sonic logo，并清楚喊出 **“Tada Words!”**。
- “Tada Words!” 的核心节奏与发音固定，结尾配器和环境尾音跟随当前选中的 World Pack；尚未选择 Starter World 时使用中性的品牌版本。
- 口播亲切、有朝气，但不尖锐；不模仿 Todo Math 的旋律、节奏或声音演员。
- 从后台短暂返回时不重复播放，避免频繁打扰。
- Guardian 可以关闭启动口播。

#### 背景音乐

- 每个 World Pack 拥有独立的原创音乐主题和乐器组合，奖励音色不跨 World 混用。
- 孩子切换 World 后，Lobby、Read、Write、结算页和 Collection 的音乐与环境声立即切换为该 World 的声音皮肤。
- 正常状态使用轻快但低密度的循环，不与 TTS、孩子朗读或书写节奏争夺注意力。
- 紧急状态使用同一原创主题的加速或加层版本，平滑切换；不突然增大音量、不加入警报声。
- TTS、Help 和标准发音播放时，背景乐自动 ducking。
- Read 开始录音前快速淡出背景乐和非必要环境音；录音结束后再平滑恢复，避免影响降噪和识别。

#### 功能音效

- 点击、正确、重试、星星和收藏品使用相同的功能语义，但具体音色与短旋律跟随当前 World。
- 点击：短、柔和、低刺激的触感音。
- 正确：原创的上行短音型，并与 1–2 秒主题动画同步。
- 有效错误：温和的“再试一次”提示，不使用蜂鸣器或失败号角。
- `technicalRetry`：使用中性提示音，必须与孩子答错的声音明显不同。
- 三颗星：三段可区分但属于同一声音家族的揭晓音。
- 永久收藏品：使用当前 World 的专属完成音，不做随机稀有度音效。

#### 首发 World 的声音方向

| World | 声音方向 |
|---|---|
| Moonpetal Kingdom | 轻柔竖琴、钟琴、木笛与细小魔法闪光音 |
| Build-It Bay | 木块、轻打击乐、柔和机械节奏与安全的工程完成音 |
| Paws & Pines | 马林巴、原声拨弦、鸟鸣和温和自然环境声 |

标准美式单词发音、Help 口播和必要教学提示不随 World 更换声音演员或发音方式，确保孩子形成稳定的听觉参照。

#### 控制与安全

- Guardian 可分别控制 `Voice`、`Music` 和 `Sound Effects`。
- 默认音量经过响度归一化，不出现突然的峰值。
- Reduce Motion 不影响必要声音提示；另提供独立的 Reduced Sound 模式。
- 所有音频资产保留来源、作者、授权和版本记录；外购音效必须具有明确的 App 商用许可。

### 可访问性

- 反馈同时依赖声音、图形和动作，不只靠颜色。
- Guardian 支持 VoiceOver 与 Dynamic Type。
- 提供左手布局，避免按钮位于主要手掌区域。
- 所有控件位置固定，加载或反馈时不发生布局跳动。

## 21. 通用组件状态

| 组件 | 核心状态 |
|---|---|
| Quest Card | ready, inProgress, completed, syncPending, disabled |
| Mic Button | idle, listening, checking, technicalRetry, disabled |
| Writing Canvas | empty, drawing, checking, correct, uncertain, retry |
| Timer | normal, emergency, paused |
| Star Rail | calibrating, earned, unearned |
| Reward Card | locked, revealed, collected |

禁用、加载、技术重试、有效错误必须有不同的视觉与语音反馈；不能用同一个“失败”状态覆盖。

## 22. Guardian 通知与隐私原则

- 原始音频永不离开设备。
- 声纹模板属于敏感信息，注册、分享、删除和密钥轮换均记录 Guardian 操作。
- Avatar 照片和声纹模板使用独立加密对象同步。
- 不接入广告 SDK 或第三方儿童行为追踪。
- Guardian 可以导出学习数据和彻底删除 Profile。
- 删除操作使用 tombstone，同步到所有设备和共享成员。

## 23. V1 验收标准

### Child

- 4 岁孩子不阅读说明文字也能选择 Profile 和进入两个 Quest。
- Read 与 Write 入口不会被误认为同一个任务。
- 完成 Read 题时，技术噪声不会被计为发音错误。
- 完成 Write 题时，停笔不会触发自动提交。
- 孩子可以看见分数、三颗星和主题奖励。
- 超过阈值后可以继续完成，不出现失败倒计时。

### Guardian

- 可在 30 秒内向任一 Pool 批量加入单词并试听。
- 自动去重不会删除另一路线的同名词。
- 报告能解释某词为何进入 Review。
- 可以纠正自动识别误判。
- 可以管理多个 Kid Profile 和 Guardian。

### Data & Privacy

- 离线完成的 Quest 恢复网络后不会丢失或重复计奖。
- 同 Apple ID 与跨 Apple ID 共享均能同步。
- 原始儿童录音不写入持久存储或云端。
- 识别不确定、噪声和错误说话人不影响分数、星星或遗忘模型。
- 删除 Profile 后，离线旧设备不能把它重新创建出来。

### Technical Spikes before full build

1. 4 岁儿童单词识别、声纹过滤和家庭噪声下的本地准确率。
2. 4 岁儿童手写在目标词约束下的正确 / 错误 / 不确定三态阈值。
3. 不同 Apple ID 的 `CKShare`、ProfileKey 分发、撤销和密钥轮换。
4. iPhone 17 Pro Max 与目标 iPad 的横屏书写可用性。

## 24. V2

V2 增加 `Grade Curriculum`：

- Guardian 选择 Pre-K、Kindergarten、Grade 1 等水平。
- App 使用经过授权、可追溯的美国分级词库自动建立或推荐 Read / Write Pool。
- 与 Parent Words 共用去重、遗忘模型、学习记录和奖励。
- V1 数据模型预留 `source = parent | curriculum`。
- 新增同类别、不同美术方向的 World Pack。

V2 仍需单独确认分级标准、词库版权和 Read / Write 分类规则；不能由生成模型随意创造课程标准。

## 25. 已确认的敏感操作认证规则

采用分层认证：

- 日常进入 Guardian 区继续使用“长按＋随机算术题”。
- 下列敏感操作必须额外通过 Face ID、Touch ID 或设备密码；算术题不能替代系统认证：
  - 邀请或移除 Guardian
  - 导出儿童数据
  - 删除 Kid Profile 或声纹
  - 重新注册声纹或轮换加密密钥

如果设备没有设置可用的系统认证，仍允许进入普通 Guardian 报告和单词录入，但阻止以上敏感操作，并引导 Guardian 先设置设备密码。
