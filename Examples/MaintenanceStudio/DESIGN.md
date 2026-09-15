# Maintenance Studio Sample

## Purpose and Scope

Parent: [Database Studio](../../DESIGN.md). Children: none. An application-owned,
reproducible equipment-maintenance dataset for Studio validation. Owns schema,
fixtures, seed/verification workflow and usability findings.

## Responsibilities and Boundaries

Generate 1,000 records: 2 factories, 18 lines, 180 equipment items, 300 sensors,
40 technicians, 260 work orders and 200 incidents. Use only an isolated sample
database. DatabaseKit owns schema semantics, DatabaseClient/CLI owns invocation,
and the server owns authorization and persistence. Never treat file generation
as successful database insertion.

## Related Designs

| Design | Relationship | Contract used |
|---|---|---|
| [Studio](../../DESIGN.md) | parent | Runtime connection and presentation |
| [Workspace](../../../SPEC.md) | authority | Ordinary database and optional MultiBase isolation |

## Architecture

```text
Fixed seed -> generator -> schema + records + SQL + expected results
                               -> authenticated sample server -> Studio
                               -> verification -> findings
```

## Contracts and Invariants

IDs and reference targets are valid and deterministic. References between factory
owned entities remain in the same factory. Integer values use tagged int64 JSON.
Output generation refuses an existing directory. Secrets never enter fixtures.
Ordinary and MultiBase runs must be verified separately. A missing capability,
denied operation or partial import is an explicit failure.

## Verification and Change Impact

The generator validates exact entity counts, unique IDs and all reference targets.
Reproducibility tests compare two runs and reject intentionally broken references.
The ordinary runner verifies exactly 1,000 persisted rows after server restart,
explicit role permissions, denied Factory deletion, and WorkOrder CRUD. It only
reports success after clean shutdown and negative readiness. Database-enforced
relationships, ontology/SHACL execution, MultiBase and Studio UI remain pending. [ISSUES.md](ISSUES.md) records
observed usability problems and the current verification boundaries.

The next sample increment publishes the generated ontology and SHACL catalog,
then verifies the CNC ancestor chain and exact catalog readback after restart.
Catalog publication does not establish SHACL validation against entity indexes.
