import XCTest
@testable import VoiceNotesCore

final class CandidateRankerTests: XCTestCase {
    private func note(_ key: String, _ title: String, daysAgo: Double) -> NoteRecord {
        NoteRecord(key: key, title: title, content: title, modificationDate: Date(timeIntervalSince1970: 1_000_000 - daysAgo * 86_400))
    }

    func testTitleMentionedInTheCommandRanksFirst() {
        let notes = [
            note("a", "Recetas", daysAgo: 0),
            note("b", "Muebles", daysAgo: 30),
            note("c", "Pendientes", daysAgo: 1),
        ]
        let ranked = CandidateRanker.rank(notes, query: "En la nota de muebles añadir algo")
        XCTAssertEqual(ranked.first?.note.key, "b")
        XCTAssertEqual(ranked.map(\.id), ["n1", "n2", "n3"])
    }

    func testFuzzyAndPluralMatches() {
        let notes = [note("a", "Lista del súper", daysAgo: 10), note("b", "Ideas", daysAgo: 0)]
        XCTAssertEqual(CandidateRanker.rank(notes, query: "en el super añade leche").first?.note.key, "a")
        let furniture = [note("a", "Mueble", daysAgo: 10), note("b", "Ideas", daysAgo: 0)]
        XCTAssertEqual(CandidateRanker.rank(furniture, query: "nota de muebles").first?.note.key, "a")
    }

    func testRecencyBreaksTiesAndLimitApplies() {
        let notes = (0..<10).map { note("k\($0)", "Nota \($0)", daysAgo: Double($0)) }
        let ranked = CandidateRanker.rank(notes, query: "algo sin relación", limit: 3)
        XCTAssertEqual(ranked.map(\.note.key), ["k0", "k1", "k2"])
    }

    func testUntitledNotesAreSkipped() {
        let notes = [note("a", "", daysAgo: 0), note("b", "Ideas", daysAgo: 1)]
        XCTAssertEqual(CandidateRanker.rank(notes, query: "ideas").map(\.note.key), ["b"])
    }
}

final class PlanValidatorTests: XCTestCase {
    private let muebles = NoteRecord(key: "k1", title: "Muebles", content: "Muebles\n- Silla", modificationDate: Date())
    private var candidates: [Candidate] { [Candidate(id: "n1", note: muebles)] }

    func testExistingCandidate() throws {
        let response = ResolveTargetsResponse(status: .ok, language: "es", message: nil, targets: [
            .init(noteID: "n1", newNoteTitle: nil, instruction: "añadir mesa"),
        ])
        let outcome = try PlanValidator.validate(response, candidates: candidates, allNotes: [muebles])
        XCTAssertEqual(outcome, .targets([ResolvedTarget(kind: .existing(muebles), instruction: "añadir mesa")]))
    }

    func testNewTitleIsCleanedAndMatchedAgainstExistingNotes() throws {
        let response = ResolveTargetsResponse(status: .ok, language: "es", message: nil, targets: [
            .init(noteID: nil, newNoteTitle: " muebles ", instruction: "añadir mesa"),
            .init(noteID: nil, newNoteTitle: "viajes", instruction: "añadir pasaporte"),
        ])
        let outcome = try PlanValidator.validate(response, candidates: [], allNotes: [muebles])
        XCTAssertEqual(outcome, .targets([
            ResolvedTarget(kind: .existing(muebles), instruction: "añadir mesa"),
            ResolvedTarget(kind: .new(title: "Viajes"), instruction: "añadir pasaporte"),
        ]))
    }

    func testDuplicateTargetsAreMerged() throws {
        let response = ResolveTargetsResponse(status: .ok, language: "es", message: nil, targets: [
            .init(noteID: "n1", newNoteTitle: nil, instruction: "añadir mesa"),
            .init(noteID: nil, newNoteTitle: "Muebles", instruction: "añadir silla"),
        ])
        let outcome = try PlanValidator.validate(response, candidates: candidates, allNotes: [muebles])
        XCTAssertEqual(outcome, .targets([ResolvedTarget(kind: .existing(muebles), instruction: "añadir mesa\nañadir silla")]))
    }

    func testClarification() throws {
        let response = ResolveTargetsResponse(status: .needsClarification, language: "es", message: "¿En qué nota?", targets: [])
        XCTAssertEqual(try PlanValidator.validate(response, candidates: candidates, allNotes: []), .clarification("¿En qué nota?"))
        let empty = ResolveTargetsResponse(status: .ok, language: "es", message: nil, targets: [])
        XCTAssertEqual(try PlanValidator.validate(empty, candidates: candidates, allNotes: []), .clarification(nil))
    }

    func testUnknownIDFails() {
        let response = ResolveTargetsResponse(status: .ok, language: "es", message: nil, targets: [
            .init(noteID: "n9", newNoteTitle: nil, instruction: "x"),
        ])
        XCTAssertThrowsError(try PlanValidator.validate(response, candidates: candidates, allNotes: []))
    }
}

final class SchemaTests: XCTestCase {
    /// Every object must list all its properties as required and forbid additional properties (strict mode).
    private func assertStrict(_ schema: JSONValue, path: String = "$", file: StaticString = #filePath, line: UInt = #line) {
        switch schema {
        case .object(let object):
            if object["type"] == .string("object") {
                guard case .object(let properties)? = object["properties"] else {
                    return XCTFail("\(path) has no properties", file: file, line: line)
                }
                XCTAssertEqual(object["additionalProperties"], .bool(false), path, file: file, line: line)
                guard case .array(let required)? = object["required"] else {
                    return XCTFail("\(path) has no required list", file: file, line: line)
                }
                XCTAssertEqual(Set(required.compactMap { if case .string(let s) = $0 { return s } else { return nil } }),
                               Set(properties.keys), path, file: file, line: line)
            }
            for (key, value) in object {
                assertStrict(value, path: "\(path).\(key)", file: file, line: line)
            }
        case .array(let values):
            for (index, value) in values.enumerated() {
                assertStrict(value, path: "\(path)[\(index)]", file: file, line: line)
            }
        default:
            break
        }
    }

    func testSchemasAreStrict() {
        assertStrict(PlanSchemas.resolveTargets(candidateIDs: ["n1", "n2"]))
        assertStrict(PlanSchemas.resolveTargets(candidateIDs: []))
        assertStrict(PlanSchemas.planEdits(targetRefs: ["T1"]))
    }

    func testCandidateIDsAreAnEnum() throws {
        let schema = PlanSchemas.resolveTargets(candidateIDs: ["n1", "n2"])
        let noteID = schema["properties"]?["targets"]?["items"]?["properties"]?["note_id"]
        XCTAssertEqual(noteID?["anyOf"], .array([["type": "string", "enum": ["n1", "n2"]], ["type": "null"]]))
    }

    func testModelOutputDecodes() throws {
        let json = """
        {"status":"ok","message":"Listo","edits":[{"target":"T1","op":"set_checked","line":3,\
        "anchor_text":"- [ ] Pan","lines":[],"checked":true}]}
        """
        let decoded = try JSONDecoder().decode(PlanEditsResponse.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.edits.first?.op, .setChecked)
        XCTAssertEqual(decoded.edits.first?.anchorText, "- [ ] Pan")
        let targets = """
        {"status":"needs_clarification","language":"es","message":"¿Qué nota?","targets":[]}
        """
        XCTAssertEqual(try JSONDecoder().decode(ResolveTargetsResponse.self, from: Data(targets.utf8)).status, .needsClarification)
    }
}

final class PromptTests: XCTestCase {
    func testResolveInputIsCompactJSON() throws {
        let note = NoteRecord(key: "k", title: "Muebles", content: "", modificationDate: Date(timeIntervalSince1970: 0))
        let text = Prompts.resolveTargetsInput(
            conversation: [ConversationTurn(role: .user, text: "hola")],
            candidates: [Candidate(id: "n1", note: note)],
            today: Date(timeIntervalSince1970: 0)
        )
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        XCTAssertNotNil(object["today"])
        XCTAssertEqual((object["candidates"] as? [[String: Any]])?.first?["id"] as? String, "n1")
        XCTAssertFalse(text.contains("\"k\""), "note keys must not be sent")
    }

    func testPlanInputUsesSnakeCase() {
        let text = Prompts.planEditsInput(conversation: [], targets: [
            Prompts.PlanTarget(ref: "T1", title: "A", isNew: true, listStyle: "none", instruction: "x", numberedLines: ["1| A"]),
        ])
        XCTAssertTrue(text.contains("\"is_new\":true"))
        XCTAssertTrue(text.contains("\"numbered_lines\":[\"1| A\"]"))
    }

    func testTranscriptionPromptRespectsLimit() {
        let prompt = Prompts.transcriptionPrompt(titles: ["Muebles", "", "Súper", String(repeating: "x", count: 700)], limit: 600)
        XCTAssertEqual(prompt, "Muebles, Súper")
        XCTAssertNil(Prompts.transcriptionPrompt(titles: []))
    }

    func testNumberedLinesKeepShortNotes() {
        XCTAssertEqual(ContextBudget.numberedLines(of: "A\nB", focus: ""), ["1| A", "2| B"])
    }

    func testNumberedLinesWindowLongNotes() {
        var lines = ["Título"]
        lines += (2...500).map { "- elemento \($0)" }
        lines[249] = "- comprar tornillos"
        let numbered = ContextBudget.numberedLines(of: lines.joined(separator: "\n"), focus: "marca tornillos", maxLines: 60)
        XCTAssertEqual(numbered.first, "1| Título")
        XCTAssertTrue(numbered.contains("250| - comprar tornillos"))
        XCTAssertTrue(numbered.contains("500| - elemento 500"))
        XCTAssertLessThanOrEqual(numbered.count, 60)
    }
}
