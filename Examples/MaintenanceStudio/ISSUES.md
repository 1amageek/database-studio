# Maintenance Sample: Findings

## Confirmed

| ID | Finding | Evidence / reproduction | Impact | Improvement |
|---|---|---|---|---|
| SAMPLE-001 | Installed CLI/server and Studio test server have different versions. | `database --version` and adjacent `database-server --version`: 26.0812.1; Studio's isolated test server: 26.0904.0. | A successful sample run against one binary does not establish compatibility with another. | Resolve and record executable paths, versions and capabilities in the sample runner before mutation. Never silently substitute binaries. |
| SAMPLE-002 | Before the fix, the standard server enabled security without a configuration path for Entity authorization policies. | `DatabaseServerHost/NativeDatabaseOperationApplicationFactory.swift` creates `SchemaDrivenDatabaseRuntimeFactory` without policies and sets security enabled; Studio CRUD test reports ACCESS_DENIED. | Authentication and schema publication can succeed while data reads/writes fail, including for admin. This prevented insertion before the authorization fix; see the resolved evidence below. | Expose explicit application-owned Entity/field policies and effective permission diagnostics. Preserve default-deny behavior; do not infer permissions from the admin role name. |
| SAMPLE-003 | Schema describe omits identifier types and Directory/Partition declarations. | `SchemaDescribeOperation.Entity` contains name, fields and indexes; matching server handler omits the complete manifest metadata. | Studio cannot derive a correct identity/partition editor from the response. | Provide a canonical, authorized complete-schema read operation; do not reconstruct missing semantics from names. |
| SAMPLE-004 | CLI skill target-selection instructions differ from installed command help. | Skill requires explicit Base/Composition for every query; installed `database help entity insert` describes Base as optional. Workspace SPEC supports ordinary target-free databases. | A user may incorrectly believe MultiBase is mandatory. | Document version-specific ordinary/MultiBase command behavior; use actual command help and advertised capabilities as executable evidence. |

| SAMPLE-005 | Installed CLI rejects the option placement printed by its own help. | `database schema plan @/tmp/maintenance-studio-sample-1/schema.json --endpoint http://127.0.0.1:1 --database maintenance-sample` exits 64: Unknown option --endpoint, despite `database schema plan --help` advertising it. Root-option and `--` variants exit 2: A command is required. Only a dummy token was used. | Cannot yet validate or apply the manifest through the advertised invocation. No server request or schema acceptance has been established. | Investigate executable command forwarding versus the internal parser; add process-level help/example parity coverage. |

| SAMPLE-006 | Endpoint root returns an empty HTTP 404; the protocol path is required. | Isolated run 2 used the constructed host/port URL and failed capabilities with 404. Run 3 used bootstrap `endpoint` ending in `/v1/database` and authenticated successfully. | Connection setup is difficult to diagnose from the host and port alone. | Always consume bootstrap endpoint; document the complete protocol URL in Studio and CLI connection help. |

### Resolved for the sample runner

- SAMPLE-005: built current CLI 26.0904.0 into `/tmp/maintenance-cli-build/DerivedData/Build/Products/Debug/database`; documented argument placement works. Installed CLI was not overwritten.
- Run `/tmp/maintenance-studio-runtime-3/evidence.json`: authenticated capabilities and schema plan/apply succeeded. First entity insert failed with exit 4 / ACCESS_DENIED; inserted count remains 0. Owned server exited 0; negative readiness confirmed.
- Generator now emits ontology, SHACL shape, combined named-graph N-Quads and per-factory graph files. Their database ingestion and server-side validation remain unverified.

## Verification Boundaries

- Generator produced exactly 1,000 records with stable IDs and within-factory references.
- Generated files are fixtures, not evidence that DatabaseWire accepted or persisted them.
- Timestamp values currently use ISO-8601 strings. Native timestamp fields and temporal queries still require implementation and validation.
- ID link fields currently use strings. They are not yet enforced database relationships.
- Ontology and SHACL fixture files exist; semantic execution and MultiBase configuration are still required. Named graphs are not Bases.

## Investigation Policy

Record failures with the exact operation, version, expected result and observed
result. Keep credentials and real user data out of this log. Label proposals and
unverified concerns explicitly. Update resolved findings with the fixing commit
and behavioral evidence instead of deleting their history.

### SAMPLE-002 implementation follow-up

The server now has an explicit `entityPolicies` launch configuration path,
with exact entity names and operation-specific role lists. Schema-driven
runtime creation rebuilds those policies for the active schema, while absent
permissions remain denied. The sample configures only its seven entities and
leaves Factory deletion denied as a negative control. Framework commit
`6b453e85` supplies canonical schema-bound authorization. The completed run at
`/tmp/maintenance-studio-auth-fixed-2/evidence.json` inserted 1000 records,
verified WorkOrder CRUD and denied Factory deletion, restarted the server, and
read back exact counts. Server exit 0 and negative readiness both passed.

### SAMPLE-007: Test harness silently selects a different Swift compiler

- Reproduction: `xcrun --toolchain org.swift.64202608141a --find swiftc` returns the Xcode default compiler on this Mac; only the 2026-09-04 snapshot is installed.
- Impact before the fix: both package harnesses claimed an August 14 pin while compiling with Apple Swift 6.4.0.30.4. The resulting build cannot prove the pinned-toolchain contract.
- Evidence: `/tmp/schema-authorization-framework-3.log` and `/tmp/schema-authorization-server.log`; both build processes were stopped. The initial download check used an incorrect `swift-6.4-branch` URL. The correct `swift-6.4.x-branch` URL returns HTTP 200; the earlier availability claim was corrected.
- Improvement: validate the resolved toolchain identity before dependency resolution or compilation; align the normative pin and runner configuration before resuming. The user approved the September 4 baseline. Both harnesses now verify the resolved compiler bundle identifier before building; wrong-compiler rejection was exercised in both.

### SAMPLE-008: Reserved aggregate alias gives an unhelpful SQL error

- Reproduction: `SELECT COUNT(*) AS count FROM Factory` returns `INVALID_QUERY_SYNTAX`; the SQL lexer treats `COUNT` as a keyword and the alias parser requires an identifier.
- Impact: the first fixed-authorization run inserted all 1000 records, passed update/delete and denied-delete checks, and restarted successfully, but its final count query failed. The run correctly reports `verified: false`.
- Workaround: the sample uses `AS sample_count` for the count column.
- Improvement: report the parser location and expected token, and document reserved identifiers. Parser behavior is outside the authorization fix.
- Evidence: `/tmp/maintenance-studio-auth-fixed-1/evidence.json`.

### SAMPLE-009: SHACL validation requires an RDF dataset index

- The current seven-entity sample has no indexes. `shacl validate` requires both an entity and an RDF dataset index; uploading `shapes.nq` alone does not validate equipment data.
- Confirmed path: `DatabaseGraphOperations/SchemaDatabaseSHACLDataSourceResolver.resolveSource` rejects a missing index and a non-RDF index before constructing the data source.
- Next sample work must define and populate the canonical RDF dataset index, then verify both conforming equipment and a missing-line violation. An empty validation result is not evidence that the 180 equipment items were checked.

### SAMPLE-010: Hierarchy includes the implicit universal class

- `/tmp/maintenance-catalog-run-1/evidence.json` records successful ontology/SHACL publication and restart, followed by an overly narrow sample assertion.
- Actual CNC ancestors are MachiningEquipment at depth 1, Equipment at depth 2, and `owl:Thing` at depth 3. The sample now includes the universal class in its exact expected result.
- Studio should distinguish explicitly declared classes from the implicit top class when presenting ontology layers. This is a presentation finding, not a server failure.
