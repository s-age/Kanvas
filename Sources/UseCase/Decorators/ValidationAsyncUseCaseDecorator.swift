/// Transparently runs `request.validate()` before delegating. Generically constrained to
/// `ValidatableRequest`, so wrapping a use case whose Request is a bare `UseCaseRequest` does NOT
/// compile (no no-op wrap). Conforms to the same `AsyncUseCase` base it wraps, so the
/// `*UseCase` typealias the callers consume is unchanged.
struct ValidationAsyncUseCaseDecorator<Request: ValidatableRequest, Response>: AsyncUseCase {
    private let wrapped: any AsyncUseCase<Request, Response>

    init(_ wrapped: any AsyncUseCase<Request, Response>) {
        self.wrapped = wrapped
    }

    func execute(_ request: Request) async throws -> Response {
        try request.validate()
        return try await wrapped.execute(request)
    }
}
