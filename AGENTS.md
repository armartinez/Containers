# AGENTS.md

Guidance for coding agents working in this repository.

## Build / Test / Format

The project is a single Xcode project with two schemes:

- `Containers (macOS)` builds the app and the `ContainerSystem` framework it embeds.
- `ContainerSystemTests` runs the framework's tests. The app target has no tests.

Signing reads `DEVELOPMENT_TEAM` from `Configuration/Local.xcconfig`, which is ignored by git. Copy `Configuration/Local.xcconfig.example` and fill in a team ID.

```bash
xcodebuild -project Containers.xcodeproj -scheme 'Containers (macOS)' build
```

```bash
xcodebuild -project Containers.xcodeproj -scheme ContainerSystemTests test
```

```bash
xcrun swift-format lint -r --configuration .swift-format Containers ContainerSystem ContainerSystemTests
```

- The app target runs the same lint as a build phase, so warnings show up in every build. Keep it clean.
- `.swift-format` and `.swift-format-nolint` hold the project's style. Don't change them. Format only the files you touched: `xcrun swift-format format -i --configuration .swift-format <files>`. Never run it with `respectsExistingLineBreaks: false`.
- `Builder.pb.swift` and `Builder.grpc.swift` are generated from BuildKit's protocol. Don't edit them.

## Architecture

The app runs Linux containers with Apple's [Containerization](https://github.com/apple/containerization) package, in process: the engine runs as actors inside the sandboxed app, with no separate server, XPC service or helper processes.

Calls flow in one direction:

```
SwiftUI / AppKit views
  → Managers         (ContainerSystem, @MainActor, public)
    → Services       (ContainerSystem, actors, internal)
      → Containerization
```

- `ContainerRuntime` (`ContainerRuntime.shared`) owns the services and the runtime's shared state: system status, setup progress and reports. It also installs the prerequisites (kernel, init image) on first start.
- Managers are thin handles over the runtime, one per domain. `ImageManager()` uses the shared runtime; tests pass a `MockContainerRuntime` through `init(testRuntime:)`.
- Services are the engine: internal actors that hold the state of containers, images and kernels. Only managers call them.
- Progress is Foundation's `Progress`. A method that reports progress takes `progress: Progress? = nil`, sets `totalUnitCount` to its own steps and runs each with `progress.performStep("…") { step in … }` (`Progress/Progress+Steps.swift`). Callers compose operations by weighting steps with `pendingUnitCount`.
- Failed work is recorded by `ReportManager` into `ReportStore`: a plist manifest plus one gzipped body per report.
- Errors are thrown as they are. Views turn them into an `ErrorAlert`; the framework and app models never build alerts.

## ContainerSystem layout

Role first, with domains inside each role:

- `Managers/`: `ContainerManager`, `ImageManager`, `VolumeManager`, `NetworkManager`, `SystemManager`, `ReportManager`.
- `Services/`: `ContainersService`, `ImagesService`, `KernelService`.
- `Container/`, `Image/`, `Network/`, `Volume/`: value types for each domain (`ContainerConfiguration`, `ContainerSnapshot`, `ImageSummary`, `VolumeSummary`, …).
- `Build/`: the BuildKit client. `Builder/` holds the gRPC client and the builder container's controller; `BuildPipeline/` handles the stream, split by concern (`+ImageResolver`, `+ContentStore`, `+FSSync`, `+Export`, `+Stdio`).
- `Persistence/`, `Plugin/`, `Log/`, `Progress/`, `Reports/`, `Common/`: one folder per infrastructure concern.

## Containers (app) layout

Layer first, like Apple's SwiftUI samples:

- `ContainersApp.swift`: scenes, window IDs and the objects put in the environment.
- `Models/`: value types, grouped by feature to mirror `Views/` (`Containers/`, `Images/`, `Volumes/`, `Reports/`, `Dashboard/`, `Shared/`). Models never fetch or do work.
- `ViewModels/`: `@Observable` objects a single view creates and owns with `@State` (`RegistryLookup`).
- `Utilities/`: `@Observable` objects the app owns and shares through the environment (`ActivityCenter`, `SystemActions`), plus support types (`ProgressObserver`, `WindowResizer`).
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
  - `Manager`: a framework facade.
  - `Service`: a framework engine actor.
  - `Controller`: an AppKit controller.
  - `Center`: an app-wide hub (`ActivityCenter`).
- Entries in a table are `…Item` (`ContainerItem`); framework list results are `…Summary`; value copies of live state are `…Snapshot`; a description of one operation to perform is `…Request`; a lifecycle enum is a nested `Status` (`SystemManager.Status`).
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

- Swift Testing only. Tests cover `ContainerSystem` and don't start virtual machines.
- One suite per file: `FooTests.swift` holds `@Suite("Foo") struct FooTests`, with traits after the name (`@Suite("Volume manager", .serialized)`).
- Tests read `@Test("Short sentence-case phrase") func camelCaseName()`, with no `test` prefix.
- Each test works in its own `TemporaryDirectory` (`ContainerSystemTests/Support`) and removes it with `defer`. Tests that need managers use `MockContainerRuntime` (`ContainerSystemTests/Mocks`); service tests build the service directly over a temporary folder.

## Requirements

- macOS 26 or later on Apple silicon.
- Xcode 26 or later, Swift 6.
- [apple/containerization](https://github.com/apple/containerization) 0.28.0 or later, up to the next major version, through Swift Package Manager.
- The Linux kernel and init image are downloaded when the app first starts the container system.
