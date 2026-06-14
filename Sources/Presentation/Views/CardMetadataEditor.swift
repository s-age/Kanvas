import SwiftUI

/// Editable card meta fields shown above the Notes editor:
/// assignee + schedule (start/end or deadline). `completedAt` is read-only —
/// it is stamped automatically when the card is moved into the board's Done column.
struct CardMetadataEditor: View {
    @Bindable var viewModel: BoardViewModel

    @State private var assignee = ""
    @State private var prURL = ""
    @State private var scheduleMode: ScheduleMode = .none
    @State private var deadline = Date()
    @State private var periodStart = Date()
    @State private var periodEnd = Date().addingTimeInterval(86_400)
    @FocusState private var assigneeFocused: Bool
    @FocusState private var prURLFocused: Bool

    private enum ScheduleMode: String, CaseIterable, Identifiable {
        case none = "None"
        case deadline = "Deadline"
        case period = "Period"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            assigneeRow
            prURLRow
            scheduleSection
            if let completedAt = viewModel.selectedCardDetail?.completedAt {
                completedRow(completedAt)
            }
        }
        .onChange(of: viewModel.selectedCardDetail?.id) { seed() }
        // The PR URL has an external writer by design — `board_card_set_pr_url` (MCP) can update the
        // *currently-selected* card. `BoardStoreWatcher` then reloads `selectedCardDetail` with the
        // card id unchanged, so the id-keyed `seed()` above never re-runs. Re-seed the buffer on a
        // prURL change while the field is unfocused, so the TextField + Link reflect the new value
        // without clobbering an in-progress edit.
        .onChange(of: viewModel.selectedCardDetail?.prURL) { _, newValue in
            if !prURLFocused { prURL = newValue ?? "" }
        }
        // `assignee` and `schedule` share the prURL situation: `board_card_edit` (MCP) can
        // rewrite the currently-selected card without the id changing, so each needs its own
        // content-keyed re-seed.
        .onChange(of: viewModel.selectedCardDetail?.assignee) { _, newValue in
            if !assigneeFocused { assignee = newValue ?? "" }
        }
        .onChange(of: viewModel.selectedCardDetail?.schedule) { _, newValue in
            guard ExternalScheduleRewrite(
                newSchedule: newValue,
                localSchedule: Self.scheduleResponse(from: buildSchedule())
            ).shouldAdopt else { return }
            seedSchedule(from: newValue)
        }
        .onAppear { seed() }
    }

    /// Pure gate for the external-rewrite re-seed of the schedule buffers, extracted as a
    /// value so the merge policy is unit-testable (mirrors `MarkdownEditorView.ExternalNotesRewrite`).
    /// Unlike the notes draft, schedule edits commit synchronously on every control change
    /// (`commitScheduleIfChanged`), so no dirty-buffer state survives past the change that
    /// created it — there is nothing to protect, and `loadedContent`-style snapshot tracking
    /// would add state without changing any decision. Adopt whenever the external value
    /// differs from what the buffers represent; a self-echo of our own commit compares equal
    /// and is skipped.
    struct ExternalScheduleRewrite {
        let newSchedule: ScheduleResponse?
        let localSchedule: ScheduleResponse?

        var shouldAdopt: Bool { newSchedule != localSchedule }
    }

}

// MARK: - Subviews

private extension CardMetadataEditor {

    // MARK: Header (task name + status)

    var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(viewModel.selectedCardDetail?.title ?? "")
                .font(.title3.weight(.semibold))
                .lineLimit(2)
            HStack(spacing: 8) {
                statusChip
                ForEach(viewModel.selectedCardDetail?.labels ?? []) { labelChip($0) }
            }
        }
    }

    @ViewBuilder
    var statusChip: some View {
        if let detail = viewModel.selectedCardDetail {
            // The card's status is its column: show the column name (follows renames) tinted by the
            // column-derived status colour.
            Text(detail.columnTitle)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(detail.status.displayColor.opacity(0.15))
                .foregroundStyle(detail.status.displayColor)
                .clipShape(Capsule())
        }
    }

    func labelChip(_ label: LabelResponse) -> some View {
        Text(label.name)
            .font(.caption)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color(hex: label.colorHex).opacity(0.2))
            .clipShape(Capsule())
    }

    // MARK: Assignee

    var assigneeRow: some View {
        HStack(spacing: 8) {
            Label("Assignee", systemImage: "person")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Unassigned", text: $assignee)
                .textFieldStyle(.roundedBorder)
                .focused($assigneeFocused)
                .onSubmit { commitAssignee() }
                .onChange(of: assigneeFocused) { _, focused in
                    if !focused { commitAssignee() }
                }
        }
    }

    // MARK: PR URL

    var prURLRow: some View {
        HStack(spacing: 8) {
            Label("PR URL", systemImage: "link")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("None", text: $prURL)
                .textFieldStyle(.roundedBorder)
                .focused($prURLFocused)
                .onSubmit { commitPRURL() }
                .onChange(of: prURLFocused) { _, focused in
                    if !focused { commitPRURL() }
                }
            // Only a parseable http(s) URL is offered as a clickable link; anything else is left
            // as plain editable text (no broken link, no AppKit — SwiftUI `Link` opens it).
            if let url = validPRURL(prURL) {
                Link(destination: url) {
                    Image(systemName: "arrow.up.right.square")
                }
                .help("Open PR in browser")
            }
        }
    }

    func validPRURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return nil }
        return url
    }

    // MARK: Schedule

    var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Schedule", selection: $scheduleMode) {
                ForEach(ScheduleMode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .onChange(of: scheduleMode) { commitScheduleIfChanged() }

            switch scheduleMode {
            case .none:
                EmptyView()
            case .deadline:
                DatePicker("Due", selection: $deadline, displayedComponents: .date)
                    .onChange(of: deadline) { commitScheduleIfChanged() }
            case .period:
                HStack(spacing: 16) {
                    DatePicker("Start", selection: $periodStart, displayedComponents: .date)
                        .onChange(of: periodStart) { commitScheduleIfChanged() }
                        .fixedSize()
                    DatePicker("End", selection: $periodEnd, in: periodStart..., displayedComponents: .date)
                        .onChange(of: periodEnd) { commitScheduleIfChanged() }
                        .fixedSize()
                }
            }
        }
        .font(.caption)
    }

    func completedRow(_ date: Date) -> some View {
        Label(
            "Completed \(date.formatted(date: .abbreviated, time: .shortened))",
            systemImage: "checkmark.circle.fill"
        )
        .font(.caption)
        .foregroundStyle(.green)
    }

}

// MARK: - Commit & seed

private extension CardMetadataEditor {

    func commitAssignee() {
        guard let cardID = viewModel.selectedCardID else { return }
        // Trim here only to diff-guard against the stored value; the canonical
        // normalization (trim + blank→nil) lives in EditCardUseCaseImpl.
        let trimmed = assignee.trimmingCharacters(in: .whitespaces)
        guard trimmed != (viewModel.selectedCardDetail?.assignee ?? "") else { return }
        Task {
            await viewModel.editCard(
                EditCardRequest(cardID: cardID, assignee: .some(trimmed.isEmpty ? nil : trimmed))
            )
        }
    }

    func commitPRURL() {
        guard let cardID = viewModel.selectedCardID else { return }
        // Trim only to diff-guard against the stored value; the canonical normalization
        // (trim + blank→nil) lives in EditCardUseCaseImpl, mirroring assignee.
        let trimmed = prURL.trimmingCharacters(in: .whitespaces)
        guard trimmed != (viewModel.selectedCardDetail?.prURL ?? "") else { return }
        Task {
            await viewModel.editCard(
                EditCardRequest(cardID: cardID, prURL: .some(trimmed.isEmpty ? nil : trimmed))
            )
        }
    }

    func commitScheduleIfChanged() {
        guard let cardID = viewModel.selectedCardID else { return }
        let desired = buildSchedule()
        guard Self.scheduleResponse(from: desired) != viewModel.selectedCardDetail?.schedule else { return }
        Task {
            await viewModel.editCard(EditCardRequest(cardID: cardID, schedule: .some(desired)))
        }
    }

    func buildSchedule() -> ScheduleInput? {
        switch scheduleMode {
        case .none:
            return nil
        case .deadline:
            return .deadline(deadline)
        case .period:
            // Guarantee end > start so EditCardRequest validation never rejects it.
            let end = periodEnd > periodStart ? periodEnd : periodStart.addingTimeInterval(86_400)
            return .period(start: periodStart, end: end)
        }
    }

    // Re-seeds every local edit buffer from the selected card, on card-id change and first
    // appearance. Same-card external updates (MCP) are handled separately by the per-field
    // content-keyed onChange re-seeds in `body`.
    func seed() {
        assignee = viewModel.selectedCardDetail?.assignee ?? ""
        prURL = viewModel.selectedCardDetail?.prURL ?? ""
        seedSchedule(from: viewModel.selectedCardDetail?.schedule)
    }

    func seedSchedule(from response: ScheduleResponse?) {
        switch response {
        case .deadline(let date):
            scheduleMode = .deadline
            deadline = date
        case .period(let start, let end):
            scheduleMode = .period
            periodStart = start
            periodEnd = end
        case nil:
            scheduleMode = .none
        }
    }

    /// Maps the edit-buffer schedule into the Response-layer representation so comparisons
    /// with `selectedCardDetail?.schedule` stay in one domain.
    private nonisolated static func scheduleResponse(from schedule: ScheduleInput?) -> ScheduleResponse? {
        switch schedule {
        case .deadline(let date): return .deadline(date)
        case .period(let start, let end): return .period(start: start, end: end)
        case nil: return nil
        }
    }
}
