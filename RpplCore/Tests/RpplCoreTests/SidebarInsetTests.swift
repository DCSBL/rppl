import Testing
@testable import RpplCore

struct SidebarInsetTests {
    @Test func noInsetsMeansNoSidebar() {
        #expect(SidebarInset.width(leading: 0, trailing: 0) == 0)
    }

    @Test func symmetricLandscapeInsetsAreNoSidebar() {
        #expect(SidebarInset.width(leading: 62, trailing: 62) == 0)
    }

    @Test func lopsidedTrailingInsetIsTheSidebar() {
        #expect(SidebarInset.width(leading: 0, trailing: 64) == 64)
        #expect(SidebarInset.width(leading: 20, trailing: 64) == 64)
    }

    @Test func smallDifferenceIsNoSidebar() {
        #expect(SidebarInset.width(leading: 0, trailing: 29) == 0)
        #expect(SidebarInset.width(leading: 0, trailing: 30) == 30)
    }
}
