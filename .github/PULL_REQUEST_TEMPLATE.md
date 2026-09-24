<!--
PR title format: <component>(<type>): <short description>
e.g. watch(feat): New feature · slang(fix): Make sure this and that
See contributions/agent.md for component/type tables.
-->

## Summary

<!-- What changed and why, in 1-3 sentences. -->

## Linear issue

<!-- Link if one exists, otherwise delete this section. -->

## Testing

<!-- e.g. `cd RpplCore && swift test`, `make lint`, manual check on device/simulator. -->

## Checklist

- [ ] Follows layer boundaries (`RpplCore` / `RpplWatch` / `Rppl`) — see AGENTS.md
- [ ] No hard constraints broken (HealthKit save flow, session file deletion timing, one-session-per-day, detection codes as strings, iPhone view-only, OS floor, Water Lock)
- [ ] Wakeboard slang preserved in any touched UI/copy strings
- [ ] Tests added/updated in `RpplCore` for new pure logic
- [ ] Docs updated if behavior/format changed (`Docs/`, `CONTRIBUTING.md`)
