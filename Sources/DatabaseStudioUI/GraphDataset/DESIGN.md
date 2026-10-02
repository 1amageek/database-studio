# GraphDataset

## Purpose and Scope

Parent: [DatabaseStudioUI](../DESIGN.md). Children: none. Own one frozen,
openly licensed automotive knowledge-graph snapshot for interactive exploration.

## Responsibilities and Boundaries

Load and validate the bundled researched data, preserve Wikidata entity and
predicate identity, and convert it to the existing GraphDocument presentation
contract. Own no database execution, online refresh, schema or synthetic data.
The source snapshot is an explicit connected sample, not the complete industry.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [DatabaseStudioUI](../DESIGN.md) | parent / used by | GraphWindowState generation-bound load and GraphView initial visibility | Presents the snapshot through existing graph navigation | Reset example visibility policy on replacement source |
| [SpatialGraph](../SpatialGraph/DESIGN.md) | depends on | Finite admission and retained native geometry | Displays all 1000 admitted entities after explicit 3D selection | No automatic projection switch; preserve typed load/layout failures |

## Architecture

```text
Wikidata car-model query -> bounded detail queries -> recorded raw source hashes
    -> deterministic connected 1000-entity induced subgraph
        -> bundled snapshot -> validated GraphDocument -> existing GraphView
```

## Contracts and Invariants

- The frozen snapshot contains exactly 1000 unique real entity IRIs; every
  relationship is an original Wikidata statement with its exact predicate IRI.
- Sampling retains all fetched relationships between chosen endpoints; it adds
  none. The connected degree-priority selection rule and excluded counts are
  recorded with retrieval time, source query URLs, license and raw source hashes.
- Labels and provenance survive conversion and are available in the inspector.
  Wikidata instance-of predicates retain their IRIs while supplying type roles.
- Missing resources, malformed data, wrong count, duplicate statements, unknown
  labels/endpoints and disconnected samples fail explicitly; no tiny fallback.
- Loading the example initially exposes all entities/classes and defaults to 2D.
  Other sources retain their existing initial visibility. User filters remain
  explicit and shared through 2D/3D changes.

## Runtime Flows

File / Open Example Graph -> clear prior publication -> load-generation advance
    -> read bundled snapshot -> decode/validate -> publish current document
    -> user chooses 3D -> bounded spatial layout -> native geometry and picking

## State, Ownership, and Lifecycle

The snapshot is immutable and bundled. GraphWindowState owns publication and
source generation on MainActor; GraphViewState owns filters, selection and layout.
No live database or developer service is modified. Startup performs no network
request; source acquisition belongs to the offline dataset-generation script.

## Failure, Concurrency, and Constraints

The source fetch uses bounded queries, at most three concurrent requests and
explicit network timeouts. Dataset size is 1000 entities and at most the spatial
relationship admission limit. The loader materializes file data once at its
ownership boundary. Original raw evidence is retained outside the repository;
its hashes and exact selection are frozen with the bundled artifact.

## Verification and Change Impact

GraphDocumentTests owns real-resource count, source provenance, exact predicate,
closed endpoints, invalid snapshot and full initial visibility checks.
SpatialGraphTests owns 1000-node layout, finite output, pair-work budget,
native mesh retention and projection. Headless Xcode tests exercise the native
path; Computer use opens the bundled graph and checks counts/rendering/selection.
Changes to the snapshot re-run generator validation and these dataset checks.

### Frozen source evidence

[Wikidata structured data](https://www.wikidata.org/wiki/Wikidata:Licensing) is
CC0. The recorded acquisition selects 1200 automobile-model entities with an
explicit manufacturer statement, then fetches model and manufacturer relations
in bounded batches. The resulting source contains 2165 unique entities and 4294
unique statements; deterministic sampling retains 1000 entities and all 2584
statements among those entities. No edge is generated or silently truncated.
978 retained entities have readable English labels; 22 retain the original
Q identifier because the source supplies no English label. No name is invented.
The snapshot records all
queries, response SHA-256 hashes, UTC retrieval time and excluded counts.
The generator reproduces identical bytes from the retained raw responses.

Raw source acquisition evidence is retained at `/var/folders/c4/bcbjzcj556d3xj45z64rzjmw0000gn/T/studio-public-graph-zbe4iajt`.
The frozen artifact is [Resources/automotive.json](Resources/automotive.json);
its acquisition/selection generator is
[prepare-automotive-dataset.py](../../../scripts/prepare-automotive-dataset.py).
Application loading performs no new query against the public endpoint.
