/// A transient, **non-error** informational message for the user, carrying its own `title` so the
/// presenting alert is not coupled to any one caller. Distinct from the `error` channel: a notice
/// is an expected, benign outcome, not a failure — surfacing it under the "Error" alert would
/// mislabel it. Each caller supplies the title that fits its event, so a future second caller
/// cannot inherit a wrong hardcoded title (the trap a bare `String?` + fixed alert title would set).
struct UserNotice: Equatable {
    let title: String
    let message: String
}
