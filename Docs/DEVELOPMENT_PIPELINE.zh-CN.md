# Tada Words 开发与交付流程

流程已拆分为按任务路由的模块，使 Agent 只加载当前工作需要的规则。
请从 [Agent Protocol 模块索引](AgentProtocol/README.md) 开始；简体中文摘要
见 [Agent 交付协议](AgentProtocol/zh-CN.md)。

R0–R4 风险分级、按 changed path 选择检查、单 writer session、第一次
context compaction checkpoint、证据复用、资源 lease、设备策略和 guarded
merge 均以英文模块为准。
