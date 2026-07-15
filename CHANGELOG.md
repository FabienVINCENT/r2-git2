# Changelog

All notable changes to r2-git2 are documented here. The section for each released version is
also shown in-app by Sparkle when an update is offered. Format loosely follows
[Keep a Changelog](https://keepachangelog.com/); versions follow [SemVer](https://semver.org/).

## [Unreleased]

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
