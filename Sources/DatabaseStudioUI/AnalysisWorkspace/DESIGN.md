# Result Page Projection

## Purpose and Scope
Parent: [DatabaseStudioUI](../DESIGN.md). Children: none.
Own bounded conversion of canonical result rows into analysis measurements.
This component supplies projection logic to [Result Presentation](../ResultPresentation/DESIGN.md), which owns the shared result modes.

## Responsibilities and Boundaries
RecordAnalysisSource owns typed scalar paths, categories and page-local identities.
The query owns canonical rows, authorization, pagination and the Table/Raw UI.
GraphClustering owns numerical algorithms. GraphView owns its original sidebar,
viewport, toolbar, query pane and inspector; it has no sidebar-free variant.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [DatabaseStudioUI](../DESIGN.md) | parent | Original presentation | Restore original information and operations | No replacement analysis window |
| [RuntimeQuery](../RuntimeQuery/DESIGN.md) | depends on | Canonical retained page | Projection input | One shared result viewport |
| [GraphClustering](../GraphClustering/DESIGN.md) | depends on | Measurement inputs | Numeric algorithms remain available | Rendering does not redefine source values |

## Architecture
```text
Server result -> original Table / Raw -> original row inspector
Canonical rows -> RecordAnalysisSource -> AnalysisDataset (projection logic)
Graph window -> original class/node sidebar + viewport + query pane + inspector
```

## Contracts and Invariants
Result Presentation owns the shared Table/Document/Analysis modes; this component
owns no replacement workspace or sidebar. Existing Table/Raw, typed inspection, page revision and request
ownership remain intact. The graph always retains its original NavigationSplitView
sidebar and native toolbar. The main directory browser and connection status are
unchanged. Numeric algorithms and category-layer rendering remain intact.
Projection preserves escaped field paths and page-local row indices. Missing and
unsupported values never become zero; integer precision loss and decimal
approximation remain explicit. Existing projection budgets and failures remain.

## State, Ownership, and Lifecycle
Restoration adds no state or I/O. Canonical data remains owned by its query.

## Verification and Change Impact
RecordAnalysisSourceTests and GraphNumericAnalysisTests retain their existing
behavioral evidence because the numerical/projection source is unchanged.
Build the actual application, then use Computer Use to verify the original
sidebar, selection/inspector, 2D/3D and query pane. A temporary host or empty
Entities list does not establish preservation of the original UI.
