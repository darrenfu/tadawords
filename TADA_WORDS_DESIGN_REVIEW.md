<!-- TADA_BILINGUAL_DOC: English is the default reading language. The original source text is preserved for verification. -->
<a id="english-default"></a>

> **Languages / 语言：** **English (default) / 英文（默认）** · [简体中文](#简体中文版)

# Tada Words — Design Review

> Review status: v0.2 device-feedback revision in progress; physical regression pending
>
> Scope reviewed: product, child UX, Guardian UX, learning design, accessibility, audio, architecture, and delivery risk

## Overall assessment

The core idea is strong: Read and Write are separate skills, practice requires real recall, technical failures do not punish the child, and rewards remain predictable. The current document is a solid product and interaction specification, but it is not yet a complete visual design and its original V1 scope combines three products:

1. a preschool word-learning app;
2. a cross-account biometric key-management system;
3. an eight-world content and reward platform.

The first executable milestone must validate the learning loop before the other two systems can delay or distort it.

## Phase 1 — Critical

### Learning evidence

- `Map the Word` may be used only for Write study. Read begins with a visible word and silence; no target audio plays before the child's first independent response.
- Record `studyExposed`, `firstIndependentAttempt`, `unaidedRetry`, `feedbackExposed`, `guidedRetry`, `helped`, `technicalRetry`, and `recognitionUncertain` separately.
- Only the first valid attempt before feedback contributes strong mastery evidence and strict Guardian accuracy. The child-facing Accuracy Star may additionally allow one first-answer miss followed immediately by one valid, unaided correct retry; that reward grace never rewrites mastery evidence.
- After one independent retry, provide the correct model before a guided retry; do not reinforce the same wrong response three times.
- A guided success earns completion feedback but not independent mastery.

### Review capacity

- Treat New counts as daily maximums, not guaranteed quotas.
- Due Review cannot be displaced by New.
- Same-session problem words may replace only not-yet-due Review items.
- Reduce New automatically when Review debt exceeds the attention budget.

### Ambiguous prompts

- An isolated sound is not always a unique spelling prompt (`right/write`, `one/won`, `sea/see`).
- Parent input stays deliberately simple: every newly added word uses the canonical isolated teacher pronunciation, including homophones and heteronyms.
- The Parent UI does not offer a pronunciation picker or contextual-sentence editor. Legacy contextual metadata remains readable only for snapshot compatibility.

### Timing and stars

- Read timing begins when the word becomes visible and the recorder is ready; it ends at detected speech onset.
- Write timing begins after the first prompt, pauses during replay, and never resets.
- Persist first-stroke latency, active-stroke time, and idle time separately.
- Build separate pace baselines by mode, device class, input method, and word length.
- Pace is a comfortable personal band, not “faster is always better.” Accuracy must pass first.
- Calibration attempts with valid timing can earn Pace; after calibration, only the slow side receives 25% grace. The too-fast side remains strict.
- A technical retry never affects accuracy, pace, stars, or the scheduler.

### Child-facing hierarchy

- The World Lobby has two dominant actions only: `Read` and `Write`.
- Read uses a word + mouth/microphone visual; Write uses a speaker + handwriting-line/pencil visual.
- Quest backgrounds become visually quiet behind the task surface.
- Live numeric points are removed from the question screen; the final score is revealed at the end.
- Results reveal in one sequence: completion, stars, score, collectible, then optional world unlock.
- `Parents` uses a normal tap to open the math Parent Gate. Results Replay is a real button that starts same-mode Practice Again.

### Blocking and recovery states

Design explicit flows for:

- empty New Pool;
- no Review due;
- microphone permission denied;
- unavailable recognition model;
- excessive noise or wrong speaker;
- voice-template mismatch;
- muted audio;
- interrupted quest;
- sync pending or failed.

Technical states must always have a finite escape path; voice matching cannot create an infinite retry loop.

## Phase 2 — Refinement

- Produce independent iPhone 17 Pro Max landscape layouts; do not shrink the iPad layout.
- On Write, the canvas owns the center, audio and one-tap `?` use the prompt rail, Done uses the action edge, and a compact tool box selects Pencil, Chalk, Brush, or Eraser. Ink stays black, Undo is omitted, the local eraser is 4× the active pen width, and Clear is immediate because the child explicitly chose a whole-canvas action.
- Reduce Guardian Today to profile switch, Read/Write cards, Manage Words, and one Needs Attention summary.
- Manage Words uses one-word Return-to-add, local Camera/Photo OCR review, a newest-first queue, and single/bulk delete with Undo. V1 never auto-adds Grade or smart-fill words.
- Unify terms: `Guardian`, `Read`, `Write`, and one public memory-state vocabulary.
- Define a complete token table: values for color, spacing, typography, radii, shadows, motion, layout, audio, and states.
- Define a World Pack contract: task-safe zone, motion budget, emergency variant, audio palette, and contrast thresholds.
- Use a neutral sonic logo on Profile Picker, then a short world sting after profile selection.

## Phase 3 — Polish

- Keep frequent correct feedback under one second and reserve longer animation for quest completion.
- Add haptic semantics for Done, correct, technical retry, star reveal, and world unlock.
- Test audio fatigue by playing two complete quests per world on real iPhone and iPad speakers.
- Do not automatically invert Kid Worlds in Dark Mode; Guardian Dark Mode needs its own semantic tokens.
- Complete nonblocking empty states for Collection, locked worlds, avatar permission, and claimed rewards.

## Architecture review

### Keep in the Learning Core

- local multi-profile data separation;
- Parent Words and independent Read/Write Pools;
- New/Review scheduling;
- neutral technical retry;
- score, stars, and deterministic rewards;
- local-first storage;
- UUID attempts and a current `WordProgress` snapshot;
- theme tokens and swappable world skins.

### Build later in the final V1 sequence

- same-Apple-ID iCloud sync;
- cross-Apple-ID Guardian sharing;
- encrypted voice-template sync and key rotation;
- full 7/30-day reports;
- the full 60 small rewards and 15 milestones.

### First vertical slice

- one sample Kid Profile;
- three thin, selectable world skins;
- two unmistakable Read/Write entry cards;
- mockable speech and handwriting recognition protocols;
- one Read quest and one Write quest;
- first-attempt event semantics;
- simple due-review prioritization;
- attainable three-star results and one collectible per world;
- local persistence boundary with in-memory implementation for previews and tests.

## Required technical spikes

1. Child ASR under Mandarin-L1 pronunciation and home noise.
2. Child/adult voice-template filtering without blocking the child.
3. Conservative three-state handwriting recognition.
4. iPhone 17 Pro Max landscape writing ergonomics.
5. CloudKit sharing and encrypted key lifecycle threat model.

## Kill criteria

- Incorrect word false acceptance above 2% disables automatic Read scoring.
- Incorrect spelling false acceptance above 2% disables automatic Write scoring.
- Voice filtering rejects the enrolled child above 10% of valid attempts, so it cannot be a gate.
- Any duplicate reward or lost attempt in offline merge testing blocks cloud sync release.
- Cross-account voice-template sync cannot ship without a written threat model, recovery drill, revocation test, and independent security review.
- World asset production must be reduced if it delays the first real-child usability test by more than two weeks.

## What “design complete” means next

Current requirements are versioned in `FOLLOWUP_BUGFIXES_AND_IMPROVEMENTS.md`. Visual design is complete only after the v0.2 physical build proves that:

- the target child distinguishes Read from Write without explanation;
- iPhone handwriting is comfortable for short, medium, and long words;
- listening, checking, valid retry, and technical retry are distinguishable;
- the relaxed recovery and Pace rules reward effort without changing strict Guardian evidence;
- emergency mode does not cause rushing;
- a Guardian can type, scan, review, and delete a list without layout clipping;
- Read help remains hidden until two valid errors, then places a reliable picture beside the word;
- the next-day Theme/Icon unlock is understandable and My Collection lets the child select only earned cosmetics;
- all three worlds preserve task contrast and component placement.
<!-- TADA_BILINGUAL_ZH_START -->

---

<a id="简体中文版"></a>

> **翻译说明：** 英文为默认阅读语言；本文同时保留原始语言文本。如中英文内容存在差异，请以原始语言文本为准。

# Tada Words — 设计审查

> 审查状态：v0.2设备反馈修订正在进行中；物理回归待定
>
> 范围审查：产品、儿童用户体验、Guardian UX、学习设计、可访问性、音频、架构和交付风险

## 整体评估

核心想法很强：Read和Write是独立的技能，练习需要真正的回忆，技术失败不会惩罚孩子，奖励仍然可以预测。当前的文档是一个坚实的产品和交互规范，但它还没有成为一个完整的视觉设计，其原始的V1范围结合了三个产品：

1. 一个学前儿童单词学习应用程序；
2. 跨帐户生物识别密钥管理系统；
3. 一个八个世界的内容和奖励平台。

在其他两个系统延迟或扭曲学习循环之前，第一个可执行里程碑必须验证学习循环。

## 第1阶段——关键

### 学习证据

- `Map the Word`只能用于Write学习。Read以一个可见的单词和沉默开始；在儿童第一次独立回应之前，不会播放目标音频。
- 分别记录 `studyExposed`、`firstIndependentAttempt`、`unaidedRetry`、`feedbackExposed`、`guidedRetry`、`helped`、`technicalRetry` 和 `recognitionUncertain`。
- 只有在反馈之前的第一次有效尝试才能提供强大的掌握证据和严格的Guardian准确性。面向儿童的准确性星还可以允许一次第一次答案错误，然后立即进行一次有效的、无助的正确重试；这种奖励恩典永远不会重写掌握证据。
- 在进行一次独立重试后，在引导重试之前提供正确的模型；不要重复三次强化相同的错误回复。
- 受指导的成功获得完成反馈，但不获得独立掌握。

### 审查能力

- 将新计数视为每日最大值，而不是保证的配额。
- 到期审查不能被新审查取代。
- 同一课程中的问题单词只能替换尚未到期的复习项目。
- 当审核债务超过关注预算时，自动减少新债务。

### 模棱两可的提示

- 孤立的声音并不总是独特的拼写提示（`right/write`，`one/won`，`sea/see`）。
- 家长输入故意保持简单：每个新添加的单词都使用规范的孤立教师发音，包括同音异义词和异义词。
- 父界面不提供发音选择器或上下文句子编辑器。传统上下文元数据仅在快照兼容性方面仍可读取。

### 时机和星星

- Read 计时从单词变得可见并录音机准备就绪时开始；在检测到语音开始时结束。
- Write 时间在第一个提示后开始，在重播期间暂停，并且永远不会重置。
- 分别保持第一击延迟、主动击时间和空闲时间。
- 按模式、设备类别、输入方法和单词长度构建单独的语速基线。
- Pace是一支舒适的个人乐队，不是“速度越快越好”。准确性必须先通过。
- 使用有效时间进行校准尝试可以获得速度；在校准后，只有慢侧获得25%的宽限。太快的侧面仍然严格。
- 技术重试不会影响准确性、速度、星级或调度器。

### 面向儿童的等级制度

- World Lobby只有两个主导行动：`Read`和`Write`。
- Read使用一个单词+嘴巴/麦克风视觉；Write使用一个扬声器+手写线/铅笔视觉。
- 任务背景在任务表面后变得视觉上安静。
- 实时数字分数从问题屏幕中删除；最终分数将在最后显示。
- 结果以一个顺序呈现：完成、星星、分数、可收集物品，然后是可选的世界解锁。
- `Parents`使用普通按键打开数学Parent Gate。结果Replay是一个实际按钮，可以启动相同模式Practice Again。

### 阻止和恢复状态

为以下内容设计明确的流程：

- 空荡荡的新游泳池；
- 没有待评审；
- 麦克风权限被拒绝；
- 不可用的识别模型；
- 噪音过大或扬声器错误；
- 语音模板不匹配；
- 静音音频；
- 中断的任务；
- 同步待定或失败。

技术状态必须始终有一个有限的逃逸路径；语音匹配不能创建无限的重试循环。

## 第2阶段——完善

- 生成独立的iPhone 17 Pro Max景观布局；不要缩小iPad布局。
- 在Write上，画布拥有中心、音频和一键`?`使用提示轨道，Done使用动作边缘，一个紧凑的工具箱选择铅笔、粉笔、画笔或橡皮擦。墨水保持黑色，忽略撤销，本地橡皮擦是活动笔宽度的4倍，清除立即生效，因为子组件明确选择了一个整个画布的动作。
- 将 Guardian Today 减少到个人资料切换、Read/Write 卡片、管理单词和一个需要关注的摘要。
- Manage Words使用单字返回添加、本地相机/照片OCR审查、最新优先队列和带有撤销功能的单个/批量删除。V1从不自动添加等级或智能填充单词。
- 统一术语：`Guardian`、`Read`、`Write`和一个公共记忆状态词汇。
- 定义一个完整的代币表：颜色、间距、排版、半径、阴影、运动、布局、音频和状态的值。
- 定义一个World Pack合同：任务安全区、运动预算、紧急变体、音频调色板和对比度阈值。
- 在Profile Picker上使用中性的声学标志，然后在选择配置文件后使用一个简短的世界刺痛。

## 第3阶段——抛光

- 保持频繁的正确反馈在不到一秒钟内，并为完成任务保留更长的动画。
- 为Done添加触觉语义，纠正、技术重试、星辰揭示和世界解锁。
- 通过在真实的iPhone和iPad扬声器上在每个世界播放两个完整的任务来测试音频疲劳。
- 不要在暗色模式下自动反转Kid Worlds；Guardian 暗色模式需要自己的语义标记。
- 完成收集、锁定世界、头像权限和领取奖励的非阻塞空状态。

## 建筑审查

### 保持在学习核心中

- 本地多配置文件数据分离；
- 父词和独立Read/Write池；
- 新/审查排程；
- 中立的技术重试；
- 分数、星星和确定性奖励；
- 本地优先存储；
- UUID尝试和当前的`WordProgress`快照；
- 主题代币和可交换的世界皮肤。

### 在最终V1序列的后面构建

- 相同 Apple ID 进行同步；
- 跨 Apple ID 共享；
- 加密语音模板同步和密钥旋转；
- 完整的7/30天报告；
- 完整的60个小奖励和15个里程碑。

### 第一个垂直切片

- 一个样本Kid Profile；
- 三种薄而可选择的世界皮肤；
- 两张不可辨别的Read/Write入场卡；
- 可模擬的语音和手写识别协议；
- 一个Read任务和一个Write任务；
- 第一次尝试事件语义；
- 简单的到期审查优先级；
- 在每个世界都能获得可实现的三星级结果和一个可收集的物品；
- 具有内存实现的本地持久性边界，用于预览和测试。

## 所需的技术峰值

1. 儿童ASR在普通话-L1发音和家庭噪音下。
2. 儿童/成人语音模板过滤，不会阻止儿童。
3. 保守的三州手写识别。
4. iPhone 17 Pro Max 景观书写人体工程学。
5. CloudKit共享和加密密钥生命周期威胁模型。

## 杀死标准

- 超过2%的错误单词错误接受会禁用自动Read评分。
- 拼写错误、错误接受率超过2%将禁用自动Write评分。
- 语音过滤器在有效尝试次数的10%以上时拒绝注册的儿童，因此它不可能是一个门户。
- 任何重复奖励或在离线合并测试块中丢失的尝试都会阻碍云同步发布。
- 如果没有书面威胁模型、恢复演习、撤销测试和独立的安全审查，跨帐户语音模板同步就无法发布。
- 如果世界资产生产推迟第一个真正的儿童可用性测试超过两周，就必须减少资产生产。

## 接下来“设计完成”意味着什么

当前的要求在`FOLLOWUP_BUGFIXES_AND_IMPROVEMENTS.md`中分版本。只有在v0.2物理构建证明以下内容后，视觉设计才为完成：

- 目标儿童在没有解释的情况下区分Read和Write；
- iPhone手写适合短、中和长单词；
- 监听、检查、有效重试和技术重试是可区分的；
- 放松的恢复和速度规则奖励努力，而不改变严格的Guardian证据；
- 紧急模式不会导致匆忙；
- a Guardian可以输入、扫描、查看和删除列表，无需布局剪裁；
- Read帮助保持隐藏状态，直到出现两个有效的错误，然后在单词旁边放置一张可靠的图片；
- 第二天主题/图标解锁是可以理解的，我的收藏让孩子只能选择获得的化妆品；
- 三个世界都保留了任务对比和组件放置。
