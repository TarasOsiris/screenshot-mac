import Foundation
@testable import Screenshot_Bro
import Testing

@MainActor
struct ProjectWriteStampsTests {
    private let earlier = Date(timeIntervalSince1970: 100)
    private let later = Date(timeIntervalSince1970: 200)

    @Test func knownIsNilBeforeAnyReadOrWrite() {
        #expect(ProjectWriteStamps().known == nil)
    }

    @Test func anInFlightWriteNewerThanTheLandedOneIsKnown() {
        let stamps = ProjectWriteStamps()
        stamps.landed = earlier
        stamps.beginWrite(modifiedAt: later)
        #expect(stamps.known == later)
    }

    @Test func theInFlightStampClearsOnlyWhenTheLastWriteEnds() {
        let stamps = ProjectWriteStamps()
        stamps.beginWrite(modifiedAt: later)
        stamps.beginWrite(modifiedAt: earlier)
        stamps.endWrite()
        #expect(stamps.known == later, "one write is still in flight")
        stamps.endWrite()
        #expect(stamps.known == nil)
    }

    @Test func aLandedStampNewerThanTheInFlightOneWins() {
        let stamps = ProjectWriteStamps()
        stamps.beginWrite(modifiedAt: earlier)
        stamps.landed = later
        #expect(stamps.known == later)
    }
}
