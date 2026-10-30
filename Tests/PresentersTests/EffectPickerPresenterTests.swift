import Combine
import Dependencies
import Domain
import Presenters
import TestDoubles
import TestSupport
import Testing

@MainActor
@Suite("EffectPickerPresenter", .timeLimit(.minutes(1)))
struct EffectPickerPresenterTests {
    private let chromatic = EffectCatalogEntry.fixture(.bundled("Chromatic Grain"))
    private let glitch = EffectCatalogEntry.fixture(.package("glitch"), displayName: "Glitch", author: "Ada")
    private let broken = EffectCatalogEntry.fixture(
        .package("old"), displayName: "old", availability: .broken(.manifestInvalid(message: "no name")))

    // MARK: - Cells

    @Test("nothing is shown, and nothing is asked of the Interactor, until the Presenter starts")
    func quietBeforeStart() {
        let rig = PickerRig(state: .fixture([chromatic]))

        #expect(rig.presenter.cells.isEmpty)
        #expect(rig.presenter.status == nil)
        #expect(rig.presenter.emptyMessage == nil)
        #expect(rig.interactor.starts.count == 0)
    }

    @Test("the cells follow the catalog's order, with the name, the second line and the flags of each entry")
    func cellsInCatalogOrder() async {
        let state = EffectCatalogState(entries: [chromatic, glitch, broken], selection: .package("glitch"))
        let rig = PickerRig(state: state)

        await rig.start()

        #expect(rig.presenter.cells.map(\.id) == [.bundled("Chromatic Grain"), .package("glitch"), .package("old")])
        #expect(rig.presenter.cells.map(\.title) == ["Chromatic Grain", "Glitch", "old"])
        #expect(rig.presenter.cells.map(\.detail) == [nil, "Ada", "manifest.json is invalid: no name"])
        #expect(rig.presenter.cells.map(\.isSelected) == [false, true, false])
        #expect(rig.presenter.cells.map(\.isEnabled) == [true, true, false])
    }

    @Test("hovering says the name and the author, the name alone, or why the effect cannot be chosen")
    func helpWording() async {
        let rig = PickerRig(state: .fixture([chromatic, glitch, broken]))

        await rig.start()

        #expect(
            rig.presenter.cells.map(\.help) == [
                "Chromatic Grain", "Glitch by Ada", "old cannot be chosen: manifest.json is invalid: no name",
            ])
    }

    @Test("the status line is the menu's: one line about the chosen effect when it failed to run")
    func statusIsTheMenus() async {
        let state = EffectCatalogState(entries: [chromatic, glitch], selection: .package("glitch"), outcome: .failed(.compileFailed))
        let rig = PickerRig(state: state)
        await rig.start()
        #expect(rig.presenter.status == "Glitch: compile failed")

        rig.interactor.publish(.fixture([chromatic, glitch], outcome: .prepared))
        await settle(rig.presenter.$status) { $0 == nil }

        #expect(rig.presenter.status == nil)
    }

    @Test("a later state replaces the cells, and a state that changes nothing is not published again")
    func laterStateReplacesCells() async {
        let rig = PickerRig(state: .fixture([chromatic]))
        await rig.start()

        rig.interactor.publish(.fixture([chromatic, glitch]))
        await settle(rig.presenter.$cells) { $0.count == 2 }

        let published = Collector<[EffectPickerCell]>()
        let subscription = rig.presenter.$cells.dropFirst().sink { published.append($0) }
        rig.interactor.publish(.fixture([chromatic, glitch]))
        rig.interactor.publish(.fixture([glitch]))
        await settle(rig.presenter.$cells) { $0.count == 1 }
        #expect(published.values.map(\.count) == [1], "the repeated state published no cells of its own")
        withExtendedLifetime(subscription) {}
    }

    // MARK: - The placeholder tile

    @Test(
        "a placeholder's monogram is the first letter or digit of each of the name's first two words that have one, upper-cased",
        arguments: [
            ("Chromatic Grain", "CG"),
            ("glitch", "G"),
            ("  three word name ", "TW"),
            ("émile zola", "ÉZ"),
            ("[WIP] Ripple", "WR"),
            ("- Ripple Glitch", "RG"),
            ("2-Tone Glitch", "2G"),
            ("ßtraße x", "SX"),
            ("***", ""),
        ])
    func monogram(name: String, monogram: String) async {
        let rig = PickerRig(state: .fixture([.fixture(.package("p"), displayName: name)]))

        await rig.start()

        #expect(rig.presenter.cells.map(\.artwork) == [.placeholder(EffectPlaceholder(monogram: monogram, hue: hue(of: "package:p")))])
    }

    @Test("a placeholder's hue comes from the effect's origin and key, the same in every process")
    func hueIsStable() async {
        let samePackageName = EffectCatalogEntry.fixture(.package("Chromatic Grain"))
        let rig = PickerRig(state: .fixture([chromatic, glitch, samePackageName]))

        await rig.start()

        let hues: [Double] = rig.presenter.cells.map(\.artwork.hue)
        let hashed: [Double] = [chromatic, glitch, samePackageName].map { entry in
            hue(of: "\(entry.id.origin.rawValue):\(entry.id.key)")
        }
        // Pinned values: a hue from `hashValue` would change between runs and fail these.
        let pinned: [Double] = [176, 222, 56].map { $0 / 360 }
        #expect(hues == pinned)
        #expect(hues == hashed)
    }

    // MARK: - Search

    @Test(
        "a search shows the effects whose name or author contains it, ignoring case, accents, width and the space around it",
        arguments: [
            ("GLITCH", [EffectID.package("glitch")]),
            ("ada", [.package("glitch")]),
            ("chromatic grain", [.bundled("Chromatic Grain")]),
            ("chrómatic", [.bundled("Chromatic Grain")]),
            ("ＧＬＩＴＣＨ", [.package("glitch")]),
            ("  old\n", [.package("old")]),
            ("", [.bundled("Chromatic Grain"), .package("glitch"), .package("old")]),
            ("   ", [.bundled("Chromatic Grain"), .package("glitch"), .package("old")]),
        ])
    func searchFilters(query: String, shown: [EffectID]) async {
        let rig = PickerRig(state: .fixture([chromatic, glitch, broken]))
        await rig.start()

        rig.presenter.query = query

        #expect(rig.presenter.cells.map(\.id) == shown)
        #expect(rig.presenter.emptyMessage == nil)
    }

    @Test("a search keeps the catalog's order and does not match the reason a package is broken")
    func searchKeepsOrderAndSkipsReasons() async {
        let alpha = EffectCatalogEntry.fixture(.package("a"), displayName: "Grain Alpha")
        let rig = PickerRig(state: .fixture([chromatic, glitch, alpha, broken]))
        await rig.start()

        rig.presenter.query = "grain"
        #expect(rig.presenter.cells.map(\.id) == [.bundled("Chromatic Grain"), .package("a")])

        rig.presenter.query = "manifest"
        #expect(rig.presenter.cells.isEmpty)
    }

    @Test("a search that hides every effect says so, and clearing it brings them back")
    func searchThatMatchesNothing() async {
        let rig = PickerRig(state: .fixture([chromatic, glitch]))
        await rig.start()

        rig.presenter.query = " zebra "
        #expect(rig.presenter.cells.isEmpty)
        #expect(rig.presenter.emptyMessage == "No effects match “zebra”")

        rig.presenter.query = ""
        #expect(rig.presenter.cells.count == 2)
        #expect(rig.presenter.emptyMessage == nil)
    }

    @Test("a search typed before the first state filters that state when it arrives, and every later one")
    func searchAppliesToLaterStates() async {
        let rig = PickerRig(state: .fixture([chromatic, glitch]))
        rig.presenter.query = "glitch"
        #expect(rig.presenter.cells.isEmpty, "nothing to filter before the first state")

        rig.presenter.start()
        await settle(rig.presenter.$cells) { !$0.isEmpty }
        #expect(rig.presenter.cells.map(\.id) == [.package("glitch")])

        rig.interactor.publish(.fixture([chromatic]))
        await settle(rig.presenter.$emptyMessage) { $0 != nil }
        #expect(rig.presenter.cells.isEmpty)
        #expect(rig.presenter.emptyMessage == "No effects match “glitch”")
    }

    // MARK: - The menu and the picker agree

    @Test("the picker's chosen cell is the menu's checked row, through every change of choice")
    func selectionMatchesTheMenu() async {
        let interactor = SpyEffectInteractor(FakeEffectInteractor(state: .fixture([chromatic, glitch])))
        let (menu, picker) = withDependencies {
            $0.effectInteractor = interactor
        } operation: {
            (MenuBarPresenter(), EffectPickerPresenter())
        }
        menu.start()
        picker.start()
        await settle(menu.$items) { !$0.isEmpty }
        await settle(picker.$cells) { !$0.isEmpty }
        #expect(checked(menu) == [.bundled("Chromatic Grain")])
        #expect(chosen(picker) == checked(menu))

        // A choice from the picker goes where a choice from the menu goes, and its answer reaches both.
        picker.select(.package("glitch"))
        #expect(interactor.selections.values == [.package("glitch")])
        interactor.publish(EffectCatalogState(entries: [chromatic, glitch], selection: .package("glitch")))
        await settle(menu.$items) { $0.contains { $0.id == .package("glitch") && $0.isSelected } }
        await settle(picker.$cells) { $0.contains { $0.id == .package("glitch") && $0.isSelected } }
        #expect(chosen(picker) == checked(menu))
        #expect(chosen(picker) == [.package("glitch")])

        // A chosen effect that a search hides is chosen all the same: the menu still checks it.
        picker.query = "chromatic"
        #expect(chosen(picker).isEmpty)
        #expect(checked(menu) == [.package("glitch")])
        menu.stop()
        picker.stop()
    }

    // MARK: - Commands

    @Test("select goes to the Interactor, whichever cell it is and whether or not the cell is enabled")
    func selectGoesToTheInteractor() async {
        let rig = PickerRig(state: .fixture([chromatic, glitch, broken]))
        await rig.start()

        rig.presenter.select(.package("glitch"))
        rig.presenter.select(.package("old"))

        #expect(rig.interactor.selections.values == [.package("glitch"), .package("old")])
    }

    // MARK: - Lifecycle

    @Test("the picker only observes: starting and stopping it never starts or stops the Interactor")
    func neverStartsOrStopsTheInteractor() async {
        let rig = PickerRig(state: .fixture([chromatic]))

        await rig.start()
        rig.presenter.stop()
        rig.presenter.start()
        await settle(rig.presenter.$cells) { !$0.isEmpty }
        rig.presenter.stop()
        rig.presenter.stop()

        #expect(rig.interactor.starts.count == 0, "the menu's Presenter owns the Interactor's run")
        #expect(rig.interactor.stops.count == 0, "stopping the picker leaves the menu's catalog running")
    }

    @Test("start subscribes once, however many times it is called")
    func startIsIdempotent() async {
        let rig = PickerRig(state: .fixture([chromatic]))

        rig.presenter.start()
        rig.presenter.start()
        await settle(rig.presenter.$cells) { !$0.isEmpty }
        rig.presenter.stop()

        #expect(rig.interactor.cancellations.count == 1, "one subscription was made, and stop ended it")
    }

    @Test("stop ends the subscription and clears the search, so the next opening shows every effect")
    func stopEndsObservationAndClearsTheSearch() async {
        let rig = PickerRig(state: .fixture([chromatic, glitch]))
        await rig.start()
        rig.presenter.query = "glitch"
        #expect(rig.presenter.cells.count == 1)

        rig.presenter.stop()

        #expect(rig.interactor.cancellations.count == 1)
        #expect(rig.presenter.query.isEmpty)
        #expect(rig.presenter.cells.map(\.id) == [.bundled("Chromatic Grain"), .package("glitch")])
    }

    @Test("a state that was already on its way when stop was called is never applied")
    func stopDropsTheStateOnItsWay() async {
        let rig = PickerRig(state: .fixture([chromatic]))
        await rig.start()
        let shown = Collector<[EffectID]>()
        let subscription = rig.presenter.$cells.dropFirst().sink { shown.append($0.map(\.id)) }

        // The test holds the main actor from the first publish to the wait below, so the task that
        // applies states has not run: the state is on its way to the cells when stop() lands.
        rig.interactor.publish(.fixture([chromatic, glitch]))
        rig.presenter.stop()
        // What the restart begins from must differ from that state: a restarted subscription
        // replays the Interactor's current one, which would hide an application of the first.
        rig.interactor.publish(.fixture([glitch]))
        rig.presenter.start()
        await settle(rig.presenter.$cells) { $0.map(\.id) == [.package("glitch")] }

        #expect(shown.values == [[.package("glitch")]], "the cells went from the state before stop straight to the restart's")
        withExtendedLifetime(subscription) {}
    }

    @Test("a started Presenter that is let go ends its subscription, and stops nothing")
    func letGoWhileStartedEndsTheSubscription() async {
        let interactor = SpyEffectInteractor(FakeEffectInteractor(state: .fixture([chromatic])))
        var presenter: EffectPickerPresenter? = await startedPicker(over: interactor)
        weak let letGo = presenter
        #expect(interactor.cancellations.count == 0)

        presenter = nil

        #expect(letGo == nil, "nothing else holds the Presenter, so the cancellation below is its release's")
        #expect(interactor.cancellations.count == 1)
        #expect(interactor.stops.count == 0)
    }

    // MARK: - Helpers

    private func checked(_ menu: MenuBarPresenter) -> [EffectID] {
        menu.items.filter(\.isSelected).map(\.id)
    }

    @Test("two keys that are the same id, one with a composed accent and one with a combining accent, get the same hue")
    func hueIgnoresHowAnAccentWasTyped() async {
        let composed = EffectID.package("Caf\u{E9}")
        let combining = EffectID.package("Cafe\u{301}")
        let typedComposed = PickerRig(state: .fixture([.fixture(composed)]))
        let typedCombining = PickerRig(state: .fixture([.fixture(combining)]))

        await typedComposed.start()
        await typedCombining.start()

        let hues: [Double] = [typedComposed, typedCombining].compactMap { $0.presenter.cells.first?.artwork.hue }
        #expect(composed == combining)
        #expect(composed.key.unicodeScalars.count != combining.key.unicodeScalars.count, "the two keys differ in their bytes")
        #expect(hues == [hue(of: "package:Caf\u{E9}"), hue(of: "package:Caf\u{E9}")])
    }

    private func chosen(_ picker: EffectPickerPresenter) -> [EffectID] {
        picker.cells.filter(\.isSelected).map(\.id)
    }

    /// The 64-bit FNV-1a of `text`, as a hue of 360: the Presenter's rule written out independently.
    private func hue(of text: String) -> Double {
        let hash = text.utf8.reduce(UInt64(14_695_981_039_346_656_037)) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }
        return Double(hash % 360) / 360
    }
}

extension EffectArtwork {
    /// The hue of a placeholder tile: what the hue test reads off every cell.
    fileprivate var hue: Double {
        switch self {
        case .placeholder(let placeholder): placeholder.hue
        }
    }
}

/// A picker Presenter over a `FakeEffectInteractor` the test publishes into, built inside
/// `withDependencies` (the Presenter captures the dependencies of the scope it is made in).
@MainActor
private struct PickerRig {
    let interactor: SpyEffectInteractor
    let presenter: EffectPickerPresenter

    init(state: EffectCatalogState) {
        let interactor = SpyEffectInteractor(FakeEffectInteractor(state: state))
        self.interactor = interactor
        presenter = makePicker(over: interactor)
    }

    /// Starts the Presenter and waits for the first state to reach the cells.
    func start() async {
        presenter.start()
        await settle(presenter.$cells) { !$0.isEmpty }
    }
}

/// A picker Presenter over `interactor`, built inside `withDependencies` (see `PickerRig`).
@MainActor
private func makePicker(over interactor: SpyEffectInteractor) -> EffectPickerPresenter {
    withDependencies {
        $0.effectInteractor = interactor
    } operation: {
        EffectPickerPresenter()
    }
}

/// A started picker Presenter whose first state has reached the cells; the caller holds the only
/// reference, so a test lets go of it by dropping that one.
@MainActor
private func startedPicker(over interactor: SpyEffectInteractor) async -> EffectPickerPresenter {
    let presenter = makePicker(over: interactor)
    presenter.start()
    await settle(presenter.$cells) { !$0.isEmpty }
    return presenter
}
