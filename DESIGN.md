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
| [MacComponent](https://github.com/1amageek/mac-component) | depends on | HSplitPane and VSplitPane | URL dependency from 0.2.0 supplies resizable internal content panes. | Native navigation and Inspector remain SwiftUI-owned; no local dependency override. |
| `storage-kit` `StorageEngine` | depends on | `requestShutdown()` plus `waitUntilShutdown()` | Requesting shutdown closes admission; waiting proves backend cleanup is complete. | `requestShutdown()` alone is not a disconnected state. |
| `database-framework` `SchemaRegistry` | used by | `loadAll()` and catalog validation | The registry loads typed schema metadata through the selected engine. | Results from a superseded generation must not be published. |

## Base Window Composition

The product entry point is one base database workspace. [Workspace](Sources/DatabaseStudioUI/Workspace/DESIGN.md) owns scene routing; server and local connection owners retain separate resource lifetimes inside that workspace. Analysis shares the current canonical result and selection with the visible Table. Direct storage remains catalog-only.

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

## Dependency Compatibility

Studio consumes the canonical QueryStatement/SQLBlock execution contract through
published Framework, Kit, Client and StorageKit 26.1026.0 URL dependencies. Package
and application/workspace locks must select those matching release revisions while
retaining their existing unrelated dependency pins, including each graph's existing
Swift Collections version. The ordinary DatabaseWire graph remains target-free.
The released Server 26.1026.0 executable is the isolated native integration peer,
not a linked Studio dependency. This dependency update preserves the application's
versioning, signing, API, scene composition and connection ownership.
Authorization, execution budgets and rollback stay in Framework/Server; Studio
owns bounded presentation and ordered result selection. See
[RuntimeQuery](Sources/DatabaseStudioUI/RuntimeQuery/DESIGN.md).

Dependency updates require the package lifecycle and result tests, the native app
build, and real authenticated server tests for handshake, typed results and
failures, paging, cancellation, and transport shutdown. Direct storage remains
catalog-only and must preserve authoritative engine shutdown.

### Native test runtime ownership

The harness uses exactly one Xcode-generated application test configuration,
selected by its scheme name. It creates a separate temporary configuration and
never uses that generated derivative as the input to another run. Ambiguous or
missing original configurations fail explicitly. This prevents stale test-host,
credential and runtime search paths from accumulating across diagnostic runs.
The identity-checked compiler's testing directory is prepended once to the test
process environment; production loading and application entitlements are unchanged.
The harness owns the derived configuration, isolated server and test host until
completion, removes its configuration and requires negative readiness after shutdown.
The server denies entity data to every role without a configured rule, so the
harness adds an `entityPolicies` rule for the persisted CRUD fixture entity only.
The launchd-hosted test runner and its failure symbolication open the testing
directory and build products with the host's own folder privacy; when they live
in a privacy-protected folder such as Desktop, the runner waits for approval and
the run hangs instead of failing. Keep them outside protected folders.

### Prior verification scope

The package regression lane uses the same clean-configuration rule. A clean
Framework 26.1022.1 build passed all 118 package tests after prior diagnostic
configurations had accumulated stale runtime paths and host substitutions.

The chart, split-pane and schema-inspection integration evidence is 125 package
tests and 19 native app integration tests against Server 26.1022.1, with zero
failures, skips, expected failures or runtime warnings, on the same URL pins.
Native UI verification in the real base window covers Table default with visible
headers, the lower Query editor, all three Swift Charts with point and cluster
selection, the original-value Inspector, both MacComponent divider directions,
Table/Document/3D round trips that retain chart kind and selection, and schema
refresh publishing a newly created entity. The earlier release-update evidence
covers Table, Document and Inspector for exact numeric scale, SQL array bounds,
JSONB null/string distinction, the time endpoint and date infinity.

The canonical execution integration adds one ordered-result collection regression
for 126 package tests. The 19 native app tests additionally compare SQL and IR
columns/values, select SQLBlock outcomes independently, and retain COPY bytes.
Both lanes run against an isolated authenticated SQLite server and require zero
failures, skips, expected failures and runtime warnings plus negative readiness
after authoritative shutdown.

### 26.1026.0 verification contract

```text
Studio UI -> canonical query operation -> released Server 26.1026.0
    -> Framework execution -> isolated SQLite storage
```

The URL-resolved package graph must pass all 135 tests, including its real-server
2,000-row collection and retained numeric dataset tests without skips. The app
must compile and pass all 20 runtime integration tests, including SQL-relation
catalog browsing of a SQL-created table, SQL/IR value
and column equality, ordered SQLBlock/COPY outcomes, authorization rejection,
resource-limit failure, transaction rollback, pagination, cancellation and
transport shutdown. The harness owns a private SQLite file, credentials, listener,
test host and authoritative server teardown with negative readiness. Build and
testing libraries remain outside privacy-protected folders; staging identical
testing-library bytes changes only their test-process search path. Raw logs,
unique result bundles, source hashes and resolved graphs retain compiler and
runtime provenance. No backend or execution contract moves into Studio.

The 2026-10-26 update passed the URL-resolved package focused 8 and consolidated
126 tests, and app focused 4 and consolidated 19 tests, against the exact released
Server 26.1026.0 executable on macOS 27.0.1 arm64 with the existing September 4
compiler. All runs reported zero failures, skips, expected failures and runtime
warnings. Both service harnesses proved negative readiness after authoritative
shutdown. The package retains the pre-existing duplicate `/usr/local/lib` rpath
linker warning; no compiler, macro-plugin or testing-runtime internal error was
reported. Workspace selection and fresh test-configuration generation were
corrected only in the isolated verification workspace, without product changes.

The 2026-10-26 design-conformance change (connection-epoch publication, first-page
complete collection, readable metadata/temporal text, SQL-relation Data browsing)
passed package focused 23 and consolidated 135 tests and app consolidated 20 tests
against the same released Server 26.1026.0 and compiler, with zero failures, skips,
expected failures and runtime warnings and negative readiness after teardown. Native
verification connected the real app to an isolated server: a SQL-created table is
listed under Tables by its SQL schema/name while its physical entity appears only
under Storage Entities; selecting the table loads its rows with ISO 8601 timestamps,
the Inspector shows the version as hexadecimal bytes and empty annotations as None,
and selecting the storage entity opens schema inspection rather than a Data query.
