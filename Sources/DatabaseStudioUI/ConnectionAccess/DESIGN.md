# Connection Access

## Purpose and Scope
Parent: [DatabaseStudioUI](../DESIGN.md). Children: none.
Own native access to previously successful server and file-backed database connections.

## Responsibilities and Boundaries
ConnectionRestoration selects the last successful destination across the two existing
history stores. RecentConnectionsMenu routes stable server IDs or saved local paths
into native SwiftUI scenes. ConnectionHistoryStore owns local path persistence within this component;
RuntimeConnectionHistory owns server persistence. Credentials stay
in Keychain. Connection/session owners perform handshake, reads and shutdown.
Existing sidebar and result presentation are unchanged.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Module](../DESIGN.md) | parent | Native app composition | Startup and File menu | Preserve existing scenes and sidebars |
| [RuntimeConnection](../RuntimeConnection/DESIGN.md) | depends on | Successful scoped history, credential lookup, handshake | Server destination | Missing tokens require entry; credentials never enter history |
| [Package](../../../DESIGN.md) | used by | Scene lifecycle | Main app opens native scenes | Scene arguments are history identity/path, never credentials |

## Architecture
```text
Successful server handshake -> RuntimeConnectionHistory + optional Keychain token
Successful local connection -> ConnectionHistoryStore(path + root)
Startup -> newest successful destination -> native server/local scene
File/Open Recent -> existing history -> native server/local scene
Server scene -> history UUID -> endpoint/scope -> Keychain lookup -> reconnect
Local scene -> saved path/root -> existing StudioDatabaseSession.connect
```

## Contracts and Invariants
Use the existing persistence keys and IDs so past history remains available.
Decode the historical clusterFilePath field into filePath and encode only the
current field after a successful mutation; preserve every other stored preference.
Server identity includes endpoint, database, tenant and workspace. Local identity
includes normalized file path and exact root path. Update recency only after
successful connection. Preserve local names, favorites, IDs and usage counts.
A history reload or mutation must not erase malformed stored history. Present
read/write failures explicitly. A new typed local scene opens the selected path;
a new typed server scene opens the selected scoped server. The untyped initial
main scene restores whichever history is newest, with local winning equal dates.
No saved token means show the prefilled form; a saved token means attempt one
existing authenticated handshake. Do not retry or save new tokens automatically.
After successful server access, update the scene binding to the recorded UUID so
restoring a window cannot reopen its previous edited endpoint. Closing a server
scene cancels its operation and disconnects its transport.

## State, Ownership, and Lifecycle
Both history stores are MainActor-owned and observable; shared views reflect
successful access. Scene arguments contain no secrets. Startup restoration occurs
once per main view lifetime. Local connection failures open existing settings;
server failures retain endpoint/scope and explicit failure for manual retry.

## Failure, Concurrency, and Constraints
Retain existing history limits and favorite exemptions. Keychain errors remain
visible. A removed server ID cannot select another server silently. A cancelled
operation cannot record success. No modal local-connection form blocks an available
recent server destination. Platforms are macOS only; no Embedded branch or shared
unsafe state is introduced.

## Verification and Change Impact
ConnectionAccessTests cover restart persistence, deduplication, root separation,
favorites/identity preservation, malformed-history mutation rejection, newest
server/local routing and equal-date choice. Existing native Keychain round-trip
coverage remains applicable. Computer Use must verify File/Open Recent, prefilled
server destination without credentials, successful recent opening and restart
restoration in the actual app. No UI XCTest. Changed scene composition requires
actual app compilation; storage/query semantics do not change.
