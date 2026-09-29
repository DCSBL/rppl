# Agent contributions

Guidance for coding agents (and humans using them) opening pull requests in this repo.

## PR titles

**PR title** must use this format (not necessarily each commit on the branch):

```
<component>(<type>): <short description>
```

This is the reverse of common Conventional Commits (`<type>(<scope>)`). Here the **component** comes first.

### Examples

- `watch(feat): New feature`
- `slang(fix): Make sure this and that`
- `core(refactor): Extract set hold logic`
- `phone(docs): Clarify export flow in PR body`

### Components

Pick the main area the PR touches:

| Component | When to use |
|-----------|-------------|
| `watch` | `RpplWatch` — session, sensors, HealthKit, WC send |
| `phone` | `Rppl` (iOS) — sync receive, list/map/export UI |
| `core` | `RpplCore` — models, detection, file store, pure logic |
| `slang` | Localized copy (`.xcstrings`, wakeboard jargon) |
| `docs` | Markdown docs only |
| `ci` | Hooks, GitHub Actions, lint config |
| `repo` | Cross-cutting or tooling that does not fit above |

Use one primary component. Split unrelated work into separate PRs when possible.

### Types

| Type | When to use |
|------|-------------|
| `feat` | New behavior or capability |
| `fix` | Bug fix |
| `refactor` | Code change without intended behavior change |
| `docs` | Documentation only |
| `test` | Tests only |
| `chore` | Maintenance, deps, housekeeping |

### Commits vs PR title

- **PR title:** follow `<component>(<type>): …` as above.
- **Commits on the branch:** Conventional Commits style is fine (`feat: …`, `fix: …`, or `type(scope): …`). Squash-merge uses the PR title, not individual commit subjects.

## Workflow for agent PRs

1. Run `pre-commit run` (commit-stage hooks) before committing. Fix what it reports.
2. Skip `xcodebuild` (and the `xcode-gate` push hook's build step) when the environment has no Xcode toolchain, such as a Linux cloud agent. Do not bypass hooks with `--no-verify`.
3. Running `swift test` locally is not required when a PR is opened. CI runs it with the proper toolchain and reports the result on the PR.
4. Open the PR, then always subscribe to its activity (CI results, reviews). Fix failures and review comments that are in scope until the PR is green and mergeable.

See also [AGENTS.md](../AGENTS.md) (source management, git) and [CONTRIBUTING.md](../CONTRIBUTING.md) (review bar).
