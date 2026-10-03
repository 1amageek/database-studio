# AnalysisWorkspace

## Purpose and Scope
Parent: [DatabaseStudioUI](../DESIGN.md). Children: none. Own presentation-only
analysis of one canonical server result page. Analysis is a Table/Raw sibling in
existing Data and Query results, not a separate application or file importer.

## Responsibilities and Boundaries
RecordAnalysisSource owns bounded projection of retained QueryColumn/QueryRow
values into measurement paths, categories and page-local row identities.
RecordAnalysisView owns cancellable preparation. AnalysisWorkspaceView owns
source coverage and returning a selected point to the original row inspector.
GraphClustering owns computation; GraphView and SpatialGraph own rendering.
The query owner retains canonical data, authorization, filters and pagination.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [DatabaseStudioUI](../DESIGN.md) | parent | Existing result composition | Preserve original sidebar and database controls | No standalone analysis window |
| [RuntimeQuery](../RuntimeQuery/DESIGN.md) | depends on | Immutable typed current page and page revision | Data/Query source and original row inspector | A page is not a whole collection |
| [GraphClustering](../GraphClustering/DESIGN.md) | depends on | Numeric configuration/result/session | Staged features and partitions | Explicit exclusions and bounded computation |
| [SpatialGraph](../SpatialGraph/DESIGN.md) | coordinates with | Shared XY category planes | Comparative layers | No inferred relationships |

## Architecture
```text
Server Data / Query -> canonical retained current page
    -> Table / Raw / Analysis
        -> typed scalar projection -> staged numeric settings -> Run
            -> 2D / 3D -> select point -> Open Row -> original Table inspector
```

## Contracts and Invariants
Analysis content contains no custom title or control header. Source coverage,
Open Row and projection/fit/inspection actions use the enclosing SwiftUI toolbar.
The server owns the navigation title, sidebar and existing toolbar actions;
analysis adds contextual items without replacing them. The native settings
sheet contract belongs to [GraphClustering](../GraphClustering/DESIGN.md).
The original sidebar, connection, entity selection, query, filter and request
remain owned by existing views. Switching display sends no database request.
The analyzed set is exactly the current retained page. Coverage states whether a
continuation exists; it never claims full-collection coverage. Replacing the page
resets display and clears analysis/selection, including identical-value pages.
Nodes identify page row indices, not guessed persisted IDs. Open Row returns the
exact canonical row in the same page and opens its original typed inspector.
Nested document objects use escaped JSON Pointer paths, preventing delimiter
collisions. Null and unsupported values remain missing, never zero. Booleans and
strings remain categorical. Exact integers unrepresentable in Double are excluded
with warnings. Decimal coordinates explicitly approximate the retained exact
values. Nonfinite values, ambiguous columns/paths and exceeded budgets fail.
At most 10000 rows, 128 visited fields per row, eight nested levels and 32 MiB of
scalar text are admitted. Canonical rows are retained without parsing display
strings or JSON round trips. Arrays, vectors and bytes are reported as excluded.
No file import, writes, new query, continuation accumulation or core semantics.

## Runtime Flows
Select Analysis -> concurrently project immutable page -> choose features -> Run
-> inspect profile/member -> Open Row -> Table/typed inspector. Leaving the
analysis projection cancels preparation; page revision removes obsolete state.

## State, Ownership, and Lifecycle
SwiftUI state is MainActor-owned. RecordAnalysisSource is immutable Sendable and
prepares on the concurrent executor. Original FieldValue ownership stays with the
query owner; scalar materialization occurs once at the presentation boundary.
Camera changes and selection never reparse or query the source.

## Failure, Concurrency, and Constraints
Typed projection failures appear in the analysis area. Cancellation publishes no
stale source. Original Table/Raw remains available for all unsupported values.
Analysis adds no database authority or transport lifecycle.

## Verification and Change Impact
RecordAnalysisSourceTests verifies typed nested fields, escaped paths, missingness,
integer/decimal handling, invalid structure, budgets, cancellation and 2000 rows.
GraphNumericAnalysisTests owns numerical behavior. Composition tests own common XY
and original identity preservation. Computer use must verify an authenticated
Data/Query result changing Table/Raw/Analysis, profile/member selection, Open Row,
page invalidation and the unchanged sidebar. Builds alone are not native proof.

## Verified Result-Page Integration

The final URL-dependent package run `FinalPackageTests.xcresult` reports 89
passes, zero failures, skips, expected failures and runtime warnings. It includes
canonical 2000-row projection, exact page identity mapping, capacity and cancellation,
real financial-fixture analysis and shared 2D/3D category composition.
`FinalServerAppBuild.xcresult` builds the actual application. Both use Swift 6.4.0.
Evidence is retained at
`/var/folders/c4/bcbjzcj556d3xj45z64rzjmw0000gn/T/studio-generic-analysis-ugntvedq`.

Computer Use verified the original Entities sidebar and Data/Schema/Query controls,
an authenticated SQL result and the embedded Analysis Setup. The isolated
26.0904.0 server rejected fixture INSERT with ACCESS_DENIED; this existing write
path was not changed. A temporary native harness linked the exact built UI object
and called RuntimeQueryResultsView against four real QueryIR VALUES result rows
from that server. These are query values, not persisted entity records. The
workflow verified feature selection, original-value profiles, member selection,
category layers and unchanged selection in 3D, Open Row returning the exact
canonical negative integer and row metadata in the Table inspector, and a new
failed query clearing the old analysis and selection. No UI XCTest ran.

The harness server stopped with exit zero; an endpoint probe failed with curl
exit seven. Native Data entity selection is not separately exercised: Data and
Query compose the same RuntimeQueryResultsView, whose row path is verified above.

### Native Header Correction

The analysis workspace and embedded GraphView render content directly and
contribute contextual native toolbar items. Source coverage uses Form/Section
headers. Native Computer Use against the exact rebuilt UI object verified that
source details, 2D/3D, Fit, Inspector and selected Open Row appear in the enclosing
toolbar alongside the unchanged server title, sidebar, Refresh Schema and
Disconnect. Cancel discarded the draft; confirming computed four typed server
QueryIR rows; Open Row returned the exact canonical row and removed the analysis
toolbar. This is shared result-view verification in a temporary native host, not
a separate Data entity CRUD run. No analysis logic test was repeated.

Evidence: `/var/folders/c4/bcbjzcj556d3xj45z64rzjmw0000gn/T/studio-native-toolbar-vs_3rdsu`.
HeaderBuild and AppBuild xcresult summaries report successful builds, zero errors;
the package test-product link has one existing duplicate-rpath warning, the app
build has zero warnings. All three edited source hashes match the verified copy.
The isolated server stopped with exit zero and a negative endpoint probe.
