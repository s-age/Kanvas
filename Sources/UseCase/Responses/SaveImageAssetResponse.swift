import Foundation

/// The id of the freshly persisted sidecar asset, returned by `SaveImageAssetUseCase`. The caller
/// (the Markdown editor's ViewModel) embeds it in the card body as `kanvas-asset://<assetID>`.
struct SaveImageAssetResponse: Sendable, Equatable {
    let assetID: UUID
}
