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
RecordAnalysisSourceTests and GraphNumericAnalysisTests must be rerun when the
canonical result algebra changes; existing numerical algorithms remain unchanged.
Build the actual application, then use Computer Use to verify the original
sidebar, selection/inspector, 2D/3D and query pane. A temporary host or empty
Entities list does not establish preservation of the original UI.

## Numeric RDF Result Values

Explicit xsd:integer, xsd:decimal, xsd:float and xsd:double literals may provide
measurements. The original RDF literal remains authoritative in Table/Raw.
Integer values outside exact Double representation are excluded with warnings;
decimal coordinates report approximation. Malformed or nonfinite numeric literals
fail visibly. String/language literals supply their original lexical category,
while IRIs retain their explicit term identity. Unknown datatypes do not become
measurements. Projection tests cover signed/zero values, precision, failure and
canonical value preservation.

## QueryValue Projection

Projection reads primitive fields from QueryValue. Primitive objects and SQL
composites traverse the same bounded escaped-field-path stack. SQL numeric values
use their exact decimal value for the existing explicitly approximate Double
projection; display scale and every original value remain in the canonical row.
SQL JSON, arrays and temporal values (SQL time/interval values and the primitive
date, time, date-time, timestamp, time-span and calendar-period kinds) are
unsupported measurements and appear in the existing omitted-field warnings; they
never become categories. Other non-numeric scalars become categories using the
readable value text, never a debug description. They never become zero or synthetic values.
The existing row, field, depth, text, cancellation and finite-number limits apply
to every branch. Component tests cover primitive parity, SQL numeric/composite
projection, unsupported warnings and canonical preservation.
