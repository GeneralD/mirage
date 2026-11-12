# Spec: effect health and auto-disable (MVP-D)

## Problem

A failing pass already passes the frame through, but nothing remembers. An effect that faults every
frame keeps being run, a hang stalls the call again and again, and a crash loop repeats at launch.
`EffectHealthPolicy` is named across the docs and does not exist.

## Shape

### What is observed

`EffectRuntimeRepositoryImpl.apply` drops `GPUTiming` with `.map { _ in () }`. It keeps answering the
pipeline `Result<Void, EffectFailure>` (the pipeline has no failure memory by design) and also reports
to a stream:

```swift
// Sources/Entity/EffectPassOutcome.swift
public struct EffectPassOutcome: Sendable, Hashable {
    public let fingerprint: EffectFingerprint          // stamped at admission
    public let result: Result<GPUTiming, EffectFailure>
}

// Sources/Entity/EffectFingerprint.swift: what compiled, not what it is called
public struct EffectFingerprint: Sendable, Hashable, Codable { public let value: String }
```

- The fingerprint is a stable hash of `(source, options, EffectParameterLayout)`, stamped when `admit`
  answers, so a pass admitted under A that ends after the user picks B is still A's.
- It must be stable across launches: a hand-written FNV-1a over the UTF-8, never `Hasher` (seeded per process).

```swift
// EffectRuntimeRepository
func outcomes() -> AsyncStream<EffectPassOutcome>
```

The stream lives in `EffectRuntimeState`, so it is executor-confined; buffering newest 64. Reporting
never suspends the frame path. A slow observer loses old outcomes, not frames.

### The policy (pure, `Sources/EffectCatalogUseCase/EffectHealthPolicy.swift`)

```swift
struct EffectHealthPolicy {
    struct Configuration {
        var failureThreshold = 5        // consecutive counted failures
        var budgetSeconds = 0.1         // a pass slower than this is over budget
        var budgetThreshold = 30        // consecutive over-budget passes
        var coolDownSeconds = 300.0     // doubled per failed trial, capped below
        var maximumCoolDownSeconds = 3600.0
    }
    enum Verdict: Equatable { case none, disable(EffectDisableReason), recovered }
    mutating func record(_ result: Result<GPUTiming, EffectFailure>, at now: ContinuousClock.Instant) -> Verdict
    func mayTrial(at now: ContinuousClock.Instant) -> Bool
    mutating func beginTrial()
}
```

| `EffectFailure` | Counted | Self-retry after cool-down |
|---|---|---|
| `timeout`, `pageFault` | yes | **no**: a retried hang stalls the user's call again |
| `accessRevoked` | yes, disables at once | **no** |
| `outOfMemory`, `unknown` | yes | yes |
| over budget | separate streak | yes |
| `compileFailed` | no, final and already shown | n/a |
| `invalidResource`, `internalError` | no, the runtime's own | n/a |

`GPUTiming` of zero (no data) is neither over budget nor proof of anything. A success resets both streaks.

### Disabled record

```swift
// Sources/Entity/DisabledEffectRecord.swift
public enum EffectDisableReason: Sendable, Hashable, Codable { case failure(EffectFailureKind), overBudget }
public struct DisabledEffectRecord: Sendable, Hashable, Codable {
    public let id: EffectID
    public let fingerprint: EffectFingerprint
    public let reason: EffectDisableReason
    public let retriesAutomatically: Bool
}
```

`Preferences.disabledEffects()` and `setDisabledEffects(_:)`, passed through `SettingsRepository`, one
JSON value under one versioned key. A record whose fingerprint no longer matches the package is
dropped when the catalog is listed: **an edit re-enables**.

### Catalog behaviour (`EffectCatalogSession`)

1. `run()` also consumes `outcomes()`. An outcome whose fingerprint is not the chosen effect's is ignored.
2. On `.disable`: the record is **written first**, then the runtime is prepared with the bundled
   effect, then the state is published. The chosen effect stays chosen and its row shows the reason.
3. The bundled effect is never disabled: when it fails too, the state says the GPU is unavailable.
4. At launch a chosen effect with a record is not prepared; the bundled effect runs.
5. Cool-down elapsed and `retriesAutomatically`: prepare it again for a trial. Success clears the record.
   Failure reopens with the doubled cool-down.
6. `reenable(_:)` on the UseCase and the Interactor clears the record and selects the effect.

### UI

`EffectMenuItem` gains the disabled reason in `detail` and a *Re-enable* action; the status line names
the effect and the reason. Wording is pure, in `MenuBarText`.

## Out

Per-encoder fault attribution in release builds, NaN detection by readback, adaptive quality, thermal
throttling, real-hang containment beyond what Metal's own watchdog gives.
