# Runtime Query

## Purpose and Scope

Parent: [DatabaseStudioUI](../DESIGN.md). Own server query presentation for FULL-03.
Children: none. Record editing and schema administration are separate workflows.

## Responsibilities and Boundaries

Preserve canonical typed responses and opaque continuation tokens. DatabaseClient
owns transport; the server owns parsing, authorization, evaluation and snapshots.
A window owns one query state. Replacing a query invalidates its pending result.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [RuntimeConnection](../RuntimeConnection/DESIGN.md) | depends on | execute and cancellation | Authenticated operation execution | Connection generation rejects stale completions |
| [Module](../DESIGN.md) | parent | FULL-03 | Data workspace | Projection changes must preserve query state |

## Architecture

```text
Editor -> RuntimeQuery -> RuntimeConnection -> query.execute
Results <- typed Response + immutable request + continuation
```

## Contracts and Invariants

A next-page request retains the original input, parameters, partitions and budget;
only its continuation changes. The UI retains one bounded page, not every page.
The selected page limit must be positive and within the request budget. A failed
next page preserves the previous page and token for an explicit retry. Starting a
new query clears the previous result. Cancellation invalidates publication before
cancelling the task. A cancelled query is distinguishable from an empty result.
Result cells retain FieldValue types; display strings never replace canonical data.

## State, Ownership, and Lifecycle

MainActor owns the current request, response, status and generation. The SwiftUI
view owns the task and cancels it when removed. Connection replacement additionally
invalidates in-flight operations through RuntimeConnection. No background polling.

## Verification and Change Impact

Tests must execute SQL against an isolated server, traverse multiple pages without
missing or duplicate rows, report syntax/permission failures, reject invalid page
limits, and reject cancelled/superseded completion. The UI must expose Run, Cancel,
Next Page and typed results. FULL-03 remains incomplete until record CRUD, scope,
query persistence and native workflow verification also pass.

## Saved Queries

The query view stores the last 20 executed or explicitly saved statements in
UserDefaults, matching the existing item-query history retention. Entries include
language and endpoint/database/tenant/workspace scope, never credentials or results.
Opening history restores editor text without executing it. Decode and persistence
failures are visible; malformed history is not overwritten by an empty history.

## Mutation Execution

The editor exposes an explicit mutation mode. It sends the entered statement to
mutation.execute, never inferring writes from text or retrying them automatically.
The result preserves the commit version and canonical effects. Cancellation or
transport failure does not prove rollback; the UI tells the user to inspect data
before retrying. A cancelled or superseded request cannot publish a later success.

Each explicit mutation submission creates one UUID idempotency key in canonical
request metadata. No automatic retry generates additional keys.

## Entity Browsing

The Data tab constructs a typed SELECT over the selected schema entity. Entity
names are values in TableRef, never interpolated SQL. Selecting a different entity
creates a fresh view/query lifetime and cancels the previous task. It reuses the
query result renderer and continuation owner. Loading, denied, empty and failed
states remain distinct. Schema/partition metadata unavailable in schema.describe
must not be inferred from entity names; partition editing remains a FULL-03 gap.

Entity browsing accepts a declared field as a typed SortKey and a positive page
size bounded by ExecutionBudget.maximumRows. Apply starts a new query; continuation
uses the previous request unchanged even if draft controls are edited.

## Result Inspection

Table and Raw are projections of the same retained response and issue no requests.
Raw displays canonical typed values and row metadata, not a lossy JSON conversion.
A row detail inspector shows every named column, version and annotations. Row
selection is page-local and is cleared when the page changes, so it cannot identify
an unrelated row after continuation. The query owner advances a page revision on clear and successful publication, including identical consecutive row values. Failed continuation preserves the revision and previous page. Inspection grants no mutation authority.

### Server Filter

The Data tab owns a draft field/comparison/typed scalar condition. Apply validates
its scalar text and supplies an Expression to SelectQuery.filter before paging.
It never filters the current page locally. Strings are literal values, not SQL.
Signed and unsigned integers preserve their full 64-bit range; malformed,
overflowing or non-finite numeric input is rejected without executing a request.
The first form supports scalar comparisons and null checks; compound and other
typed expressions remain available through the query editor. Continuations keep
the applied expression regardless of subsequent draft edits. Runtime verification
must find matching values beyond the unfiltered first page and reject bad input.


## RDF Graph Page Projection

The result presentation retains canonical quads from one bounded page. A graph
projection selects exactly one graph name (nil means the default graph); it must
not union named graphs or infer MultiBase membership. Only exact RDF type and RDFS
subclass predicates change node roles. Literal values retain datatype/language
in inspector metadata, including repeated predicates. Unknown quoted triple node
presentation is an explicit typed failure, not a dropped edge. The canonical
Table/Raw page remains authoritative. A graph projection is not a complete-server
graph or an inference result. Wire decoding, authorization and paging stay with
their existing owners. Tests cover graph isolation, role predicates, repeated
literals and explicit unsupported term failure before UI wiring.

## Shared Result Presentation

Data and Query compose [Result Presentation](../ResultPresentation/DESIGN.md).
The query publishes canonical rows/quads and a page revision; presentation owns
Table/Document/Relationships/Analysis projections and page-local selection.
Toolbar actions remain native and additive. Display changes never execute queries.
All existing execution, filtering, failure and pagination contracts above remain.

### Native Source Controls
Data uses the parent native navigation title and native Refresh/Cancel, Next Page
and Data Options actions. Options stage a draft in a native NavigationStack/Form
sheet; Cancel discards it and Apply performs one existing typed reload. Page size
must be within the existing ExecutionBudget. The Query editor remains content;
Language, Mutation, History, Save, Run/Cancel and Next Page use native toolbar items.
There are no custom entity or Results title bars inside the result content.

Query language, mutation mode, history and Save are grouped in the native Query Options
menu. Run remains a primary action. The editor height is bounded to retain an
initially usable result area. SwiftUI vertical composition prevents nested AppKit
split-view safe-area overlays from covering native table/list headers.

## Query Pane Placement

The result or execution status occupies the upper content area. The bounded query
editor remains at the bottom for empty, row, RDF, boolean and mutation responses.
A divider separates the result from the editor. Switching display modes preserves
this placement, the original sidebar and the native execution toolbar. Native
verification executes a query and compares both positions before and after a mode
change; layout changes do not alter request, cancellation or pagination ownership.

The editor uses an AppKit NSTextView inside an edge-filling NSScrollView.
NSTextView.textContainerInset owns the text margin; SwiftUI applies no outer
padding to the editor. The native view owns selection, undo and scrolling.
Its MainActor delegate publishes edits through the SwiftUI text binding; external
text replacement updates only changed content. Dismantling clears the delegate.
Verification checks typing, query execution, internal margins and mode changes.
