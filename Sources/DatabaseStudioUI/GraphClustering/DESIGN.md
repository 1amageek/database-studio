# GraphClustering

## Purpose and Scope

Parent: [DatabaseStudioUI](../DESIGN.md). Children: none. Own presentation-only
feature analysis of one immutable graph snapshot. The result is usable in 2D
independently of the spatial renderer. No database query, mutation, inferred RDF
statement or authorization change is produced.

## Responsibilities and Boundaries

The analyzer owns feature selection/weighting, deterministic clustering in the
original feature space, two-component PCA projection and inspectable cluster
profiles. The MainActor session owns one cancellable task and generation-bound
result. Views own local camera and canvas controls, not sidebar composition.
SpatialGraph consumes this immutable result without rerunning analysis.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [DatabaseStudioUI](../DESIGN.md) | parent | Graph identity, selection and revision | Composes existing graph UI and independent analysis | Preserve query and navigation state |
| [SpatialGraph](../SpatialGraph/DESIGN.md) | used by | Original identity/edge rendering | Lifts XY onto semantic role layers | Camera/filter changes never recluster |

## Architecture

```text
GraphDocument + analysis configuration
    -> validated same-role samples
        -> sparse weighted feature rows
            -> deterministic bounded k-means (original feature space)
            -> bounded implicit covariance PCA (display only)
                -> immutable result: XY, membership, profiles, excluded IDs
                    -> 2D Canvas
                    -> SpatialGraph semantic layers
```

## Contracts and Invariants

- Compare only the selected GraphNodeRole (instances by default). Other roles
  supply context and original relationships, not clustering samples.
- Features are exact type identity; directed predicate/neighbor identity;
  explicitly selected metadata categories; explicitly selected numeric metrics.
  Node IDs/labels, degree, Source/License/URL/retrieval metadata are not implicit
  features. Exact IRIs distinguish same-label predicates and neighbors.
- Drop categorical dimensions present in every sample or only one sample.
  Apply inverse document frequency and square-root family weights, then normalize
  each nonzero sparse row. Numeric metrics are standardized over observed finite
  values; missing indicators distinguish absent values from measured zero.
- k-means uses squared Euclidean distance in the retained feature space, stable
  identity order and deterministic farthest-first seeds. Requested K is a user
  setting (2–24, default 8); fewer distinct rows yield fewer clusters. Cluster
  IDs are stable for identical input/configuration, not persistent identities
  across independently recomputed snapshots. It is not automatic optimal-K or
  statistical-confidence evidence.
- PCA is a two-dimensional approximation with retained variance reported. It
  never determines membership. Degenerate dimensions remain zero; no jitter,
  artificial cluster gaps or ID-hash coordinates are added.
- Zero-feature samples are explicitly unassigned. Context nodes obtain XY from
  nearest analyzed neighbors through original edges, averaging equal-distance
  predecessors. Disconnected/unassigned nodes occupy a labeled unpositioned
  gutter, not an inferred similarity position. No new nodes/edges are created.
- Profiles expose strongest mean feature coordinates and members. They describe
  the selected model; they are not generated semantic class assertions.

Methods: [k-means](https://scikit-learn.org/stable/modules/clustering.html#k-means)
and [PCA](https://scikit-learn.org/stable/modules/decomposition.html#pca). This
implementation is native Swift and adds no Python/service/runtime dependency.

## Runtime Flows

```text
Enable feature clusters -> prepare current document/configuration
    -> publish current immutable result -> 2D analysis or 3D layers
Config/source replacement -> invalidate generation -> cancel old task -> prepare
Disable/close -> cancel incomplete work; switching 2D/3D retains ready result
Selection/filter/camera -> redraw current result without analysis
```

## State, Ownership, and Lifecycle

Session state is MainActor-owned. Analyzer state is task-local Sendable data
running on the concurrent executor. One structured task is retained, cancellation
checked between bounded steps and before publication. Superseded failures and
results cannot overwrite the current generation. Source/config changes clear
selection and result. Ready results retain the exact configuration and identity
scope; no persistence or cross-source reuse is implied.

## Failure, Concurrency, and Constraints

Admit at most 1000 nodes, 4096 edges, 128 selected attribute/metric keys,
8192 retained features, 65536 retained sparse entries,
24 centroids, 40 clustering iterations and 48 iterations per PCA component.
Elapsed deadline is 10 seconds. These component-owned operational ceilings keep
work/memory bounded and are falsified by the real 1000-entity fixture and timing.
Invalid weights/identity/endpoints/nonfinite metrics, insufficient informative
samples, exhausted resource/convergence/deadline and cancellation are explicit.
No default-data success or network-layout fallback replaces failed analysis.

## Verification and Change Impact

[GraphClusterTests](../../../Tests/GraphDocumentTests/GraphClusterTests.swift)
must test separated feature populations, input permutation, exact predicate
identity, weighting/config changes, common/unique dimensions, numeric missingness,
one-dimensional projection, context mapping, unassigned preservation, invalid
inputs, cancellation and superseded session publication. The native 1000-entity
fixture records analysis timing, finite projection, original identity coverage
and profiles. SpatialGraph verifies exact XY lifting and retained topology.
[GraphClusterCompositionTests](../../../Tests/GraphDocumentTests/GraphClusterCompositionTests.swift)
verify layer lifting, emphasis, projection/config refresh and original query state.
Native Computer use verifies controls, result selection, 2D/3D switching and
unchanged sidebar/inspector/query behavior. No UI XCTest is introduced.
