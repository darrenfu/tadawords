# Tada Words — V1 产品与交互设计

> 状态：v0.3.1 已完成 iPhone production Vision 真机测试，以及 iPad production/UI 真机自动化回归；儿童手写、音频听感、布局与辅助功能仍待人工验收
>
> 项目名称：**Tada Words**
>
> 目标版本：家庭私有测试版 / TestFlight V1

## 1. 产品定义

Tada Words 是一款面向学前儿童的英语 sight-word 学习 App。Guardian 每天分别录入或选择需要“会读”和“会写”的单词；孩子通过两个彼此独立的主题闯关，最终做到：

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

- 不按年级自动填充 Read 或 Write Pool。V1 的离线 Preset Catalog 只提供排序、浏览和搜索，必须由 Guardian 明确选择并提交；自动课程模式进入 V2。
- 不做 Read 配对、听音找词等额外小游戏。
- 不做社交、儿童排行榜、广告、抽卡或随机宝箱。
- 不保存或上传任何原始练习录音。
- 不承诺专业的 phoneme-level 发音评分；V1 判断的是孩子是否独立读出了目标词。
- 不复制 Todo Math 或其他产品的旋律、音效、角色口播、采样和声音资产。

## 2. 用户与权限

| 角色 | 能力 |
|---|---|
| Owner Guardian | 创建家庭、邀请 Guardian、创建和删除 Kid Profile、管理所有数据 |
| Guardian | 手输、OCR 或选择 Preset 单词，调整设置、查看报告、管理声纹与主题 |
| Kid Profile | 选择自己的头像、完成 Quest、查看收藏与世界 |

V1 的 Kid 是 App 内 Profile，而不是必须拥有独立 Apple ID 的 CloudKit 成员。孩子在 Guardian 已登录 iCloud 的设备上使用；不同 Guardian 可以通过邀请共享同一个 Kid Profile。

### Kid Profile 最小资料

- 昵称
- 头像
- 当前年级
- 年龄；新建 Profile 必须明确选择 3–8 岁，旧版缺失年龄仍可读取
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

### 当前真机自动化证据

2026-07-14，Team `6S245NCUPQ` 签名的 `Tada Words QA` v0.3.1 (`2026071403`) 已在 Darren iPad Air 13-inch (M4)、iPadOS 26.5 安装并启动。Production DeviceTests 2/2 通过，覆盖 wrong-word rejection 与 `of/go` case variants；LocalQA Critical XCUITest 7/7 通过，覆盖 OCR Add All、Delete All/restore、明确批准 Preset、连续删除/排序、Photo picker/排序及 Read/Write 完成反馈消失。

这些证据验证 production 识别链路和关键交互可以在 iPad 真机运行，但不替代儿童真实手写、发音听感、横竖屏布局、Apple Pencil、VoiceOver 与 Dynamic Type 验收。

### 方向规则

- Profile Picker、World Lobby、Kid Quest、结果页与 Collection 只支持 `Landscape Left` 与 `Landscape Right`。
- `Parents`、Parent Gate、Guardian 管理页与首次家长设置支持横竖屏。
- iPhone 家长路线支持 Portrait 与两个 Landscape，不支持 Portrait Upside Down；iPad 家长路线支持四个方向。
- 离开家长路线后，App 必须通过 route-level geometry update 立即恢复横屏；孩子页面左右两个横屏方向都要验收。
- iPhone Kid Quest 会减少背景装饰，优先保证大单词、麦克风和完整书写区。

Write 支持手指；Apple Pencil 仅在兼容设备上启用，并使用防误触。Apple 官方当前的 Pencil 兼容设备为 iPad，因此 iPhone 17 Pro Max 的 Write 输入使用手指。[Apple Pencil compatibility](https://support.apple.com/en-am/108937)

## 4. 信息架构

```text
App Launch
├── Profile Picker
│   ├── New Kid（没有 Profile 时直接展开；孩子输入昵称与年龄）
│   ├── 上次 Profile（有 Profile 时突出显示，孩子点击确认）
│   └── World Lobby
│       ├── Read Today’s Quest
│       ├── Write Today’s Quest
│       ├── Practice Again
│       ├── Quest Calendar
│       ├── My Collection（选择已获得 Theme / Icon）
│       └── Treasure Collection
└── Parent Gate
    ├── Today
    ├── Words
    │   ├── Read Pool：Type / Camera / Photo / Select / Delete
    │   └── Write Pool：Type / Camera / Photo / Select / Delete
    ├── Preset Words（按年龄、年级与精细分类浏览；家长明确选择后才加入）
    ├── Reports
    ├── Profiles & Family
    ├── Worlds
    └── Settings
```

儿童端的固定心智模型只有三个选择：

1. 我是谁？
2. 今天 Read 还是 Write？
3. 在哪个已解锁世界冒险？

App 只从 Guardian 已明确批准进入 Pool 的词中编排 New、Review、难词回流和计时。来源可以是手输、OCR，或家长在内置 Preset Catalog 中主动选择的词；年龄和年级只改变推荐排序，任何 catalog 或生成模型都不得自动添加练习词。

## 5. 首次设置

首次启动必须先处理 Profile，不先要求输入单词：

1. 已有 Profile：显示 Picker，并突出上次使用的有效 Profile；孩子点击后进入。
2. 没有 Profile：直接显示 `New Kid`，输入昵称和年龄，并选择头像、年级和 Starter World。V1 新建范围为 3–8 岁，对应 Pre-K–Grade 3；旧 Profile 缺少年龄仍可兼容读取。
3. 阅读并同意儿童声纹、同步与删除规则。
4. 声纹注册、单词录入和通知均可稍后在 Parents 中完成，不阻塞第一次进入 Kid Lobby。

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
│ Tada Words                                       Parents │
│                                                          │
│       ( Panda )        ( Bunny )        ( Photo )         │
│         Mia              Leo              Addy            │
│                                                          │
│                    “Who’s playing?”                       │
└──────────────────────────────────────────────────────────┘
```

- 每个 Profile 使用 96 pt 以上的大头像卡片。
- 孩子先点击自己的头像；App 不依赖声纹自动切换 Profile。
- App 记住最后使用的有效 Profile；下次冷启动在 Picker 中突出该 Profile，但仍由孩子点击确认。若该 Profile 已不存在，则显示普通 Picker，不猜测其他身份。
- 上次 Profile 使用静态 1.03× 尺寸与更高叠放层级突出；其他 Profile 不降透明度，也不使用持续动画。
- Picker 提供 `New Kid` 卡片。孩子输入昵称并明确选择 3–8 岁年龄；App 按年龄给出当前支持的 Grade 建议，并自动分配内置动物头像与 Starter World。完整编辑仍由 Guardian 完成。
- Read 录音时，才用选中 Profile 的声纹过滤其他说话人。
- `Parents` 入口放在稳定的右上角，普通单击后立即进入随机算术 Parent Gate，不与 Quest 主入口争夺注意力。

## 7. World Lobby

```text
┌──────────────────────────────────────────────────────────┐
│ (Mia)                                 My Collection Parents│
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
- Header 不重复放置不可点击的 World 名称胶囊；它容易被误认为按钮。当前主题由整页场景和 My Collection 选中态表达。
- 已完成的入口显示当日分数和星星，并提供 `Practice Again`。
- Practice Again 会更新记忆模型，但不重复发放当日永久收藏品，也不计入世界解锁次数。
- Results 页的 Replay 图标必须是可点击按钮；单击后重新开始同一模式的 `Practice Again`，不重复永久奖励或 Theme / Icon 解锁。
- `Quest Calendar` 展示当前月每天实际完成的 Quest 次数；Read、Write 和 Practice Again 都按一次完成记录计数，并严格按 Profile 隔离。

### v0.2 Pre-K 视觉层级

- iPhone 横屏 Header 保留左侧带字 `Kids`；右侧 `Worlds`、`Calendar`、`Badge` 收入半透明图标 dock。每个图标视觉直径 48 pt，实际触控框 72 × 72 pt，并提供完整 VoiceOver label/hint。
- iPad Header 继续显示 `Worlds`、`Calendar`、`Badge` 文字，不为追求统一而牺牲大屏可读性。
- Lobby 主 mascot 在紧凑/标准布局分别为 72/104 pt。
- Read 主 mascot 为 80/104 pt；标准布局单词卡宽度为 560–760 pt，目标词为 112 pt；iPhone 紧凑布局保留 78 pt 目标词以避免挤压麦克风。
- Result 主 mascot 为 68/104 pt，reward/replay 主视觉为 96/144 pt。尺寸变化只强化完成感，不改变积分、星星、奖励或 Replay 行为。
- 以上尺寸来自集中式 child-scale component tokens；不同 World 继续使用自己的 palette、scene、mascot 与 reward，不统一改成公主粉色。

## 8. 单词池与每日编排

Guardian 每天向两个独立 Pool 录入或选择单词：

- `Read New Words Pool`
- `Write New Words Pool`

### 输入规则

- `Type one word` 每次只接收一个词；按 Return 后立即加入当前 Pool、清空输入框，并实时显示在队列最前面。
- `Take Photo` 与 `Choose Photo` 使用本机 OCR 一次识别照片中的所有英文词；先提供可编辑的去重预览，Guardian 点击 `Add All` 后才写入。
- OCR 批次整体排在旧词之前，批次内部保持照片中的阅读顺序；识别图片不上传服务器。
- 自动去掉首尾空格、统一 Unicode 形式并忽略大小写去重。
- 默认显示为小写；Guardian 可为个别单词保留指定大小写。
- Read 与 Write 之间不跨组去重；同一个词可以拥有两套独立记录。
- 同 Pool 重复输入时不创建副本，而是把已有词移动到队列最前面并保留学习历史。
- `Preset Words` 按 Profile 的年龄与年级排序，支持分层浏览、搜索、逐词选择或全选；只有点击 Add 才写入 Read、Write 或 Both。
- Preset 导入绑定发起操作的 Profile。Both 必须全部完成；任一 Pool 失败、部分成功或返回不一致时，只撤销本次插入或重新启用的 membership，不得停用导入前已 active 的词。
- 支持单条删除、选择模式与批量删除；第一次删除确认与 Undo 状态按 Profile 隔离。
- Read 与 Write 各自支持 `Delete all N words`；每次明确确认数量与 Pool，保留学习历史和另一 Pool，并可完整 Undo。
- 自动生成标准美式英语发音，允许 Guardian 试听。
- 不提供多读音选择，也不要求 Guardian 自己录音。
- 所有新增词必须来自 Guardian typing、OCR 或明确批准的 Preset selection；Pool 不足时只练已有词，绝不自动补词。

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
- 新 Profile、新词和进入 Read Quest 时都保持安静；第一次独立作答前绝不播放目标发音。
- 每个 World 通过设计 token 指定唯一、配套且高对比的深色目标词颜色；同一 World 的所有 Read 单词保持一致，只有切换 World 才改变颜色，颜色不表示正确或错误。
- 连续两次有效读错后，才显示唯一的 Help 按钮：`Hear it` 播放标准发音。Read 不显示图片提示；技术重试不解锁 Help。
- 使用 `Hear it` 后，后续尝试记录为 guided evidence。
- 孩子点击一次大麦克风，App 自动开始并检测说完。
- 进行降噪、回声消除、语音活动检测、静音裁剪和声纹匹配。
- 原始音频只在本机短暂处理，完成后立即删除。
- App 判断“识别为目标词”，不显示专业发音分数。
- 文本匹配允许经过测试的保守音近等价，例如目标 `come` 被儿童 ASR 转写为 `kum/cum`；不得用无边界编辑距离把 `come/some`、`cat/cap` 等不同词误判为通过。该等价层不能绕过有效音频、声纹或置信度门。

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
│   🔊  [?]   [✏️ Pencil / Chalk / Brush] [Eraser] Clear [Done]│
└──────────────────────────────────────────────────────────┘
```

### 行为

- 每个词开始时只播放发音，绝不预先显示完整拼写；只有孩子主动点 `?` 才显示答案。
- Read 与 Write 使用同一清晰、连贯的 canonical teacher cadence。离线 fallback 采用适中速度、自然音高、单个不中断的 utterance，并在 Write 保留更长的句尾释放，确保 `of`、`at`、`look` 等短词的末尾辅音可听见。
- 不建立“拼字 → 描写 → 抄写 → 默写”的强制渐进路线。
- 正式题目只给发音、三线练字区域和按字母数量显示的淡色空位。
- 发音按钮可以无限重播；重播不算 Help，但记录次数。
- 单独的 `?` 图标点击后立即显示正确拼写，不出现三选一菜单；使用后仍可完成，但不计独立成功。
- 支持手指和兼容设备上的 Apple Pencil。
- 笔盒只提供 Pencil、Chalk、Brush 三种黑色笔；不显示颜色选择或 Crayon。笔型按 Profile 保存，旧版彩色/Crayon 设置迁移为黑色 Pencil。
- 三种笔拥有可区分但低刺激的书写音色；只在实际移动落笔时节流播放，发音或录音期间不争夺注意力。
- 不提供 Undo。固定位置的 Eraser 进行局部擦除，擦除轨迹为当前笔宽的 4 倍；`Clear` 单击立即清空，不弹确认。
- 保留大号 `Done`，停笔不会自动提交。

### 识别结果

- `confidentCorrect`：计分并触发奖励。
- `confidentIncorrect`：温和提示重写；具体词可出现可点图片，但不自动显示拼写。
- `uncertain`：不直接判错或显示答案；作为技术重试允许再次提交。
- 第二次仍不能确认：标记为需要复习并继续，不让识别引擎阻塞 Quest。
- 匹配忽略大小写；Vision 使用目标词的 lower/Initial-cap/ALL-CAPS 词表、语言修正和前五个候选。生产识别最多使用两个彼此独立的有界栅格（默认 26-point 与 36-point fallback），每个 pass 都必须独立得到完整目标，不跨 pass 拼接或投票。只允许完整目标对齐时的 `0` → `o`；`9` → `g` 还必须由同一 Vision fragment 的同长度候选在相同位置明确给出 `g`。不使用会接受 `if/on/or/off/do/no/90` 等邻词或数字的模糊编辑距离。
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
2. **Accuracy Star**：严格首答正确率达到默认 80%；或整轮只有一次首答错误，并在下一次有效、无辅助重试中立即答对。Guardian 报告的首答正确率仍使用严格值，不被奖励宽限改写。
3. **Personal Pace Star**：有效中位用时位于个人舒适区；慢侧给予 25% 宽限，过快侧不放宽。前 3 次有效 Quest 的校准期只要有有效计时也授予该星。

### 分数默认公式

- 总分 0–100。
- Accuracy 占 80 分，Personal Pace 占 20 分。
- Help 后答对可获得完成分，但不算独立正确。
- 不倒扣、不出现负分、不做跨儿童排名。
- 技术重试和模型不确定完全排除在分母之外。
- 前 3 次有效 Quest 用来建立个人速度基线，并显示为 `Learning your pace`；校准期不再因此失去第三颗星。

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

V1 当前实现八个完整 World Pack：

| World | 类别 | 美术方向 | 示例奖励 |
|---|---|---|---|
| Moonpetal Kingdom | Princess | 温暖手绘森林童话 | 皇冠、礼服、宠物、城堡房间 |
| Build-It Bay | Construction | 明快立体绘本城市 | 工程车、工具、桥梁、城市建筑 |
| Paws & Pines | Animals | 自然探索与照料 | 动物伙伴、食物、玩具、栖息地 |
| Dino Discovery | Dinosaurs | 丛林、火山与化石探索 | 小恐龙、化石、探险装备、失落山谷 |
| Firehouse Heroes | Rescue | 友善消防站与城市救援 | 消防车、安全装备、团队徽章、救援路线 |
| Brickwork City | Building | 原创彩色积木建造 | 积木、齿轮、车辆、房屋与城市作品 |
| Frostlight World | Winter | 冰晶、雪地与极光 | 雪花、冰冠、冬日伙伴、晶莹山脉 |
| Coaster Carnival | Amusement | 过山车与夜间游园会 | 车票、游乐设施、气球、烟花庆典 |

同一类别未来可以拥有多个完全不同画风的 World Pack，例如水彩森林童话、冰晶音乐剧或星空舞会。美术只借鉴抽象的情绪和媒介语言，不复刻 Disney、Ghibli、《冰雪奇缘》的角色、服装、场景和标志性造型。

### 奖励节奏

- 每个正确答案触发 1–2 秒主题微动画。
- 完成一轮 Today’s Quest 获得一个明确可见的永久收藏品。
- 多轮共同推进大型场景。
- 分数与星星推进当前 World 的成就轨道。
- 不使用随机宝箱或概率奖励。
- 在哪个 World 完成，就只获得该 World 的奖励。

### 世界解锁

- 首次从八个世界中选择一个 Starter World。
- 同一本地自然日完成 Read Today Quest 和 Write Today Quest，形成一次 `Double Quest Day`。
- 到下一个本地自然日后，每个尚未领取的 Double Quest Day 按稳定 catalog 顺序解锁一个新 World Theme 和一个新 Profile Icon；当天不提前解锁，隔天才再次打开 App 时会幂等补发。
- Practice Again、Replay、单独只完成 Read 或 Write 都不计入该解锁。
- 八个 World Theme 全部获得后不虚构新 Theme；Icon catalog 与未来 World Pack 均可扩展。
- Guardian 可以更换 Starter World 或直接解锁。
- 未解锁世界允许预览，但不允许进入 Quest。
- Kid Lobby 的独立 `My Collection` 页面同时展示已获得/未获得 Theme、Icon 和 Treasure。每个 World 的 25 件 Treasure 都显示相关且互不重复的图标；未解锁时保留灰色图标并叠加锁，而不是换成通用锁。
- 孩子可以把已收集 Treasure 选为 Profile 头像，未收集 Treasure 不能选择。Theme、动物 Icon、Treasure 头像均按 Profile 持久化，原始照片数据不会因选择奖励头像而被删除。

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
- `Manage Words`
- `Choose preset words`

### Words

- Read / Write 两个明确 Tab。
- 顶部单词输入栏：每次一个词，Return 即时加入。
- 本机 `Take Photo` / `Choose Photo` OCR、可编辑导入预览和 `Add All`。
- 下方 newest-first 队列、单条删除、选择模式、批量删除确认与 Undo；首次删除确认和 Undo 状态按 Profile 隔离。
- Read / Write 各自提供 `Delete all N words`；高影响操作每次都明确确认数量和目标 Pool，完成后仍可完整 Undo，且不删除学习历史或修改另一 Pool。
- 独立的 Preset Words 浏览器提供 3–8 岁 / Pre-K–Grade 3 推荐；先显示最多 6 组匹配内容，再按“基础词/拼读/名词主题/动词/形容词与概念”逐层浏览或搜索。
- Preset Catalog 的每个叶子词组为 30–50 个原创编排的单词；家长可逐词选择或 Select all，并明确加入 Read、Write 或 Both。打开列表、年龄匹配或推荐排序均不会自动写入 Pool；目标 Pool 内按标准化拼写去重。
- Preset 导入始终写入发起操作的 Profile。Both 导入按补偿事务处理；失败时只撤销本次插入或重新启用的 membership，保留已有 active word。
- 布局在 iPhone / iPad 的 Parent 横竖屏均保持 44 pt 触控目标、键盘不遮挡操作。
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
- “Why this word is due for review now”

Guardian 可以纠正一次明显的语音或手写误判。系统修正该 AttemptEvent 并重算状态，不清空整个单词历史。

### Profiles & Family

- 创建、编辑、删除 Kid Profile。
- 所有新建入口都必须采集 3–8 岁年龄；孩子自建时由年龄给出当前支持范围内的年级建议，首次设置与 Parent 编辑仍由家长明确选择年级，修改年龄不静默覆盖家长选择。
- 邀请或移除 Guardian。
- 查看同步状态、待同步修改数和最近一次成功时间；每台设备分别显示是否需要重新注册声纹。
- 在当前设备重新注册或删除声纹；声纹模板不跨设备复制。
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
- 本地提交后把 Profile 标记到持久 outbox；恢复网络、App 回到前台或家长点击 `Sync now` 后重试。
- Attempt、QuestCompletion、RewardGrant 使用不可变 UUID 事件。
- Profile、Pool membership 和 Settings 使用持久逻辑 revision 与 device ID 做确定性合并，不能只依赖设备时钟。
- Attempt / Correction 合并后从事件历史重算 WordProgress 与遗忘曲线；竞争的 progress snapshot 不是权威数据。
- Today completion、Daily Plan 与 Reward 使用 Profile + Mode/World + LocalDay 的稳定业务 key，离线双设备完成也只能计一次 Today 奖励。
- 重复 Word 在同步后由 `Profile + Mode + normalized word` 合并；Read 与 Write 的同名词仍是两个独立学习对象。
- 同步状态、待处理数量、最近成功时间和可恢复错误在重启后仍可见；孩子做题页面不弹同步阻塞框。

当前实现保持可检查的本地 JSON snapshot 作为运行真源，通过自定义 CloudKit record adapter 同步，不为 v0.3 再引入 Core Data 或自建服务器。完整 record scope、合并规则、outbox、删除与验收见 [ADR-0001](Docs/ADR-0001-CROSS-DEVICE-FAMILY-SYNC.md)。

### 同一 Apple ID

- 使用 CloudKit private database 自动同步 Profile 数据。
- 家长在每台设备分别 opt in 后，同步 Profile/头像、Read/Write Pool、设置、Attempt/Correction、Calendar completion 和 Reward。
- 最近使用的 Profile、系统通知实例、声纹、图片提示和教师发音缓存保持设备本地。

### 不同 Apple ID

- 通过 `CKShare` 明确邀请和接受；属于 Apple Family 不会自动获得 App 数据。
- 一名 Kid Profile 对应一个共享对象图。
- Owner Guardian 拥有根 Profile；其他 Guardian 获得读写权限。
- CloudKit 的原生 participant 权限只有只读/读写，因此 V1 不把独立儿童 Apple ID 加入为可写 participant。[CloudKit sharing](https://developer.apple.com/documentation/cloudkit/sharing-cloudkit-data-with-other-icloud-users)

## 18. 声纹与可重下载资产的设备隔离

- 原始录音不持久化、不上传。
- 声纹模板只保存在当前设备 Keychain；Profile 同步时导出 `notEnrolled`，导入时保留接收设备自己的 enrollment 状态。
- 新 iPhone/iPad 需要为同一个 Kid Profile 单独完成一次声纹注册；声纹不可用不能阻塞学习历史同步。
- 具体词图片和未来的远端 audio 补包只写入 App `Caches`，不进入 CloudKit。首发 500 词的 Katie 双语速音频随 App bundle 离线分发；bundle 外的家长自定义词使用本机 Apple 英语女声 fallback。两类音频都不进入家庭同步数据。
- Avatar 原图属于家长明确选择的 Profile 数据，不是 cache；Family Sync 开启后可同步，但生产版应使用有大小上限的独立 `CKAsset`。

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

- 每次冷启动播放约 1.5–2 秒的原创 sonic logo，并用 Aurora 离线录制的一条连续短句清楚喊出 **`Ta-dá↗ woooords↘!`**（近似“它达，沃尔子”）。
- `da` 略拉长并上扬，随后不做刻意逗号停顿，直接连入明显拉长且下落的 `wor`；整体兴奋有朝气，同时不得出现多个排队 utterance 的机械接缝。
- 正常启动固定使用 Cartesia Aurora 声线，确保所有设备的品牌读法一致；资源损坏或缺失时才使用确定性的 Apple 美式女声回退，不能静音或联网临时合成。
- 结尾配器和环境尾音跟随当前选中的 World Pack；尚未选择 Starter World 时使用中性的品牌版本。
- 不模仿 Todo Math 的旋律、节奏、声音演员或任何真人声线。
- 从后台短暂返回时不重复播放，避免频繁打扰。
- Guardian 可以关闭启动口播。

#### 背景音乐

- 每个 World Pack 拥有独立的原创音乐主题和乐器组合，奖励音色不跨 World 混用。
- 孩子切换 World 后，Lobby、Read、Write、结算页和 Collection 的音乐与环境声立即切换为该 World 的声音皮肤。
- 正常状态使用轻快但低密度的循环，不与 TTS、孩子朗读或书写节奏争夺注意力。
- 紧急状态使用同一原创主题的加速或加层版本，平滑切换；不突然增大音量、不加入警报声。
- TTS、Help 和标准发音播放时，背景乐自动 ducking。
- Read `Hear it`、Write 自动提示和 Parent 试听优先使用 500 词离线包：Katie 是 canonical teacher，Read 为清晰自然的 0.90×，Write 为保留尾音的 0.82×。若双识别审计确认某个孤立词的 canonical 输出不清楚，允许在 manifest 中记录单词级 voice/speed override；首包仅 `bun` 使用 Aurora。每词两个版本不可互换；未覆盖词使用同一条 Apple 美式女声 fallback。播放期间切到 spoken-audio session 并同时压低 App 音乐与外部音频，结束后再恢复混音。
- Read 开始录音前快速淡出背景乐和非必要环境音；录音结束后再平滑恢复，避免影响降噪和识别。

#### 功能音效

- 点击、正确、重试、星星和收藏品使用相同的功能语义，但具体音色与短旋律跟随当前 World。
- 点击：短、柔和、低刺激的触感音。
- 正确：先立即播放当前 World 的原创上行短音型，再依序轮换六条 Aurora 微庆祝语（如 `Ta-da!`、`Yes!`、`You did it!`），避免连续重复同一句；Reduced Sound 只保留必要非语言反馈并关闭这些装饰口播。
- 有效错误：温和的“再试一次”提示，不使用蜂鸣器或失败号角。
- `technicalRetry`：使用中性提示音，必须与孩子答错的声音明显不同。
- 三颗星：三段可区分但属于同一声音家族的揭晓音。
- Quest 结算：星星仍使用当前 World 的专属音色，完成时增加 Aurora 的短句 `Quest complete! Ta-da!`；不做随机稀有度音效。
- 三种书写工具使用原创的短促摩擦/颗粒音色，并按实际移动节流；Reduced Sound 关闭这些装饰性书写音，提示发音播放时也不叠加。

#### 首发 World 的声音方向

| World | 声音方向 |
|---|---|
| Moonpetal Kingdom | 约 100 BPM 的欢快原创循环；竖琴、钟琴、低音脉冲、轻鼓、柔和刷奏与魔法闪光音；场景加入两侧彩虹、云朵与独角兽，中央学习安全区保持清晰 |
| Build-It Bay | 木块、轻打击乐、柔和机械节奏与安全的工程完成音 |
| Paws & Pines | 马林巴、原声拨弦、鸟鸣和温和自然环境声 |
| Dino Discovery | 约 80 BPM 的丛林踏步、马林巴与温和低音，不使用吓人的吼叫 |
| Firehouse Heroes | 约 120 BPM 的欢快巡游节奏，不使用警报器或刺耳警笛 |
| Brickwork City | 约 120 BPM 的木质积木律动与拼搭音色，不借用商业玩具品牌声音 |
| Frostlight World | 约 75 BPM 的冰晶钟琴华尔兹与轻盈双倍细分 |
| Coaster Carnival | 约 150 BPM 的升降拨弦与游园节奏，保持安全峰值和语音空间 |

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
- 声纹模板属于敏感的设备本地信息；注册、重新注册和删除均是 Guardian 操作，但不进入 Family Sync。
- Family Sync 开启后 Avatar 照片作为 Profile 数据同步；图片提示与教师发音 cache 不同步。
- 不接入广告 SDK 或第三方儿童行为追踪。
- Guardian 可以导出学习数据和彻底删除 Profile。
- 删除操作使用不含昵称、照片、单词或学习内容的最小 tombstone，同步到所有设备和共享成员；tombstone 无条件压过任何同 Profile ID 的旧资料，其他 CloudKit records 物理擦除。

## 23. V1 验收标准

### Child

- 4 岁孩子不阅读说明文字也能选择 Profile 和进入两个 Quest。
- 冷启动先显示 Profile；没有 Profile 时直接创建，已有 Profile 时突出上次选择但不跳过孩子确认。
- Read 与 Write 入口不会被误认为同一个任务。
- Read 第一次独立作答前保持安静；两次有效错误后才出现唯一的 `Hear it` Help。
- 完成 Read 题时，技术噪声不会被计为发音错误。
- 完成 Write 题时，停笔不会触发自动提交。
- Write 的教师发音清晰连贯，不会因过度减速或音频恢复过早而吞掉短词尾音。
- 孩子可以看见分数、较宽松的三颗星和主题奖励，并从 My Collection 选择已获得 Theme / Icon。
- 普通单击 Results Replay 会真正开始同模式 Practice Again。
- 超过阈值后可以继续完成，不出现失败倒计时。

### Guardian

- 可在 30 秒内通过逐词 typing、Camera / Photo OCR 或明确批准的 Preset selection 向任一 Pool 加词并试听。
- 新词即时出现在队列最前；可单删、多选批量删除、整组清空并 Undo，删除状态不会跨 Profile。
- 新建 Profile 必须明确选择 3–8 岁年龄；年龄与 Grade 只排序 Preset 建议。
- App 不会在空 Pool 或数量不足时自动生成、加入推荐词或补充单词。
- Both Preset 导入要么更新两个 Pool，要么只回滚本次变更，不影响既有 active word 或其他 Profile。
- 自动去重不会删除另一路线的同名词。
- 报告能解释某词为何进入 Review。
- 可以纠正自动识别误判。
- 可以管理多个 Kid Profile 和 Guardian。

### Data & Privacy

- 离线完成的 Quest 恢复网络后不会丢失或重复计奖。
- 同 Apple ID 与跨 Apple ID 共享均能同步。
- 原始儿童录音不写入持久存储或云端。
- 声纹模板保持每台设备独立；新设备只同步学习资料并重新注册声纹。
- 图片提示与教师发音 cache 不跨设备复制，必要时可安全重下载。
- 识别不确定、噪声和错误说话人不影响分数、星星或遗忘模型。
- 删除 Profile 后，离线旧设备不能把它重新创建出来。

### Technical Spikes before full build

1. 4 岁儿童单词识别、声纹过滤和家庭噪声下的本地准确率。
2. 4 岁儿童手写在目标词约束下的正确 / 错误 / 不确定三态阈值。
3. 不同 Apple ID 的 `CKShare`、ProfileKey 分发、撤销和密钥轮换。
4. 4 岁儿童在 iPhone 17 Pro Max 与目标 iPad 上的横屏手写、听感、布局与辅助功能可用性；iPad 自动化链路已通过，人工验收仍未完成。

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

- 日常进入 Guardian 区使用“普通单击 `Parents`＋随机算术题”。
- 下列敏感操作必须额外通过 Face ID、Touch ID 或设备密码；算术题不能替代系统认证：
  - 邀请或移除 Guardian
  - 导出儿童数据
  - 删除 Kid Profile 或声纹
  - 重新注册声纹或轮换加密密钥

如果设备没有设置可用的系统认证，仍允许进入普通 Guardian 报告和单词录入，但阻止以上敏感操作，并引导 Guardian 先设置设备密码。
