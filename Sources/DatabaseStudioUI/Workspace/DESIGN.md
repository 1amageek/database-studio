# Workspace

## Purpose and Scope
Parent: [DatabaseStudioUI](../DESIGN.md). Children: none.
Own the base window's selected connection destination and native navigation.

## Responsibilities and Boundaries
WorkspaceDestination is a non-secret scene value containing a saved local path
or a server history identity. DatabaseWorkspaceView routes it in the base window.
ConnectionAccess owns history; RuntimeConnection and StudioDatabaseSession own
authentication, catalog reads and resource shutdown. WorkspaceNavigation carries
the focused window's explicit navigation action; it owns no database semantics.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Module](../DESIGN.md) | parent | Base-window composition | DB navigation survives analysis | Do not replace DB navigation with cluster navigation |
| [ConnectionAccess](../ConnectionAccess/DESIGN.md) | depends on | Latest successful destination and saved identity | Startup and Open Recent | Scene values never contain credentials |
| [RuntimeConnection](../RuntimeConnection/DESIGN.md) | depends on | Authenticated lifetime and catalog | Server content in the base window | Explicit route replacement closes the previous view's session |
| [ResultPresentation](../ResultPresentation/DESIGN.md) | coordinates with | Linked Table/analysis and selection | Same source through multiple representations | Result-page identity is not persisted identity |

## Architecture
```text
Base WindowGroup -> DatabaseWorkspaceView
  startup / File commands / Open Recent -> WorkspaceDestination
    local -> MainView -> original directory browser + catalog inspection
    server -> RuntimeConnectionView -> browser + Data/Query + DB information
      canonical result -> Table / Document / linked Table + Analysis/Relationships
                         -> lower Query + contextual Inspector
```

## Contracts and Invariants
- Server startup, Connect and Open Recent select the base window; no independent
  runtime window is created. Explicit New Window remains a native scene operation.
- Server and local destinations preserve their existing history keys and exact
  scopes. No token or result is serialized in the scene value.
- Explicit navigation starts a fresh content lifetime. Recording a successful
  server UUID updates the scene value without restarting the active connection.
- The original local directory browser and graph sidebar remain intact. Server
  navigation displays only returned entity/field/index metadata; absent Directory,
  identifier and partition metadata remains explicitly unavailable.

## Runtime Flows
An unselected base window loads both histories once and selects the newest successful
destination, or a new server form. Focused commands and recent menus replace the
destination inside that window. Removed history identities fail visibly.

## State, Ownership, and Lifecycle
SwiftUI/MainActor owns destination and content revision. Route replacement removes
the old content; each connection view cancels its work and closes its owned session.
Changing representation inside a connected workspace never disconnects the server.

## Failure, Concurrency, and Constraints
History failures are visible and preserve stored data. Missing credentials leave
the exact saved scope prefilled. Direct storage remains catalog-only and does not
gain record operations from sharing a window with authenticated server access.

## Verification and Change Impact
ConnectionAccessTests cover scene encoding, destination mapping and scope identity.
Computer Use verifies startup and Connect in the actual base window, DB catalog
information during analysis and unchanged lower Query. App compilation verifies
the scene contract; connection tests remain authoritative for transport lifecycle.

The connected root owns separate retained Data and Query workspace state. Source
switches cancel active tasks but preserve editor, options, published canonical
results and analysis/selection. Selecting another entity replaces Data state only.
Disconnect invalidates both query owners before the connection is released.
