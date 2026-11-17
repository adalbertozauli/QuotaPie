import Testing
@testable import QuotaPie

struct UsageRingWindowsTests {
    private func window(_ id: String, _ minutes: Int?) -> UsageWindow {
        UsageWindow(id: id, name: id, usedPercent: 37.5, resetAt: nil, durationMinutes: minutes)
    }

    @Test func mainAndModelWindowsRemainSeparate() {
        let selection = UsageRingWindows(windows: [
            window("seven_day_fable", 10080), window("five_hour", 300), window("seven_day", 10080)
        ])
        #expect(selection.session?.id == "five_hour")
        #expect(selection.weekly?.id == "seven_day")
        #expect(selection.additional.map(\.id) == ["seven_day_fable"])
    }

    @Test func modelOnlyIsNotGlobalWeekly() {
        let selection = UsageRingWindows(windows: [window("seven_day_fable", 10080)])
        #expect(selection.weekly == nil)
        #expect(selection.additional.count == 1)
    }

    @Test func differentBucketsAreNotPaired() {
        let selection = UsageRingWindows(windows: [window("a.primary", 300), window("b.secondary", 10080)])
        #expect(selection.session?.id == "a.primary")
        #expect(selection.weekly == nil)
        #expect(selection.additional.map(\.id) == ["b.secondary"])
    }

    @Test func unknownAndAmbiguousWindowsRemainVisibleAsAdditional() {
        let selection = UsageRingWindows(windows: [
            window("unknown", nil), window("a", 300), window("b", 300)
        ])
        #expect(selection.session == nil)
        #expect(selection.weekly == nil)
        #expect(selection.additional.count == 3)
    }
}
