import Testing
@testable import RpplCore

struct MarkdownBlocksTests {
    @Test func parsesHeadingsParagraphsListsAndBreaks() {
        let source = """
            # Title

            Intro paragraph
            continued on next line.

            ## Section

            - First
            - Second

            ---

            Closing.
            """

        let blocks = MarkdownBlocks.parse(source)
        #expect(blocks == [
            .heading(level: 1, text: "Title"),
            .paragraph("Intro paragraph continued on next line."),
            .heading(level: 2, text: "Section"),
            .listItem("First"),
            .listItem("Second"),
            .thematicBreak,
            .paragraph("Closing."),
        ])
    }

    @Test func keepsInlineMarkupInBlockText() {
        let blocks = MarkdownBlocks.parse("**Bold** and [mail](mailto:a@b.c)")
        #expect(blocks == [
            .paragraph("**Bold** and [mail](mailto:a@b.c)"),
        ])
    }

    @Test func ignoresFalseThematicBreaks() {
        let blocks = MarkdownBlocks.parse("-- Duco\n\n- real item")
        #expect(blocks == [
            .paragraph("-- Duco"),
            .listItem("real item"),
        ])
    }
}
