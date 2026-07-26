# Implementation and verification

[Back to module index](README.md)

For a bug, add a failing regression test before the fix when practical. Do not
expand scope silently; create a related Issue for adjacent work.

Before a PR becomes ready for human review, run:

1. strict formatting and static checks;
2. Swift unit and integration tests;
3. relevant regression tests;
4. iPhone simulator build and critical E2E;
5. iPad simulator build and critical E2E;
6. signed LocalQA installation on at least one physical iPhone and one physical
   iPad when devices and signing are available;
7. per-device launch smoke tests and relevant automated device tests.

For a true documentation or internal-automation-only batch that cannot affect
app runtime, signing, persistence, or packaged content, record the simulator
and physical-device rows as not applicable with a concrete rationale. This
exception is forbidden if the diff changes any app or LocalQA version/build
metadata, source or generated Plist, `project.yml`, generated Xcode project,
entitlement, resource, or other package input. Do not mutate devices merely to
satisfy an irrelevant checklist. Any such metadata/package change, as well as
any app/runtime/platform change, keeps the applicable simulator and signed
one-iPhone-plus-one-iPad gates.
