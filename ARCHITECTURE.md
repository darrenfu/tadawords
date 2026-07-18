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
