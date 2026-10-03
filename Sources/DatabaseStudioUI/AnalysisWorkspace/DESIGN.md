# AnalysisWorkspace

## Purpose and Scope
Parent: [DatabaseStudioUI](../DESIGN.md). Children: none. Own standalone,
presentation-only numeric dataset intake and workspace composition. No database
write, server query or application-specific financial schema is introduced.

## Responsibilities and Boundaries
`AnalysisDatasetReading` defines immutable local-file intake. `AnalysisDatasetReader`
validates CSV/JSON and retains original row identities, scalar columns, missingness,
quality flags and envelope provenance. `AnalysisWorkspaceView` owns one cancellable,
generation-guarded import and source summary. GraphClustering owns analysis;
GraphView and SpatialGraph own existing navigation, selection and rendering.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [DatabaseStudioUI](../DESIGN.md) | parent | Workspace composition | Separate analysis window | Existing sidebar composition remains unchanged |
| [GraphClustering](../GraphClustering/DESIGN.md) | depends on | Numeric configuration/result/session | Analyze imported metrics or graph metrics | Explicit exclusion and bounded computation |
| [SpatialGraph](../SpatialGraph/DESIGN.md) | coordinates with | Common XY category planes | Optional comparative layers | No inferred relationships |

## Architecture
```text
Local CSV / JSON -> validated immutable GraphDocument + source receipt
    -> GraphView (numeric analysis mode)
        -> staged features / transforms / ratios / weights / peers / XY / layers
            -> Run -> GraphClustering result -> 2D or category layers
```

## Contracts and Invariants
JSON accepts an array of row objects or an object with a `rows` array. Row numeric
scalars, nested `metrics`, string categories, `id`, and label/name/company are
retained. Null is absent, boolean is categorical. Nested non-scalar fields are
reported as omitted, except preserved quality flags. Explicit duplicate or empty
IDs fail. Missing IDs receive source-scoped row identities, not durable issuer IDs.
CSV is UTF-8 comma- or semicolon-separated with quoted fields, doubled quotes and
embedded newlines; header names must be nonempty/unique and widths must match.
Columns whose nonempty values are all finite numeric values become metrics;
other columns remain categories. No currency/unit conversion is inferred.
At most 32 MiB of file bytes, 10000 rows, and 128 scalar columns per row are
admitted. Malformed structure/encoding/nonfinite numeric values fail explicitly.
Source display includes row count, numeric columns, null counts, flags and
available envelope units/period/provenance. Import never silently replaces a
working document on failure and never calls GraphWindowState refresh.

## Runtime Flows
Open workspace -> import CSV/JSON -> source summary -> choose features -> Run
-> results -> selection/profile -> 2D/3D. New import cancels the old task and
publishes only the latest generation. Closing cancels the pending task.

## State, Ownership, and Lifecycle
View state is MainActor-owned; immutable parsing runs on the concurrent executor.
Security-scoped URL access is acquired/released in the same task. Imported rows
remain window-local; no mutation of the original file or another graph window.

## Failure, Concurrency, and Constraints
Typed reader failures and native file errors are shown in the workspace.
Cancellation publishes no error or stale document. Imports are serialized by
one retained task and generation. Bounded Data and scalar materialization are
required at the external file/GraphNode ownership boundary; no repeated parsing
occurs on camera or selection changes.

## Verification and Change Impact
`AnalysisDatasetTests` verifies CSV quotes/newlines, scalar typing, nulls,
provenance, all 2000 retained rows, malformed data, IDs and input budgets. Numeric
behavior belongs to GraphClustering tests; category geometry to composition tests.
Computer use verifies real file import, settings, Run, inspection and source
replacement. App builds and headless tests do not substitute for native UI checks.
