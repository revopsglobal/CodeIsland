import Foundation

enum RemoteTaskAttentionKind: Equatable {
    case approval
    case question
    case needsYou
    case failed
    case followed
    case verified
    case waitingForMac
    case working
}

struct RemoteTaskAttentionCandidate: Equatable, Identifiable {
    let id: String
    let kind: RemoteTaskAttentionKind
    let priority: Int
    let taskID: UUID?

    init(id: String, kind: RemoteTaskAttentionKind, priority: Int, taskID: UUID? = nil) {
        self.id = id
        self.kind = kind
        self.priority = priority
        self.taskID = taskID
    }
}

enum RemoteTaskPresentationModel {
    static func immediateAttentionCount<S: Sequence>(
        in candidates: S
    ) -> Int where S.Element == RemoteTaskAttentionCandidate {
        candidates.reduce(into: 0) { count, candidate in
            switch candidate.kind {
            case .approval, .question, .needsYou, .failed:
                count += 1
            case .followed, .verified, .waitingForMac, .working:
                break
            }
        }
    }

    static func candidates(
        approvalIDs: [String],
        questionIDs: [String],
        tasks: [RemoteTaskSummary],
        drafts: [RemoteTaskDraft],
        followedTaskID: UUID?,
        reviewedVerifiedTaskIDs: Set<UUID>
    ) -> [RemoteTaskAttentionCandidate] {
        var result = approvalIDs.map {
            RemoteTaskAttentionCandidate(id: "approval:\($0)", kind: .approval, priority: 100)
        }
        result.append(contentsOf: questionIDs.map {
            RemoteTaskAttentionCandidate(id: "question:\($0)", kind: .question, priority: 100)
        })

        for task in tasks where task.state != .cancelled {
            let candidate: RemoteTaskAttentionCandidate?
            switch task.state {
            case .needsYou:
                candidate = .init(id: "task:\(task.id.uuidString.lowercased())", kind: .needsYou, priority: 90, taskID: task.id)
            case .failed:
                candidate = .init(id: "task:\(task.id.uuidString.lowercased())", kind: .failed, priority: 80, taskID: task.id)
            case .verified where !reviewedVerifiedTaskIDs.contains(task.id):
                candidate = .init(id: "task:\(task.id.uuidString.lowercased())", kind: .verified, priority: 60, taskID: task.id)
            case .working where task.id == followedTaskID,
                 .queued where task.id == followedTaskID:
                candidate = .init(id: "task:\(task.id.uuidString.lowercased())", kind: .followed, priority: 70, taskID: task.id)
            case .working, .queued:
                candidate = .init(id: "task:\(task.id.uuidString.lowercased())", kind: .working, priority: 40, taskID: task.id)
            case .waitingForMac:
                candidate = .init(id: "task:\(task.id.uuidString.lowercased())", kind: .waitingForMac, priority: 50, taskID: task.id)
            case .verified, .cancelled:
                candidate = nil
            }
            if let candidate { result.append(candidate) }
        }

        let representedClientIDs = Set(tasks.map(\.clientTaskID))
        for draft in drafts where !representedClientIDs.contains(draft.id) {
            result.append(.init(
                id: "draft:\(draft.id.uuidString.lowercased())",
                kind: .waitingForMac,
                priority: 50
            ))
        }

        return result.sorted {
            if $0.priority != $1.priority { return $0.priority > $1.priority }
            return $0.id < $1.id
        }
    }

    static func selection<S: Sequence>(
        previousID: String?,
        preferredID: String? = nil,
        candidates: S
    ) -> String? where S.Element == RemoteTaskAttentionCandidate {
        let values = Array(candidates)
        guard let highestPriority = values.map(\.priority).max() else { return nil }
        let highest = values.filter { $0.priority == highestPriority }
        if let preferredID, highest.contains(where: { $0.id == preferredID }) {
            return preferredID
        }
        if let previousID, highest.contains(where: { $0.id == previousID }) {
            return previousID
        }
        return highest.sorted { $0.id < $1.id }.first?.id
    }
}

enum RemoteTaskReviewPersistence {
    private static let maximumStoredIDs = 200

    static func decode(_ rawValue: String) -> Set<UUID> {
        guard let data = rawValue.data(using: .utf8),
              let values = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return Set(values.compactMap(UUID.init(uuidString:)))
    }

    static func encode(_ ids: Set<UUID>) -> String {
        let values = ids
            .map { $0.uuidString.lowercased() }
            .sorted()
            .suffix(maximumStoredIDs)
        guard let data = try? JSONEncoder().encode(Array(values)) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }
}
