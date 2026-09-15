# DatabaseStudioUI

## Purpose and Scope

Status: implementation in progress, 2026-09-15. A standalone macOS RealityView
probe on the pinned toolchain rendered a plane, moved its camera and accepted
screen-aligned selection. Integrated renderer verification remains pending.

Parent: [Database Studio](../../DESIGN.md).
Child: [SpatialGraph](SpatialGraph/DESIGN.md).
Existing folders are source navigation locations, not newly declared component
boundaries. Studio integrates the existing database runtime through DatabaseClient; it does
not implement a new runtime. Source-dependent presentation capabilities remain
explicit gates until their canonical operations are connected.

The requested result is a beautiful, readable graph whose **space is 3D and
whose nodes remain 2D**, with reversible 2D/3D presentation switching. The
existing implementation informs data meaning and useful interactions; its
exact appearance is not an immutable design requirement.

### Fixed decisions

- Flat class and individual glyphs retain distinguishable silhouettes, icons,
  labels and domain colors; they have no extrusion, bevel or volumetric body.
- Layers, node coordinates and relationship paths occupy spatial depth.
- One central viewport presents either 2D or 3D and either the ontology view
  or an available MultiBase view. MultiBase is never a second bottom canvas.
- The lower pane remains the SPARQL editor and Table/Raw result panel.
- Changing projection preserves data identity, selection, filters, query text,
  results, inspector state and navigation history.
- Unknown provenance, missing runtime access and unsupported capabilities are
  explicit states. Visual grouping is not permission, inference or membership.

## Responsibilities and Boundaries

| Owner | Responsibility | Boundary |
|---|---|---|
| Graph window and `GraphViewState` | Document revision, selection, filtering, focus, query presentation and projection state | No independent renderer-owned copy of semantic state |
| Graph conversion in Studio | Preserve node/edge identity, role, labels and supplied provenance | No Base membership inferred from IRI, color, folder name or proximity |
| 2D layout and spatial layout | Presentation coordinates keyed by identity and revision | No changes to triples, class membership or authorization |
| `GraphCanvas` / proposed RealityKit view | Draw the same visible graph and emit identity-based interaction intents | No storage handles, queries, grants or ontology reasoning |
| Existing query panel | Edit and evaluate local document queries; render results and errors | Projection switching never changes the query dataset |
| DatabaseKit / database runtime | Canonical ontology, Base, Composition and source/derived lineage | Studio consumes their contracts; it does not recreate them |

Use the existing state and conversion responsibilities before adding new
abstractions. This design does not introduce a public renderer protocol or
core-package DTO. Any eventual provenance carrier is Studio presentation state
wrapping canonical values, with exact API shape decided at its integration gate.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Package](../../DESIGN.md) | parent | Connection generation and authoritative shutdown | Owns access lifecycle | A stale scene must not outlive its data generation |
| [Workspace specification](../../../SPEC.md) | authority | Sections 8, 15, 16, 19 | Directory/Partition, Base, grants and Composition | Base partitions remain independent; federation has no global snapshot |
| [DatabaseKit](../../../database-kit/DESIGN.md) | depends on | Graph semantics and optional MultiBase values | Owns domain representation | Projection does not redefine canonical identity |
| [DatabaseFramework](../../../database-framework/DESIGN.md) | depends on | Execution, authorization and ontology reads | Supplies permitted data | Current Studio record access is unavailable |

## Architecture

```text
Graph window
├── Sidebar: class tree / available Base targets / filters
├── Detail column
│   ├── Toolbar: [2D | 3D]   [Ontology | MultiBase, when available]
│   ├── ONE graph viewport: GraphCanvas OR RealityKit presentation
│   │   └── in-viewport orbit / pan / zoom / fit / layer controls
│   └── Existing optional VSplitView lower pane
│       └── HSplitView: SPARQL editor | results [Table | Raw]
└── Existing inspector: Detail / Events / People / Places
```

```mermaid
flowchart TD
  Input[Authorized document and optional provenance] --> State[Shared graph state + revision]
  State --> Visible[One visible node and edge selection]
  Visible --> Flat[2D positions + GraphCanvas]
  Visible --> Space[Spatial positions + RealityKit]
  Flat --> Intent[Select / focus / drag intents by identity]
  Space --> Intent
  Intent --> State
  State --> Sidebar[Sidebar and inspector]
  State --> Query[Existing SPARQL editor and results]
```

### Confirmed current paths

These observations come from source, not a live-data rendering verification.

| Path | Current behavior and consequence |
|---|---|
| [ItemsContentView](Views/Items/ItemsContentView.swift) → [GraphWindowView](Views/Graph/GraphWindowView.swift) | A property-graph index enables loading records, constructing a graph, then merging ontology information |
| [Records conversion](Views/Graph/GraphDocument+Records.swift), [RDF conversion](Views/Graph/GraphDocument+RDF.swift) | Class membership becomes an edge; literal values become node metadata rather than additional visible nodes |
| [Ontology conversion](Views/Graph/GraphDocument+Ontology.swift) | Standalone conversion handles named class axioms and domain/range edges; merging into records adds classes and subclass edges. It does not retain import provenance |
| [GraphViewState](Views/Graph/GraphViewState.swift) | Removes `owl:Thing`, computes metrics, applies class/search/facet/neighborhood/backbone visibility, and owns separate full/focus layouts |
| [GraphCanvas](Views/Graph/GraphCanvas.swift) | Actual production renderer uses rounded squares for classes and circles for other roles; camera scale controls detail, icons and labels. `GraphNodeView` is not this rendering path |
| [GraphNodeStyle](Views/Graph/GraphNodeStyle.swift) and state | Class ancestors supply icons and domain colors; instances inherit them through their type edges |
| [GraphView](Views/Graph/GraphView.swift) → [QueryPanelView](Views/Graph/QueryPanelView.swift) | The optional bottom pane is a SPARQL editor plus Table/Raw results. Query execution uses the graph document snapshot, not the visible subset |
| [StudioDatabaseSession](Services/StudioDatabaseSession.swift) | Loads only the first stored ontology; record operations explicitly require a database runtime. A multi-ontology or MultiBase source is not currently wired |

## Contracts and Invariants

### Visual language

| Element | Presentation |
|---|---|
| Class | Flat rounded square with icon and label |
| Individual | Flat circle with icon and label |
| Other existing roles | Preserve their explicit role and fallback styling; do not convert metadata into invented graph objects |
| Domain family | Restrained inherited color; color never stands for Base authorization |
| Selection / search | Separate outline treatments; selection does not overwrite domain color |
| Relationship | Directed line with original predicate; show readable labels primarily near focus or at close zoom |
| Layer | Thin, low-contrast plane/contour with heading; optional guides, no glass slab |
| Base | Independently bounded peer region containing its graph |
| Composition | Separate association to participating Base regions, never a relationship triple or containment edge |

Beauty comes from spacing, typographic hierarchy, stable motion, restrained
color and legible relationships. Labels and glyphs face the camera without
tilting with layer surfaces. No lighting-dependent contrast on node faces.
Respect light/dark appearance and reduced motion. Shape, text and the accessible
sidebar must identify objects without relying on color or depth alone.

### Shared projection state

2D/3D is presentation state, not a document reload. Both renderers consume
identical visible node/edge identities and shared filters. Occlusion and
level-of-detail are rendering decisions and do not remove graph data.

Retain independent 2D and 3D camera/position state. Returning to a visited mode
restores it rather than fitting again. The first spatial view initializes from
the existing layout and explicit layer assignment. Keep the selected identity
as the transition anchor. Spatial drag changes presentation offsets only; it
does not reparent nodes or move data between Bases. Layer assignment changes
through explicit presentation controls, not dragging across a plane.

Existing timeline layout remains a 2D presentation in the first implementation.
While timeline mode is active, explain why 3D is unavailable; switching requires
turning timeline off. Do not discard timeline state silently. The current 2D
minimap remains 2D-only; spatial Fit and orientation controls occupy the viewport.

### Ontology layers

Use explicit named `subClassOf` edges for hierarchy layout. Do not hard-code
three planes or insert an `owl:Thing` hub. For display depth, collapse strongly
connected class groups, then compute deterministic longest-parent-path depth
on the resulting acyclic graph; disconnected roots start at depth zero. Keep
all original edges and identities, including cycles and multiple inheritance.
Grouping cycles is layout bookkeeping, not an assertion of class equivalence.

Place individuals after the deepest retained class layer and keep every type
edge. Untyped individuals receive an explicitly unclassified group. Existing
role visibility still applies; enabling 3D does not implicitly enable classes.
Compute layer assignment from the retained document, not a transient filtered
subset, so searching does not move every node between layers.

Imported-ontology grouping is a separate, provenance-dependent arrangement.
An imports list alone does not assign every node or axiom to a source ontology.
Offer it only after source membership is supplied. Imports, subclass edges and
instance edges have different meanings and may not be substituted for one another.

### MultiBase layers

Each Base is an independent region; hierarchy depth remains inside that region.
Preserve a scoped presentation identity consisting of the supplied source scope
and local graph identity. Equal IRIs in different Bases must not be merged merely
to simplify rendering. For repeated representations of shared ontology classes,
retain one semantic identity plus distinct presentation occurrences; selection
must expose the current occurrence's scope.

Consume canonical `CompositionOrigin.source` or `.derived(contributors:)`.
Derived results occupy a clearly identified result group with all contributors;
never attribute them to an arbitrary single Base. Composition connections are
presentation associations, separate from the query's triples. Retain each
member's authorization and snapshot semantics; cross-domain Federation must
not be labeled a single consistent snapshot.

Until scoped data access and complete provenance are wired, MultiBase is shown
as unavailable with a reason. A production empty scene must not pretend to be a
successful MultiBase load. Demonstration data must be explicitly labeled.

## Runtime Flows

1. Accept a document revision and its source scope in the owning graph state.
2. Derive visibility once, preserving the existing filter and focus semantics.
3. Compute presentation coordinates and layer membership for that revision.
4. Publish only if the document, source generation and layout request still match.
5. Update the active renderer by stable identity; selection updates the existing
   sidebar and inspector, never a separate spatial selection model.
6. On a mode switch, pause the previous layout/render work and activate the other
   view from shared state. Keep the lower query pane mounted with unchanged state.

A projection switch issues zero storage reads and zero query executions. A
target change is different: it must enter a visible loading state and retain
result provenance. MultiBase query execution requires its own authorized runtime
integration; the current local evaluator must not receive an unqualified union
of multiple Base graphs that could merge identities or create cross-Base joins.

## State, Ownership, and Lifecycle

`GraphViewState` remains the MainActor semantic presentation owner. A spatial
view owns its scene entities. The parent retains the spatial camera and cached
coordinates. Layout is synchronous on MainActor and invalidated when the document
changes; it creates no background task or subscription.

Window close, source replacement, disconnect and renderer teardown cancel
pending work and release subscriptions/resources. Mode switching suspends hidden
simulation; it does not create a second continuously running graph session.
Stale loading/layout completion may not publish into a newer generation.

`GraphView` compares the complete input document rather than a count fingerprint,
so equal-count labels and edge replacements invalidate presentation. Window loading
uses a generation token and cancellation check; query submission uses a generation
token invalidated by document replacement. Projection changes do not invalidate
query results.

## Failure, Concurrency, and Constraints

Use macOS `RealityView` for spatial planes and edges, with a screen-space
Canvas overlay for flat glyphs, labels and matching pointer hit tests. Apple's [RealityView documentation](https://developer.apple.com/documentation/realitykit/realityview.md)
provides a macOS camera-content initializer; its visionOS attachment initializer
is not an assumed macOS label solution. [BillboardComponent](https://developer.apple.com/documentation/realitykit/billboardcomponent.md)
faces entities toward the active camera but does not expose the final adjusted
orientation through the normal transform. Picking must therefore be verified
against rendered glyphs rather than assumed from that transform.

Documentation lists both APIs from macOS 15, within this package's macOS 26
minimum. This is API availability evidence, not a compile/link, rendering,
interaction or performance result on the pinned September 4 toolchain.

If spatial initialization fails, retain the document and 2D state, display the
failure and offer explicit return to 2D. Do not silently substitute a renderer.
No camera hardware or AR tracking is part of the desktop interaction contract.

Resource limits belong to the presentation owner: visible glyphs/edges, labels,
cached coordinates and layout work are bounded. Reuse existing backbone
and visibility decisions. Choose operational limits from measurements on the
supported Mac and representative small/dense graphs; record the chosen limits
and measured input sizes in implementation evidence. Do not invent FPS promises.
Camera movement must not rebuild semantic documents or allocate one SwiftUI view
per node per frame. Update transforms and reuse glyph resources; disclose any
sampling or label reduction without reporting it as missing database data.

## Verification and Change Impact

### Falsifiable acceptance matrix

| Contract | Required evidence before implementation completion |
|---|---|
| Same graph across projections | Assert equal visible node/edge IDs, selected scoped identity, filters and query text/results through 2D → 3D → 2D; query/storage invocation counters stay unchanged |
| Existing pane preserved | UI test opens SPARQL, executes a query, switches both modes and checks editor, Table/Raw results, error presentation and divider position |
| Flat nodes in spatial space | macOS screenshots at different orbit angles show depth-separated layers and camera-facing flat silhouettes; hit-test selected glyphs at each angle |
| Ontology correctness | Multiple parents, disconnected roots, cycles, untyped individuals and hidden classes retain original relations and deterministic grouping |
| Base isolation | Same IRI in two Bases stays distinguishable; source and derived contributor lineage round-trip through selection; absent capability is explicit |
| Snapshot freshness | Equal-count updates change labels/endpoints; stale background completion cannot overwrite a newer document or source generation |
| Lifecycle | Close/switch/disconnect during load/layout; confirm cancelled work cannot publish and scene subscriptions/resources release |
| Usability | Sidebar/inspector keyboard parity, reduced motion, light/dark contrast, dense-graph label readability, camera restoration |
| Platform and bounds | Timeout-bounded `xcodebuild test` on actual macOS/Metal path; record toolchain, SDK, inputs, layout/frame cost, allocation/resource bounds and xcresult warnings |

Existing [RDF conversion tests](../../Tests/GraphDocumentTests/GraphDocumentRDFTests.swift)
and [ontology conversion tests](../../Tests/GraphDocumentTests/GraphDocumentOntologyTests.swift)
are regression inputs, not proof of the proposed renderer. New rendering/state
checks belong to Studio's test targets, not DatabaseKit or storage backends.

### Implementation gates and bounded sequence

| Gate | Confirmed gap | Closure evidence |
|---|---|---|
| P1 — native spatial path | No RealityKit renderer or tested camera/picking path in Studio | Minimal pinned-toolchain macOS prototype proves flat glyphs, orbit, matching picking, resizing and teardown before renderer API is frozen |
| P2 — shared state | Layout currently starts from canvas appearance; refresh fingerprint is count-only | Revision-driven state integration plus switching/query-pane/lifecycle tests |
| P3 — source membership | GraphDocument has no Base/import provenance; Studio loads one ontology and rejects record runtime operations | Trace and implement the authorized source adapter with canonical identities and lineage; verify success, denied/unsupported and partial-load failures before enabling MultiBase/import grouping |

Implement P1 first, then shared-state and ontology-depth presentation under P2.
P3 is an explicit integration boundary, not a license to build a new database
runtime or invent an authorization API in Studio. Its unavailable views remain
honest until the source contract is established. Final whole-feature readiness
requires every enabled path's acceptance evidence; this document alone does not
declare implementation-ready or runtime-verified status for P1–P3.

Child design: [RuntimeConnection](RuntimeConnection/DESIGN.md), owning the
connection handshake, operation lifetime and server catalog.

## Complete Studio Implementation Scope

The user's full implementation request supersedes the earlier spatial-only
implementation boundary. Spatial work remains required, but cannot establish
Studio completeness. The following matrix is the acceptance authority for the
expanded work; PROGRESS.md records execution status without narrowing this scope.

| Requirement | Owner / execution source | Required observable evidence |
|---|---|---|
| Connection, authentication, history, reconnect, disconnect | Studio connection state -> DatabaseClient HTTP/WebSocket | Authenticated isolated server handshake, rejected credentials, cancelled connect, authoritative shutdown; secrets absent from history/logs |
| Capabilities and permission failures | capabilitiesDescribe and typed remote errors | Unsupported, forbidden, empty and failed remain distinguishable; disabled action explains missing capability |
| Database/Base/Composition selection | DatabaseSessionClient / MultiBase target contract | Same-IRI records in two Bases remain distinct; default database works without MultiBase |
| Schema and Directory/Partition inspection | schemaDescribe / schemaExecute and schema declarations | All field types, identity, constraints, relations and index configuration round-trip; dynamic partition values reach execution |
| Record browsing/detail/paging | queryExecute | Typed values retained; cursor pages neither duplicate nor omit records; loading cancellation and target changes discard stale results |
| Server search/filter/sort | QueryIR through queryExecute | Match beyond the first loaded page; explicit limit and ordering applied by runtime |
| Create/update/delete | mutationExecute | Round-trip, validation, conflicting update and denied mutation against real server |
| Query editor/history/results | queryExecute; Studio presentation history | Execute/cancel/save/reopen; Table/Raw identity and typed result/error retained |
| Graph exploration | queryExecute / graphAlgorithm | Neighbors, direction and paths match runtime results; bounded expansion |
| Ontology catalog/details/imports | ontologyExecute | Select multiple ontologies, inspect IRI/version/imports, hierarchy, properties, domain/range, axioms and instances |
| Inference and explanations | ontologyExecute | Asserted and inferred facts distinguished; provided explanations link to sources |
| SHACL | shaclExecute | Shapes, real validation violations and focus-node/property navigation |
| Base/Composition/Grant | corresponding canonical operations | Catalog/detail/authorized administration, effective rights, selection and contributor provenance; no inferred authority |
| Projection and pane integration | SpatialGraph and shared GraphViewState | Existing spatial acceptance matrix, real screenshots/selection/orbit, 2D restoration, query pane and inspector continuity |
| Import/export | Studio format adapters -> typed mutation/query | Types and scope preserved; preflight, progress and exact partial failures |
| Schema changes | schemaExecute | Preview difference, validate, apply, reread, rejection and failure |
| Index lifecycle | maintenanceExecute / job operations | Definition/state/build/rebuild results and real failed-job diagnosis |
| Durable jobs | jobStart/status/result/cancel | Target retained, state transitions, paging, cancellation, reconnect to known jobs |
| Specialized search/visualization | runtime full-text/vector/geographic/time contracts | Exact backend results represented in Studio; capability absence explicit |
| Query diagnostics/statistics/health | runtime query/maintenance/capabilities | Actual plan/index/cost/statistics, bounds and source identified; no fabricated metrics |
| Version history/diff/restore | supported runtime version contract | Historical values/differences and authorized restoration round-trip |
| Maintenance | canonical runtime maintenance operations | Real operation result, limits, cancellation and typed failures |

### Confirmed integration gaps

- Studio now imports DatabaseClient and exposes an authenticated runtime window
  with capabilities and schema discovery. Its direct-storage session rejects
  record and statistics operations by design. That inspection mode remains
  distinct from the runtime connection; data editing is not yet wired.
- DatabaseClient's released HTTP adapter owns framing, token headers, bounded
  responses, timeout/cancellation and transport shutdown; Studio must consume it.
- The inspected DatabaseClient 26.0904.0 exposes target-free calls by default and
  target-bound calls with the MultiBase trait. Selecting that trait globally is
  not proof of compatibility with both ordinary and MultiBase servers. Both
  paths must be verified before completing FULL-05.
- CapabilitiesDescribe exposes feature versions and job operation identifiers;
  it is not a substitute for per-operation authorization or effective Grant data.
- The existing local filter and SPARQL evaluators operate on loaded snapshots.
  They do not establish server-wide query execution.
