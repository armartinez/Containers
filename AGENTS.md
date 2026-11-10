# AGENTS.md

Guidance for coding agents working in this repository.

## Build / Test / Format

The project is a single Xcode project with two schemes:

- `Containers (macOS)` builds the app and the `ContainersCore` framework it embeds.
- `ContainersCoreTests` runs the framework's tests. The app target has no tests.

Signing reads `DEVELOPMENT_TEAM` from `Configuration/Local.xcconfig`, which is ignored by git. Copy `Configuration/Local.xcconfig.example` and fill in a team ID.

```bash
xcodebuild -project Containers.xcodeproj -scheme 'Containers (macOS)' build
```

```bash
xcodebuild -project Containers.xcodeproj -scheme ContainersCoreTests test
```

```bash
xcrun swift-format lint -r --configuration .swift-format Containers ContainersCore ContainersCoreTests
```

- The app target runs the same lint as a build phase, so warnings show up in every build. Keep it clean.
- `.swift-format` and `.swift-format-nolint` hold the project's style. Don't change them. Format only the files you touched: `xcrun swift-format format -i --configuration .swift-format <files>`. Never run it with `respectsExistingLineBreaks: false`.
- `Builder.pb.swift` and `Builder.grpc.swift` are generated from BuildKit's protocol. Don't edit them.

## Architecture

The app runs Linux containers with Apple's [Containerization](https://github.com/apple/containerization) package, in process: the container system runs inside the sandboxed app, with no separate server, XPC service or helper processes.

Calls flow in one direction:

```
SwiftUI / AppKit views
  → ContainerSystem and managers  (ContainersCore, @MainActor, public)
    → ContainerSystem.…Service (internal)
      → Services     (ContainersCore, internal)
        → Containerization
```

- `ContainerSystem` (`ContainerSystem.shared`) is the container system itself: its mode, status and lifecycle, the CLI beside it (`+CLI`), and the services it runs, created on start and released on stop. It holds the state the managers share, such as setup progress and reports, and installs the prerequisites (kernel, init image) on first start.
- The framework's public objects are `ContainerSystem` and one manager per domain, along with the value types they take and return, the way Apple's container client puts system handles (`ClientHealthCheck`) beside its per-domain clients (`ContainerClient`, `ClientImage`). The system is not a manager: it's the one running thing the managers work in. The services and everything else below them are internal.
- Managers are thin handles over the container system, one per domain. `ImageManager()` uses `ContainerSystem.shared`; tests pass a `MockContainerSystem` through `init(testSystem:)`. A manager can use any service, but never another manager.
- Services are what the container system runs: internal types that hold the state of containers, images, kernels and reports. A service is an actor only when it has mutable state to protect (`DefaultContainerService`, `ReadOnlyContainerService`, `ReportService`, `DNSService`); one that only holds `let`s is a `Sendable` struct. Only the container system creates them, when the system starts, and lets go of them when it stops. Everything else reaches them through the container system's internal, throwing `…Service` properties: managers and `Build/`. Nothing works while the system is stopped, by design.
- A service the system runs differently beside the container CLI's API server is a protocol (`ContainerService`, `ImageService`, `NetworkService`, `VolumeService`) with a `Default…` variant for the app's own mode and a `ReadOnly…` one that only reads the CLI's folder and throws `ContainerCLIError.apiServerRunning` for anything else. The container system picks the variants when the system starts, so managers never check the mode.
- Progress is Foundation's `Progress`. A method that reports progress takes `progress: Progress? = nil`, sets `totalUnitCount` to its own steps and runs each with `progress.performStep("…") { step in … }` (`Progress/Progress+Steps.swift`). Callers compose operations by weighting steps with `pendingUnitCount`.
- Failed work is recorded by `ReportManager` through `ReportService` into `ReportStore`: a plist manifest plus one gzipped body per report. Managers that delete items also delete their reports through `ReportService`.
- Errors are thrown as they are. Views turn them into an `ErrorAlert`; the framework and app models never build alerts.

## ContainersCore layout

Layer first, with domains inside each layer, like Apple's container project (`ContainerResource/`, `ContainerAPIService/Client/`, `ContainerAPIService/Server/`):

- `System/`: the public `ContainerSystem` and its extensions (`+CLI`, `+Configuration`, `+Prerequisites`, `+Services`), with the internal `Services/` inside it (`ContainerService`, `ImageService`, `KernelService`, `ReportService`), since the system owns the services. "Runtime" is kept for what it means in Apple's container CLI: the helper that runs one container (`runtimeHandler`, `runtime-configuration.json`).
- `Managers/`: `ContainerManager`, `ImageManager`, `VolumeManager`, `NetworkManager`, `ReportManager`.
- `Container/`, `Image/`, `Network/`, `Volume/`: value types for each domain (`ContainerConfiguration`, `ContainerSnapshot`, `ImageSummary`, `VolumeSummary`, …).
- `Build/`: the BuildKit client. `Builder/` holds the gRPC client and the builder container's controller; `BuildPipeline/` handles the stream, split by concern (`+ImageResolver`, `+ContentStore`, `+FSSync`, `+Export`, `+Stdio`).
- `Persistence/`, `Log/`, `Progress/`, `Reports/`, `Common/`: one folder per infrastructure concern.

## Containers (app) layout

Layer first, like Apple's SwiftUI samples:

- `ContainersApp.swift`: scenes, window IDs and the objects put in the environment.
- `Models/`: value types, grouped by feature to mirror `Views/` (`Containers/`, `Images/`, `Volumes/`, `Reports/`, `Dashboard/`, `Shared/`). Models never fetch or do work.
- `ViewModels/`: `@Observable` objects that hold state and actions for views: `RegistryLookup`, owned by the pull sheet with `@State`, and `SystemActions`, created by the app and shared by the menu bar and the status bar.
- `Utilities/`: app-wide objects not tied to a screen (`ActivityCenter`), plus support types (`ProgressObserver`, `WindowResizer`).
- `Controllers/`: AppKit controllers only, such as the `NSToolbarDelegate` objects. Their `NSViewRepresentable` binders live in `Views/`.
- `Views/<Feature>/`: one folder per screen. `Views/Shared/` holds complete units that appear once on a screen (`TableView`, `DetailView`, `CreateView`, `ScopeBar`). `Views/Components/` holds small reusable elements that can repeat on a screen (`BarToggle`, `SearchToken`, form rows).
- `Extensions/`: one `Type+Topic.swift` per extension.
- `Supporting Files/`: Info.plist, assets and entitlements. Don't rename it; the Info.plist membership exception depends on the path.

Rules for where logic goes:

- Split a large view into subviews or modifiers first. Add a view model only when that isn't enough.
- Exactly one place drives each fetch: a view, its view model, or an app-owned object. Fetching for display never happens in a model.
- Form state for a sheet lives in value models (`ImagePullRequest`, `ImageBuildRequest`, `ImageLoadRequest`) with an `isComplete` check.
- Long-running work (pull, build, create, start) runs through `ActivityCenter`, so its progress and failures show on the item's row.

## Naming

- Suffixes mean one thing each:
  - `Store`: persistence (`ReportStore`, `DefaultsStore`).
  - `Manager`: a framework facade over a collection of items (containers, images, …). A type that is one running thing is named after it instead (`ContainerSystem`).
  - `Service`: an internal type the container system runs.
  - `Controller`: an AppKit controller.
  - `Center`: an app-wide hub (`ActivityCenter`).
- Entries in a table are `…Item` (`ContainerItem`); framework list results are `…Summary`; value copies of live state are `…Snapshot`; a description of one operation to perform is `…Request`; a lifecycle enum is a nested `Status` (`ContainerSystem.Status`).
- Where a type mirrors one in Containerization, keep Apple's name and shape.
- Extension files are `Type+Topic.swift`, never `Type+Extensions.swift`. One primary type per file.

## Conventions

- **Concurrency:** Swift 6 language mode. The app target defaults to `MainActor` isolation; the framework is nonisolated by default. Add `nonisolated` only where the compiler needs it (table sort key paths, `Layout`, AppKit overrides that AppKit calls off the main actor), and group such constants in a `nonisolated` enum rather than marking each one.
- **Layout:** write like Apple's Containerization code. 180 columns is a ceiling, not a target: most lines stay under about 110. A call or signature that gets long goes one argument per line, with `)` on its own line. Don't nest a call inside another call's arguments (`append(Item(…))`); name the value first. Long `if`/`guard` conditions break at their commas, with `else {` on its own line. Blank lines contain no spaces.
- **Comments:** few, around 6% of lines. Comment only where the code would otherwise be "fixed" into something broken: an AppKit or SwiftUI ordering constraint, an API contract, an isolation assumption. State the reason itself. Don't narrate what the code does, record history, or justify a design by pointing at another app ("as Xcode does").
- **`let` over `var`:** a stored property is `var` only when something writes it after creation, such as a binding, a modified copy or state filled in later.
- **Native over forced:** accept AppKit's and SwiftUI's own sizing, toolbar behavior and dividers instead of working around them. The dashboard and detail toolbars are AppKit's for that reason.
- **Foundation first:** prefer platform APIs (`Progress`, `URLCache`, `@AppStorage` for state a view keeps in user defaults) over hand-written equivalents.
- **Unreleased:** the app hasn't shipped. Renaming storage keys, folders or labels needs no migration code yet.

## Tests

- Swift Testing only. Tests cover `ContainersCore` and don't start virtual machines.
- One suite per file: `FooTests.swift` holds `@Suite("Foo") struct FooTests`, with traits after the name (`@Suite("Volume manager", .serialized)`).
- Tests read `@Test("Short sentence-case phrase") func camelCaseName()`, with no `test` prefix.
- Each test works in its own `TemporaryDirectory` (`ContainersCoreTests/Support`) and removes it with `defer`. Tests that need managers use `MockContainerSystem` (`ContainersCoreTests/Mocks`); service tests build the service directly over a temporary folder.

## Releases

- To release, set `MARKETING_VERSION` (such as `0.2`), then push a tag with that number on `main`. `containers-testflight.yml` checks that the tag is on `main` and matches the version, then uploads the build to TestFlight.
- Release notes are the What's New text in App Store Connect; the repository keeps no changelog. `containers-release.yml` polls the App Store and, once a version is live, publishes a GitHub release for its tag with those notes and a Mac App Store link.

## Requirements

- macOS 26 or later on Apple silicon.
- Xcode 26 or later, Swift 6.
- [apple/containerization](https://github.com/apple/containerization) 0.28.0 or later, up to the next major version, through Swift Package Manager.
- The Linux kernel and init image are downloaded when the app first starts the container system.
