<!-- TADA_BILINGUAL_DOC: English is the default reading language. The original source text is preserved for verification. -->
<a id="english-default"></a>

> **Languages / 语言：** **English (default) / 英文（默认）** · [简体中文](#简体中文版)

# Architecture

## Dependency rule

```text
Preview / iOS App
       ↓
Features + Apple Platform + Design System
       ↓
Content + Learning
       ↓
Domain
```

Infrastructure adapters depend on Domain contracts; Domain never depends on infrastructure.

## Module responsibilities

### TadaWordsDomain

- Stable product vocabulary and identifiers.
- Immutable attempt evidence.
- Profile, word, quest, progress, score, and world value objects.
- Protocols for recognition, repositories, clocks, and audio.

### TadaWordsLearning

- Deterministic quest planning.
- Due Review protection and New-cap calculation.
- First-independent-attempt scoring.
- Comfortable personal pace bands.
- Pure reducers that update progress from valid learning evidence.

### TadaWordsContent

- Manual Read and Write word pools with normalization and de-duplication.
- Deterministic daily New-word selection.
- Adapts pool content into Learning quest-planning inputs.
- Durable atomic JSON repositories for profiles, child launch preference, settings,
  pools, attempts, progress, and daily quest history.
- Coordinates child-created profiles so isolated default settings exist before a
  new profile becomes visible.
- Owns the local-first Family Sync coordinator, versioned data manifest, durable
  journal/outbox, crash-safe apply transaction, deterministic merge rules, and
  event-derived projections. Child and Parent writes commit locally before sync.

### TadaWordsGuardianFeatures

- Parent-gated word entry, pool inspection, and daily limits.
- Depends on injected Content stores; owns no recognition or persistence framework.

### TadaWordsDesignSystem

- Primitive, semantic, and component tokens.
- Cross-world component geometry.
- Theme-specific visual surfaces without feature logic.

### TadaWordsFeatures

- Small state machines and SwiftUI views.
- No direct Speech, PencilKit, CloudKit, or crypto calls.
- Dependencies arrive through explicit service protocols.

### TadaWordsApplePlatform

- Apple framework adapters for Domain service contracts.
- No product rules and no feature navigation state.
- Replaceable implementations for audio, speech, handwriting, device security,
  private/shared `CKSyncEngine`, bounded Profile-photo `CKAsset`, and CloudKit
  deletion-ledger transport.

## Clean Code constraints

- Prefer small value types and pure functions.
- One reason to change per type.
- Name business rules in domain language instead of UI language.
- Keep async side effects behind protocols.
- Avoid global singletons and hidden service lookup.
- Technical failures are data, never generic `Bool` values.
- Do not mutate historical attempts; append corrections that reference the original event.
- Add a test before changing scheduler or scoring semantics.
<!-- TADA_BILINGUAL_ZH_START -->

---

<a id="简体中文版"></a>

> **翻译说明：** 英文为默认阅读语言；本文同时保留原始语言文本。如中英文内容存在差异，请以原始语言文本为准。

# 建筑物

## 依赖规则

```text
预览/iOS应用程序
       ↓
功能+苹果平台+设计系统
       ↓
内容+学习
       ↓
域
```

基础设施适配器依赖于域合同；域永远不会依赖于基础设施。

## 模块职责

### TadaWordsDomain

- 稳定的产品词汇和标识符。
- 不可改变的尝试证据。
- Profile，单词，任务，进度，分数和世界价值对象。
- 识别、存储库、时钟和音频的协议。

### TadaWordsLearning

- 确定性任务规划。
- 应付审查保护和新帽计算。
- 第一次独立尝试评分。
- 舒适的个人步速带。
- 从有效的学习证据中更新进度的纯还原器。

### TadaWordsContent

- 手册Read和Write单词库具有归一化和重复删除功能。
- 确定性每日新单词选择。
- 将库存内容调整为学习任务计划输入。
- 用于配置文件、子启动偏好、设置的持久原子JSON存储库，
池子、尝试、进度和每日任务历史记录。
- 协调由孩子创建的配置文件，以便在
新的配置文件变得可见。
- 拥有本地优先的家庭同步协调器、版本数据清单、持久性
日志/出站箱、安全崩溃应用事务、确定性合并规则和事件衍生投影。子节点和父节点在同步前在本地写入提交。

### TadaWordsGuardian特点

- 家长门禁单词输入、池塘检查和每日限制。
- 取决于注入的内容存储库；不拥有任何识别或持久框架。

### TadaWordsDesignSystem

- 原始、语义和组件代币。
- 跨世界组件几何。
- 没有功能逻辑的特定主题视觉表面。

### TadaWordsFeatures

- 小型状态机和SwiftUI视图。
- 禁止直接语音、PencilKit、CloudKit或加密通话。
- 依赖项通过明确的服务协议到达。

### TadaWordsApplePlatform

- 用于域服务合同的 Apple 框架适配器。
- 没有产品规则和没有功能导航状态。
- 可替换的音频、语音、手写、设备安全实现，
私人/共享`CKSyncEngine`，受限Profile-照片`CKAsset`，以及CloudKit删除-账簿传输。

## 清洁代码约束

- 更喜欢小值类型和纯函数。
- 根据类型更改的一个原因。
- 在域语言中命名业务规则，而不是UI语言。
- 将异步副作用保持在协议后方。
- 避免全球单一值和隐藏服务查找。
- 技术故障是数据，而不是通用`Bool`值。
- 不要改变历史尝试；附上引用原始事件的更正。
- 在更改调度器或评分语义之前添加一个测试。
