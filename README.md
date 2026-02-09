# Database Studio

A native macOS data browser and graph visualizer for FoundationDB.

Browse and manage `@Persistable` data through the `SchemaRegistry` provided by [database-framework](https://github.com/1amageek/database-framework).

## Features

### Data Browser

- **Connection Management** — Connect to FoundationDB via cluster file
- **Entity Tree** — Display `Schema.Entity` in a directory hierarchy
- **Item Table** — Paginated table view for records of the selected entity
- **CRUD** — Create, edit, and delete items
- **Query Builder** — Build predicates with a GUI for filtering
- **Import / Export** — CSV and JSON support
- **Schema Visualization** — Inspect field definitions, indexes, and directory structure
- **Performance Metrics** — Operation timing and slow query log

### Graph Visualizer

Visualize RDF triples, OWL ontologies, and GraphIndex data with a force-directed layout.

- **Force-Directed Layout** — Barnes-Hut O(N log N) repulsion + spring attraction
- **LOD Rendering** — 4 levels of detail based on zoom scale
- **Viewport Culling** — Skip rendering off-screen nodes and edges
- **N-hop Neighborhood Filter** — Show only nodes within N hops of the selected node
- **Edge Label Filter** — Toggle which relationship types to display
- **Node Search** — Search and highlight nodes by label
- **Visual Mapping** — Map node size/color to PageRank, community, degree, etc.
- **SPARQL Console** — Query panel (executable when connected to FoundationDB)
- **Minimap** — Overview overlay of the entire graph
- **Inspector** — View IRI, metadata, connected edges, and metrics for the selected node

## Requirements

- macOS 15+
- Swift 6
- FoundationDB (installed locally)

## Build

```bash
swift build
```

To open in Xcode:

```bash
open Studio.xcworkspace
```

## Dependencies

| Package | Role |
|---------|------|
| [database-framework](https://github.com/1amageek/database-framework) | DatabaseEngine, SchemaRegistry, CatalogDataAccess |
| [database-kit](https://github.com/1amageek/database-kit) | Persistable, Schema.Entity, Graph (OWL/RDF) |

## Architecture

```
DatabaseStudioUI (SwiftUI)
├── Views/          UI components
├── ViewModels/     @Observable state management
├── Services/       StudioDataService, MetricsService
└── Query/          Query builder and history

         ↓ async/await

database-framework
├── SchemaRegistry    Persist and load Schema.Entity
├── CatalogDataAccess Dynamic data access (no @Persistable types needed)
└── DatabaseEngine    FDBContainer, FDBContext
```

## License

MIT
