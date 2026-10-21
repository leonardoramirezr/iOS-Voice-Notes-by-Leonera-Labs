import Foundation
import XCTest
@testable import VoiceNotesCore

/// Returns scripted answers and records what the pipeline asked.
final class ScriptedModel: PlanningModel, @unchecked Sendable {
    private let lock = NSLock()
    private var resolveAnswers: [ResolveTargetsResponse]
    private var planAnswers: [PlanEditsResponse]
    private(set) var resolveInputs: [String] = []
    private(set) var planInputs: [String] = []

    init(resolve: [ResolveTargetsResponse], plan: [PlanEditsResponse]) {
        resolveAnswers = resolve
        planAnswers = plan
    }

    func resolveTargets(system: String, input: String, schema: JSONValue) async throws -> ResolveTargetsResponse {
        lock.withLock {
            resolveInputs.append(input)
            return resolveAnswers.removeFirst()
        }
    }

    func planEdits(system: String, input: String, schema: JSONValue) async throws -> PlanEditsResponse {
        lock.withLock {
            planInputs.append(input)
            return planAnswers.removeFirst()
        }
    }
}

final class CommandPipelineTests: XCTestCase {
    private let command = [ConversationTurn(role: .user, text: "En la nota de muebles añadir en mercado Basco de Quiroga compró sus muebles Brandon")]
    private let line = "- En Mercado Basco de Quiroga compró sus muebles Brandon"

    private func note(_ key: String, _ content: String) -> NoteRecord {
        NoteRecord(key: key, title: NoteText.title(of: content), content: content, modificationDate: Date(timeIntervalSince1970: 100))
    }

    private func appendAnswer(_ lines: [String]) -> PlanEditsResponse {
        PlanEditsResponse(status: .ok, message: "Listo", edits: [.init(target: "T1", op: .append, lines: lines)])
    }

    func testCreatesMueblesWhenItDoesNotExist() async throws {
        let model = ScriptedModel(
            resolve: [.init(status: .ok, language: "es", message: nil, targets: [
                .init(noteID: nil, newNoteTitle: "Muebles", instruction: "añadir en mercado Basco de Quiroga compró sus muebles Brandon"),
            ])],
            plan: [appendAnswer([line])]
        )
        let outcome = try await CommandPipeline(model: model).plan(conversation: command, notes: [note("k1", "Recetas\n- Sopa")])
        guard case .review(let changes, let summary, let language) = outcome else {
            return XCTFail("expected review, got \(outcome)")
        }
        XCTAssertEqual(summary, "Listo")
        XCTAssertEqual(language, "es")
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes[0].target, .new(title: "Muebles"))
        XCTAssertEqual(changes[0].result.newContent, "Muebles\n" + line)
        XCTAssertTrue(model.planInputs[0].contains("\"is_new\":true"))
    }

    func testAppendsToTheExistingMueblesNote() async throws {
        let muebles = note("k2", "Muebles\n- Silla de Ikea")
        let model = ScriptedModel(
            resolve: [.init(status: .ok, language: "es", message: nil, targets: [
                .init(noteID: "n1", newNoteTitle: nil, instruction: "añadir ..."),
            ])],
            plan: [appendAnswer([line])]
        )
        let outcome = try await CommandPipeline(model: model).plan(conversation: command, notes: [muebles, note("k1", "Recetas")])
        guard case .review(let changes, _, _) = outcome else {
            return XCTFail("expected review, got \(outcome)")
        }
        XCTAssertEqual(changes[0].target, .existing(key: "k2"))
        XCTAssertEqual(changes[0].result.newContent, "Muebles\n- Silla de Ikea\n" + line)
        XCTAssertTrue(model.resolveInputs[0].contains("\"title\":\"Muebles\""))
        XCTAssertTrue(model.planInputs[0].contains("\"2| - Silla de Ikea\""))
    }

    func testClarificationWhenTheNoteIsMissing() async throws {
        let model = ScriptedModel(
            resolve: [.init(status: .needsClarification, language: "es", message: "¿En qué nota lo agrego?", targets: [])],
            plan: []
        )
        let outcome = try await CommandPipeline(model: model).plan(conversation: [ConversationTurn(role: .user, text: "añade leche")], notes: [])
        XCTAssertEqual(outcome, .clarification(message: "¿En qué nota lo agrego?", language: "es"))
    }

    func testClarificationFromThePlanStep() async throws {
        let model = ScriptedModel(
            resolve: [.init(status: .ok, language: "es", message: nil, targets: [.init(noteID: "n1", newNoteTitle: nil, instruction: "marcar huevos")])],
            plan: [.init(status: .needsClarification, message: "No encontré huevos.", edits: [])]
        )
        let outcome = try await CommandPipeline(model: model).plan(
            conversation: [ConversationTurn(role: .user, text: "en súper marca huevos")], notes: [note("k1", "Súper\n- [ ] Leche")]
        )
        XCTAssertEqual(outcome, .clarification(message: "No encontré huevos.", language: "es"))
    }

    func testInvalidEditsAreRepairedOnce() async throws {
        let super_ = note("k1", "Súper\n- [ ] Leche\n- [ ] Pan")
        let model = ScriptedModel(
            resolve: [.init(status: .ok, language: "es", message: nil, targets: [.init(noteID: "n1", newNoteTitle: nil, instruction: "marcar pan")])],
            plan: [
                .init(status: .ok, message: nil, edits: [.init(target: "T1", op: .setChecked, line: 9, anchorText: "- [ ] Huevos", checked: true)]),
                .init(status: .ok, message: "Marqué Pan.", edits: [.init(target: "T1", op: .setChecked, line: 3, anchorText: "- [ ] Pan", checked: true)]),
            ]
        )
        let outcome = try await CommandPipeline(model: model).plan(
            conversation: [ConversationTurn(role: .user, text: "marca pan en súper")], notes: [super_]
        )
        guard case .review(let changes, _, _) = outcome else {
            return XCTFail("expected review, got \(outcome)")
        }
        XCTAssertEqual(changes[0].result.newContent, "Súper\n- [ ] Leche\n- [x] Pan")
        XCTAssertEqual(model.planInputs.count, 2)
        XCTAssertTrue(model.planInputs[1].contains("could not be applied"))
    }

    func testPlansInsideTheOpenNoteWithoutPickingNotes() async throws {
        let super_ = note("k1", "Súper\n- [ ] Leche")
        let model = ScriptedModel(resolve: [], plan: [appendAnswer(["- [ ] Pan"])])
        let outcome = try await CommandPipeline(model: model).plan(
            conversation: [ConversationTurn(role: .user, text: "añade pan")], in: super_
        )
        guard case .review(let changes, _, _) = outcome else {
            return XCTFail("expected review, got \(outcome)")
        }
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes[0].target, .existing(key: "k1"))
        XCTAssertEqual(changes[0].result.newContent, "Súper\n- [ ] Leche\n- [ ] Pan")
        XCTAssertTrue(model.resolveInputs.isEmpty)
        XCTAssertTrue(model.planInputs[0].contains("\"instruction\":\"añade pan\""))
    }

    func testReapplyAfterRemoteEdit() throws {
        let change = ProposedChange(
            id: "T1", target: .existing(key: "k1"), title: "Súper", originalContent: "Súper\n- [ ] Pan",
            edits: [.init(target: "T1", op: .setChecked, line: 2, anchorText: "- [ ] Pan", checked: true)],
            result: try EditApplier.apply(
                [.init(target: "T1", op: .setChecked, line: 2, anchorText: "- [ ] Pan", checked: true)], to: "Súper\n- [ ] Pan"
            )
        )
        XCTAssertEqual(try change.reapplied(toCurrentContent: "Súper\n- [ ] Pan").newContent, "Súper\n- [x] Pan")
        XCTAssertEqual(try change.reapplied(toCurrentContent: "Súper\n- [ ] Café\n- [ ] Pan").newContent, "Súper\n- [ ] Café\n- [x] Pan")
    }
}
