import Foundation
import Testing
@testable import QuotaPie

struct ClaudeBridgeTests {
    @Test func stripsAllUnrelatedFields() throws {
        let input = Data(#"{"token":"secret","prompt":"private","rate_limits":{"five_hour":{"used_percentage":37.5,"resets_at":1930947200,"token":"secret"},"seven_day":{"used_percentage":false},"spend_limit":{"used_percentage":44}}}"#.utf8)
        let output = try ClaudeBridge.sanitizedData(input)
        let text = String(decoding: output, as: UTF8.self)
        #expect(!text.contains("secret"))
        #expect(!text.contains("private"))
        #expect(!text.contains("spend_limit"))
        #expect(!text.contains("false"))
        let snapshot = try ClaudeLocalSource.parse(output)
        #expect(snapshot.windows.first?.availablePercent == 62.5)
        #expect(snapshot.windows.last?.availablePercent == nil)
    }
    @Test func missingLimitsNeverBecomeZero() throws {
        let output = try ClaudeBridge.sanitizedData(Data("{}".utf8))
        let snapshot = try ClaudeLocalSource.parse(output)
        #expect(snapshot.windows.isEmpty)
        #expect(snapshot.state == .unavailable)
        #expect(snapshot.message?.contains("Ponte conectada") == true)
    }
}
