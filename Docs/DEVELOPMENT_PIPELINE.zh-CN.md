# Tada Words 开发与交付流水线

本文件是 [`../AGENTS.md`](../AGENTS.md) 的中文操作说明。英文
`AGENTS.md` 保存精简且不可绕过的规则；本文件解释日常执行方式。

## 核心变化

```text
Issue 和验收条件
  -> 确定风险等级和唯一 PR writer
  -> 开发期 focused tests
  -> scope freeze
  -> PR gate
  -> guarded merge
  -> nightly integration
  -> 不可变 RC
  -> 一次 archive/export
  -> 所需真机验收
  -> Internal TestFlight / App Store
```

PR 验证回答“这项改动是否可以安全集成”。RC 验证回答“这个精确
artifact 是否可以发布”。两者不再使用同一套默认门禁。

## 风险等级

| 等级 | 典型改动 | PR 证据 | 真机 |
|---|---|---|---|
| R0 | 文档、不会影响 App 的内部自动化 | 相关 lint 和 changed-path tests | 无 |
| R1 | Domain、算法、确定性状态机 | focused + unit/integration；需要时一个代表 simulator build | 无 |
| R2 | 普通 SwiftUI、布局、动画、音效 | focused tests + 相关 iPhone/iPad simulator | scope freeze 后最多一台代表设备体验 |
| R3 | Camera、Speech、Photos、Pencil、权限、持久化迁移 | 相关自动化、simulator、受影响设备 | 只测受影响设备类别 |
| R4 | Family Sync、TestFlight/App Store RC | `make check-rc`、archive、完整适用矩阵 | 默认组一台 iPhone + 一台 iPad |

混合改动取最高等级。R0 不得修改 App/runtime、资源、entitlement、
Plist、`project.yml` 或生成的 Xcode 设置。

## 版本规则

- 普通 R0–R3 PR 不再仅因为“存在一个 PR”就升级营销版本和 build。
- 只有晋升 R4 或 owner 明确要求 versioned artifact 时才预留版本。
- R4 尽量只 archive/export 一次；身份和 provisioning 覆盖两台设备时，
  将同一个 artifact 顺序安装到 iPhone 和 iPad。

## scope freeze

动画、声音、星星计算、文案或验收条件仍在变化时，只跑 focused tests。
不要启动完整 simulator/device/RC gate。

冻结记录至少包含：

```text
Issue / PR
风险等级
完整 HEAD
纳入的验收条件
明确排除项
人工体验检查
R4 artifact 目标
```

冻结后出现新需求，先回到开发状态。完成下一候选版本后再验证一次；
不要每改一次就立即重跑全量。

## 唯一 writer 和资源租约

worktree 隔离不等于 writer 隔离。同一个 PR/branch 只能有一个写 session。

使用：

```sh
python3 Scripts/delivery-lease.py acquire \
  --kind pr-writer --resource PR-141 --owner SESSION_ID \
  --issue 141 --branch "$(git branch --show-current)" \
  --head "$(git rev-parse HEAD)" --ttl-seconds 14400
```

共享资源类型：

- `pr-writer`
- `heavy-xcode`
- `signing-archive`
- `iphone`
- `ipad`
- `testflight`

同一台 Mac 同时最多一个 heavy UI/Xcode lane。Family Sync 由一个
coordinator 同时控制两台设备和完整证据顺序。

## 三种检查

开发中：

```sh
make check-changed BASE_REF=origin/main TEST_FILTER=相关测试过滤器
```

普通 PR：

```sh
make check-pr BASE_REF=origin/main
```

R4 或 nightly：

```sh
make check-rc
```

Issue Agent 和 release-preflight 没有相关路径变更时，普通功能 PR 不再
重复跑它们。旧的 `make check` 兼容入口等同于 `check-pr`。

## evidence reuse

证据绑定完整 commit SHA、风险等级、命令、环境和 artifact 身份。
HEAD 和环境不变时，status 只读取已有 evidence manifest，不重跑测试、
构建、签名、安装或审计。

新 commit 使旧 HEAD 的证据失效，但只重跑新等级适用的门禁；不会把
R1/R2 PR 自动提升为 R4。

## session 和 token

- 一个 Issue/PR 使用一个 root session。
- routine 工作不使用 subagent。
- 复杂只读调查最多两个直接 subagent；禁止嵌套和并发 writer。
- 第一次 compaction 时写不超过 2 KB 的 checkpoint，结束旧 session，
  用新 session 继续。
- routine/unattended 默认 Terra medium；复杂 bug 可用 Terra high；
  架构、同步、安全、签名和 RC 决策才使用 Sol high。
- Ultra 只允许极少数有界的最终审计，不能作为后台默认。

checkpoint 包含：

```text
Issue / PR
worktree、branch、HEAD
writer/resource leases
changed files
已完成检查和 evidence 路径
剩余验收条件
blocker 和下一条精确命令
```

## 真机规则

- 默认验收组仍是一台 iPhone + 一台 iPad。
- 备用设备未经 owner 明确批准不得启用。
- Camera 通常只需要 iPhone；Pencil 通常只需要 iPad。
- 普通动画/声音在两种 simulator 覆盖布局后，只需一台代表设备做体验。
- 只有跨设备行为和 R4 才默认需要两台真机。
- 不卸载、不清数据、不重置权限、不切换 Team/bundle。

## 下一批十个 PR 的指标

记录：

- 首次提交到 merge 的时间；
- 每个 PR 的全量测试次数；
- 真机安装和人工分钟数；
- stale evidence 重跑次数；
- compaction 和工具调用数；
- focused、PR、nightly、真机各自发现的唯一缺陷。

只有采用新流水线后，heavy-Xcode 排队仍超过交付周期 30%，才考虑增加
第二台 Mac。
