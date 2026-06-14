import Foundation

/// DataSource-style repository for canvas image assets. Pass-through to the Infrastructure
/// `ImageAssetStoreProtocol`; the payload is opaque `Data`, so there is no DTO↔entity mapping.
final class ImageAssetRepository: ImageAssetRepositoryProtocol, Sendable {
    private let store: any ImageAssetStoreProtocol

    init(store: any ImageAssetStoreProtocol) {
        self.store = store
    }

    func save(assetID: UUID, data: Data) async throws {
        try await store.save(assetID: assetID, data: data)
    }

    func load(assetID: UUID) async throws -> Data {
        try await store.load(assetID: assetID)
    }

    func delete(assetID: UUID) async throws {
        try await store.delete(assetID: assetID)
    }

    func assetIDs(modifiedBefore cutoff: Date) async throws -> Set<UUID> {
        try await store.assetIDs(modifiedBefore: cutoff)
    }
}
