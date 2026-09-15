# Equipment Maintenance Studio Sample

A deterministic, fictional two-factory workspace for Database Studio.

```sh
python3 generate.py --output /tmp/maintenance-demo
```

The destination must not already exist. This generates exactly 1,000 records,
a Schema JSON manifest, tagged values, SQL inserts, expected results and checksums.
It does not connect to or modify a database.

Current status: ordinary SQLite import and restart/readback are verified with
1,000 records, authorized CRUD, and denied-operation checks. Ontology, SHACL,
MultiBase setup and Studio UI validation remain in progress. Use a fresh sample
database. See [ISSUES.md](ISSUES.md) for observed problems and fixes.


## Isolated database verification

```sh
python3 run.py --cli /absolute/path/database --server /absolute/path/database-server --directory /tmp/maintenance-run
```

Both binaries must have identical versions. The destination must be new. The
runner bootstraps a private SQLite server, uses its returned endpoint, checks
capabilities, applies the schema, inserts records, exercises CRUD and denied deletion, restarts
the server, and reads exact counts. It records
partial progress in `evidence.json` and stops its server on both success and
failure. Credentials never appear in arguments or output. A server without Entity
policies rejects inserts; this failure is preserved, not bypassed.

The generated N-Quads include a common ontology, two factory graph files and a
SHACL Equipment-line shape. They are not yet automatically imported by the runner.
Factory graphs are named graphs, not a substitute for MultiBase instances.

The runner writes explicit `entityPolicies` into its isolated server configuration.
The `admin` role is granted sample entity operations by that configuration; it
has no implicit data access. Factory deletion is intentionally omitted and must
fail, while a temporary WorkOrder exercises insert/update/read/delete before
final counts are checked after restarting the server. These checks require a server containing the
schema-driven authorization fix.

## Verified run

`/tmp/maintenance-studio-auth-fixed-2/evidence.json` records a successful run using
CLI/server 26.0904.0 and the schema-driven authorization fix. It retained exactly
2 factories, 18 lines, 180 equipment items, 300 sensors, 40 technicians, 260 work
orders and 200 incidents after restart. The owned server exited with status 0
and was unreachable after shutdown. The SQLite file remains in that isolated
run directory; the runner does not leave a background server running.
