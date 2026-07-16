# Kid UI copy matrix — v0.6.0

This matrix inventories the visible English copy in Kid-facing routes on the
`v0.5.1` baseline and records its `v0.6.0` disposition. VoiceOver labels and
hints remain complete when visible copy moves to a visual semantic.

| Route / state | Baseline visible copy | Classification | v0.6.0 treatment |
|---|---|---|---|
| Profile Picker header | `Tada Words`, `Who’s playing?`, `Tap your picture to begin.` | Brand/header essential; instruction VoiceOver-only | Keep brand and question; remove tap instruction. |
| Profile cards | Profile name, `Last played`, World name | Name essential; status/world replace with visual | Keep name. Use existing scale, border, sparkle, and World motif badges; preserve full card accessibility label. |
| Profile overflow | `Swipe to see more kids` | Replace with visual | Show the existing horizontal-arrow symbol only in the `ViewThatFits` overflow fallback; keep the phrase as its accessibility label. |
| New Kid card | `New Kid`, `Nickname & age` | Identity essential; explanation VoiceOver-only | Keep `New Kid` and plus symbol; move setup detail to the existing accessibility hint. |
| New Kid setup | `Make Your Profile!`, nickname/age questions, validation, saving/error, `Let’s Play!` | Essential form/recovery copy | Keep unchanged. A child cannot infer form requirements or recovery from symbols alone. |
| Lobby profile control | `Kids` | Replace with meaningful name | Show the active profile name with the profile symbol; VoiceOver announces the current profile and action. |
| Lobby welcome | `Ready, <name>?`, `Choose today’s quest.` | Redundant / VoiceOver-only | Remove. Profile name remains in the profile control; two dominant quest cards are self-evident. |
| Lobby utilities | `Worlds`, `Calendar`, `Badge` | Replace with visual in compact layout; short labels acceptable in regular layout | Keep the established globe/calendar/medal dock on compact height and full accessibility labels. Regular iPad labels remain for large-screen clarity. |
| Lobby quest cards | `Read`, `Write`, `See it. Say it.`, `Hear it. Write it.` | Mode essential; subtitles redundant | Keep `Read` / `Write` and distinct marks. Remove instruction subtitles. Practice state uses replay, points, and stars; blocked recovery title stays visible. |
| Read idle | `Read it aloud`, target word, `Tap to read` | Target essential; two instructions redundant | Keep only target word and microphone visual. The microphone exposes `Start listening` plus a hint to VoiceOver. |
| Read active | `Checking microphone…`, `Listening…` | Essential state feedback | Keep visible only while those states are active; waveform and color are not the sole signal. |
| Read help/retry | `Hear it`, retry/permission/technical messages, `Move On` | Essential ambiguity/recovery copy | Keep unchanged. Help appears only after the existing policy allows it. |
| Handwriting idle | `Hear`, `Write the word you hear`, letter slots, pen names, `Erase`, `Clear`, `Done` | Slots essential; Hear/instruction/eraser/Done replace with visual; Clear essential destructive label | Use speaker, mascot/canvas, tool, eraser, trash + `Clear`, and 72 pt checkmark. Keep all labels/hints in accessibility. |
| Handwriting active/retry | guided spelling, `Checking`, feedback, picture hint, `Move On` | Essential state/recovery copy | Keep guided/state/recovery meaning. The checkmark changes to hourglass and VoiceOver says `Checking`. |
| Spell idle | `Spell the word you hear`, `Hear`, letter slots, A–Z keys, `Delete`, `Done` | Slots/letters essential; instruction/actions replace with visual | Use speaker, backspace, and 72 pt checkmark. Keep `Delete last letter` and `Done` accessibility contracts and stable identifiers. |
| Spell guided/retry | example spelling and retry message | Essential state copy | Keep unchanged. |
| Result header | `Quest complete` / `Practice complete` plus explanatory sentence | VoiceOver-only | Mascot + checkmark tell the visible story; the complete summary remains the accessibility label and announcement. |
| Result achievement | `Stars earned`, star row, `Complete`, accuracy, pace, points | Star heading redundant; score/progress essential | Remove the heading; keep stars, score, accuracy, and pace. |
| Result reward | `New collectible` / `Practice power-up`, reward name/status/detail | Category/detail redundant; reward identity essential | Keep the reward/power-up symbol and name. Remove repeated category and follow-up sentence; preserve the complete result announcement. |
| Result navigation | Replay label, `Back to quests` | Essential ambiguous navigation | Keep both labels. |
| Worlds header/cards | `Choose a World`, global progress paragraph, World name, current/ready/locked status | Header/name/locked progress essential; global/current/ready status replace with visual | Keep title, World names, and locked remaining-day copy. Use checkmark/sparkles for current/available state. |
| Calendar | `Quest Calendar`, profile completion subtitle, month/day/counts | Title/data essential; subtitle redundant | Keep title and calendar data; remove repeated profile sentence. Loading/error/empty recovery copy remains. |
| Collection header/sections | `My Collection`, unlock explanation, section titles/details | Titles essential; explanatory paragraphs redundant | Keep `My Collection`, `My Worlds`, `My Icons`, and themed Treasure title. Remove repeated instructions. |
| Collection World/Icon cards | Item name plus `Using` / `Earned` / `Locked` | Name essential; status replace with visual | Keep names. Use checkmark/sparkle/lock badges, border, grayscale, and opacity; preserve accessibility values and hints. |
| Treasure cards | Treasure name plus `Using as icon` / `Use as icon` / `Locked` | Name essential; status replace with visual | Keep treasure name and existing badge semantic; keep complete accessibility value/hint. |
| Close controls | Visible `Close` | Replace with visual | Use the established `xmark.circle.fill` with `Close` accessibility label and a return hint. |
| Loading, blocked, permissions, technical retry, destructive/recovery | State title, cause, safe recovery action | Essential | Keep unchanged. Visual simplification never hides why the child is blocked or what a parent must do. |

## Accessibility and behavior boundary

- State is never conveyed by color alone: selection, completion, replay, lock,
  listening, checking, and disabled states retain symbols, borders, shapes, or
  visible state text.
- Decorative mascots and scene art remain hidden from accessibility.
- The change does not alter quest state machines, scoring, recognition, audio,
  timing, persistence, rewards, navigation, Reduced Motion, or Reduced Sound.
- Guardian/Parent routes and Audio Issue #13 are explicitly excluded.
