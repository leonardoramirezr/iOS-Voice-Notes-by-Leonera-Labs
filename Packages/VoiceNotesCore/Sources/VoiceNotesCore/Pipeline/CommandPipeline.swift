import Foundation

/// Produces the two planning answers; implemented with Groq in the app and with fakes in tests.
public protocol PlanningModel: Sendable {
    func resolveTargets(system: String, input: String, schema: JSONValue) async throws -> ResolveTargetsResponse
    func planEdits(system: String, input: String, schema: JSONValue) async throws -> PlanEditsResponse
}

/// `PlanningModel` backed by a Groq chat model with structured outputs.
public struct GroqPlanningModel: PlanningModel {
    private let client: GroqClient
    private let model: String

    public init(client: GroqClient, model: String) {
        self.client = client
        self.model = model
    }

    public func resolveTargets(system: String, input: String, schema: JSONValue) async throws -> ResolveTargetsResponse {
        try await client.completeJSON(
            ResolveTargetsResponse.self, model: model, system: system, user: input,
            schemaName: PlanSchemas.resolveTargetsName, schema: schema
        )
    }

    public func planEdits(system: String, input: String, schema: JSONValue) async throws -> PlanEditsResponse {
        try await client.completeJSON(
            PlanEditsResponse.self, model: model, system: system, user: input,
            schemaName: PlanSchemas.planEditsName, schema: schema
        )
    }
}

/// A change proposed for one note, ready for the review screen.
public struct ProposedChange: Equatable, Sendable, Identifiable {
    public enum Target: Equatable, Sendable {
        case existing(key: String)
        case new(title: String)
    }

    public let id: String
    public let target: Target
    public let title: String
    /// The content the edits were planned against (empty for a new note).
    public let originalContent: String
    public let edits: [PlanEditsResponse.Edit]
    public let result: AppliedEdit

    public var isNew: Bool {
        if case .new = target {
            return true
        }
        return false
    }

    /// The change applied to the note as it is now: unchanged notes keep the reviewed result, notes edited
    /// elsewhere in the meantime get the same edits again, located by their anchor text.
    public func reapplied(toCurrentContent content: String) throws -> AppliedEdit {
        guard !isNew, content != originalContent else {
            return result
        }
        return try EditApplier.apply(edits, to: content)
    }
}

public enum PipelineOutcome: Equatable, Sendable {
    case review(changes: [ProposedChange], summary: String?, language: String?)
    /// The note or the change is missing; `message` explains it in the user's language when available.
    case clarification(message: String?, language: String?)
}

/// Turns the dictated conversation into reviewed note changes: pick target notes, plan edit steps, apply them.
public struct CommandPipeline: Sendable {
    private let model: PlanningModel
    private let candidateLimit: Int

    public init(model: PlanningModel, candidateLimit: Int = 50) {
        self.model = model
        self.candidateLimit = candidateLimit
    }

    public func plan(conversation: [ConversationTurn], notes: [NoteRecord], today: Date = Date()) async throws -> PipelineOutcome {
        let query = conversation.filter { $0.role == .user }.map(\.text).joined(separator: "\n")
        let candidates = CandidateRanker.rank(notes, query: query, limit: candidateLimit)
        let schemaA = PlanSchemas.resolveTargets(candidateIDs: candidates.map(\.id))
        let inputA = Prompts.resolveTargetsInput(conversation: conversation, candidates: candidates, today: today)

        var responseA = try await model.resolveTargets(system: Prompts.resolveTargetsSystem, input: inputA, schema: schemaA)
        var outcome: ResolveOutcome
        do {
            outcome = try PlanValidator.validate(responseA, candidates: candidates, allNotes: notes)
        } catch let error as PlanValidationError {
            responseA = try await model.resolveTargets(
                system: Prompts.resolveTargetsSystem, input: inputA + Prompts.repairNote(error.description), schema: schemaA
            )
            guard let retried = try? PlanValidator.validate(responseA, candidates: candidates, allNotes: notes) else {
                return .clarification(message: nil, language: responseA.language)
            }
            outcome = retried
        }
        let language = responseA.language

        guard case .targets(let targets) = outcome else {
            if case .clarification(let message) = outcome {
                return .clarification(message: message, language: language)
            }
            return .clarification(message: nil, language: language)
        }

        return try await planEdits(conversation: conversation, targets: targets, language: language)
    }

    /// Plans the conversation as changes to `note` only: the command is given inside that note, so the step
    /// that picks the notes is skipped and nothing else can be changed.
    public func plan(conversation: [ConversationTurn], in note: NoteRecord) async throws -> PipelineOutcome {
        let instruction = conversation.filter { $0.role == .user }.map(\.text).joined(separator: "\n")
        let target = ResolvedTarget(kind: .existing(note), instruction: instruction)
        return try await planEdits(conversation: conversation, targets: [target], language: nil)
    }

    /// Step B: plans the edit steps for the resolved notes and applies them, repairing invalid edits once.
    private func planEdits(
        conversation: [ConversationTurn],
        targets: [ResolvedTarget],
        language: String?
    ) async throws -> PipelineOutcome {
        let refs = targets.indices.map { "T\($0 + 1)" }
        let planTargets = zip(refs, targets).map { ref, target -> Prompts.PlanTarget in
            let content = Self.content(of: target)
            return Prompts.PlanTarget(
                ref: ref,
                title: target.title,
                isNew: target.isNew,
                listStyle: Checklist.style(of: NoteDocument(text: content).lines).identifier,
                instruction: target.instruction,
                numberedLines: ContextBudget.numberedLines(of: content, focus: target.instruction)
            )
        }
        let schemaB = PlanSchemas.planEdits(targetRefs: refs)
        let inputB = Prompts.planEditsInput(conversation: conversation, targets: planTargets)

        var responseB = try await model.planEdits(system: Prompts.planEditsSystem, input: inputB, schema: schemaB)
        for attempt in 0..<2 {
            if responseB.status == .needsClarification {
                return .clarification(message: responseB.message, language: language)
            }
            do {
                let changes = try Self.apply(responseB, refs: refs, targets: targets)
                return .review(changes: changes, summary: responseB.message, language: language)
            } catch let error as EditApplyError {
                guard attempt == 0 else {
                    break
                }
                responseB = try await model.planEdits(
                    system: Prompts.planEditsSystem, input: inputB + Prompts.repairNote(error.description), schema: schemaB
                )
            }
        }
        return .clarification(message: nil, language: language)
    }

    static func content(of target: ResolvedTarget) -> String {
        switch target.kind {
        case .existing(let note):
            return note.content
        case .new(let title):
            return title
        }
    }

    static func apply(_ response: PlanEditsResponse, refs: [String], targets: [ResolvedTarget]) throws -> [ProposedChange] {
        var changes: [ProposedChange] = []
        for (ref, target) in zip(refs, targets) {
            let edits = response.edits.filter { $0.target == ref }
            switch target.kind {
            case .new(let title):
                let result = try EditApplier.applyToNewNote(title: title, edits: edits)
                changes.append(ProposedChange(
                    id: ref, target: .new(title: title), title: title, originalContent: "", edits: edits, result: result
                ))
            case .existing(let note):
                guard !edits.isEmpty else {
                    continue
                }
                let result = try EditApplier.apply(edits, to: note.content)
                changes.append(ProposedChange(
                    id: ref, target: .existing(key: note.key), title: note.title,
                    originalContent: note.content, edits: edits, result: result
                ))
            }
        }
        guard !changes.isEmpty else {
            throw EditApplyError.noChanges
        }
        return changes
    }
}
