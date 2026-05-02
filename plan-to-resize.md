# Plan: Resizable Panel via Click-and-Drag

## Goal
Allow users to drag the popup's "free" corner to resize it, with the new dimensions persisted across Plasma restarts.

## Background
The full representation's size is controlled by `Layout.preferredWidth/Height` in `FullRepresentation.qml:41-42` (currently fixed at `gridUnit * 28` × `gridUnit * 32`). Plasma reads these values to size the popup. By binding them to configuration entries, we can resize the popup at runtime by writing to those entries.

## Changes

### 1. Config schema — `package/contents/config/main.xml`
Add two entries (default `0` = "use built-in default"):

```xml
<entry name="panelWidth" type="Int">
  <label>User-set panel width in pixels (0 = default)</label>
  <default>0</default>
  <min>0</min>
</entry>
<entry name="panelHeight" type="Int">
  <label>User-set panel height in pixels (0 = default)</label>
  <default>0</default>
  <min>0</min>
</entry>
```

### 2. `FullRepresentation.qml` — bind layout to config

Replace the fixed `Layout.preferredWidth/Height` (line 41-42) with config-aware bindings, keeping minimums/maximums as guardrails:

```qml
readonly property int defaultWidth:  Kirigami.Units.gridUnit * 28
readonly property int defaultHeight: Kirigami.Units.gridUnit * 32
readonly property int maxWidth:  Kirigami.Units.gridUnit * 80
readonly property int maxHeight: Kirigami.Units.gridUnit * 80

Layout.minimumWidth:   Kirigami.Units.gridUnit * 20
Layout.minimumHeight:  Kirigami.Units.gridUnit * 24
Layout.maximumWidth:   maxWidth
Layout.maximumHeight:  maxHeight
Layout.preferredWidth:  Plasmoid.configuration.panelWidth  > 0 ? Plasmoid.configuration.panelWidth  : defaultWidth
Layout.preferredHeight: Plasmoid.configuration.panelHeight > 0 ? Plasmoid.configuration.panelHeight : defaultHeight
```

### 3. Resize grip — adaptive corner

Add an invisible `MouseArea` (≈16×16 px) overlaid on the chosen corner, computed from `Plasmoid.location`:

| `Plasmoid.location`             | Popup expands toward | Grip corner   | Cursor                     |
| ------------------------------- | -------------------- | ------------- | -------------------------- |
| `BottomEdge`                    | up                   | top-right     | `Qt.SizeBDiagCursor`       |
| `TopEdge`                       | down                 | bottom-right  | `Qt.SizeFDiagCursor`       |
| `LeftEdge`                      | right                | bottom-right  | `Qt.SizeFDiagCursor`       |
| `RightEdge`                     | left                 | bottom-left   | `Qt.SizeBDiagCursor`       |
| `Floating` / `Desktop` / other  | —                    | bottom-right  | `Qt.SizeFDiagCursor`       |

Implementation sketch (placed as a sibling of the `contentItem`'s root, anchored according to a `gripCorner` property):

```qml
property int gripCorner: {
    switch (Plasmoid.location) {
    case PlasmaCore.Types.BottomEdge: return Qt.TopRightCorner;
    case PlasmaCore.Types.RightEdge:  return Qt.BottomLeftCorner;
    case PlasmaCore.Types.TopEdge:
    case PlasmaCore.Types.LeftEdge:
    default:                          return Qt.BottomRightCorner;
    }
}

MouseArea {
    id: resizeGrip
    width: Kirigami.Units.gridUnit
    height: Kirigami.Units.gridUnit
    z: 100
    cursorShape: (gripCorner === Qt.TopRightCorner || gripCorner === Qt.BottomLeftCorner)
                 ? Qt.SizeBDiagCursor : Qt.SizeFDiagCursor

    // Anchor by corner
    anchors.right:  (gripCorner === Qt.TopRightCorner || gripCorner === Qt.BottomRightCorner) ? parent.right : undefined
    anchors.left:   (gripCorner === Qt.TopLeftCorner  || gripCorner === Qt.BottomLeftCorner)  ? parent.left  : undefined
    anchors.top:    (gripCorner === Qt.TopLeftCorner  || gripCorner === Qt.TopRightCorner)    ? parent.top   : undefined
    anchors.bottom: (gripCorner === Qt.BottomLeftCorner || gripCorner === Qt.BottomRightCorner) ? parent.bottom : undefined

    property real startW
    property real startH
    property point startGlobal

    onPressed: function(mouse) {
        startW = fullRep.width;
        startH = fullRep.height;
        startGlobal = mapToGlobal(mouse.x, mouse.y);   // global => stable across resizes
    }

    onPositionChanged: function(mouse) {
        if (!pressed) return;
        var g = mapToGlobal(mouse.x, mouse.y);
        var dx = g.x - startGlobal.x;
        var dy = g.y - startGlobal.y;

        // Translate delta into width/height delta per corner
        var signX = (gripCorner === Qt.BottomRightCorner || gripCorner === Qt.TopRightCorner) ?  1 : -1;
        var signY = (gripCorner === Qt.BottomRightCorner || gripCorner === Qt.BottomLeftCorner) ?  1 : -1;

        var newW = Math.round(startW + signX * dx);
        var newH = Math.round(startH + signY * dy);

        newW = Math.max(fullRep.Layout.minimumWidth,  Math.min(fullRep.maxWidth,  newW));
        newH = Math.max(fullRep.Layout.minimumHeight, Math.min(fullRep.maxHeight, newH));

        Plasmoid.configuration.panelWidth  = newW;
        Plasmoid.configuration.panelHeight = newH;
    }
}
```

Notes on the implementation:
- **Global coordinates** for tracking mouse delta avoid drift as the MouseArea itself moves while the popup resizes.
- **Live writes** to `Plasmoid.configuration` propagate through the `Layout.preferredWidth/Height` bindings, so the popup follows the cursor in real time. KConfig coalesces these writes to disk.
- **Min/max clamps** prevent the user from making the popup unusably small or larger than reasonable (gridUnit*20 → gridUnit*80, matching Layout constraints).
- **Z-order**: `z: 100` keeps the grip above `messageList`'s scroll-to-end button (`z: 1`) and other overlays.
- **No visible affordance**: per your choice, just the cursor change on hover. Users who don't know about it won't be bothered; users who do can find it by hovering the corner.

### 4. Files touched
- `package/contents/config/main.xml` — add `panelWidth`, `panelHeight`
- `package/contents/ui/FullRepresentation.qml` — replace fixed Layout sizes, add resize grip MouseArea, import `org.kde.plasma.core` if not already (it is already imported in `main.qml` but not here — needs adding for `PlasmaCore.Types`)

### 5. Validation
- Restart Plasma (`plasmashell --replace &`) and test:
  - Hover the appropriate corner → diagonal resize cursor appears.
  - Drag → popup grows/shrinks live.
  - Close and reopen popup → size persists.
  - Move widget to different panel positions (top/bottom/left/right) → grip relocates correctly.
  - Min/max clamps hold.
  - Existing fixed-size feel is preserved for users who never drag (defaults unchanged).

## Caveats / Open Questions
- Plasma's popup sometimes snaps to multiples of `gridUnit`; live resize may visually lag by a frame. If choppy, we can switch to debounced writes — easy follow-up.
- If `Plasmoid.location` changes at runtime (rare — user re-docks the widget), the grip corner updates automatically via the binding, but a mid-drag relocation would be surprising. Not a real concern in practice.
