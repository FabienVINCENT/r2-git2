# Changelog

All notable changes to r2-git2 are documented here. The section for each released version is
also shown in-app by Sparkle when an update is offered. Format loosely follows
[Keep a Changelog](https://keepachangelog.com/); versions follow [SemVer](https://semver.org/).

## [Unreleased]

## [1.3.1] - 2026-07-16

### Fixed
- No more ghost lines above/below the popover when its content is small: the transparent
  panel's cached window shadow is now recomputed after every resize, so shrinking to the
  measured content height no longer leaves the old frame's shadow behind.

## [1.3.0] - 2026-07-16

### Fixed
- Popover is now much less transparent: the translucent background gets a dark scrim so the
  content stays readable even over bright/white windows, instead of being washed out.

## [1.2.0] - 2026-07-16

### Added
- PR staleness indicator: PRs open for 3+ days show a "waiting Xd" badge, turning red once a
  week old (drafts excluded).
- Sort options for the PR lists — recent activity (default), CI status (failing first), or
  oldest first — via a new sort button in the filter bar. Bot PRs always stay at the bottom.
- Native notification when one of your PRs receives a review: approved ✅, changes requested 🔁,
  or a review comment 💬 — so you know the review you've been waiting for has landed. A
  re-review notifies again; your own comments on your PR don't.
- PR rows now show the overall review decision as a badge ("approved" / "changes requested").

## [1.1.1] - 2026-07-16

### Fixed
- Popover no longer shows an empty gap above its content (removed `ignoresSafeArea` on the
  translucent background, which extended it into the top safe area).
- Settings window now activates and is brought to the front. As an accessory (menu-bar) app it
  could otherwise slip behind other apps' windows and never return.

## [1.1.0] - 2026-07-16

### Added
- Group followed-repo PRs by repository, under a subheader per repo.
- `CHANGELOG.md`; release notes are now embedded in the Sparkle appcast and the GitHub Release.

### Fixed
- Notifications: "mark as done" now uses `DELETE /notifications/threads/{id}` (removes it from
  the GitHub inbox) instead of `PATCH` (which only marked it read, so it stayed visible on GitHub).
- Requests now bypass URLSession's HTTP cache (`reloadIgnoringLocalCacheData`): GitHub sends
  `Cache-Control: max-age=60` on `/notifications`, so the OS replayed a stale list for ~60s and
  made just-handled notifications reappear on refresh. Conditional caching is still done via ETag.
- "Hide bots" (👥) now also hides dependabot/renovate notifications, not just bot PRs.
- Followed repos: PRs and Actions runs are now fetched independently per repo, so a failure
  fetching one no longer drops the other (a repo's PRs could disappear if its runs call failed).

## [1.0.0] - 2026-07-15

### Added
- Menu-bar app (SwiftUI `MenuBarExtra`) for GitHub PRs, Actions, and mentions.
- Sign in with a classic Personal Access Token, stored in the macOS Keychain.
- Repository auto-discovery with per-repo follow selection.
- "PRs for me" (review-requested / assigned / author) with CI status via GraphQL.
- Open PRs for followed repos; text filter; bot-PR sort & hide.
- GitHub Actions: in-progress runs + recent failures, each dismissable.
- Notifications / mentions with per-item "mark as read".
- Native macOS notifications, menu-bar badge, launch-at-login.
- ETag conditional requests with a rate-limit debug panel.
- Sparkle EdDSA-signed auto-updates and a tag-driven release pipeline.
