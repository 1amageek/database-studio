# SpatialGraph

## Purpose and Scope

Parent: [DatabaseStudioUI](../DESIGN.md). Children: none. This component owns
spatial coordinates, camera projection and the macOS RealityKit viewport.

## Responsibilities and Boundaries

The graph state supplies immutable documents, visibility and selection. This
component derives presentation coordinates and returns identity-based gestures;
it never opens storage or alters query semantics or source membership.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [DatabaseStudioUI](../DESIGN.md) | parent / used by | Shared graph state and flat-node presentation | Owns switching, query pane and source capabilities | Source membership is not inferred |

## Architecture

```text
GraphViewState -> deterministic layer coordinates -> RealityKit planes/edges
                                       + camera -> Canvas glyphs/labels/hit test
```

The same camera basis projects world positions for flat glyph drawing and
pointer interaction. RealityKit uses that camera and world geometry. Glyphs
are a screen-space Canvas overlay, not extruded meshes or per-node SwiftUI
views. This avoids relying on BillboardComponent's inaccessible final transform.

## Contracts and Invariants

- Class depth uses iterative strongly connected components and longest paths;
  cycles terminate without changing original graph edges.
- Layer grouping is based on the full document; visibility only reduces draws.
- Each visible glyph is drawn and picked at the same projected position.
- Nearest visible overlapping glyph wins selection; labels do not own identity.
- Spatial dragging changes an offset on the node's assigned plane only.
- All retained mutable scene/camera state is MainActor-isolated. There are no
  subscriptions, detached tasks, unsafe Sendable conformances or platform locks.

## State, Ownership, and Lifecycle

The view owns a native scene whose lifetime ends with the viewport. The
parent retains camera and coordinate state across projection changes. Rebuild
native geometry only for document/visibility/spacing changes; camera motion
updates the camera transform and Canvas projection without rebuilding geometry.

## Failure, Concurrency, and Constraints

Reject nonfinite input positions in projection. Clamp interactive pitch, zoom
and layer spacing to keep the camera outside the near plane. Native graphics
unavailability is an explicit view state with return-to-2D control. Display
resources scale with the existing visible graph and backbone; no extra unlimited
cache is retained. Labels and icons are suppressed below a projected radius of 9 points; glyphs
remain available and sidebar navigation preserves text access.

## Verification and Change Impact

Tests belong to the Studio app test target and cover SCCs, multiple parents,
projection/picking and shared-state switching. The app UI target exercises the
real macOS RealityKit path, query-pane retention, selection, orbit and teardown.
Native acceptance requires rendered screenshots and successful user interaction,
not just compiled declarations. Parent camera/state changes require rechecking
both the 2D renderer and this component.
