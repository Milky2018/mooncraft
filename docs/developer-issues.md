Agents do not edit this. This file is maintainable by human developers.

- [ ] Why `/js/debug/` instead of `/js/release/`
- [ ] React.ts frontend as backup
- [x] Persist a workspace snapshot per project or per run, instead of treating workspace_path as the source of truth.
- [x] Hydrate that snapshot into a temp directory before each Codex run.
- [x] Run Codex against the hydrated temp workspace.
- [x] Save the resulting workspace back after the run, whether success or failure.
- [ ] Keep codex_thread_id, but also persist the initial project brief explicitly so you can recover if the session ever becomes unusable.
- [ ] Now it is hard coded template.
- [ ] Add a real durability smoke test: first run, delete the canonical workspace/, send a follow-up message, and verify the run hydrates from workspace.tar, validates, and refreshes preview.