import XCTest
@testable import VoiceNotesCore

final class EditApplierTests: XCTestCase {
    private typealias Edit = PlanEditsResponse.Edit

    func testMueblesNewNote() throws {
        let result = try EditApplier.applyToNewNote(title: "Muebles", edits: [
            Edit(target: "T1", op: .append, lines: ["- En Mercado Basco de Quiroga compró sus muebles Brandon"]),
        ])
        XCTAssertEqual(result.newContent, "Muebles\n- En Mercado Basco de Quiroga compró sus muebles Brandon")
        XCTAssertEqual(result.diff.map(\.kind), [.added, .added])
        XCTAssertEqual(result.firstChangeIndex, 0)
    }

    func testNewNoteWithoutEditsIsJustTheTitle() throws {
        let result = try EditApplier.applyToNewNote(title: "Viajes", edits: [])
        XCTAssertEqual(result.newContent, "Viajes")
        XCTAssertEqual(result.diff.map(\.text), ["Viajes"])
    }

    func testMueblesExistingNoteAppendsAtTheEnd() throws {
        let content = "Muebles\n- Silla de Ikea\n\n"
        let result = try EditApplier.apply([
            Edit(target: "T1", op: .append, lines: ["- En Mercado Basco de Quiroga compró sus muebles Brandon"]),
        ], to: content)
        XCTAssertEqual(
            result.newContent,
            "Muebles\n- Silla de Ikea\n- En Mercado Basco de Quiroga compró sus muebles Brandon\n\n"
        )
        XCTAssertEqual(result.diff.map(\.kind), [.context, .context, .added, .context])
        XCTAssertEqual(result.firstChangeIndex, 2)
    }

    func testMarkDoneChecksTheMatchingLine() throws {
        let content = "Súper\n- [ ] Leche\n- [ ] Pan\n"
        let result = try EditApplier.apply([
            Edit(target: "T1", op: .setChecked, line: 3, anchorText: "- [ ] Pan", checked: true),
        ], to: content)
        XCTAssertEqual(result.newContent, "Súper\n- [ ] Leche\n- [x] Pan\n")
        XCTAssertEqual(result.diff.map(\.kind), [.context, .context, .removed, .added])
        XCTAssertEqual(result.diff[3].segments?.filter(\.isChanged).map(\.text), ["x"])
    }

    func testMarkDoneOnPlainBulletBecomesChecklist() throws {
        let result = try EditApplier.apply([
            Edit(target: "T1", op: .setChecked, line: 2, anchorText: "- Pagar luz", checked: true),
        ], to: "Pendientes\n- Pagar luz")
        XCTAssertEqual(result.newContent, "Pendientes\n- [x] Pagar luz")
    }

    func testUncheck() throws {
        let result = try EditApplier.apply([
            Edit(target: "T1", op: .setChecked, line: 2, anchorText: "- [x] Pan", checked: false),
        ], to: "Súper\n- [x] Pan")
        XCTAssertEqual(result.newContent, "Súper\n- [ ] Pan")
    }

    func testAnchorFindsTheLineWhenTheNumberIsWrong() throws {
        let result = try EditApplier.apply([
            Edit(target: "T1", op: .setChecked, line: 2, anchorText: "- [ ] Pan", checked: true),
        ], to: "Súper\n- [ ] Leche\n- [ ] Pan")
        XCTAssertEqual(result.newContent, "Súper\n- [ ] Leche\n- [x] Pan")
    }

    func testAnchorIgnoresCheckboxStateAndCase() throws {
        let result = try EditApplier.apply([
            Edit(target: "T1", op: .delete, line: 9, anchorText: "pan"),
        ], to: "Súper\n- [x] Pan\n- [ ] Leche")
        XCTAssertEqual(result.newContent, "Súper\n- [ ] Leche")
    }

    func testMissingAnchorFails() {
        XCTAssertThrowsError(try EditApplier.apply([
            Edit(target: "T1", op: .setChecked, line: 2, anchorText: "- [ ] Huevos", checked: true),
        ], to: "Súper\n- [ ] Leche")) { error in
            XCTAssertEqual(error as? EditApplyError, .anchorNotFound(line: 2, anchor: "- [ ] Huevos"))
        }
    }

    func testLineOutOfRangeWithoutAnchorFails() {
        XCTAssertThrowsError(try EditApplier.apply([
            Edit(target: "T1", op: .delete, line: 5),
        ], to: "Title\nOne")) { error in
            XCTAssertEqual(error as? EditApplyError, .lineOutOfRange(line: 5, lineCount: 2))
        }
    }

    func testConflictingEditsFail() {
        XCTAssertThrowsError(try EditApplier.apply([
            Edit(target: "T1", op: .delete, line: 2, anchorText: "- Pan"),
            Edit(target: "T1", op: .replace, line: 2, anchorText: "- Pan", lines: ["- Pan integral"]),
        ], to: "Súper\n- Pan")) { error in
            XCTAssertEqual(error as? EditApplyError, .conflictingEdits(line: 2))
        }
    }

    func testTitleCannotBeCheckedOrDeleted() {
        XCTAssertThrowsError(try EditApplier.apply([
            Edit(target: "T1", op: .setChecked, line: 1, anchorText: "Súper", checked: true),
        ], to: "Súper\n- Pan")) { error in
            XCTAssertEqual(error as? EditApplyError, .titleLineChange(.setChecked))
        }
        XCTAssertThrowsError(try EditApplier.apply([
            Edit(target: "T1", op: .delete, line: 1, anchorText: "Súper"),
        ], to: "Súper\n- Pan"))
    }

    func testTitleCanBeRenamed() throws {
        let result = try EditApplier.apply([
            Edit(target: "T1", op: .replace, line: 1, anchorText: "Súper", lines: ["Supermercado"]),
        ], to: "Súper\n- Pan")
        XCTAssertEqual(result.newContent, "Supermercado\n- Pan")
    }

    func testInsertAfterAndReplace() throws {
        let content = "Viaje\n- Pasaporte\n- Boletos"
        let result = try EditApplier.apply([
            Edit(target: "T1", op: .insertAfter, line: 1, anchorText: "Viaje", lines: ["- Maleta"]),
            Edit(target: "T1", op: .replace, line: 3, anchorText: "- Boletos", lines: ["- Boletos de avión"]),
        ], to: content)
        XCTAssertEqual(result.newContent, "Viaje\n- Maleta\n- Pasaporte\n- Boletos de avión")
        XCTAssertEqual(result.diff.map(\.kind), [.context, .added, .context, .removed, .added])
    }

    func testMultilineStringsAreSplitAndBlankLinesDropped() throws {
        let result = try EditApplier.apply([
            Edit(target: "T1", op: .append, lines: ["- Uno\n- Dos  ", "   ", ""]),
        ], to: "Lista")
        XCTAssertEqual(result.newContent, "Lista\n- Uno\n- Dos")
    }

    func testCRLFIsPreserved() throws {
        let result = try EditApplier.apply([
            Edit(target: "T1", op: .append, lines: ["- Dos"]),
        ], to: "Lista\r\n- Uno\r\n")
        XCTAssertEqual(result.newContent, "Lista\r\n- Uno\r\n- Dos\r\n")
    }

    func testNoChangesFails() {
        XCTAssertThrowsError(try EditApplier.apply([
            Edit(target: "T1", op: .setChecked, line: 2, anchorText: "- [x] Pan", checked: true),
        ], to: "Súper\n- [x] Pan")) { error in
            XCTAssertEqual(error as? EditApplyError, .noChanges)
        }
    }

    func testReapplyAfterTheNoteChanged() throws {
        let edits = [Edit(target: "T1", op: .setChecked, line: 2, anchorText: "- [ ] Pan", checked: true)]
        // Someone added a line at the top on another device after planning.
        let result = try EditApplier.apply(edits, to: "Súper\n- [ ] Café\n- [ ] Pan")
        XCTAssertEqual(result.newContent, "Súper\n- [ ] Café\n- [x] Pan")
    }

    func testAppendToEmptyNote() throws {
        let result = try EditApplier.apply([Edit(target: "T1", op: .append, lines: ["Hola"])], to: "")
        XCTAssertEqual(result.newContent, "Hola")
    }
}

final class DiffTests: XCTestCase {
    func testWordDiffMarksOnlyChangedWords() {
        let (old, new) = WordDiff.compare(old: "- Boletos de tren", new: "- Boletos de avión")
        XCTAssertEqual(old.filter(\.isChanged).map(\.text), ["tren"])
        XCTAssertEqual(new.filter(\.isChanged).map(\.text), ["avión"])
        XCTAssertEqual(old.map(\.text).joined(), "- Boletos de tren")
        XCTAssertEqual(new.map(\.text).joined(), "- Boletos de avión")
    }

    func testDissimilarLinesAreNotPaired() {
        XCTAssertFalse(WordDiff.areSimilar("- Leche", "- Gasolina para el coche"))
        XCTAssertTrue(WordDiff.areSimilar("- [ ] Pan", "- [x] Pan"))
    }

    func testLineDiff() {
        let diff = LineDiff.compute(old: "A\nB\nC", new: "A\nC\nD")
        XCTAssertEqual(diff.map(\.kind), [.context, .removed, .context, .added])
        XCTAssertEqual(diff.map(\.text), ["A", "B", "C", "D"])
        XCTAssertEqual(diff.map(\.id), [0, 1, 2, 3])
    }
}
