import AppKit

/// Pure-AppKit infinite canvas. Renders stickies by hand and runs its own hit-testing, so
/// zoom and click-targeting stay consistent at any scale (a CALayer transform would desync
/// AppKit's frame-based hit-testing). The view owns only display + interaction; every state
/// change is routed back through `actions` to the ViewModel.
final class CanvasNSView: NSView, NSTextViewDelegate {

    // MARK: - Transform (world ⇄ view)

    /// A world point `w` maps to view point `w * scale + pan`. Both are unbounded → truly
    /// infinite canvas. World coordinates match the persisted sticky positions (a sticky's
    /// position is its centre).
    private(set) var scale: CGFloat = 1.0
    // private(set): mutated only here (pan/zoom/mouse handlers), read by the geometry extension.
    private(set) var pan: CGPoint = .zero
    private var didCenter = false
    /// The configured initial zoom is applied exactly once, when settings first arrive — never
    /// again, so a board/settings reload doesn't yank the user's current zoom back to the default.
    private var didApplyInitialZoom = false

    private let minScale: CGFloat = 0.25
    private let maxScale: CGFloat = 4.0
    /// Pinch sensitivity — gentler than the raw trackpad magnification.
    private let zoomDamping: CGFloat = 0.75

    // MARK: - Model + actions

    /// Invariant: assigned **only** in `update(_:)`, which rebuilds `stickyByID` in the same step.
    /// Never assign `stickies` elsewhere or the index silently desyncs.
    private(set) var stickies: [StickyResponse] = []
    /// O(1) sticky lookup by id, rebuilt in `update` whenever `stickies` changes (see the invariant
    /// above). Connector endpoint resolution (`edgeMidpointWorld`) runs twice per connector per draw;
    /// a linear `stickies.first(where:)` there made every frame O(connectors × stickies).
    private(set) var stickyByID: [UUID: StickyResponse] = [:]
    private(set) var shapes: [ShapeResponse] = []
    /// Bitmap images placed on the canvas. Their decoded `NSImage`s are cached separately
    /// (`CanvasNSView+Images`), fetched lazily by `assetID`; this array is only the placements.
    private(set) var images: [ImageResponse] = []
    /// Free-text objects (background/border-less text). Join the `items` z-order like stickies/shapes.
    private(set) var texts: [TextResponse] = []
    /// Directed sticky→sticky links. Drawn in their own pass behind every sticky/shape (they take
    /// no part in the `items` z-order), so a connector change only needs a redraw — not an `items`
    /// rebuild. Each endpoint is resolved live to its sticky's edge midpoint, so connectors follow
    /// their stickies as those move or resize.
    private(set) var connectors: [ConnectorResponse] = []
    /// Stickies + shapes merged and sorted by the shared `sortIndex` (ascending = back to front).
    /// The single source the canvas draws, hit-tests, drags, and resizes against. Cached and rebuilt
    /// only when the data changes (in `update`) — a single mouse event reads it many times, so the
    /// O(n log n) merge must not run per access (or per draw).
    private(set) var items: [CanvasItem] = []
    /// The items drawn with a selection highlight. Usually one (single-select, which also drives the
    /// SwiftUI toolbar); ⌘-click and marquee can grow it to several. Kind-agnostic — rendering only
    /// needs each item's rect. Single-only affordances (resize handle, connector-grow edge handles,
    /// label icon) appear only when this holds exactly the one item (`isSoleSelection`).
    ///
    /// **This is a one-way push *mirror* of the ViewModel's `selectedItems`** — `update(_:)` copies the
    /// VM's derived `selectedIDs` in; this view never writes selection back here. ⌫/⌦ (`+Keyboard`)
    /// deletes the ids in *this* mirror, so it is the one spot where a selection could lag the VM (a
    /// keypress landing between a VM selection change and the next `update`). Accepted by design: the
    /// VM is the single source of truth, both run on the main actor, and `update` follows every change
    /// within the same render pass — but it is the sole mirror, so it is called out here explicitly.
    private(set) var selectedIDs: Set<UUID> = []
    /// The board's canvas settings (sticky fill colours, initial zoom, grid-snap interval),
    /// pushed in via `update`. `nil` before the first board load — drawing/snapping then fall
    /// back to the built-in defaults (system yellow/blue, scale 1.0, no snap).
    private(set) var canvasSettings: CanvasSettingsResponse?
    /// The board's global appearance settings (background colour), pushed in via `update`. Drives
    /// the canvas background fill, so the canvas honours the same Global background as the Kanban
    /// board. `nil` before the first board load. (Sticky text colour is now always per-sticky.)
    private(set) var globalSettings: GlobalSettingsResponse?
    /// Resolved canvas background — recomputed only when `globalSettings` changes (in `update`), so
    /// the per-draw / per-sticky `flattenedFill` path never re-parses the background hex. Defaults
    /// to the dynamic system window background (light/dark aware) until a Global override arrives.
    private(set) var canvasBackgroundColor: NSColor = .windowBackgroundColor
    /// The sticky currently under the cursor. Like a sole selection, it surfaces the label icon —
    /// so the icon is reachable on hover without first selecting the sticky. View-local state
    /// (not routed through the ViewModel): it drives only the affordance overlay. Mutated from
    /// the hover extension (`CanvasNSView+Hover`), so its setter is not file-scoped.
    var hoverID: UUID?
    weak var actions: (any CanvasActionHandler)?

    // MARK: - Image asset cache
    //
    // Decoded image pixels, keyed by `ImageResponse.assetID`, fetched lazily on first draw via
    // `actions.imageData(assetID:)`. Mutated only from `CanvasNSView+Images` (same actor, same
    // folder), so the setters are not file-scoped. `pendingImageLoads` dedupes in-flight fetches.
    var imageCache: [UUID: NSImage] = [:]
    var pendingImageLoads: Set<UUID> = []
    /// Assets that failed **terminally** — a genuinely missing file or undecodable bytes. A negative
    /// cache: without it, a broken asset re-triggers a disk read on **every** redraw (drag/zoom/hover),
    /// looping I/O per frame. A *transient* failure (a read fault during an external atomic replace, a
    /// cancelled fetch) is deliberately kept out, so it retries on the next redraw. Cleared for an id
    /// only when it leaves `images` (so a re-add retries).
    var failedImageLoads: Set<UUID> = []
    /// Consecutive transient fetch failures per asset. A fault that keeps recurring is not transient
    /// (an unreadable sidecar: EACCES/EIO/path-is-a-directory); without a cap it would re-fetch every
    /// redraw forever — and silently, since transient failures aren't reported. `loadImageIfNeeded`
    /// promotes an id to `failedImageLoads` once this hits the retry limit. Cleared on success and on
    /// leaving `images`, like the caches above.
    var transientImageLoadAttempts: [UUID: Int] = [:]

    // MARK: - Inline text editing

    /// The sticky currently being text-edited via the overlaid `editor`, if any. Mutated from the
    /// editing extension (`CanvasNSView+Editing`, same folder), so not file-scoped.
    var editingID: UUID?

    /// Overlaid editor shown on double-click. Created once, reused — sized/positioned to the
    /// sticky's current view rect each time editing begins. Driven from `CanvasNSView+Editing`.
    lazy var editor: NSTextView = {
        let view = NSTextView()
        view.isRichText = false
        view.drawsBackground = true
        view.backgroundColor = .textBackgroundColor
        view.textContainerInset = .zero
        view.delegate = self
        view.isHidden = true
        return view
    }()

    /// Cached tag glyph for the label-icon affordance. Building it (`systemSymbolName` +
    /// palette-coloured `SymbolConfiguration`) allocates an `NSImage`; it depends only on the
    /// constant icon size and the accent colour, so it is rebuilt only when one of those inputs can
    /// change: the effective appearance (`viewDidChangeEffectiveAppearance`, light/dark) or the
    /// accent/tint colour (`NSColor.systemColorsDidChangeNotification`, which fires *without* an
    /// appearance change when only the accent colour is changed in System Settings). Mutated from the
    /// drawing extension (same actor), so its setter is not file-scoped.
    var cachedLabelIconImage: NSImage?

    /// Cached label-pill font, valid for `cachedPillFontSize`. The font depends only on the pill
    /// font size (a function of the zoom-derived `pillHeight`), not on the individual label — so
    /// rebuilding `NSFont.systemFont(...)` per visible pill per draw (drag/zoom redraws the whole
    /// view every event) was pure waste. Rebuilt only when the pill font size changes. Mutated from
    /// the drawing extension (same actor), so its setter is not file-scoped.
    var cachedPillFont: NSFont?
    /// The font size `cachedPillFont` was built for; `.nan` until first built so any real size misses.
    var cachedPillFontSize: CGFloat = .nan
    /// Measured label-pill text sizes, keyed by `(name, fontSize)`. `size(withAttributes:)` is a
    /// non-trivial text-layout call run per visible pill; the label set and zoom hold steady across a
    /// drag, so caching the measured size keeps redraws from re-measuring the same strings every
    /// frame. Bounded on *both* axes: the live-label-name prune in `update(_:)` evicts vanished names
    /// (rename/delete/card switch), and `pillFont(ofSize:)` clears the whole cache when the
    /// zoom-derived font size changes — every entry is keyed at the prior, now-unreachable size, so
    /// without that reset a continuous pinch-zoom would mint float-distinct keys per persistent label
    /// for the process lifetime. Together they cap the cache at the labels measured at the current
    /// zoom. Mutated from the drawing extension (same actor), unlocked.
    var pillTextSizeCache: [PillTextSizeKey: CGSize] = [:]

    /// Constant paragraph style for sticky text — built once, not per draw (see redraw note
    /// on `draw(_:)`).
    let textParagraphStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byWordWrapping  // wrap within the sticky instead of truncating
        return style
    }()

    // MARK: - Interaction state

    private var mouseDownView: CGPoint?
    // private(set) on the live-interaction state: mutated only by the mouse handlers here, read by
    // the geometry extension (separate file) to apply the live drag/resize offsets.
    private(set) var draggingID: UUID?
    /// The full set of items moving together this drag. For a normal drag it is just `draggingID`;
    /// when the grabbed item is part of a multi-selection it is the whole selection, so `worldRect`
    /// previews every member following the cursor. Empty when no object drag is active.
    private(set) var draggingGroupIDs: Set<UUID> = []
    /// Live drag offset in world units for the item(s) being dragged.
    private(set) var dragWorldDelta: CGSize = .zero
    // private(set): written only by the mouse handlers here, read by the gesture-commit extension.
    private(set) var didDrag = false
    private let dragThreshold: CGFloat = 3

    /// Live rubber-band (marquee) rect in **view** space while dragging from empty canvas, else nil.
    /// Drawn as a dashed accent rectangle; on mouse-up every item it intersects is selected. The
    /// marquee's anchor is `mouseDownView` itself: a marquee drag is exactly the `draggingID == nil`
    /// (empty-canvas) case, so the mouse-down point already held there is the origin — no second
    /// copy of it is kept.
    private(set) var marqueeViewRect: CGRect?
    /// Whether the in-progress marquee unions with the existing selection (⌘ held at mouse-down).
    // private(set): written only by the mouse handlers here, read by the gesture-commit extension.
    private(set) var marqueeAdditive = false

    /// The selected sticky/image being live-resized via its corner handle, if any. (Shapes use
    /// `activeHandleDrag` instead.)
    private(set) var resizingID: UUID?
    /// Live drag offset in world units. Applied to the corner during a sticky/image resize and to
    /// the grabbed handle during a shape `activeHandleDrag` (box corner or segment endpoint).
    private(set) var resizeWorldDelta: CGSize = .zero
    /// The in-progress shape handle drag (box corner / segment endpoint), if any — drives the live
    /// shape preview and commits via `ShapeRegistry.defaultHandles(for:)`.
    private(set) var activeHandleDrag: CanvasShapeHandleDrag?
    /// The in-progress connector-grow gesture (dragging out from a selected sticky's edge handle),
    /// if any — drives the live connector preview. Committed on mouse-up. `private(set)`: written
    /// only by the mouse handlers in this file, read by the drawing/commit extension.
    private(set) var connectorDraft: ConnectorDraft?
    /// The in-progress connector-reconnect gesture (dragging a selected connector's endpoint handle
    /// to a different sticky/edge), if any — drives the live reconnect preview. Committed on
    /// mouse-up. `private(set)`: written only by the mouse handlers in this file, read by the
    /// drawing/commit extension.
    private(set) var connectorReconnectDraft: ConnectorReconnectDraft?
    /// The in-progress connector-waypoint gesture (dragging a selected elbow/curve connector's
    /// central deformation handle), if any — drives the live waypoint preview. Committed on mouse-up.
    /// `private(set)`: written only by the mouse handlers in this file, read by the drawing/commit
    /// extension. Mutually exclusive with the grow/reconnect drafts (one draft per mouse-down).
    private(set) var connectorWaypointDraft: ConnectorWaypointDraft?
    /// Side of the square resize handle, in view points (zoom-independent).
    let resizeHandleSize: CGFloat = 12

    // MARK: - Setup

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        // `.string` carries the palette payload (sticky preset / shape tool); the image types let
        // an image file or picture be dropped from Finder/another app onto the canvas.
        registerForDraggedTypes([.string, .fileURL, .tiff, .png])
        // The accent colour can change without an effective-appearance (light/dark) change, which
        // would leave the baked label glyph stale; `systemColorsDidChange` covers that case. The
        // selector-based observer is auto-removed on dealloc (macOS 10.11+), so no `deinit` cleanup.
        NotificationCenter.default.addObserver(
            self, selector: #selector(systemColorsDidChange),
            name: NSColor.systemColorsDidChangeNotification, object: nil)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        // The cached label glyph baked the accent colour in the old appearance; drop it so it
        // rebuilds (and redraw, since the canvas background may flip light/dark too).
        cachedLabelIconImage = nil
        needsDisplay = true
    }

    /// Drops the cached label glyph when the accent/tint colour changes (no appearance change fires
    /// for an accent-only switch), so it rebuilds in the new accent on the next draw.
    @objc private func systemColorsDidChange() {
        cachedLabelIconImage = nil
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        // Place the world origin at the viewport centre, once, after first sizing.
        if !didCenter, bounds.width > 0, bounds.height > 0 {
            pan = CGPoint(x: bounds.midX, y: bounds.midY)
            didCenter = true
            needsDisplay = true
        }
    }

    // MARK: - Pan / Zoom (trackpad)

    override func scrollWheel(with event: NSEvent) {
        // Two-finger swipe → pan. Precise deltas come from the trackpad.
        commitEditing()  // the editor frame would otherwise desync from its sticky.
        pan.x += event.scrollingDeltaX
        pan.y += event.scrollingDeltaY
        needsDisplay = true
    }

    override func magnify(with event: NSEvent) {
        // Pinch → zoom anchored at the pointer (the world point under the cursor stays put).
        commitEditing()  // the editor frame would otherwise desync from its sticky.
        let anchor = convert(event.locationInWindow, from: nil)
        let worldAtAnchor = viewToWorld(anchor)
        let newScale = min(max(scale * (1 + event.magnification * zoomDamping), minScale), maxScale)
        scale = newScale
        pan = CGPoint(x: anchor.x - worldAtAnchor.x * newScale, y: anchor.y - worldAtAnchor.y * newScale)
        needsDisplay = true
    }

    // MARK: - Mouse (object drag / tap-to-create)

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        // Take key focus so keyDown (Delete) reaches the canvas. beginEditing re-targets the
        // editor afterward when a double-click starts text editing.
        window?.makeFirstResponder(self)

        // A single-click on a handle/icon affordance (line endpoint, resize handle, label icon)
        // pre-empts hit-testing, selection, and editing.
        if event.clickCount == 1, beginAffordancePress(at: location) { return }

        let hit = item(atWorld: viewToWorld(location))

        // Clicking anywhere other than the sticky already being edited commits that edit first.
        if let editingID, hit?.id != editingID {
            commitEditing()
            // A click on empty canvas just finishes editing — don't also create anything.
            // A click on another item falls through to select/edit it.
            if hit == nil {
                mouseDownView = nil
                draggingID = nil
                return
            }
        }

        // Double-click on a sticky or a free-text object → enter inline text editing (no drag/select
        // this gesture). Shapes/images have no text, so a double-click on one falls through to
        // normal select/drag.
        if event.clickCount >= 2, let hit, beginEditingIfTextual(hit) {
            mouseDownView = nil
            draggingID = nil
            return
        }

        let commandHeld = event.modifierFlags.contains(.command)

        // ⌘-click on an item toggles its membership in the selection — no drag, no editing.
        if commandHeld, let hit {
            actions?.toggleSelection(id: hit.id)
            mouseDownView = nil
            draggingID = nil
            return
        }

        mouseDownView = location
        didDrag = false
        dragWorldDelta = .zero
        draggingID = hit?.id
        resizingID = nil
        // Dragging a member of a ≥2 selection moves the whole group; otherwise just the grabbed item.
        draggingGroupIDs = groupDragIDs(for: hit?.id)
        // An empty-canvas drag rubber-bands a marquee (⌘ unions with the current selection). The
        // marquee anchor is `mouseDownView`, already set above; only the union flag is recorded here.
        if hit == nil {
            marqueeAdditive = commandHeld
        }
    }

    /// The set of ids a drag starting on `hitID` moves together: the whole selection when the grabbed
    /// item is part of a multi-selection, else just the grabbed item (or empty for an empty-canvas
    /// drag). Keeps a single-object drag unaffected by whatever else happens to be selected.
    private func groupDragIDs(for hitID: UUID?) -> Set<UUID> {
        guard let hitID else { return [] }
        if selectedIDs.count >= 2, selectedIDs.contains(hitID) { return selectedIDs }
        return [hitID]
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownView else { return }
        let location = convert(event.locationInWindow, from: nil)
        let viewDelta = CGSize(width: location.x - start.x, height: location.y - start.y)
        if abs(viewDelta.width) > dragThreshold || abs(viewDelta.height) > dragThreshold { didDrag = true }
        // A connector grow/reconnect/waypoint gesture tracks the cursor live (the preview follows it).
        if connectorDraft != nil || connectorReconnectDraft != nil || connectorWaypointDraft != nil {
            connectorDraft?.currentWorld = viewToWorld(location)
            connectorReconnectDraft?.currentWorld = viewToWorld(location)
            connectorWaypointDraft?.currentWorld = viewToWorld(location)
            needsDisplay = true
            return
        }
        // A sticky/image corner resize or a shape handle drag tracks the cursor live; both use
        // `resizeWorldDelta` and pre-empt the move path.
        if resizingID != nil || activeHandleDrag != nil {
            resizeWorldDelta = CGSize(width: viewDelta.width / scale, height: viewDelta.height / scale)
            needsDisplay = true
            return
        }
        // An empty-canvas drag rubber-bands a marquee instead of moving an item. The mouse-down
        // point (`start`) is the marquee anchor — `draggingID == nil` *is* the empty-canvas case.
        if draggingID == nil {
            marqueeViewRect = CGRect(x: min(start.x, location.x), y: min(start.y, location.y),
                                     width: abs(location.x - start.x), height: abs(location.y - start.y))
            needsDisplay = true
            return
        }
        dragWorldDelta = CGSize(width: viewDelta.width / scale, height: viewDelta.height / scale)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        // One reset for every live-gesture field, grouped by concern; kept compact (not one line per
        // field) because this file is at its `file_length` budget — the waypoint state added here.
        defer {
            mouseDownView = nil
            draggingID = nil; draggingGroupIDs = []; resizingID = nil; activeHandleDrag = nil
            connectorDraft = nil; connectorReconnectDraft = nil; connectorWaypointDraft = nil
            dragWorldDelta = .zero; resizeWorldDelta = .zero; didDrag = false
            marqueeViewRect = nil; marqueeAdditive = false
        }
        // A double-click already consumed this gesture in mouseDown (no drag start recorded).
        guard let downView = mouseDownView else { return }

        // Each in-progress gesture commits its own way; only one is ever active per mouse-down. The
        // connector branch covers grow, reconnect, and waypoint drafts (either/or, dispatched inside).
        if connectorDraft != nil || connectorReconnectDraft != nil || connectorWaypointDraft != nil {
            if didDrag { commitActiveConnectorGesture() }
        } else if let drag = activeHandleDrag {
            if didDrag { commitShapeHandleDrag(drag) }
        } else if let id = resizingID {
            if didDrag { commitResize(id: id) }
        } else {
            commitDragOrTap(downView: downView)
        }
    }

}

// MARK: - NSView geometry/responder overrides
//
// Trivial constant overrides, in an extension only to keep the class body within its length budget
// (the waypoint-draft state grew it to the limit). Flipped coordinates so world/view y align; the
// canvas takes key focus and acts on first click.

extension CanvasNSView {

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - Model push (from the ViewModel)
//
// Same-file extension (reaches the class's private model + cache state) so the data-diffing entry
// point stays out of the class-body length budget.

extension CanvasNSView {

    func update(_ content: CanvasContent, selectedIDs: Set<UUID>, settings: CanvasSettingsResponse?,
                global: GlobalSettingsResponse?) {
        applyInitialZoomIfNeeded(settings)
        // updateNSView fires for unrelated observable changes too, so redraw only on a real
        // change (Sticky/Shape/Image/ConnectorResponse are Equatable). A settings change is a
        // visual change too (fill colours, global background/text), so it forces a redraw via
        // `settingsChanged`.
        let settingsChanged = settings != canvasSettings || global != globalSettings
        canvasSettings = settings
        globalSettings = global
        guard content.stickies != stickies || content.shapes != shapes || content.images != images
            || content.texts != texts || content.connectors != connectors
            || selectedIDs != self.selectedIDs || settingsChanged else {
            return
        }
        // Parse the background hex only when the settings actually change — not on every `update`
        // (which fires for unrelated observable changes too) and not per sticky per draw. The
        // resolved colour depends solely on `global`, which can only differ when `settingsChanged`.
        if settingsChanged {
            canvasBackgroundColor = global?.backgroundColorHex.map { NSColor(hex: $0) } ?? .windowBackgroundColor
        }
        // Connectors don't join the `items` z-order, so they don't trigger an items rebuild.
        let stickiesChanged = content.stickies != stickies
        let itemsChanged = stickiesChanged || content.shapes != shapes
            || content.images != images || content.texts != texts
        stickies = content.stickies
        if stickiesChanged {
            // first-wins on a duplicate id, matching the old `stickies.first(where:)` tie-break (ids
            // are unique in practice, so this only pins behaviour).
            stickyByID = Dictionary(stickies.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            // Prune measured pill-text sizes to the labels still present on the canvas — a rename,
            // a label delete, or a card/board switch otherwise leaves their (name, fontSize) entries
            // wedged in the dictionary for the whole (long-lived, cached) view's lifetime. Keyed only
            // by name (fontSize is the zoom axis), so every stale entry for a vanished name is dropped
            // regardless of zoom. Mirrors the image-cache eviction below.
            let liveLabelNames = Set(stickies.flatMap { $0.labels.map(\.name) })
            pillTextSizeCache = pillTextSizeCache.filter { liveLabelNames.contains($0.key.name) }
        }
        shapes = content.shapes
        if content.images != images {
            // Evict decoded pixels (and pending/negative-cache entries) for images that left the
            // canvas — a card/board switch or an image delete — so the caches don't grow without
            // bound across every card ever visited.
            let liveAssetIDs = Set(content.images.map(\.assetID))
            imageCache = imageCache.filter { liveAssetIDs.contains($0.key) }
            pendingImageLoads.formIntersection(liveAssetIDs)
            failedImageLoads.formIntersection(liveAssetIDs)
            transientImageLoadAttempts = transientImageLoadAttempts.filter { liveAssetIDs.contains($0.key) }
        }
        images = content.images
        texts = content.texts
        connectors = content.connectors
        self.selectedIDs = selectedIDs
        if itemsChanged {
            items = (stickies.map(CanvasItem.sticky) + shapes.map(CanvasItem.shape)
                     + images.map(CanvasItem.image) + texts.map(CanvasItem.text))
                .sorted { $0.sortIndex < $1.sortIndex }
        }
        needsDisplay = true
    }

    /// Applies the board's configured initial zoom the first time settings arrive (clamped to the
    /// canvas's live-zoom range). `pan` is set by `layout`'s first-center, independent of scale.
    /// (No `needsDisplay` here: `update(...)` always redraws on the first settings arrival via
    /// `settingsChanged`, so flagging it again would be redundant.)
    fileprivate func applyInitialZoomIfNeeded(_ settings: CanvasSettingsResponse?) {
        guard !didApplyInitialZoom, let settings else { return }
        didApplyInitialZoom = true
        scale = min(max(CGFloat(settings.initialZoomScale), minScale), maxScale)
    }
}

// MARK: - Affordance press routing
//
// Same-file extension (can reach the class's private interaction state) so the gesture-precedence
// logic stays out of the `mouseDown` body and the class-body length budget.

extension CanvasNSView {

    /// Handles a single-click that lands on a handle/icon affordance, in precedence order: a line's
    /// endpoint handle, a filled shape's / sticky's resize handle, then a sticky's label icon.
    /// Returns `true` when it consumed the press (the caller should stop), `false` otherwise.
    func beginAffordancePress(at location: CGPoint) -> Bool {
        // A connector gesture (grow from a selected sticky's edge handle, or reconnect a selected
        // connector's endpoint handle) pre-empts the resize/label affordances — the handles sit just
        // outside the edges. Sticky and connector selection are mutually exclusive, so the grow and
        // reconnect handle families never collide.
        if beginConnectorGesture(at: location) { return true }
        if let drag = shapeHandleHit(atView: location) {
            commitEditing()
            mouseDownView = location
            didDrag = false
            resizeWorldDelta = .zero
            activeHandleDrag = drag
            resizingID = nil
            draggingID = nil
            return true
        }
        if let resizeID = resizeHandleItemID(atView: location) {
            commitEditing()
            mouseDownView = location
            didDrag = false
            resizeWorldDelta = .zero
            resizingID = resizeID
            draggingID = nil
            return true
        }
        if let labelStickyID = labelIconStickyID(atView: location) {
            commitEditing()
            actions?.openLabelManager(stickyID: labelStickyID)
            mouseDownView = nil
            draggingID = nil
            resizingID = nil
            return true
        }
        return false
    }

    /// Begins a connector grow (from a selected sticky's edge handle) or reconnect (from a selected
    /// connector's endpoint handle) when the press lands on one — reconnect takes precedence, but
    /// the two are mutually exclusive in practice. Kept in this file (not the `+Connectors` /
    /// `+ConnectorReconnect` extensions) because it writes the `private(set)` interaction state,
    /// which only same-file code may mutate. Returns whether it consumed the press.
    private func beginConnectorGesture(at location: CGPoint) -> Bool {
        let world = viewToWorld(location)
        if let endpoint = connectorEndpointHandleHit(atView: location) {
            connectorReconnectDraft = ConnectorReconnectDraft(
                connectorID: endpoint.connectorID, side: endpoint.side, currentWorld: world)
        } else if let waypointConnectorID = connectorWaypointHandleHit(atView: location) {
            connectorWaypointDraft = ConnectorWaypointDraft(
                connectorID: waypointConnectorID, currentWorld: world)
        } else if let handle = edgeHandleHit(atView: location) {
            connectorDraft = ConnectorDraft(
                sourceStickyID: handle.stickyID, sourceEdge: handle.edge, currentWorld: world)
        } else { return false }
        commitEditing()
        mouseDownView = location
        didDrag = false
        resizingID = nil
        draggingID = nil
        return true
    }
}

