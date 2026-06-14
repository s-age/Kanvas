import Foundation

/// DTO ⇄ entity mapping for the board catalog index (`catalog.json`). Both the load path
/// (`BoardRepository.loadedCatalog`) and the save path (`persistCatalog`) route through here so the
/// encode/decode pair cannot drift.
enum BoardCatalogMapper {

    static func toEntity(_ dto: BoardCatalogDTO) -> BoardCatalog {
        BoardCatalog(
            boards: dto.boards.map { Board(id: $0.id, title: $0.title) },
            activeBoardID: dto.activeBoardID
        )
    }

    static func toDTO(_ catalog: BoardCatalog) -> BoardCatalogDTO {
        BoardCatalogDTO(
            activeBoardID: catalog.activeBoardID,
            boards: catalog.boards.map { BoardRefDTO(id: $0.id, title: $0.title) }
        )
    }
}
