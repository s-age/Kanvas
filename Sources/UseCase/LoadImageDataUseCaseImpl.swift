import Foundation

final class LoadImageDataUseCaseImpl: LoadImageDataUseCase, Sendable {
    private let imageService: any CanvasImageServiceProtocol

    init(imageService: any CanvasImageServiceProtocol) {
        self.imageService = imageService
    }

    func execute(assetID: UUID) async throws -> Data {
        try await imageService.loadImageData(assetID: assetID)
    }
}
