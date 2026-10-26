/// A sidebar selection: SQL relations open Data browsing, storage entities open inspection only.
enum RuntimeBrowserSelection: Hashable {
    case relation(RuntimeRelation.ID)
    case entity(String)
}
