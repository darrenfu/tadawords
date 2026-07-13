# Tada Words design audit follow-up

This follow-up records the implementation state after the 2026-07-12 visual audit. The original Phase 1 through Phase 3 source issues are resolved. Physical-device and real-child acceptance remain open.

## Current verdict

The V1 child hierarchy is implementation-complete. Read and Write use separate shapes, icons, and interaction rhythms. Each World has its own scene, reward catalog, progression, and audio identity. Guardian screens use a calmer information hierarchy.

The remaining work is observation, not another speculative polish pass. Test the app with the target child, VoiceOver, physical landscape rotation, real input devices, and device speakers before changing layout or motion again.

## Resolved Phase 1 findings

- V1 forces Light appearance at the app root, including bootstrap and Guardian routes
- Parent Gate supports compact landscape height, scrolling, numeric input, 44-point controls, and clear errors
- Results display **Not scored** when technical Move On has no independent accuracy evidence
- Read, Write, and result feedback announce through VoiceOver and move focus to the relevant state
- Saving overlays hide the underlying Guardian destination from accessibility
- Quest chrome, Lobby, blocked states, and loading states provide compact and Dynamic Type-safe layouts
- Guardian Today now orders Profile, Pools, Quick Add, Needs Attention, Calendar, then settings
- Child and Guardian secondary controls meet the 44-point minimum target

## Resolved Phase 2 findings

- iPad Read uses a wider task card without breaking compact layouts
- Result metric captions use semantic typography and secondary surface contrast
- Import Report keeps **Done** as the primary action and renders **Add more** as secondary
- Parent settings use **Rescue timer**, matching the child experience
- Write controls share one disabled appearance
- Compact Lobby shows fewer reward previews and an aggregate count
- Quest chrome, action rails, state surfaces, captions, touch targets, and disabled controls use shared design tokens

## Resolved Phase 3 findings

- Calendar, bootstrap, loading, blocked, empty, and error routes use a shared child state component
- Child and Guardian navigation transitions honor Reduce Motion
- Parent Gate no longer repeats its footer label
- New Player errors use the shared inline-error component
- Handwriting accessibility copy says finger on iPhone and finger or Apple Pencil on iPad
- The app supports left-handed Write controls, Reduced Sound, and Calm Rescue

## World and reward system

| World | Visual identity | Reward scope |
|---|---|---|
| Moonpetal Kingdom | Original fairy-tale princess atmosphere | 20 small rewards and five milestones |
| Build-It Bay | Original engineering vehicle and construction atmosphere | 20 small rewards and five milestones |
| Paws & Pines | Original animal and forest atmosphere | 20 small rewards and five milestones |

Rewards never cross World boundaries. The World Picker unlocks additional Worlds after 3 and 8 Today Quest completions. Collection shows permanent small rewards and derived milestone progress.

## Current screenshot evidence

- `QAArtifacts/Final-2026-07-12/iPhone17ProMax-first-run.png`
- `QAArtifacts/Final-2026-07-12/iPadPro13-first-run.png`
- `QAArtifacts/VisualAccessibility-2026-07-12/iPhone17ProMax-launch.png`
- `QAArtifacts/VisualAccessibility-2026-07-12/iPadPro13-launch.png`
- `QAArtifacts/VisualAccessibility-2026-07-12/iPhone17ProMax-system-dark-app-light.png`

Headless simulator screenshots can store a rotated or letterboxed framebuffer even when the built orientation declarations are correct. Do not crop those images and treat them as full-screen rotation evidence.

## Physical visual acceptance still required

- Launch and rotate a physical iPhone 17 Pro Max in Landscape Left and Landscape Right
- Launch and rotate a physical iPad in both landscape directions
- Verify no route enters Portrait and no keyboard clips Parent Gate or Quick Add
- Walk every child and Guardian route at accessibility Dynamic Type sizes
- Complete Read and Write with VoiceOver and confirm announcements do not overlap
- Test Reduce Motion during navigation, feedback, Rescue, and reward reveals
- Test finger, Apple Pencil, palm contact, and left-handed controls
- Run a short session with the target child and observe independent navigation and reward appeal

## Design change policy for Device Alpha

Only change the visual system after a failed acceptance observation identifies the child, device, route, and consequence. Preserve learning evidence, retry rules, timing, scoring, review, and mastery while adjusting presentation.
