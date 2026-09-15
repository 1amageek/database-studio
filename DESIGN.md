# Database Studio

## Purpose and Scope

Database Studio is a macOS database workspace for authenticated runtime operations
and direct-storage catalog inspection. This package owns presentation state and
the lifecycle of the connections used by that state. It does not implement
database, schema, index, transaction, or backend semantics.

The parent design is the [workspace design](../DESIGN.md), under the
[normative specification](../SPEC.md). [ARCHITECTURE.md](ARCHITECTURE.md)
provides existing package context. The child design is
[DatabaseStudioUI](Sources/DatabaseStudioUI/DESIGN.md).

## Responsibilities and Boundaries

`DatabaseStudioUI` owns:

- the observable connection state exposed to SwiftUI;
- one active storage inspection connection and its schema registry;
- authenticated runtime connection presentation, using DatabaseClient transport
  and canonical DatabaseWire operations;
- generation ordering for overlapping connection requests;
- detaching, requesting, and awaiting storage-engine shutdown;
- presentation-only conversion of `DatabaseKit` schema values.

`DatabaseStudioUI` does not own storage-engine cleanup internals, query
execution, physical key layout, authorization policy, or runtime hosting.
Those contracts remain with `storage-kit`, `database-framework`, and
`database-kit` respectively.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [DatabaseStudioUI](Sources/DatabaseStudioUI/DESIGN.md) | child | Graph presentation and shared 2D/3D interaction contract | Owns the proposed spatial graph presentation. | Spatial rendering grants no additional database access; provenance and platform gates remain explicit. |
| [Workspace ownership contract](../AGENTS.md) | parent contract | Package ownership and dependency direction | The workspace assigns storage semantics to `storage-kit` and in-process execution to `database-framework`. | A local Studio change must not move those responsibilities into the UI. |
| [Architecture](ARCHITECTURE.md) | package companion | UI boundary and `IndexDescriptor` presentation contract | Studio consumes typed schema metadata and exposes catalog inspection only. | Physical index details must not be reconstructed in Studio. |
| `storage-kit` `StorageEngine` | depends on | `requestShutdown()` plus `waitUntilShutdown()` | Requesting shutdown closes admission; waiting proves backend cleanup is complete. | `requestShutdown()` alone is not a disconnected state. |
| `database-framework` `SchemaRegistry` | used by | `loadAll()` and catalog validation | The registry loads typed schema metadata through the selected engine. | Results from a superseded generation must not be published. |

## Architecture

```text
SwiftUI views
    -> DatabaseStudioState (@MainActor)
        -> StudioDatabaseSession (@MainActor)
            -> one generation-bound ConnectionResource
                -> StorageEngine + SchemaRegistry
                    -> requestShutdown()
                    -> await waitUntilShutdown()
```

Connection replacement follows one ownership path:

```text
new request
    -> invalidate previous generation
    -> cancel and await previous connection operation
    -> detach active/pending resources
    -> .disconnecting
    -> request + await engine shutdown
    -> create and load the new generation
    -> publish .connected only after its metadata is loaded
```

## Contracts and Invariants

- `StudioDatabaseSession` owns at most one published connection resource.
- A connection attempt has one monotonically increasing generation. Only the
  current generation may publish an engine, registry, entities, or an error.
- A resource is detached before shutdown begins. Detached resources remain
  strongly held by the shutdown operation until `waitUntilShutdown()` returns.
  The completed shutdown operation is then released by the current generation.
- `.disconnected` means every resource detached by that transition has
  completed authoritative shutdown. `.disconnecting` is observable while the
  wait is pending.
- A new connection is not installed until the previous connection operation
  and all detached-engine shutdown work have completed.
- Cancellation and setup failure shut down any engine already created and do
  not publish partial metadata or a connected state.
- Repeated disconnect requests share the existing shutdown work and are
  idempotent. A stale disconnect completion cannot change a newer generation's
  state.
- Schema and ontology reads are bound to the connection generation that
  started them. Results from a disconnected or superseded resource are
  rejected rather than copied into the current UI state.
- Direct storage access exposes catalog inspection only; record operations
  continue to fail with `StudioError.databaseRuntimeRequired`.

## Runtime Flows

Connect, replace, disconnect, and cancellation are serialized by the
`@MainActor` session. Suspension occurs only while opening, probing, loading,
or awaiting backend shutdown. The actor may re-enter during these awaits, so
every continuation checks its generation before publishing state.

The connection operation owns setup failure cleanup. An explicit disconnect
invalidates the operation, starts shutdown for resources already visible to
the session, awaits the cancelled operation, and then awaits the shared
shutdown task before publishing `.disconnected`.

## State, Ownership, and Lifecycle

```text
disconnected
    | connect
    v
disconnecting -- shutdown complete --> connecting -- metadata loaded --> connected
    ^                                      |                               |
    |                                      | failure/cancel                | disconnect
    +-------------- shutdown complete <----+-------------------------------+
                                      -> error (only after cleanup)
```

The session owns the active resource and a pending resource while it is being
probed or loaded. Detaching clears the session references immediately, while a
shutdown task owns the detached resources until completion. New generations
may begin setup only after the prior operation and shutdown task finish.

## Failure, Concurrency, and Constraints

- Backend setup errors are reported as `.error` only after cleanup completes.
- Cancellation is not an error presentation; it ends in `.disconnected` when
  the relevant shutdown completes.
- Backend shutdown is asynchronous and must never be replaced by a synchronous
  nil assignment.
- No mutex is held across `await`; actor isolation orders session state, and
  `StorageEngine` owns backend synchronization.
- A shutdown task must not capture the session, preventing a lifecycle cycle;
  it captures only detached connection resources.
- A superseded attempt may finish its backend probe, but it must close that
  resource before the next generation can publish a connection.

## Verification and Change Impact

The lifecycle contract is verified through injected connection resources that
can block shutdown and setup. Tests must prove shutdown completion before
reconnect, idempotent disconnect, cancellation cleanup, stale-generation
rejection, and failed SQLite/FDB setup cleanup. Existing SQLite format
validation and catalog tests remain behavioral coverage for the production
path.

Changes to the session state machine require rechecking
`DatabaseStudioState`, connection settings, main-view state rendering, and all
session tests. Changes to `StorageEngine` shutdown semantics require the
`storage-kit` contract and its backend tests to be reviewed, not reimplemented
in Studio.

Sample application design: [Maintenance Studio](Examples/MaintenanceStudio/DESIGN.md).
