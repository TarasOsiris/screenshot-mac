import Testing
@testable import Screenshot_Bro

@Suite struct ThumbnailConcurrencyGateTests {

    @Test func capsConcurrentPermits() async {
        let gate = ThumbnailConcurrencyGate(limit: 2)

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<12 {
                group.addTask {
                    await gate.acquire()
                    try? await Task.sleep(for: .milliseconds(20))
                    await gate.release()
                }
            }
        }

        let peak = await gate.peakActive
        #expect(peak >= 1)
        #expect(peak <= 2)
    }

    @Test func allWaitersComplete() async {
        let gate = ThumbnailConcurrencyGate(limit: 1)
        let counter = Counter()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<8 {
                group.addTask {
                    await gate.acquire()
                    await counter.increment()
                    await gate.release()
                }
            }
        }

        #expect(await counter.value == 8)
    }

    private actor Counter {
        private(set) var value = 0
        func increment() { value += 1 }
    }
}
