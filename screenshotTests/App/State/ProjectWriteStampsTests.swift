import Foundation
@testable import Screenshot_Bro
import Testing

@MainActor
struct ProjectWriteStampsTests {
    private let earlier = Date(timeIntervalSince1970: 100)
    private let later = Date(timeIntervalSince1970: 200)
    private let project = UUID()

    @Test func knownIsNilBeforeAnyReadOrWrite() {
        #expect(ProjectWriteStamps().known(for: project) == nil)
    }

    @Test func anInFlightWriteNewerThanTheLandedOneIsKnown() {
        let stamps = ProjectWriteStamps()
        stamps.recordLoad(project, modifiedAt: earlier, catalogModified: nil, sequence: ProjectWriteStamps.currentLandedSequence())
        stamps.beginWrite(project, modifiedAt: later)
        #expect(stamps.known(for: project) == later)
    }

    @Test func theInFlightStampClearsOnlyWhenTheLastWriteEnds() {
        let stamps = ProjectWriteStamps()
        stamps.beginWrite(project, modifiedAt: later)
        stamps.beginWrite(project, modifiedAt: earlier)
        stamps.endWrite(project)
        #expect(stamps.known(for: project) == later, "one write is still in flight")
        stamps.endWrite(project)
        #expect(stamps.known(for: project) == nil)
    }

    @Test func aLandedStampNewerThanTheInFlightOneWins() {
        let stamps = ProjectWriteStamps()
        stamps.beginWrite(project, modifiedAt: earlier)
        stamps.recordLoad(project, modifiedAt: later, catalogModified: nil, sequence: ProjectWriteStamps.currentLandedSequence())
        #expect(stamps.known(for: project) == later)
    }

    /// The write a project switch queues for the outgoing project must not make the incoming one
    /// look newer on disk than it is, or a genuine remote change to it would be ignored.
    @Test func anotherProjectsInFlightWriteDoesNotCount() {
        let stamps = ProjectWriteStamps()
        stamps.beginWrite(UUID(), modifiedAt: later)
        #expect(stamps.known(for: project) == nil)
    }

    /// A reload that moves the active project (the open one was deleted elsewhere) must open the
    /// new one rather than compare its file against the old project's save and keep the old rows.
    @Test func anotherProjectsLandedStampDoesNotCount() {
        let stamps = ProjectWriteStamps()
        stamps.recordLoad(UUID(), modifiedAt: later, catalogModified: later, sequence: ProjectWriteStamps.currentLandedSequence())
        #expect(stamps.known(for: project) == nil)
        #expect(stamps.catalogModified(for: project) == nil)
    }

    /// A queued autosave whose completion arrives after a newer synchronous save reached disk must
    /// not roll the stamp back, or the next reload re-applies our own write and wipes undo.
    @Test func aLateCompletionOfAnEarlierWriteKeepsTheNewerStamp() {
        let stamps = ProjectWriteStamps()
        let first = ProjectWriteStamps.nextLandedSequence()
        let second = ProjectWriteStamps.nextLandedSequence()
        stamps.recordWrite(project, modifiedAt: later, catalogModified: later, sequence: second)
        stamps.recordWrite(project, modifiedAt: earlier, catalogModified: earlier, sequence: first)
        #expect(stamps.known(for: project) == later)
        #expect(stamps.catalogModified(for: project) == later)
    }

    /// Bytes that landed last win even when their snapshot is older: the stamp tracks disk, not clocks.
    @Test func aWriteThatLandsLaterWinsEvenWithAnOlderSnapshot() {
        let stamps = ProjectWriteStamps()
        stamps.recordWrite(project, modifiedAt: later, catalogModified: nil, sequence: ProjectWriteStamps.nextLandedSequence())
        stamps.recordWrite(project, modifiedAt: earlier, catalogModified: nil, sequence: ProjectWriteStamps.nextLandedSequence())
        #expect(stamps.known(for: project) == earlier)
    }

    @Test func aLoadSupersedesWritesThatLandedBeforeIt() {
        let stamps = ProjectWriteStamps()
        let beforeLoad = ProjectWriteStamps.nextLandedSequence()
        stamps.recordLoad(project, modifiedAt: later, catalogModified: nil, sequence: ProjectWriteStamps.currentLandedSequence())
        stamps.recordWrite(project, modifiedAt: earlier, catalogModified: nil, sequence: beforeLoad)
        #expect(stamps.known(for: project) == later)
    }
}
