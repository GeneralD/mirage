# Swift Idioms

## Immutability First

**Every `var` must be justified.** Default to `let` with functional chains.

```swift
// Bad — mutable accumulator
var frames: [FrameRef] = []
for await frame in stream { frames.append(frame) }

// Good — let + reduce
let frames = await stream.reduce(into: [FrameRef]()) { $0.append($1) }
```

When `map` cannot be used with `await`, hide the `var` in a private
`asyncMap` helper.

## No Force Unwraps

`!`, `try!`, `as!` are forbidden in `Sources/`. Errors propagate explicitly;
`Result` for handlers that must not throw.

## Type Safety over Strings

Fixed sets are `enum … : CaseIterable, Sendable`, never `[String]`. Effect
parameter types, failure kinds, install states and log subsystems are closed
enums; adding a case is the only way to add a value.

## Scoped Resources

A resource with a lifetime (surface, Mach port right, compiled library,
capture session) is handed out as an opaque handle (`SurfaceToken`,
`MachPortToken`, `LibraryHandle`, `CaptureSessionHandle`) that its owner gives
back exactly once — through the port that issued it, or through the handle's
own `stop()`. Never expose `retain`/`release` pairs to callers. Where a handle
can be given back twice, make that detectable: the generation tag on
`SurfaceToken` turns a double release into a `false`, not a corrupted slot.

## No Actors on the Frame Path

Frame-path types are `final class` state machines run on the `FrameExecutor`
port, or value types. `actor` is acceptable only for off-path, low-rate state
(settings, catalog) and never holds an `IOSurface`.

## View File Organization — `XxxView.swift` Holds Only the Struct

As in lyra: the SwiftUI `View` struct alone. Geometry goes to
`XxxGeometry.swift` (pure, tested); irreducible drawing goes to
`XxxRenderer.swift` (`@MainActor`, thin, untested by design). The Presenter
decides values; the View maps values to pixels.

## Pattern Matching in Async Streams

Use `for await case .completed(let x) in stream` to filter variants directly.

## Formatting

`swift format` with the repository `.swift-format` (4 spaces, 150 columns).
`make lint` is a CI gate.
