import XCTest
@testable import VoiceNotesCore

final class NoteDocumentTests: XCTestCase {
    func testRoundTripsLinesAndTrailingNewline() {
        for text in ["", "a", "a\n", "a\nb", "a\nb\n", "\n", "a\n\n", "a\r\nb\r\n"] {
            XCTAssertEqual(NoteDocument(text: text).text, text, "round trip of \(text.debugDescription)")
        }
    }

    func testSplitsCRLF() {
        let document = NoteDocument(text: "Title\r\n- one\r\n")
        XCTAssertEqual(document.lines, ["Title", "- one"])
        XCTAssertEqual(document.lineEnding, "\r\n")
        XCTAssertTrue(document.hasTrailingNewline)
    }

    func testTitleAndLastContentIndexes() {
        let document = NoteDocument(text: "\n  \nTitle\nbody\n\n")
        XCTAssertEqual(document.titleIndex, 2)
        XCTAssertEqual(document.lastContentIndex, 3)
    }
}

final class NoteTextTests: XCTestCase {
    func testTitleSkipsBlankLinesAndHeadingMarkers() {
        XCTAssertEqual(NoteText.title(of: "\n\n  # Muebles  \n- item"), "Muebles")
        XCTAssertEqual(NoteText.title(of: "#hashtag"), "#hashtag")
        XCTAssertEqual(NoteText.title(of: ""), "")
    }

    func testPreviewJoinsBodyLines() {
        XCTAssertEqual(NoteText.preview(of: "Súper\n- Leche\n\n- Pan  \n"), "- Leche - Pan")
        XCTAssertEqual(NoteText.preview(of: "Only title"), "")
    }

    func testNormalizeIgnoresCaseDiacriticsAndPunctuation() {
        XCTAssertEqual(NoteText.normalize("  ¡Súper   Mercado! "), "super mercado")
        XCTAssertEqual(NoteText.normalize("MUEBLES"), NoteText.normalize("muebles"))
    }

    func testWords() {
        XCTAssertEqual(NoteText.words("La nota de muebles, ¿sí?"), ["la", "nota", "de", "muebles", "si"])
    }

    func testCleanTitle() {
        XCTAssertEqual(NoteText.cleanTitle("  muebles "), "Muebles")
        XCTAssertEqual(NoteText.cleanTitle(""), "")
    }
}

final class ChecklistTests: XCTestCase {
    func testParse() {
        XCTAssertEqual(Checklist.parse("- [ ] Leche"), .checklist(indent: "", checked: false, text: "Leche"))
        XCTAssertEqual(Checklist.parse("  - [x] Pan"), .checklist(indent: "  ", checked: true, text: "Pan"))
        XCTAssertEqual(Checklist.parse("- [X]Huevos"), .checklist(indent: "", checked: true, text: "Huevos"))
        XCTAssertEqual(Checklist.parse("- [] vacío"), .checklist(indent: "", checked: false, text: "vacío"))
        XCTAssertEqual(Checklist.parse("* Café"), .bullet(indent: "", marker: "*", text: "Café"))
        XCTAssertEqual(Checklist.parse("• Té"), .bullet(indent: "", marker: "•", text: "Té"))
        XCTAssertEqual(Checklist.parse("- [link](x)"), .bullet(indent: "", marker: "-", text: "[link](x)"))
        XCTAssertEqual(Checklist.parse("-no space"), .plain(indent: "", text: "-no space"))
        XCTAssertEqual(Checklist.parse("Plain"), .plain(indent: "", text: "Plain"))
    }

    func testSetChecked() {
        XCTAssertEqual(Checklist.setChecked(true, line: "- [ ] Leche"), "- [x] Leche")
        XCTAssertEqual(Checklist.setChecked(false, line: "  - [x] Pan"), "  - [ ] Pan")
        XCTAssertEqual(Checklist.setChecked(true, line: "- Pan"), "- [x] Pan")
        XCTAssertEqual(Checklist.setChecked(true, line: "* Café"), "- [x] Café")
        XCTAssertEqual(Checklist.setChecked(true, line: "Pagar luz"), "- [x] Pagar luz")
        XCTAssertEqual(Checklist.setChecked(false, line: "Pagar luz"), "Pagar luz")
        XCTAssertEqual(Checklist.setChecked(false, line: "- Pan"), "- Pan")
    }

    func testItemText() {
        XCTAssertEqual(Checklist.itemText("  - [x] Pan"), "Pan")
        XCTAssertEqual(Checklist.itemText("* Café"), "Café")
        XCTAssertEqual(Checklist.itemText("Hola"), "Hola")
    }

    func testStyle() {
        XCTAssertEqual(Checklist.style(of: ["Title", "- a", "- [ ] b"]), .checklist)
        XCTAssertEqual(Checklist.style(of: ["Title", "* a", "* b", "- c"]), .bullet("*"))
        XCTAssertEqual(Checklist.style(of: ["Title", "text"]), .none)
        XCTAssertEqual(Checklist.Style.none.itemPrefix, "- ")
        XCTAssertEqual(Checklist.Style.checklist.itemPrefix, "- [ ] ")
    }
}

final class SystemTagsTests: XCTestCase {
    func testDecodeAndEncode() {
        XCTAssertEqual(SystemTags.decode("[\"pinned\",\"markdown\"]"), ["pinned", "markdown"])
        XCTAssertEqual(SystemTags.decode("[\n  \"pinned\"\n]"), ["pinned"])
        XCTAssertEqual(SystemTags.decode(nil), [])
        XCTAssertEqual(SystemTags.decode("garbage"), [])
        XCTAssertEqual(SystemTags.encode(["pinned", "a/b"]), "[\"pinned\",\"a/b\"]")
    }

    func testSettingKeepsOtherTags() {
        XCTAssertEqual(SystemTags.setting("pinned", true, in: "[\"markdown\"]"), "[\"markdown\",\"pinned\"]")
        XCTAssertEqual(SystemTags.setting("pinned", false, in: "[\"pinned\",\"markdown\"]"), "[\"markdown\"]")
        XCTAssertEqual(SystemTags.setting("pinned", true, in: "[\"pinned\"]"), "[\"pinned\"]")
        XCTAssertTrue(SystemTags.contains("pinned", in: "[\"pinned\"]"))
        XCTAssertFalse(SystemTags.contains("pinned", in: nil))
    }
}
