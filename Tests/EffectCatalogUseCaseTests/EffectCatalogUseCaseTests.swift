import Domain
import TestDoubles
import TestSupport
import Testing

/// What the effects menu's policy decides: which effect a run starts with, what choosing and
/// editing do to the runtime, and what becomes of a chosen effect that goes away. Every
/// `prepare` is answered by the test (`EffectCatalogRig.answer`), so each interleaving is
/// written down; nothing waits on time.
@Suite("EffectCatalogUseCase", .timeLimit(.minutes(1)))
struct EffectCatalogUseCaseTests {
    private typealias Rig = EffectCatalogRig
    private let bundled = Rig.bundled
    private let glitch = Rig.glitch
    private let other = Rig.other

    // MARK: - Where a run starts

    @Test("with nothing persisted, the bundled effect is prepared and chosen, and nothing is written or logged as lost")
    func nothingPersisted() async {
        let rig = Rig()
        let watcher = rig.watch()
        let run = rig.start()

        let request = await rig.answer(1)
        await watcher.states.waitForCount(1)

        #expect(request.effect == Rig.bundledSource)
        #expect(watcher.states.values == [Rig.state(selection: bundled)])
        #expect(rig.settings.reads.count == 1)
        #expect(rig.settings.writes.values.isEmpty, "restoring is not choosing")
        #expect(rig.log.messages(in: .effect) == ["effect 'Chromatic Grain' selected"])
        await rig.stop(run)
    }

    @Test("a persisted choice the catalog has ready is the one prepared")
    func persistedChoiceIsRestored() async {
        let rig = Rig(persisted: glitch.id)
        let watcher = rig.watch()
        let run = rig.start()

        let request = await rig.answer(1)
        await watcher.states.waitForCount(1)

        #expect(request.effect == Rig.glitchSource)
        #expect(watcher.states.values == [Rig.state(selection: glitch)])
        #expect(rig.runtime.prepareRequests.count == 1, "the bundled effect is not prepared first")
        #expect(rig.settings.writes.values.isEmpty)
        #expect(rig.log.messages(in: .effect) == ["effect 'Glitch' selected"])
        await rig.stop(run)
    }

    @Test("a persisted choice the catalog no longer has falls back to the bundled effect, with a log, and is not forgotten")
    func persistedChoiceIsGone() async {
        let rig = Rig(persisted: .package("vanished"))
        let watcher = rig.watch()
        let run = rig.start()

        let request = await rig.answer(1)
        await watcher.states.waitForCount(1)

        #expect(request.effect == Rig.bundledSource)
        #expect(watcher.states.values == [Rig.state(selection: bundled)])
        #expect(rig.log.messages(in: .effect) == ["effect 'vanished' is gone; back to 'Chromatic Grain'"])
        #expect(rig.settings.writes.values.isEmpty, "the persisted choice stays the user's last explicit one")
        await rig.stop(run)
    }

    @Test("a persisted choice whose package is broken falls back to the bundled effect, naming it by its display name")
    func persistedChoiceIsBroken() async {
        let broken = EffectCatalogEntry.fixture(.package("glitch"), displayName: "Glitch", availability: .broken(.manifestMissing))
        let rig = Rig(entries: [bundled, broken, other], persisted: glitch.id)
        let watcher = rig.watch()
        let run = rig.start()

        let request = await rig.answer(1)
        await watcher.states.waitForCount(1)

        #expect(request.effect == Rig.bundledSource)
        #expect(watcher.states.values == [Rig.state([bundled, broken, other], selection: bundled)])
        #expect(rig.log.messages(in: .effect) == ["effect 'Glitch' is gone; back to 'Chromatic Grain'"])
        await rig.stop(run)
    }

    @Test("a listing with no bundled effect offers nothing to fall back on: no state, no prepare, until one has it")
    func noBundledEffect() async {
        let rig = Rig(entries: [glitch, other])
        let watcher = rig.watch()
        let run = rig.start()
        await rig.packages.catalogRequests.waitForCount(1)

        rig.packages.publish([bundled, glitch, other])
        let request = await rig.answer(1)
        await watcher.states.waitForCount(1)

        #expect(request.effect == Rig.bundledSource)
        #expect(rig.runtime.prepareRequests.count == 1, "nothing was prepared for the first listing")
        #expect(rig.packages.sourceRequests.values == [bundled.id], "no source was read for it either")
        await rig.stop(run)
    }

    // MARK: - Choosing

    @Test("select prepares the effect's source, remembers the choice, and publishes the outcome it returns")
    func selectPrepares() async {
        let rig = Rig()
        let watcher = rig.watch()
        let run = rig.start()
        await rig.answer(1)
        await watcher.states.waitForCount(1)

        let selection = Task { await rig.subject.select(glitch.id) }
        let request = await rig.answer(2)
        let outcome = await selection.value
        await watcher.states.waitForCount(2)

        #expect(request.effect == Rig.glitchSource)
        #expect(outcome == .prepared)
        #expect(watcher.states.values.last == Rig.state(selection: glitch, outcome: .prepared))
        #expect(rig.settings.writes.values == [glitch.id])
        #expect(rig.log.messages(in: .effect).last == "effect 'Glitch' selected")
        await rig.stop(run)
    }

    @Test("a source the runtime cannot compile is the outcome of the choice, and the choice stands")
    func selectFailed() async {
        let rig = Rig()
        let watcher = rig.watch()
        let run = rig.start()
        await rig.answer(1)
        await watcher.states.waitForCount(1)

        let selection = Task { await rig.subject.select(glitch.id) }
        await rig.answer(2, with: .failure(.compileFailed))
        let outcome = await selection.value
        await watcher.states.waitForCount(2)

        #expect(outcome == .failed(.compileFailed))
        #expect(watcher.states.values.last == Rig.state(selection: glitch, outcome: .failed(.compileFailed)))
        #expect(rig.settings.writes.values == [glitch.id])
        await rig.stop(run)
    }

    @Test("choosing a broken package, or one the catalog does not have, answers unavailable and calls and publishes nothing")
    func selectUnavailable() async {
        let broken = EffectCatalogEntry.fixture(.package("broken"), availability: .broken(.sourceMissing))
        let rig = Rig(entries: [bundled, broken])
        let watcher = rig.watch()
        let run = rig.start()
        await rig.answer(1)
        await watcher.states.waitForCount(1)
        let sourceReads = rig.packages.sourceRequests.count

        #expect(await rig.subject.select(broken.id) == .unavailable(.sourceMissing))
        #expect(await rig.subject.select(.package("nowhere")) == .unavailable(nil))

        #expect(rig.runtime.prepareRequests.count == 1)
        #expect(rig.packages.sourceRequests.count == sourceReads)
        #expect(rig.settings.writes.values.isEmpty)
        // A sentinel through the same pipeline: the next state published is the next one in line.
        rig.packages.publish([bundled])
        await watcher.states.waitForCount(2)
        #expect(watcher.states.values == [Rig.state([bundled, broken]), Rig.state([bundled])])
        await rig.stop(run)
    }

    @Test(
        "choosing a ready package whose files cannot be read keeps and remembers the choice, shows the problem as the outcome, and leaves the runtime alone"
    )
    func selectUnreadable() async {
        let rig = Rig()
        let watcher = rig.watch()
        let run = rig.start()
        await rig.answer(1)
        await watcher.states.waitForCount(1)
        let problem = EffectPackageProblem.unreadable(message: "busy")
        rig.packages.script(.failure(problem), for: glitch.id)

        #expect(await rig.subject.select(glitch.id) == .unavailable(problem))
        await watcher.states.waitForCount(2)

        #expect(rig.runtime.prepareRequests.values.map(\.effect) == [Rig.bundledSource], "the runtime keeps the effect it has")
        #expect(rig.settings.writes.values == [glitch.id], "the choice was made before the files were read, and stands")
        #expect(rig.log.contains("effect 'Glitch' cannot be read"))
        #expect(watcher.states.values.last == Rig.state(selection: glitch, outcome: .unavailable(problem)))
        await rig.stop(run)
    }

    @Test("a choice before the run has listed anything has nothing to choose from")
    func selectBeforeTheFirstListing() async {
        let rig = Rig()
        #expect(await rig.subject.select(glitch.id) == .unavailable(nil))
        #expect(rig.settings.writes.values.isEmpty)
        #expect(rig.runtime.prepareRequests.count == 0)
    }

    @Test("choosing the effect that is already chosen prepares it again: the way to retry")
    func selectAgain() async {
        let rig = Rig()
        let watcher = rig.watch()
        let run = rig.start()
        await rig.answer(1, with: .failure(.internalError))
        await watcher.states.waitForCount(1)

        let selection = Task { await rig.subject.select(bundled.id) }
        let request = await rig.answer(2)
        #expect(await selection.value == .prepared)
        await watcher.states.waitForCount(2)

        #expect(request.effect == Rig.bundledSource)
        #expect(watcher.states.values == [Rig.state(outcome: .failed(.internalError)), Rig.state(outcome: .prepared)])
        await rig.stop(run)
    }

    // MARK: - Hot reload

    @Test("a listing in which the chosen effect's source changed prepares the new source")
    func hotReload() async {
        let rig = Rig(persisted: glitch.id)
        let watcher = rig.watch()
        let run = rig.start()
        await rig.answer(1)
        await watcher.states.waitForCount(1)

        let edited = EffectSource(name: "Glitch", source: "glitch v2")
        rig.packages.script(.success(edited), for: glitch.id)
        rig.packages.publish([bundled, glitch, other])
        let request = await rig.answer(2)
        // A reload that works changes nothing the menu shows, so no state says it has landed; the
        // next listing, which changes a row, can only be taken after it did.
        rig.packages.publish([bundled, glitch])
        await watcher.states.waitForCount(2)

        #expect(request.effect == edited)
        #expect(rig.runtime.prepareRequests.count == 2)
        #expect(watcher.states.values.last == Rig.state([bundled, glitch], selection: glitch, outcome: .prepared))
        #expect(rig.log.messages(in: .effect) == ["effect 'Glitch' selected", "effect 'Glitch' reloaded"])
        await rig.stop(run)
    }

    @Test("a broken edit is the outcome (the runtime passes frames through), and fixing it brings the effect back")
    func brokenEditThenFix() async {
        let rig = Rig(persisted: glitch.id)
        let watcher = rig.watch()
        let run = rig.start()
        await rig.answer(1)
        await watcher.states.waitForCount(1)

        rig.packages.script(.success(EffectSource(name: "Glitch", source: "glitch broken")), for: glitch.id)
        rig.packages.publish([bundled, glitch, other])
        await rig.answer(2, with: .failure(.compileFailed))
        await watcher.states.waitForCount(2)
        rig.packages.script(.success(EffectSource(name: "Glitch", source: "glitch fixed")), for: glitch.id)
        rig.packages.publish([bundled, glitch, other])
        await rig.answer(3)
        await watcher.states.waitForCount(3)

        #expect(watcher.states.values.map(\.outcome) == [.prepared, .failed(.compileFailed), .prepared])
        #expect(watcher.states.values.allSatisfy { $0.selection == glitch.id }, "a broken edit does not change the choice")
        await rig.stop(run)
    }

    @Test("a listing in which the source did not change prepares nothing, whatever else it changed")
    func unchangedSource() async {
        let rig = Rig(persisted: glitch.id)
        let watcher = rig.watch()
        let run = rig.start()
        await rig.answer(1)
        await watcher.states.waitForCount(1)

        rig.packages.publish([bundled, glitch])  // a row went away: the new rows are published, the source was read and is the old one
        await watcher.states.waitForCount(2)
        let edited = EffectSource(name: "Glitch", source: "glitch v2")
        rig.packages.script(.success(edited), for: glitch.id)
        rig.packages.publish([bundled, glitch, other])
        let request = await rig.answer(2)
        await watcher.states.waitForCount(3)

        #expect(request.effect == edited, "the very next prepare is the edit: the listing before it prepared nothing")
        #expect(rig.runtime.prepareRequests.count == 2)
        #expect(watcher.states.values.map(\.entries) == [[bundled, glitch, other], [bundled, glitch], [bundled, glitch, other]])
        await rig.stop(run)
    }

    // MARK: - A chosen effect that goes away

    @Test("when the chosen package disappears the bundled effect is prepared and chosen, with a log, and nothing is written")
    func chosenPackageVanishes() async {
        let rig = Rig(persisted: glitch.id)
        let watcher = rig.watch()
        let run = rig.start()
        await rig.answer(1)
        await watcher.states.waitForCount(1)

        rig.packages.publish([bundled, other])
        let request = await rig.answer(2)
        await watcher.states.waitForCount(2)

        #expect(request.effect == Rig.bundledSource)
        #expect(watcher.states.values.last == Rig.state([bundled, other], selection: bundled))
        #expect(rig.log.messages(in: .effect) == ["effect 'Glitch' selected", "effect 'Glitch' is gone; back to 'Chromatic Grain'"])
        #expect(rig.settings.writes.values.isEmpty, "going away is not a choice")
        await rig.stop(run)
    }

    @Test("when the chosen package turns broken the bundled effect takes over, and the package listed again does not take it back")
    func chosenPackageTurnsBroken() async {
        let rig = Rig(persisted: glitch.id)
        let watcher = rig.watch()
        let run = rig.start()
        await rig.answer(1)
        await watcher.states.waitForCount(1)

        let broken = EffectCatalogEntry.fixture(.package("glitch"), displayName: "Glitch", availability: .broken(.manifestInvalid(message: "x")))
        rig.packages.publish([bundled, broken, other])
        await rig.answer(2)
        await watcher.states.waitForCount(2)
        rig.packages.publish([bundled, glitch, other])
        await watcher.states.waitForCount(3)

        #expect(watcher.states.values.map(\.selection) == [glitch.id, bundled.id, bundled.id])
        #expect(rig.runtime.prepareRequests.count == 2, "the effect that took over is still the prepared one")
        await rig.stop(run)
    }

    @Test(
        "a chosen package that is listed ready but cannot be read is the outcome (unavailable); the runtime is left alone, and the next listing tries again"
    )
    func unreadableSource() async {
        let rig = Rig(persisted: glitch.id)
        let problem = EffectPackageProblem.unreadable(message: "permission denied")
        rig.packages.script(.failure(problem), for: glitch.id)
        let watcher = rig.watch()
        let run = rig.start()
        await watcher.states.waitForCount(1)

        #expect(watcher.states.values == [Rig.state(selection: glitch, outcome: .unavailable(problem))])
        #expect(rig.runtime.prepareRequests.count == 0)
        #expect(rig.log.contains("effect 'Glitch' cannot be read"))

        rig.packages.script(.success(Rig.glitchSource), for: glitch.id)
        rig.packages.publish([bundled, glitch, other])
        await rig.answer(1)
        await watcher.states.waitForCount(2)
        #expect(watcher.states.values.last == Rig.state(selection: glitch, outcome: .prepared))
        await rig.stop(run)
    }

    @Test("a source that could not be read once and reads again as the one the runtime has brings back how the runtime took it: prepared")
    func unreadableOnceThenSameSourcePrepared() async {
        let rig = Rig(persisted: glitch.id)
        let problem = EffectPackageProblem.unreadable(message: "mid-save")
        let watcher = rig.watch()
        let run = rig.start()
        await rig.answer(1)
        await watcher.states.waitForCount(1)

        rig.packages.script(.failure(problem), for: glitch.id)
        rig.packages.publish([bundled, glitch, other])
        await watcher.states.waitForCount(2)
        rig.packages.script(.success(Rig.glitchSource), for: glitch.id)
        rig.packages.publish([bundled, glitch, other])
        await watcher.states.waitForCount(3)

        #expect(watcher.states.values.map(\.outcome) == [.prepared, .unavailable(problem), .prepared])
        #expect(rig.runtime.prepareRequests.count == 1, "the runtime never lost the effect, so it is not handed it again")
        await rig.stop(run)
    }

    @Test("... and when the runtime had refused that source, it is the refusal that comes back, not a success")
    func unreadableOnceThenSameSourceFailed() async {
        let rig = Rig(persisted: glitch.id)
        let problem = EffectPackageProblem.unreadable(message: "mid-save")
        let watcher = rig.watch()
        let run = rig.start()
        await rig.answer(1, with: .failure(.compileFailed))
        await watcher.states.waitForCount(1)

        rig.packages.script(.failure(problem), for: glitch.id)
        rig.packages.publish([bundled, glitch, other])
        await watcher.states.waitForCount(2)
        rig.packages.script(.success(Rig.glitchSource), for: glitch.id)
        rig.packages.publish([bundled, glitch, other])
        await watcher.states.waitForCount(3)

        #expect(watcher.states.values.map(\.outcome) == [.failed(.compileFailed), .unavailable(problem), .failed(.compileFailed)])
        #expect(rig.runtime.prepareRequests.count == 1)
        await rig.stop(run)
    }

    @Test("a prepare still out when the source cannot be read goes on: its answer waits behind the problem, and returns with the source")
    func unreadableWhileAPrepareIsOut() async {
        let rig = Rig(persisted: glitch.id)
        let problem = EffectPackageProblem.unreadable(message: "mid-save")
        let watcher = rig.watch()
        let run = rig.start()
        await rig.answer(1)
        await watcher.states.waitForCount(1)

        let choice = Task { await rig.subject.select(other.id) }
        await rig.runtime.prepareRequests.waitForCount(2)
        rig.packages.script(.failure(problem), for: other.id)
        rig.packages.publish([bundled, glitch, other])
        await watcher.states.waitForCount(2)
        await rig.answer(2, with: .failure(.compileFailed))
        #expect(await choice.value == .failed(.compileFailed), "the caller hears the runtime")
        // A sentinel through the same pipeline: a state for the next listing, which still cannot read the file.
        rig.packages.publish([bundled, glitch, other, EffectCatalogEntry.fixture(.package("later"))])
        await watcher.states.waitFor { $0.entries.count == 4 }
        rig.packages.script(.success(Rig.otherSource), for: other.id)
        rig.packages.publish([bundled, glitch, other])
        await watcher.states.waitForCount(4)

        #expect(
            watcher.states.values.map(\.outcome) == [.prepared, .unavailable(problem), .unavailable(problem), .failed(.compileFailed)],
            "the answer was not shown over the problem, and came back once the source read again")
        #expect(rig.runtime.prepareRequests.count == 2)
        await rig.stop(run)
    }

    @Test("a source that reads again while its prepare is still out shows no outcome yet, and the answer lands when it comes")
    func recoveryWhileAPrepareIsOut() async {
        let rig = Rig(persisted: glitch.id)
        let problem = EffectPackageProblem.unreadable(message: "mid-save")
        let watcher = rig.watch()
        let run = rig.start()
        await rig.answer(1)
        await watcher.states.waitForCount(1)

        let choice = Task { await rig.subject.select(other.id) }
        await rig.runtime.prepareRequests.waitForCount(2)
        rig.packages.script(.failure(problem), for: other.id)
        rig.packages.publish([bundled, glitch, other])
        await watcher.states.waitForCount(2)
        rig.packages.script(.success(Rig.otherSource), for: other.id)
        rig.packages.publish([bundled, glitch, other])
        await watcher.states.waitForCount(3)
        await rig.answer(2)
        #expect(await choice.value == .prepared)
        await watcher.states.waitForCount(4)

        #expect(watcher.states.values.map(\.outcome) == [.prepared, .unavailable(problem), nil, .prepared])
        #expect(rig.runtime.prepareRequests.count == 2, "the recovery listing handed the runtime nothing it already has")
        await rig.stop(run)
    }

    // MARK: - Small things

    @Test("opening the effects folder is the Repository's")
    func openFolderIsDelegated() {
        let rig = Rig()
        rig.subject.openEffectsFolder()
        #expect(rig.packages.folderOpens.count == 1)
    }

    @Test("the compile failure is the runtime's to log: the catalog adds no line for it")
    func noSecondFailureLog() async {
        let rig = Rig()
        let watcher = rig.watch()
        let run = rig.start()
        await rig.answer(1, with: .failure(.compileFailed))
        await watcher.states.waitForCount(1)

        #expect(rig.log.messages(in: .effect) == ["effect 'Chromatic Grain' selected"])
        await rig.stop(run)
    }
}
