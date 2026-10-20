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

/// Adds your places in chapters read straight from a server's sources.
/// The other models are unchanged, so they carry over as they are.
enum ChekSchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        [ChekSchemaV1.Book.self, ChekSchemaV1.ServerAccount.self, ChekSchemaV1.RemoteReadingState.self, ChekSchemaV2.SourceReadingState.self]
    }
}

/// Keeps the series' cover with your place in a source chapter, so it can
/// show in Continue Reading.
enum ChekSchemaV3: VersionedSchema {
    static let versionIdentifier = Schema.Version(3, 0, 0)

    static var models: [any PersistentModel.Type] {
        [ChekSchemaV1.Book.self, ChekSchemaV1.ServerAccount.self, ChekSchemaV1.RemoteReadingState.self, SourceReadingState.self]
    }
}

/// Adds the series you follow from sources.
enum ChekSchemaV4: VersionedSchema {
    static let versionIdentifier = Schema.Version(4, 0, 0)

    static var models: [any PersistentModel.Type] {
        [ChekSchemaV1.Book.self, ChekSchemaV1.ServerAccount.self, ChekSchemaV1.RemoteReadingState.self, ChekSchemaV3.SourceReadingState.self, FollowedSeries.self]
    }
}

enum ChekMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [ChekSchemaV1.self, ChekSchemaV2.self, ChekSchemaV3.self, ChekSchemaV4.self]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: ChekSchemaV1.self, toVersion: ChekSchemaV2.self),
            .lightweight(fromVersion: ChekSchemaV2.self, toVersion: ChekSchemaV3.self),
            .lightweight(fromVersion: ChekSchemaV3.self, toVersion: ChekSchemaV4.self),
        ]
    }
}

/// The current schema, which the store opens with.
typealias ChekSchema = ChekSchemaV4
typealias FollowedSeries = ChekSchemaV4.FollowedSeries

typealias Book = ChekSchemaV1.Book
typealias ServerAccount = ChekSchemaV1.ServerAccount
typealias RemoteReadingState = ChekSchemaV1.RemoteReadingState
typealias SourceReadingState = ChekSchemaV3.SourceReadingState

extension ModelContainer {
    /// Chek's store, or an in-memory one for previews and tests.
    ///
    /// The store is named `Chek` because Chek ships as an update to Chibi
    /// Manga, which keeps a different schema in the default store. A store
    /// of its own keeps the two from meeting.
    static func chek(inMemory: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration("Chek", schema: Schema(versionedSchema: ChekSchema.self), isStoredInMemoryOnly: inMemory)
        return try ModelContainer(
            for: Schema(versionedSchema: ChekSchema.self),
            migrationPlan: ChekMigrationPlan.self,
            configurations: configuration
        )
    }
}
