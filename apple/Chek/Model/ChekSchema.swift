import Foundation
import SwiftData

/// The first version of Chek's stored data.
///
/// Models are declared inside a versioned schema from the start, so a later
/// change adds a `ChekSchemaV2` and a migration stage instead of resetting
/// people's libraries.
enum ChekSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Book.self, ServerAccount.self, RemoteReadingState.self]
    }
}

enum ChekMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [ChekSchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}

typealias Book = ChekSchemaV1.Book
typealias ServerAccount = ChekSchemaV1.ServerAccount
typealias RemoteReadingState = ChekSchemaV1.RemoteReadingState

extension ModelContainer {
    /// Chek's store, or an in-memory one for previews and tests.
    ///
    /// The store is named `Chek` because Chek ships as an update to Chibi
    /// Manga, which keeps a different schema in the default store. A store
    /// of its own keeps the two from meeting.
    static func chek(inMemory: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration("Chek", schema: Schema(versionedSchema: ChekSchemaV1.self), isStoredInMemoryOnly: inMemory)
        return try ModelContainer(
            for: Schema(versionedSchema: ChekSchemaV1.self),
            migrationPlan: ChekMigrationPlan.self,
            configurations: configuration
        )
    }
}
