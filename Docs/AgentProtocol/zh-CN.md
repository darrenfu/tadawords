# Tada Words Agent 交付协议（简体中文）

[返回模块索引](README.md) · [英文权威规则](../../AGENTS.md)

本文是操作指南；英文根规则及英文模块具有最终解释权。

## 核心原则

- 每个 Issue/PR 使用独立 branch、worktree、rollback boundary 和唯一
  writer，并持有 `pr-writer` lease。
- 不得擅自卸载 App、清除数据、重置隐私、更换 Apple Account、签名团队
  或证书。
- source、simulator、signed artifact、install、device automation、人工验收、
  TestFlight 和 App Store 是不同的证据状态。
- 常规工作不使用 subagent；复杂调查最多两个直接、非嵌套、只读
  subagent。
- 第一次 context compaction 时写不超过 2 KB 的 checkpoint，然后换新
  session。HEAD 和环境不变时复用证据，不为状态汇报重跑。

## R0–R4 风险分级

| 等级 | 范围 | PR 门禁 | 真机 |
|---|---|---|---|
| R0 | 不影响 App package/runtime 的文档或内部自动化 | 相关 lint 和 changed-path tests | 不需要 |
| R1 | 纯逻辑、算法、确定性状态机 | focused unit/integration；仅 linkage 改变时做代表性 simulator build | 不需要 |
| R2 | 普通 SwiftUI、布局、动画、音频表现 | focused tests 和相关 iPhone/iPad simulator | 最多一次代表性体验检查 |
| R3 | Camera、Speech、Photos、Pencil、权限、签名邻近逻辑、持久化迁移 | 受影响的自动化和 simulator | 只测受影响设备类别；跨设备才两台 |
| R4 | 不可变 release candidate、Family Sync、TestFlight/App Store | `make check-rc`、精确 artifact identity 和完整发布门禁 | 批准的 iPhone + iPad |

若 diff 修改 App/runtime code、package resources、entitlements、源或生成的
Plist、`project.yml` 或生成的 Xcode settings，则不能声明 R0。

普通 R0–R3 PR 不因“存在一个 PR”而升级 marketing version 或 build。
只有 R4 promotion 或 owner 明确要求 versioned artifact 时才预留版本。

## 检查与证据

- 开发阶段：`make check-changed`
- 普通 PR：`make check-pr`
- R4、定时验证或明确 final audit：`make check-rc`

昂贵的 R2–R4 验证前先 freeze scope。证据绑定完整 commit SHA、tier、
command、environment 和必要的 artifact identity。新 commit 只使旧 HEAD
证据失效，不会把低风险 PR 自动升级成 R4，也不要求重跑无关门禁。

使用共享资源前，通过 `Scripts/delivery-lease.py` 获取对应的
`heavy-xcode`、`signing-archive`、`iphone`、`ipad` 或 `testflight` lease。
R4 优先只构建/导出一次，并在 provisioning 覆盖时把同一 artifact 依次
安装到两台批准设备。

## PR 与合并

一个 batch 只开一个 draft PR，并用单独的 `Closes #N` 行关联 Issue。
记录 tier、完整 HEAD、适用证据、限制和 rollback；只有存在 versioned
artifact 时才记录版本/build。

合并前重新获取 PR，验证 ready、mergeable、clean、直接指向 `main`、
非 stacked、exact HEAD、base OID、PR body SHA-256、
`closingIssuesReferences`、适用检查、blocker、review 和目标环境。

唯一允许的自动合并入口是
`Automation/issue-agent/issue_agent.py guarded-merge`。禁止直接 merge、
admin bypass、update branch、rebase 或 `git push main`。远端
`refs/heads/agent-leases/merge-critical` 保护合并关键元数据。GitHub 对 PR
metadata 没有 CAS，因此短暂关键区仍有 trusted-operator boundary。

合并后必须 fetch `origin/main`，核对 tested HEAD、base parent、merged
tree、body digest、closing set 和 Issue 结果。PR 仅关闭但未合并不算完成。

破坏性儿童数据操作、凭据/认证、不可逆 provider/account 变更、未解决的
安全/隐私/支付决策、模糊产品行为或测试 artifact 之外的环境必须停止并
交由人工确认。
