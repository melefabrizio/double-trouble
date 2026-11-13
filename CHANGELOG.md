# Changelog

## 1.0.1 — 2026-11-13

### Fixed

- Launchers pinned to the Dock no longer turn into a question mark after a
  while. Dragging a launcher out of the window used to pin a temporary copy
  kept in `~/Library/Caches`, which macOS deletes when it cleans its caches.
  Dragging now pins the launcher in `/Applications` itself, so later changes
  to its color or badge also reach the Dock.

  If a launcher in your Dock already shows a question mark, or was pinned
  with 1.0, remove it from the Dock and drag it in again.

### Changed

- Launchers are dragged from the large icon in the environment's details.
  Rows in the sidebar can no longer be dragged.

## 1.0 — 2026-11-06

Initial release.
