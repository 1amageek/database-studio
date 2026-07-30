# Database Studio Agent Context

The canonical repository instructions are in [`../AGENTS.md`](../AGENTS.md).
They apply to public, internal, private, test, generated-support, and
host-boundary declarations.

## Current architecture

```text
DatabaseStudioState
├── StudioDatabaseSession
│   ├── DatabaseFormatCatalog validation
│   ├── SchemaRegistry
│   └── OntologyStore
└── authenticated DatabaseWire runtime for record operations
```

Direct `StorageEngine` access is catalog-only. Do not recreate the removed
dynamic CRUD path in Database Studio. Record query and mutation operations must
use the authenticated DatabaseWire runtime. Until that transport is configured,
the existing typed `databaseRuntimeRequired` failure is the correct behavior.

Use semantic declaration names. Calling convention, implementation language,
ABI, binary representation, storage layout, and architectural mechanism are not
acceptable declaration names.
