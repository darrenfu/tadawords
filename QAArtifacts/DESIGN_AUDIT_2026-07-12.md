# Tada Words design audit follow-up

This follow-up records the implementation state after the 2026-07-12 visual audit. The original Phase 1 through Phase 3 source issues are resolved. Physical-device and real-child acceptance remain open.

The active `v0.2` branch supersedes the original three-World screenshots with
eight World implementations, richer pose-aware mascot faces, a Profile-first
last-played confirmation, locked treasure artwork, treasure avatars, and a
four-tool/12-color Write palette with a local eraser. The original screenshots
remain baseline evidence; the fresh 2026-07-13 Phase 1 captures are the current
simulator visual evidence.

## Current verdict

The V1 child hierarchy is implementation-complete. Read and Write use separate shapes, icons, and interaction rhythms. Each World has its own scene, reward catalog, progression, and audio identity. Guardian screens use a calmer information hierarchy.

The owner approved one focused Pre-K Phase 1 refinement on 2026-07-13. It is now implemented and simulator-reviewed. Further visual changes still require a failed observation from the target child, VoiceOver, physical child-landscape and parent-route rotation, real input devices, or device speakers.

## Approved Pre-K Phase 1 — 2026-07-13

- The remembered Profile card has a static 1.03× emphasis and higher stacking priority. Other children are neither dimmed nor animated.
- iPhone landscape keeps labeled `Kids` on the left and groups icon-only `Worlds`, `Calendar`, and `Badge` in a translucent dock. Each icon has a 48-point visual circle inside a 72-point touch frame. iPad retains labels.
- Lobby mascots use 72/104 points; Read mascots use 80/104 points; Result mascots use 68/104 points for compact/regular layouts.
- The regular Read card is 560–760 points wide and uses a 112-point target word. Compact iPhone keeps its 78-point word so the microphone remains comfortably separated.
- Result reward and Replay emphasis use 96/144 points for compact/regular layouts.
- All new scale values live in `TadaChildScaleTokens`; the compact utility interaction lives in `TadaLobbyUtilityButtonStyle`. No quest logic, Write canvas structure, or World palette was changed.
- Fresh iPhone 17 Pro Max and iPad Pro 13-inch (M5) captures show no clipping, card overlap, dock crowding, or cross-World color leakage. The focused presentation test plus the full 480-test suite pass, and both LocalQA builds pass.

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
- New Kid errors use the shared inline-error component
- Handwriting accessibility copy says finger on iPhone and finger or Apple Pencil on iPad
- The app supports left-handed Write controls, Reduced Sound, and Calm Rescue

## World and reward system

| World | Visual identity | Reward scope |
|---|---|---|
| Moonpetal Kingdom | Original fairy-tale princess atmosphere | 20 small rewards and five milestones |
| Build-It Bay | Original engineering vehicle and construction atmosphere | 20 small rewards and five milestones |
| Paws & Pines | Original animal and forest atmosphere | 20 small rewards and five milestones |
| Dino Discovery | Original jungle dinosaur and fossil exploration | 20 small rewards and five milestones |
| Firehouse Heroes | Friendly firehouse and rescue atmosphere without alarm imagery | 20 small rewards and five milestones |
| Brickwork City | Original colorful block-building atmosphere with no commercial toy branding | 20 small rewards and five milestones |
| Frostlight World | Original snow, crystal, and aurora atmosphere | 20 small rewards and five milestones |
| Coaster Carnival | Original roller-coaster and night-carnival atmosphere | 20 small rewards and five milestones |

Rewards never cross World boundaries. A same-day Read+Write Double Quest unlocks
one new World and one animal icon on the following local day. Collection shows
25 distinct icons per World even while locked; collected treasures can become
Profile avatars without replacing the source photo.

## Historical screenshot evidence

The Phase 1 screenshot set covered:

- iPhone last-played Profile, Moonpetal Lobby, Read, and Result
- iPad last-played Profile, Moonpetal Lobby, Paws Read, and Result

The temporary Phase 1 and pre-refinement image files were removed by the
Issue #114 repository cleanup after the audit conclusions were recorded here.

Headless simulator screenshots can store a rotated or letterboxed framebuffer even when the built orientation declarations are correct. Do not crop those images and treat them as full-screen rotation evidence.

## Physical visual acceptance still required

- On a physical iPhone 17 Pro Max, verify child routes in both Landscapes and Parents in Portrait plus both Landscapes; reject Upside Down
- On a physical iPad, verify child routes in both Landscapes and Parents in all four orientations
- Exit Parents while portrait and verify Profile/Lobby immediately restores landscape; confirm no keyboard clips Parent Gate or Word Manager
- Walk every child and Guardian route at accessibility Dynamic Type sizes
- Complete Read and Write with VoiceOver and confirm announcements do not overlap
- Test Reduce Motion during navigation, feedback, Rescue, and reward reveals
- Test finger, Apple Pencil, palm contact, and left-handed controls
- Run a short session with the target child and observe independent navigation and reward appeal

## Design change policy for Device Alpha

Only change the visual system after a failed acceptance observation identifies the child, device, route, and consequence. Preserve learning evidence, retry rules, timing, scoring, review, and mastery while adjusting presentation.
