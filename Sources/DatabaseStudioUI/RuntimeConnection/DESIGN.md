# RuntimeConnection

## Purpose and Scope

Parent: [DatabaseStudioUI](../DESIGN.md). Children: none. Own the Studio-side
lifetime of an authenticated server connection and its advertised catalog.

## Responsibilities and Boundaries

Studio selects endpoint/database and credentials. DatabaseClient owns wire
encoding, request correlation, transport response bounds, timeout and cancellation.
Server capabilities are descriptive, not authorization grants. Direct-storage
inspection remains a separate existing session.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [DatabaseStudioUI](../DESIGN.md) | parent | Complete Studio scope | UI connects and consumes the catalog | A handshake does not verify CRUD |
| [DatabaseClient](../../../../database-client/DESIGN.md) | depends on | Typed operations and HTTP shutdown | Execute canonical operations | Ordinary/MultiBase compatibility is a separate gate |

## Architecture

```text
Connection UI -> RuntimeConnection (@MainActor)
                     -> DatabaseClient<HTTPDatabaseTransport>
                         -> authenticated database-server
```

## Contracts and Invariants

Connecting requires a successful capabilities and schema response from the same
candidate. Only the latest generation may publish. Failure closes the candidate.
Disconnect clears published state before awaiting transport shutdown. An operation
whose connection changed while awaiting cannot return stale success to its caller.
A cancelled or superseded operation reports CancellationError even if shutting
its URLSession concurrently produced a transport-unavailable error. Errors from
the current, non-cancelled session retain their original typed failure.
Credentials remain in the transport lifetime and are not persisted by this owner.

## State, Ownership, and Lifecycle

MainActor owns generation, catalog, transport and client references. Each connect
allocates one candidate transport; replacement and disconnect invalidate its URL
session through the existing HTTP transport shutdown operation. UI lifetime owns
calling disconnect; a hidden view is not permission to keep an unwanted session.

## Failure, Concurrency, and Constraints

Invalid configuration, unavailable session, client failure and cancellation remain
explicit. Existing HTTP configuration owns byte and timeout limits. No retries of
mutations are introduced. MultiBase is not silently enabled or emulated.

## Verification and Change Impact

Focused tests must reject bad configuration, rejected authentication, stale
connection/operation completions, malformed frames and post-disconnect operations.
An isolated real server must provide successful capabilities/schema and shutdown
verification. Test transport responses alone are not server integration evidence.

## Runtime Flows

File > Connect to Server (Command-K) selects server access in the base database
window, through [Workspace](../Workspace/DESIGN.md). The connected view owns its
connection independently from the local catalog-inspection session. Connect validates the endpoint,
performs the authenticated handshake, then displays the returned entity and
feature catalogs. Cancel/window disappearance clears the token, cancels connection
work and disconnects. Successful connections record endpoint/database/tenant/workspace/last-used metadata in a separate
UserDefaults history. The opt-in Remember Token control stores a generic-password
item in the device-local unlocked Keychain keyed by the history UUID. Unchecking
it removes that entry after successful authentication. Selecting history resolves
the token only from Keychain; deletion removes the credential before history.
Neither the history schema nor UserDefaults contains an access-token field.
History decode errors and Keychain OSStatus failures remain visible and do not
reset history silently. Recording history before saving a token means a failed
Keychain write leaves a usable history entry requiring manual credentials.

The connected workspace composes Data and Query with a persistent database
browser, connection status and native Database Info inspection using
[Runtime Query](../RuntimeQuery/DESIGN.md). Operation request metadata is forwarded
unchanged to DatabaseClient; explicit mutations own one idempotency key per
submission. Authentication and authorization remain with their existing owners.

## Recent Access and Restoration
[Connection Access](../ConnectionAccess/DESIGN.md) owns the native recent menu and
startup destination choice. Base workspace server destinations accept a non-secret history UUID, restore
its exact endpoint/database/tenant/workspace and attempt one handshake if a token
already exists in Keychain. Missing tokens show a prefilled form. History selections
use the same path; successful handshake alone updates lastUsed. Explicit Disconnect
does not initiate automatic reconnect. Closing a scene retains its saved history.
