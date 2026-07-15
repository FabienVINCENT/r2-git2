# Changelog

All notable changes to r2-git2 are documented here. The section for each released version is
also shown in-app by Sparkle when an update is offered. Format loosely follows
[Keep a Changelog](https://keepachangelog.com/); versions follow [SemVer](https://semver.org/).

## [Unreleased]

### Added
- Group followed-repo PRs by repository, under a subheader per repo.
- `CHANGELOG.md`; release notes are now embedded in the Sparkle appcast and the GitHub Release.

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
