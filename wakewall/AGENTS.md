# WakeWall Agent Guidance

- Read `PROJECT_SPEC.md` before making product, architecture, storage, rendering,
  lifecycle, or UX changes.
- Treat `PROJECT_SPEC.md` as a living specification. Update it when a durable
  decision or important behavior changes, but do not fill it with temporary
  implementation notes.
- Preserve the screen-off fast path and rapid screen-off/on cycling behavior.
- Do not add old-backup compatibility or permanent one-time migration code
  unless the user explicitly requests it.
- Keep the interface minimal and prefer automatic housekeeping over new
  settings.
- After completed development changes, start `flutter build apk --release` from
  this directory without monitoring it unless the user asks for build output.
- After every successful release build, leave the final artifact named
  `WakeWall.apk` and replace `F:\My Drive\WakeWall\WakeWall.apk` using a
  delete-then-copy flow. Verify that the copied APK matches the local build.
  Continue doing this by default until the user explicitly asks to stop.
- Use the verification commands documented in `PROJECT_SPEC.md`.
