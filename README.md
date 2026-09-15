# Database Studio

Database Studio is a native macOS inspector for databases built with
[`database-framework`](https://github.com/1amageek/database-framework).

It presents schema, index, ontology, graph, and record-oriented tools while
preserving the runtime boundary defined by database-framework.

## Runtime boundary

```text
DatabaseStudioState
        |
        +-- StudioDatabaseSession -- direct StorageEngine
        |                              |
        |                              +-- DatabaseFormatCatalog validation
        |                              +-- SchemaRegistry
        |                              +-- OntologyStore
        |
        +-- authenticated DatabaseWire runtime -- record/query/mutation operations
```

Direct storage access is intentionally limited to catalog, schema, and ontology
inspection. Record listing, lookup, mutation, and collection statistics require
an authenticated application runtime over DatabaseWire. Until that runtime is
configured, those operations return `StudioError.databaseRuntimeRequired` and
the UI presents the failure. They never return placeholder records or report a
successful mutation.

## Features

- SQLite and FoundationDB connection selection
- Canonical database-format validation
- Schema entity and index inspection
- OWL ontology and RDF graph visualization
- Local SPARQL dataset exploration
- Record query, import, export, metrics, map, search, vector, and analytics UI
- Typed import/export failures without skipped records or empty-data fallbacks
- Zero-copy-oriented import ownership using Swift collection copy-on-write
- Streaming-style JSONL and CSV export assembly without whole-file line arrays

Record-dependent tools become operational only when the DatabaseWire runtime
connection described above is installed.

## Requirements

- macOS 26 or later
- Swift snapshot `swift-6.4.x-DEVELOPMENT-SNAPSHOT-2026-09-04-a`
- Xcode 27, whose bundled compiler evaluates the Swift 6.4 package manifests
- FoundationDB client libraries for FoundationDB connections

## Build and test

Build and launch the macOS app:

```bash
./run.sh
```

The script uses the installed September 4 snapshot for source compilation and
Xcode's bundled toolchain for package evaluation and linking. It saves build
logs and a result bundle in a unique temporary directory and launches only
after a successful build. Build products are retained in `DerivedData`.

Run the launch UI tests with local ad-hoc signing:

```bash
result_directory="$(mktemp -d)"
perl -e 'alarm shift; exec @ARGV' 600 env \
  TOOLCHAINS=com.apple.dt.toolchain.XcodeDefault xcodebuild \
  -project "Database Studio/Database Studio.xcodeproj" \
  -scheme "Database Studio" \
  -destination "platform=macOS" \
  -derivedDataPath DerivedData \
  -resultBundlePath "$result_directory/Launch.xcresult" \
  '-only-testing:Database StudioUITests' \
  SWIFT_EXEC="$(xcrun --toolchain org.swift.64202609041a --find swiftc)" \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
  test 2>&1 | tee "$result_directory/test.log"
xcrun xcresulttool get test-results summary \
  --path "$result_directory/Launch.xcresult"
```

## Dependencies

| Package | Responsibility |
|---|---|
| `database-framework` | Catalog validation, schema registry, ontology and graph runtimes |
| `database-kit` | Canonical schema, RDF, query, and value models |
| `storage-kit` | SQLite and FoundationDB `StorageEngine` implementations |

## Source organization

```text
Sources/DatabaseStudioUI
├── ApplicationState/  Application and dashboard state ownership
├── Components/        Reusable presentation components
├── Models/            Studio presentation and error models
├── Query/             Local record-filter and query-history models
├── Services/          Database session, metrics, and history stores
└── Views/             Database inspection tools
```

The API and declaration naming contract is defined in
[`AGENTS.md`](AGENTS.md). Declarations are named for database responsibility,
observable behavior, state, ownership, or lifecycle—not their implementation
language, calling convention, or storage representation.

## License

Licensed under the [MIT License](LICENSE).
