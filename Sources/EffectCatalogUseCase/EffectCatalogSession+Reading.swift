/// `EffectCatalogSession`, reading half: a look at an effect's source, and whether that look is still the newest.
import Domain

extension EffectCatalogSession {
    // MARK: - Reading a source

    /// What a look at an effect's source found, and the number the look was issued under.
    struct SourceRead {
        let token: Int
        let answer: Result<EffectSource, EffectPackageProblem>
    }

    /// Reads the source of `id`. The number is taken before the read is issued, with no
    /// suspension in between, so a later read always holds a later number.
    func read(source id: EffectID) async -> SourceRead {
        readToken += 1
        let token = readToken
        return SourceRead(token: token, answer: await packages.source(of: id))
    }

    /// Whether no read was issued after `read`. A read that is not the newest may hold files that
    /// have been edited since, whichever effect it was for, and must not act on its answer.
    func isNewest(_ read: SourceRead) -> Bool {
        read.token == readToken
    }
}
