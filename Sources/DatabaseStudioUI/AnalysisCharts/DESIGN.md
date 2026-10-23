# Analysis Charts

## Purpose and Scope
Parent: [DatabaseStudioUI](../DESIGN.md). Children: none. Own read-only Swift
Charts representations of one immutable, already computed analysis result.

## Responsibilities and Boundaries
AnalysisChartProjecting exposes the projection contract; AnalysisChartProjection
validates row identities and prepares reusable points, counts and quartile series.
AnalysisChartView owns marks and plot-coordinate picking. ResultPresentation owns
chart preferences, cached projection, source selection and the enclosing toolbar.
GraphClustering remains the sole owner of analysis and cluster membership.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [DatabaseStudioUI](../DESIGN.md) | parent | Native composition | Same Data/Query window | No sidebar or window ownership |
| [ResultPresentation](../ResultPresentation/DESIGN.md) | used by | Page row identity and selection | Links charts to Table/Inspector | Selection must not change the population |
| [GraphClustering](../GraphClustering/DESIGN.md) | depends on | Immutable result, axis inverse, original-value profiles and palette | Display existing computation | No reclustering or inferred edges |

## Architecture
```text
GraphClusterResult -> AnalysisChartProjection -> immutable AnalysisChartData
    -> PointMark: shared analysis XY and cluster color
    -> BarMark: exact member counts
    -> RuleMark + PointMark: original-value Q1/median/Q3
Plot picking -> row/cluster callback -> ResultPresentation -> Table + Inspector
```

## Contracts and Invariants
- Every admitted point maps to an original page row and one declared cluster.
  Missing/invalid positions, identities, membership or quartiles fail explicitly.
- Excluded rows do not become zero points or counted cluster members. Charts
  display analyzed and excluded counts; excluded rows remain in the original Table.
- Selected axes invert the existing [-4,4] mapping to transformed, robust units;
  PCA coordinates remain unchanged and expose retained variance. Neither chart
  position nor a display change determines cluster membership.
- Profiles show original-value medians and interquartile ranges for one selected
  feature with its population median as a reference. Features are never combined
  onto a shared numeric scale. Quartiles are not confidence intervals.
- Marks share the existing cluster palette. Point picking searches only inside
  the plot and uses a 12-point hit radius with stable original-row tie breaking.
  Count/profile picking selects exact cluster members through the parent callback.
- Chart kind, feature and selection changes perform no query or analysis. Projection
  is cached once per session revision, reused across Table/3D switches and cleared
  on analysis revision or page replacement. At most the existing numeric analysis
  capacity of 10000 points, 24 groups and 32 features is admitted.

## Runtime Flows
Enter 2D Analysis -> await existing session result -> project concurrently ->
publish only for the current page/session revision -> render selected chart.
Configuration replacement cancels old preparation and hides stale chart data.
Return from 3D reuses the ready session and projection. Empty configuration asks
for setup; loading, cancellation and failed analysis remain distinct.

## State, Ownership, and Lifecycle
AnalysisChartData is immutable Sendable storage. ResultPageState is MainActor-owned
and retains projection/preferences for its page lifetime. Views never mutate
canonical values or own an additional clustering session. Structured view tasks
propagate cancellation; stale completions cannot replace current chart data.

## Failure, Concurrency, and Constraints
Projection validates bounded shapes before materialization, checks cancellation
between batches and propagates typed errors. No pointer or unchecked shared state
is used. Chart rendering consumes prepared arrays; selection picking is O(N) only
on a tap, not on every redraw. Failed charts preserve Table/Raw access.

## Verification and Change Impact
[AnalysisChartTests](../../../Tests/GraphDocumentTests/AnalysisChartTests.swift)
executes the real analyzer and checks coordinate inversion, PCA identity, exact
counts/profiles, excluded rows, invalid input, cancellation, cache invalidation and
selection after sorting. Native Computer Use verifies all three Swift Charts,
point/cluster selection and original-value Inspector inside the real base window,
native toolbar and original sidebar, both MacComponent dividers, lower Query and
2D/3D/Table switching. UI XCTest is not used. Changes to projection/session contracts
require rechecking ResultPresentation and GraphClustering assumptions.
