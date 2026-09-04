/// A purely fictional desk. Its entire state is a form and a story beat: it has
/// no store, wallet, gameplay RNG, clock, network, or persistence dependency.
struct ShopPaperwork: Equatable, Sendable {
    enum Form: Int, CaseIterable, Sendable {
        case roundness, lessPaperwork, missingSupervisor

        var title: String {
            switch self {
            case .roundness: "Form 8-B: Ball Exists"
            case .lessPaperwork: "Form 0: Less Paperwork"
            case .missingSupervisor: "Form 404: Missing Supervisor"
            }
        }

        var stamp: String {
            switch self {
            case .roundness: "OFFICIALLY ROUND"
            case .lessPaperwork: "DUPLICATE ORIGINAL"
            case .missingSupervisor: "CHAIR IN CHARGE"
            }
        }
    }

    enum Stage: Int, CaseIterable, Sendable {
        case intake, review, escalation, filed

        var action: String {
            switch self {
            case .intake: "Request review"
            case .review: "Escalate"
            case .escalation: "Stamp it anyway"
            case .filed: "File another form"
            }
        }
    }

    private(set) var form: Form
    private(set) var stage: Stage

    init(form: Form = .roundness, stage: Stage = .intake) {
        self.form = form
        self.stage = stage
    }

    var line: String {
        switch (form, stage) {
        case (.roundness, .intake):
            "Psyduck has classified a Poké Ball as round. Unfortunately, ‘round’ is not a valid checkbox."
        case (.roundness, .review):
            "The second opinion is square. We have suspended geometry."
        case (.roundness, .escalation):
            "The supervisor is a Slowpoke. He has marked the case ‘urgent, eventually.’"
        case (.roundness, .filed):
            "Certified round. This certificate is rectangular. Please do not alert the committee."
        case (.lessPaperwork, .intake):
            "To request less paperwork, please complete the Request for Less Paperwork paperwork."
        case (.lessPaperwork, .review):
            "Your form was rejected for being the correct form. We weren’t prepared for that."
        case (.lessPaperwork, .escalation):
            "The appeals committee is a Ditto. It has made an exact copy of the problem."
        case (.lessPaperwork, .filed):
            "One copy for you. One for the archive. One to explain why there are copies."
        case (.missingSupervisor, .intake):
            "The supervisor is missing. His chair has been promoted until further notice."
        case (.missingSupervisor, .review):
            "The chair has requested a standing desk. Psyduck has escalated the furniture."
        case (.missingSupervisor, .escalation):
            "Snorlax signed in his sleep. That is still our most alert signature."
        case (.missingSupervisor, .filed):
            "The chair is now management. Please direct all complaints to the lumbar support."
        }
    }

    mutating func advance() {
        switch stage {
        case .intake: stage = .review
        case .review: stage = .escalation
        case .escalation: stage = .filed
        case .filed:
            form = Form.allCases[(form.rawValue + 1) % Form.allCases.count]
            stage = .intake
        }
    }
}
