import Foundation
@testable import Screenshot_Bro
import Testing

struct CoordinatedReadErrorTests {

    @Test func fileProviderNoSuchItemIsAReplacedItem() {
        let error = NSError(domain: "NSFileProviderErrorDomain", code: -1005)
        #expect(ICloudSyncService.isReplacedItem(error))
    }

    @Test func otherFailuresStillReport() {
        #expect(!ICloudSyncService.isReplacedItem(NSError(domain: "NSFileProviderErrorDomain", code: -1000)))
        #expect(!ICloudSyncService.isReplacedItem(NSError(domain: NSCocoaErrorDomain, code: -1005)))
        #expect(!ICloudSyncService.isReplacedItem(CocoaError(.fileReadCorruptFile)))
    }
}
