/// A record-level capability requested by Database Studio.
public enum StudioDatabaseOperation: Sendable, Equatable {
    case listRecords
    case readRecord
    case writeRecord
    case deleteRecord
    case readCollectionStatistics

    public var displayName: String {
        switch self {
        case .listRecords:
            return "Listing records"
        case .readRecord:
            return "Reading a record"
        case .writeRecord:
            return "Writing a record"
        case .deleteRecord:
            return "Deleting a record"
        case .readCollectionStatistics:
            return "Reading collection statistics"
        }
    }
}
