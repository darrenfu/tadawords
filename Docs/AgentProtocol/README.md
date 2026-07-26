# Tada Words agent protocol modules

The root [`AGENTS.md`](../../AGENTS.md) contains the repository authority,
instruction precedence, non-negotiable rules, and task-routing table. This
directory contains the detailed normative protocol.

Read each routed module completely before acting. Rules from multiple selected
modules are cumulative. If two module statements appear to conflict, the root
`AGENTS.md` wins; otherwise stop and request clarification instead of choosing
the weaker rule.

## Modules

1. [Intake and release batches](01-intake-and-batches.md)
2. [Versioning and project generation](02-versioning-and-generation.md)
3. [Implementation and verification](03-verification.md)
4. [Device delivery](04-device-delivery.md)
5. [Pull-request gates](05-pr-gates.md)
6. [Guarded merge and reconciliation](06-guarded-merge.md)
7. [Human gates and policy rollback](07-human-gates-and-rollback.md)

## Translation

The [Simplified Chinese translation](zh-CN.md) is provided for convenience.
English remains the default and authoritative protocol when translations
diverge.
