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

### Native behavior evidence (2026-10-03)

Evidence directory: `/var/folders/c4/bcbjzcj556d3xj45z64rzjmw0000gn/T/studio-feature-clusters-5b2b2z3h`.
macOS 27 arm64, Xcode 27 and Swift 6.4.0 release; default traits and URL
package dependencies. No UI XCTest or external database service was used.

| Verification owner | Observed behavior | Limit |
|---|---|---|
| Analyzer/session focused tests | 10 pass; numeric missingness, exact relationship profiles and superseded completion rechecks pass; updated session framing passes | Native fixture, not arbitrary future graph sizes |
| Composition tests | 3 pass; exact XY lifting, original paths, occupied roles, configuration refresh and query/selection preservation; focused label/emphasis recheck passes | Headless native geometry/state execution |
| Computer use | 1000 entities yield 939 assigned, 41 explicitly unassigned, 352 features, 8 clusters and 18% retained variance; K 8→7→8 refreshes; cluster profiles expose original predicate/neighbor IRIs | Low retained variance limits planar-distance interpretation |
| Computer use | Cluster 4 member Daimler Truck opens the existing Inspector; 2D→3D retains Cluster 4, its node selection, query text and five executed SPARQL results | Local graph query path, not server query evidence |
| Computer use | Instances 980 and Types 20 planes, original inter-layer edges, neutral labeled unpositioned gutter and cluster emphasis render; cluster-wide predicate clutter is removed | Inherited three-finger input is unchanged; this task does not claim a new physical-touch verification |

Analysis took 0.084–0.086 seconds for this fixture in the focused native runs.
This measures analysis, not GPU frame time or end-to-end application launch.
Ready results are reused by both surfaces; camera/filter/selection changes do not
invoke analysis. Known pre-existing duplicate-rpath/AppIntents build warnings are
preserved in logs; no compiler internal error was observed.

The consolidated package lane `IntegratedAfterLoad.xcresult` executes exactly
79 tests: 79 passed, zero failures, skips, expected failures and runtime warnings.
All 16 changed production/test source files match the isolated verification copy
(`verified-source-hashes.json`); 22 external URL dependency pins are retained in
`PackageDerivedData-resolved-pins.json`. The native app composes the local Studio
package and the same external URL graph; no external local-path override was used.
Package.swift and dependency traits were not changed by this task.

Two earlier consolidated runs each recorded 78 passes and one ordinary-network
elapsed-limit failure during heavy concurrent host work (observed load up to
141.98). That case passed alone in 3.26 seconds. With the busy build finished and
load reduced to 25.66, the unchanged consolidated artifact passed all 79 tests;
ordinary layout took 1.72 seconds and feature analysis 0.206 seconds. The original
10-second deadlines remain intact. Failure bundles and logs are preserved;
focused timings are not generalized to a loaded machine. All required gaps are
closed; further unchanged verification is unnecessary.

## Generic Numeric Analysis Contract

GraphClustering additionally owns numeric feature specifications and analysis of
same-role graph metrics through `GraphNumericAnalyzer`. `GraphFeatureAnalyzer`
dispatches explicitly by configuration mode. Graph mode retains its original
1000-node normalization and capacity contract. Numeric mode admits 10000 nodes,
4096 edges, 32 selected features, 24 centroids, 100 k-means iterations, 48 PCA
iterations per component and a 10-second deadline. Its dense N-by-D table is the
required transformed ownership boundary; no N-by-N matrix is retained.

Features are selected measurements or a numerator divided by a strictly positive
denominator. Identity, labels and categories are never implicit numeric features.
Identity/log10/asinh transforms precede median/IQR scaling (zero IQR uses one transformed unit; constant dimensions
have zero coordinates). Rows missing any selected feature, with invalid transform
or with explicit source quality flags are excluded with reasons, retained in the
result and shown in a gutter. Missing values are never zero-imputed. A finite
row at the population median remains a valid sample. No row L2 normalization is
applied. Per-feature finite weights 0–8 apply after scaling; at least one positive
weight and one varying dimension are required.

Optional peer comparison subtracts each category's feature median in the globally
scaled space. Missing groups and groups smaller than two usable rows are excluded
explicitly; this is group centering, not matched-peer valuation inference.
Direct XY uses selected transformed/scaled coordinates (including peer centering
when enabled), independently maps each axis to [-4,4], and retains tick values and
labels. PCA is an alternative display approximation only. Both displays classify
in the same full feature space. Every cluster reports original-value feature
medians/IQR and the population reference. No automatic optimal K or confidence
claim is made. K is staged with the feature configuration until Run Analysis.

Optional metadata layers have common plane bounds and the exact same XY as 2D;
category labels define height, which has no numeric interpretation. Up to 64
occupied categories are admitted; excess categories fail explicitly. No edges
are inferred from numerical similarity. Result reuse, cancellation, generation
checks and retained cameras use the existing MainActor session.

Verification: `GraphNumericAnalysisTests` owns transforms, ratios, nonzero and
zero-median samples, missing/quality exclusion, deterministic membership, peer
centering, display-only changes, the real 2000-row fixture, capacity and cancelled
work. Composition tests own exact category lifting and source/selection state.
Native Computer use owns staged settings, retained-page inspection and 2D/3D behavior.

Core evidence: `CoreFocused3.xcresult` in
`/var/folders/c4/bcbjzcj556d3xj45z64rzjmw0000gn/T/studio-generic-analysis-ugntvedq`
reports 9 passed, zero failures/skips/expected failures/runtime warnings. Native
Swift 6.4 release compilation uses Xcode Default for package-manifest tool lookup,
with explicit release SWIFT_EXEC for target builds. The full retained 2000-row
snapshot yields 1996 assigned and four explicitly flagged exclusions, retaining
all identities; measured analysis was 0.55 seconds / 47 iterations. The integrated result-page evidence is recorded in
[AnalysisWorkspace](../AnalysisWorkspace/DESIGN.md).
