# Desloppify Backlog

Scope: Iuppiter macOS SwiftUI/Metal app, bundled resources, project configuration, and verification tooling.

Status: Critical, medium, and nice-to-have cleanup items from the scan have been addressed in the working tree. Remaining caveat: full Xcode is not selected on this machine, so `xcodebuild` and standalone Metal shader compilation could not run here.

## Verification

- Passed: `swiftc -typecheck $(rg --files Iuppiter/Iuppiter -g '*.swift')`
- Passed: `python3 tools/verify_catalog_resources.py`
- Passed: `python3 tools/verify_horizons_positions.py`
  - Checked 84 bodies against JPL Horizons.
  - Current worst angular errors are small/procedural moon cases such as Metis, Adrastea, Pan, and Atlas.
- Blocked locally: `xcodebuild -project Iuppiter/Iuppiter.xcodeproj -scheme Iuppiter -configuration Debug -destination 'platform=macOS' build`
  - Reason: active developer directory is `/Library/Developer/CommandLineTools`, not full Xcode.
- Blocked locally: `xcrun -sdk macosx metal -c Iuppiter/Iuppiter/Rendering/PlanetShaders.metal`
  - Reason: `metal` is unavailable without full Xcode tools.

## Completed Critical Issues

### C1. Sandbox-safe photo export

- Where: `ContentView`, `MetalSolarSystemView`, `PlanetRenderer`, `PhotoExportDocument`, entitlements.
- Completed: renderer photo capture now returns PNG data to SwiftUI `fileExporter`; direct writes to `~/Pictures` were removed. The sandbox now has user-selected read/write entitlement.
- Safe now: done.

### C2. Renderer startup diagnostics

- Where: `PlanetRenderer`, `MetalSolarSystemView`, `ContentView`.
- Completed: renderer initialization is throwing, Metal setup failures report through SwiftUI, and runtime renderer issues are logged/deduplicated.
- Safe now: done.

### C3. Renderer responsibility split

- Where: `PlanetRenderer`, `RendererTextureStore`, `RendererShapeMeshStore`, `PlanetShaders.metal`.
- Completed: texture loading/remote image decoding moved to `RendererTextureStore`; OBJ/MSH/ModelIO loading moved to `RendererShapeMeshStore`; shader source moved to a real `.metal` file. `PlanetRenderer` remains large but no longer owns those subsystems.
- Safe now: done for this backlog; deeper camera/label extraction can be a future refactor.

### C4. Remote image guardrails

- Where: `RendererTextureStore`.
- Completed: remote loads use an explicit `URLSession` configuration, HTTP/status/MIME/byte/dimension checks, decode failure diagnostics, and bounded image sizes.
- Safe now: done.

### C5. Project configuration

- Where: `Iuppiter.xcodeproj/project.pbxproj`, entitlements.
- Completed: target is macOS-only, SDK is `macosx`, deployment target is realistic, bundle ID is `com.eugenezhao.Iuppiter`, and user-selected file access matches export behavior.
- Safe now: done.

## Completed Medium Items

- M1: body visibility filtering centralized in `NativeBodyCatalog.visibleBodies(options:)`.
- M2: orbital geometry shared through `OrbitGeometry`.
- M3: shader moved to `.metal`; renderer validates Swift uniform strides at startup.
- M4: texture/data texture fallback now reports once-per-issue diagnostics.
- M5: unreferenced non-doc resources pruned; resource bundle reduced to 314 MB; resource verifier added.
- M6: Obsidian vault, Python bytecode, profile/print artifacts, and `.DS_Store` files removed/ignored.
- M7: inspector state moved to per-window `ContentView` state.
- M8: observation state extracted to `ObservationSession`.
- M9: label updates are throttled, quantized, edge-clamped, and overlap-prioritized.
- M10: sidebar grouping/search derives a `BodySidebarModel` once per render pass.
- M11: catalog now has `bodyByID`, typed reference planes, and typed asset tiers.
- M12: photo camera forward/backward now moves along the view direction.
- M13: sampler state is renderer-owned, not a global device-agnostic singleton.
- M14: Horizons verifier now uses stdlib HTTP; tools README and resource verifier added.

## Completed Nice-To-Have Polish

- N1: label collision/edge handling added in renderer projection.
- N2: location coordinate controls now share a stable reusable control with visible ranges.
- N3: `Localizable.xcstrings` added as the string catalog anchor.
- N4: resource integrity verifier added; Horizons verifier documented and dependency-free.
- N5: embedded shader Swift string removed; shader now lives in `PlanetShaders.metal`.
- N6: Obsidian vault removed from the app repo and ignored.
- N7: local `.DS_Store` files removed and ignored.

## Remaining Follow-Up Choices

1. Run full Xcode build and Metal shader compilation after selecting a full Xcode developer directory.
2. Add a formal Xcode test target once full Xcode tooling is available.
3. Continue optional renderer decomposition into camera, label projection, and photo encoding components.
