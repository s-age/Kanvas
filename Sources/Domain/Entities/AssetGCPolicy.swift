import Foundation

/// How long a canvas-image sidecar asset must sit untouched on disk before the orphan GC may sweep
/// it. "How recent is too recent to reclaim" is a domain/safety decision, not a storage detail — so
/// the value has a Domain home rather than a hard-coded constant inside the store. The store is
/// *told* the cutoff (`now - gracePeriod`) and only enumerates files older than it; it never picks
/// the number.
///
/// The grace period closes the one cross-process race the save-before-mutate ordering creates: when
/// another process (the MCP server) is mid-`add`, it has written the asset bytes but not yet
/// committed the `CanvasImage` that references them. A sweep that ran in that window would see the
/// file as unreferenced and delete a live-to-be asset. Excluding files younger than the grace
/// period keeps a just-written asset off-limits until its reference is certainly visible. A true
/// orphan (a crashed `mutate`, or a delete-then-quit from a past session) is always older than the
/// window by the next launch, so it is still reclaimed.
struct AssetGCPolicy: Sendable, Equatable {
    /// Minimum on-disk age (seconds since last modification) an asset must reach before it is
    /// eligible for sweeping.
    var gracePeriod: TimeInterval

    init(gracePeriod: TimeInterval) {
        self.gracePeriod = gracePeriod
    }

    /// One hour — comfortably longer than any in-flight cross-process `add` (milliseconds to
    /// seconds between byte-save and mutate-commit), while still letting every normal relaunch
    /// reclaim genuine orphans.
    static let `default` = AssetGCPolicy(gracePeriod: 3600)
}
