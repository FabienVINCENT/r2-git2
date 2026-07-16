# Roadmap

Status of r2-git2. Shipped in **1.0.0**: token auth (Keychain), repo discovery + follow,
PRs-for-me & followed-repo PRs (CI status via GraphQL), Actions (running + recent failures,
dismissable), notifications/mentions (mark-as-read), text filter, bot sort/hide, translucent UI,
native notifications, menu-bar badge, launch-at-login, ETag conditional requests, Sparkle signed
auto-updates + CI/CD release pipeline, app icon.

## v1.1 — Quick wins 🟢
- [x] Release notes in the appcast (`<description>`) + `CHANGELOG.md` → "What's new" on update *(1.1.0)*
- [x] Group followed PRs by repository (per-repo subsections) *(1.1.0)*
- [x] PR staleness indicator ("waiting X days") + sort options (CI / age)
- [x] Notify when one of my PRs receives a review (approved / changes requested / comment)
- [ ] Hide drafts + per-repo notification mute
- [ ] Keyboard shortcuts (open, ⌘F filter, Esc to clear)

## v1.2 — Direct actions 🔵
- [ ] Re-run a failed workflow from the Failures section
- [ ] Approve / merge a PR from its row (with confirmation)
- [ ] Mark all notifications as read

## v1.3 — Reliability 🟣
- [ ] Clear re-auth banner (expired token / missing scope)
- [ ] Handle secondary rate limits (backoff)
- [ ] Tests for the store logic

## v2.x — Distribution & config 🟠
- [ ] Apple notarization (Developer ID) → no more Gatekeeper warning
- [ ] Homebrew cask (`brew install --cask r2-git2`)
- [ ] GitHub Enterprise base-URL setting in the UI
- [ ] Configurable failure window / which sections to show
