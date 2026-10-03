# Result Presentation

## Purpose and Scope
Parent: [DatabaseStudioUI](../DESIGN.md). Children: none. Own read-only presentation
of one immutable canonical server result page shared by Data and Query.

## Responsibilities and Boundaries
ResultPageView composes a native toolbar, content projection and one Inspector.
ResultPageState owns page-local identity, selection, loaded-page ordering, column
visibility and retained graph/analysis state. The query owner retains execution,
authorization, filtering, continuation and canonical data. GraphClustering and
SpatialGraph own existing computation and rendering. MainView, RuntimeConnectionView
and standalone GraphView retain their original sidebars. No new window or sidebar.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [DatabaseStudioUI](../DESIGN.md) | parent | Existing composition | Preserve sidebar and operations | Native navigation title remains with parent |
| [RuntimeQuery](../RuntimeQuery/DESIGN.md) | depends on | Canonical page/revision and named RDF graph projection | Data/Query source | Mode changes never execute a request |
| [Result Page Projection](../AnalysisWorkspace/DESIGN.md) | depends on | Bounded typed measurements and fixed row identities | Numeric input | Exact values remain canonical; explicit projection failures |
| [GraphClustering](../GraphClustering/DESIGN.md) | depends on | Configuration/session/result and native settings | 2D analysis | XY projection is separate from clustering |
| [SpatialGraph](../SpatialGraph/DESIGN.md) | depends on | Relationship network or shared-XY category layers | Conditional 3D | Preserve identity and category semantics |

## Architecture
```text
Data / Query -> immutable canonical page + revision -> ResultPageView
    toolbar: Table (default) / Document / Relationships (RDF only) / Analysis (rows only)
    content: native Table / structured values / linked Table + relationship or analysis viewport
    selection: fixed original page indices <-> Inspector / viewport
    supplemental actions: Columns / Raw / Coverage / Inspector
Parent sidebar, title, source filter, pagination and request execution remain intact.
```

## Contracts and Invariants
Table is the default for every new result. Each row keeps its original zero-based
page index through ordering, column visibility and mode changes. Multi-selection
is supported by Table; analysis point selection maps to that exact original row.
Document and Inspector consume original values and metadata, never display strings.
Rows are formatted for reading without numeric coercion; Raw retains typed data.
Local header ordering sorts only loaded rows using canonical FieldValue ordering;
the Data source controls remain responsible for whole-query server ordering.
Only explicitly returned RDF quads enable Relationships. A graph selector isolates
one named/default graph; different graphs are not merged. Graph selection maps to
all matching incident quads within that graph. Unsupported quoted terms fail
explicitly; Table/Document/Raw remain available. Numeric Analysis uses only the
currently published rows (one page or an explicitly collected bounded query result), reports capacity/missing/precision failures and never fetches
additional records or claims full-collection coverage from a missing continuation.
Mode, source coverage, projection, fit and Inspector actions live in the enclosing
SwiftUI toolbar. Display modes use primaryAction so the native TabView navigation
can retain its own placement. Query settings/history/save share a native menu,
and the editor is bounded to leave room for results. Content has no custom title/control header. Native analysis setup and cluster selection belong to the enclosing toolbar, not
an overlay content header. The Inspector shows cluster profiles and original row
values. Selecting a cluster highlights all member rows without filtering the source;
selecting a point or Table row highlights that exact row. Programmatic graph-selection
echoes cannot collapse a multi-row selection. Returning to Table retains selection,
columns and ordering. No persisted identity
or mutation authority is inferred from an aggregate result or a page-local index.

## Runtime Flows
Page publication -> one row-wrapper array retaining canonical backing -> Table.
Mode switch retains selection/order and sends no request. Analysis and Relationships
keep the same Table beside the viewport in one SwiftUI horizontal composition,
so selected values remain visible without a representation round trip. Analysis selection maps
via page-row identity. Returning to Table highlights the original selected row.
Replacing the page destroys presentation state via page revision, cancels pending
preparation and discards the prior selection. Failed continuation retains the page.

## State, Ownership, and Lifecycle
All mutable presentation state is MainActor-owned. Row wrappers materialize once
per page; canonical values share their existing immutable/COW backing. Sorting
reorders wrappers only when the header sort changes. Numeric source projection
runs concurrently and checks cancellation before publishing. Graph session results,
configuration and cameras remain retained across display changes. Leaving the
page cancels active preparation and graph/session work.

## Failure, Concurrency, and Constraints
The query's admitted page bounds apply to tables/documents. Numeric and spatial
capacity follows the existing component contracts. Invalid row shape fails before
cell indexing. No failure becomes an empty successful dataset. A page cannot grant
edit/delete authority. Empty rows are distinguishable from failures.

## Verification and Change Impact
ResultPresentationTests own exact cluster-member highlighting, multi-selection echo
rejection, preserved ordering/configuration and native-page identity across typed sorting (including
UInt64 boundaries and duplicate rows), selection/mode changes, graph isolation and
incident quad mapping, exact formatting, invalid shape, numeric preparation and
cancellation. Existing numeric/spatial tests remain valid when their code is
unchanged. Computer Use in the actual application must establish Table default,
Document/Raw/Analysis selection, source coverage and original sidebar preservation.
A temporary result-only host is insufficient evidence of application composition.

Query passes its source editor as view content. ResultPageView composes that editor
below the viewport before applying the native Inspector; the Inspector belongs to
the complete screen rather than an embedded lower split pane. This keeps native
scroll-view safe areas aligned with the enclosing toolbar. Data passes no editor.

Editor placement is owned by [Runtime Query](../RuntimeQuery/DESIGN.md#query-pane-placement).
