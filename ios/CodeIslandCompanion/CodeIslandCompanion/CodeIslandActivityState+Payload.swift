import Foundation

extension CompanionStatePayload {
    init?(remoteApprovalSnapshot snapshot: RemoteApprovalSnapshot) {
        guard let sequence = snapshot.companionSequence else { return nil }

        let approvals = snapshot.approvals.map { item in
            CompanionSessionPreview(
                sessionId: item.sessionId,
                source: item.source,
                status: .waitingApproval,
                toolName: item.tool,
                workspaceName: item.workspace,
                message: nil,
                updatedAt: item.createdAt
            )
        }
        let questions = snapshot.questions.map { item in
            CompanionSessionPreview(
                sessionId: item.sessionId,
                source: item.source,
                status: .waitingQuestion,
                toolName: "Question",
                workspaceName: item.workspace,
                message: nil,
                updatedAt: item.createdAt
            )
        }
        let sessions = (questions + approvals).sorted { $0.updatedAt > $1.updatedAt }
        let primary = sessions.first
        let status = primary?.status ?? .idle

        self.init(
            version: snapshot.version,
            sequence: sequence,
            sessionId: primary?.sessionId,
            source: primary?.source ?? "codeisland",
            status: status,
            toolName: primary?.toolName,
            workspaceName: primary?.workspaceName,
            messages: [],
            pendingAction: status == .waitingQuestion ? .question : (status == .waitingApproval ? .approval : nil),
            question: nil,
            sessions: sessions,
            updatedAt: snapshot.generatedAt
        )
    }
}

extension CodeIslandActivityAttributes.ContentState {
    init(payload: CompanionStatePayload) {
        self.init(
            sequence: payload.sequence,
            source: payload.source,
            status: payload.status.rawValue,
            toolName: nil,
            workspaceName: nil,
            message: Self.privateSummary(for: payload.status),
            pendingAction: payload.pendingAction?.rawValue,
            questionText: nil,
            questionHeader: nil,
            questionProgress: payload.question.flatMap { question in
                question.total > 1 ? "\(question.index)/\(question.total)" : nil
            },
            sessions: Self.sessionPreviews(from: payload),
            updatedAt: payload.updatedAt
        )
    }

    private static func sessionPreviews(from payload: CompanionStatePayload) -> [CodeIslandSessionActivityPreview] {
        let previews = payload.sessions
        if !previews.isEmpty {
            return previews.map {
                CodeIslandSessionActivityPreview(
                    sessionId: $0.sessionId,
                    source: $0.source,
                    status: $0.status.rawValue,
                    toolName: nil,
                    workspaceName: nil,
                    message: Self.privateSummary(for: $0.status),
                    updatedAt: $0.updatedAt
                )
            }
        }

        return [
            CodeIslandSessionActivityPreview(
                sessionId: payload.sessionId,
                source: payload.source,
                status: payload.status.rawValue,
                toolName: nil,
                workspaceName: nil,
                message: Self.privateSummary(for: payload.status),
                updatedAt: payload.updatedAt
            )
        ]
    }

    private static func privateSummary(for status: CompanionStatus) -> String {
        switch status {
        case .waitingApproval:
            return "Approval waiting · open Buddy privately"
        case .waitingQuestion:
            return "Answer waiting · open Buddy privately"
        case .processing, .running:
            return "Session active on your Mac"
        case .idle:
            return "No action waiting"
        }
    }
}
