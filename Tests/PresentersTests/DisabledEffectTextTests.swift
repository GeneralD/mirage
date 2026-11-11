import Domain
import TestDoubles
import Testing

@testable import Presenters

@Suite("Disabled effect wording", .timeLimit(.minutes(1)))
struct DisabledEffectTextTests {
    private let chromatic = EffectCatalogEntry.fixture(.bundled("Chromatic Grain"))
    private let glitch = EffectCatalogEntry.fixture(.package("glitch"), displayName: "Glitch", author: "Ada")
    private let broken = EffectCatalogEntry.fixture(
        .package("old"), displayName: "old", availability: .broken(.manifestMissing))

    /// Every reason that can switch an effect off, with the words the menu and the picker show for it.
    private let reasons: [(reason: EffectDisableReason, words: String)] = [
        (.failure(.timeout), "timed out"),
        (.failure(.pageFault), "GPU page fault"),
        (.failure(.accessRevoked), "GPU access revoked"),
        (.failure(.outOfMemory), "out of memory"),
        (.failure(.unknown), "unknown error"),
        (.overBudget, "over the GPU time budget"),
    ]

    // MARK: - Words

    @Test("a reason that switches an effect off is said in its own words, one for each reason")
    func reasonWords() {
        for (reason, words) in reasons {
            #expect(MenuBarText.reason(reason) == words)
        }
    }

    @Test("a switch-off reason and the failure it records say the same words, for the kinds both name")
    func reasonWordsMatchFailure() {
        let shared: [(EffectDisableReason, EffectFailure)] = [
            (.failure(.timeout), .timeout),
            (.failure(.pageFault), .pageFault),
            (.failure(.accessRevoked), .accessRevoked),
            (.failure(.outOfMemory), .outOfMemory),
        ]
        for (disabled, failure) in shared {
            #expect(MenuBarText.reason(disabled) == MenuBarText.reason(failure))
        }
    }

    // MARK: - Menu rows

    @Test("a switched-off effect's row says `Disabled: ` and then the reason, for every reason")
    func rowDetailSaysReason() {
        for (reason, words) in reasons {
            let state = EffectCatalogState.fixture([glitch], disabled: [glitch.id: reason])
            #expect(MenuBarText.detail(of: glitch, in: state) == "Disabled: \(words)")
        }
    }

    @Test("a switched-off effect's row is disabled and offers to re-enable it; every other row is enabled and offers nothing")
    func rowFlagsFollowSwitchOff() {
        let state = EffectCatalogState.fixture([chromatic, glitch], disabled: [glitch.id: .overBudget])
        let items = MenuBarText.items(of: state)

        #expect(items.map(\.isEnabled) == [true, false])
        #expect(items.map(\.reenableTitle) == [nil, "Re-enable Glitch"])
    }

    @Test("a broken package that is also switched off says why it is broken and still offers to re-enable it")
    func brokenAndSwitchedOffSaysWhyBroken() {
        let state = EffectCatalogState.fixture([chromatic, broken], disabled: [broken.id: .failure(.timeout)])
        let row = MenuBarText.items(of: state)[1]

        #expect(row.detail == "manifest.json is missing")
        #expect(row.isEnabled == false)
        #expect(row.reenableTitle == "Re-enable old")
    }

    @Test("a ready package that is not switched off keeps its author as its detail")
    func readyDetailKeepsAuthor() {
        let state = EffectCatalogState.fixture([glitch])

        #expect(MenuBarText.detail(of: glitch, in: state) == "Ada")
    }

    // MARK: - Status

    @Test("the status names the chosen effect when health has switched it off, with the reason")
    func statusNamesSwitchedOffChoice() {
        let state = EffectCatalogState.fixture([glitch], disabled: [glitch.id: .failure(.timeout)])

        #expect(MenuBarText.status(of: state) == "Glitch: disabled, timed out")
    }

    @Test("a switched-off effect that is not the chosen one leaves the status nil")
    func statusIgnoresUnchosenSwitchOff() {
        let state = EffectCatalogState(
            entries: [chromatic, glitch], selection: chromatic.id, outcome: .prepared, disabled: [glitch.id: .failure(.timeout)])

        #expect(MenuBarText.status(of: state) == nil)
    }

    @Test("with the GPU unavailable the status says so, before a switch-off or a failure of the chosen effect")
    func statusGPUUnavailableFirst() {
        let gpu = "GPU unavailable: frames pass through unchanged"
        let switchedOff = EffectCatalogState.fixture(
            [glitch], outcome: .failed(.compileFailed), disabled: [glitch.id: .failure(.timeout)], isGPUUnavailable: true)
        let failed = EffectCatalogState.fixture([glitch], outcome: .failed(.compileFailed), isGPUUnavailable: true)

        #expect(MenuBarText.status(of: switchedOff) == gpu)
        #expect(MenuBarText.status(of: failed) == gpu)
    }

    // MARK: - Picker cells

    @Test("a switched-off effect's picker cell is disabled, says why in its detail and names the reason in its help")
    func pickerCellSaysSwitchedOff() {
        let state = EffectCatalogState.fixture([chromatic, glitch], disabled: [glitch.id: .failure(.timeout)])
        let cells = pickerCells(of: state, matching: "")

        #expect(cells.map(\.isEnabled) == [true, false])
        #expect(cells[1].detail == "Disabled: timed out")
        #expect(cells[1].help == "Glitch is disabled: timed out")
    }

    @Test("a broken package's picker help names why it cannot be chosen, switched off or not")
    func brokenPickerHelpUnchanged() {
        let state = EffectCatalogState.fixture([broken], disabled: [broken.id: .overBudget])

        #expect(pickerCells(of: state, matching: "")[0].help == "old cannot be chosen: manifest.json is missing")
    }
}
