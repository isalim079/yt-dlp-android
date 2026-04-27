# Intentionally deferred

The following items are out of scope for the current production-polish pass or are blocked by platform policy:

- **iOS support** — App Store restrictions and entitlement overhead for bundled binaries.
- **Login / YouTube Premium** — No authenticated flows or premium-only formats.
- **In-app video player** — Downloads are file-based only.
- **Download scheduling** — No background job scheduler.
- **Notification on download complete** — No POST_NOTIFICATIONS flow or channels yet.
- **Auto-update yt-dlp binary** — Bundled asset version follows app releases only.
- **Full `AnimatedList` diffing** for the download queue — Current UI uses per-row entrance animations; a full insert/remove `AnimatedList` sync for multi-section lists can be added later if needed.
