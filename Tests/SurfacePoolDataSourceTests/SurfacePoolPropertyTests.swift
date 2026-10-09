import Dependencies
import Domain
import TestDoubles
import TestSupport
import Testing

@testable import SurfacePoolDataSource

/// Random operation sequences against a trivial model of the pool. The model is
/// deliberately naive (arrays and a set) so that it cannot share a bug with the
/// slot table it checks.
@Suite("SurfacePoolDataSource properties")
struct SurfacePoolPropertyTests {
    private static let capacity = 4
    private static let steps = 300

    private enum Operation {
        case adopt, allocate, allocateFilled, releaseValid, releaseStale, releaseFabricated, releaseAll

        /// Weighted so the pool both fills up (exhaustion) and churns (slot reuse).
        static let weighted: [Operation] =
            Array(repeating: .adopt, count: 3) + Array(repeating: .allocate, count: 2) + [.allocateFilled] + Array(repeating: .releaseValid, count: 4)
            + Array(repeating: .releaseStale, count: 2) + [.releaseFabricated, .releaseAll]
    }

    private struct Model {
        // Mutable by design: the model is the expected state the pool is compared against.
        var live: [(token: SurfaceToken, handle: any SurfaceHandle, descriptor: SurfaceDescriptor)] = []
        var dead: [SurfaceToken] = []
        var issued: Set<SurfaceToken> = []

        mutating func issue(_ token: SurfaceToken, _ handle: any SurfaceHandle, _ descriptor: SurfaceDescriptor) {
            #expect(issued.insert(token).inserted, "slot \(token.index) reused with generation \(token.generation) twice")
            live.append((token, handle, descriptor))
        }

        mutating func retire(at position: Int) {
            dead.append(live.remove(at: position).token)
        }
    }

    private func check(_ pool: SurfacePoolDataSourceImpl, against model: Model, seed: UInt64) {
        #expect(pool.liveCount == model.live.count, "seed \(seed)")
        #expect(pool.liveCount <= Self.capacity, "seed \(seed)")
        #expect(model.live.allSatisfy { pool.handle(for: $0.token) === $0.handle && pool.descriptor(for: $0.token) == $0.descriptor }, "seed \(seed)")
        #expect(model.dead.allSatisfy { pool.handle(for: $0) == nil && pool.descriptor(for: $0) == nil }, "seed \(seed)")
    }

    @Test("liveCount, capacity, staleness and handle identity hold after every step", arguments: Seeds.range(0..<50))
    func invariants(seed: UInt64) throws {
        let gateway = FakeIOSurfaceGateway()
        let pool = withDependencies {
            $0.ioSurfaceGateway = gateway
        } operation: {
            SurfacePoolDataSourceImpl(capacity: Self.capacity)
        }
        // Mutable by design: the generator and the model advance with each step.
        var generator = SeededGenerator(seed: seed)
        var model = Model()
        var nextID: UInt32 = 1_000

        for _ in 0..<Self.steps {
            let full = model.live.count == Self.capacity
            switch Operation.weighted.randomElement(using: &generator) ?? .adopt {
            case .adopt:
                let handle = FakeSurfaceHandle(id: nextID)
                nextID += 1
                let token = pool.adopt(handle, descriptor: handle.descriptor)
                guard !full else {
                    #expect(token == nil, "seed \(seed)")
                    break
                }
                model.issue(try #require(token), handle, handle.descriptor)
            case .allocate:
                let before = gateway.createdCount
                let token = try pool.allocate(.hd720)
                guard !full else {
                    #expect(token == nil && gateway.createdCount == before, "seed \(seed)")
                    break
                }
                let issued = try #require(token)
                model.issue(issued, try #require(pool.handle(for: issued)), .hd720)
            case .allocateFilled:
                let before = gateway.createdCount
                let failing = Bool.random(using: &generator)
                gateway.failFill(with: failing ? .allocationFailed : nil)
                defer { gateway.failFill(with: nil) }
                let token: SurfaceToken?
                do {
                    token = try pool.allocate(.hd720, filledWith: 0)
                } catch {
                    #expect(failing && !full, "seed \(seed)")
                    break
                }
                guard !full else {
                    #expect(token == nil && gateway.createdCount == before, "seed \(seed)")
                    break
                }
                #expect(!failing, "seed \(seed)")
                let issued = try #require(token)
                model.issue(issued, try #require(pool.handle(for: issued)), .hd720)
            case .releaseValid:
                guard !model.live.isEmpty else { break }
                let position = Int.random(in: 0..<model.live.count, using: &generator)
                #expect(pool.release(model.live[position].token), "seed \(seed)")
                model.retire(at: position)
            case .releaseStale:
                guard let stale = model.dead.randomElement(using: &generator) else { break }
                #expect(!pool.release(stale), "seed \(seed)")
            case .releaseFabricated:
                let fake = SurfaceToken(
                    index: Int.random(in: -2...(Self.capacity + 2), using: &generator), generation: UInt64.random(in: 0...3, using: &generator))
                let valid = model.live.contains { $0.token == fake }
                #expect(pool.release(fake) == valid, "seed \(seed)")
                guard let position = model.live.firstIndex(where: { $0.token == fake }) else { break }
                model.retire(at: position)
            case .releaseAll:
                pool.releaseAll()
                model.dead += model.live.map(\.token)
                model.live = []
            }
            check(pool, against: model, seed: seed)
        }
    }
}
