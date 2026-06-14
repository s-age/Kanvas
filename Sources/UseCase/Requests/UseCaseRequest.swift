import Foundation

/// Pure marker — every UseCase Request conforms. Reads, empty requests, and no-op reorders
/// conform for free. Carries NO `validate()`; do not add a defaulted no-op (see arch-usecase.md).
protocol UseCaseRequest: Sendable {}

/// A request that carries a real input invariant. Conform ONLY when there is something to check.
protocol ValidatableRequest: UseCaseRequest {
    func validate() throws
}
