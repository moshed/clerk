import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Apple's on-device model.
///
/// It matters for one reason: **nothing it is given leaves the Mac.** The paste
/// importer was the single place a real value went out, and that exception is
/// what made a card number in the box dangerous. With this there is no
/// exception - the importer reads a card number, a routing number and a social
/// security number on the machine they are already on.
///
/// It is not used for FILLING a form. That has to feel instant and only ever
/// sees labels anyway; measured on 2026-09-27 it takes about a second a line,
/// against about fifty milliseconds for Jev.
///
/// Measured the same day, on real notes: six lines out of six right, French and
/// Hebrew included, and it did not refuse a card number.
enum OnDevice {
    #if canImport(FoundationModels)
    /// One line of somebody's notes, read.
    @Generable
    struct Line {
        @Guide(description: "the field key it holds, exactly one from the list given, or \"unknown\"")
        var field: String
        @Guide(description: "the first name of the person it is about, or empty when the line does not say")
        var person: String
    }
    #endif

    /// Whether the model is here and ready. False when Apple Intelligence is
    /// switched off or the model is still downloading, and then Jev is used
    /// instead - with card and bank lines held back, as before.
    static var available: Bool {
        #if canImport(FoundationModels)
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
        #else
        return false
        #endif
    }

    /// Why it is not here, in words Moshe would use.
    static var whyNot: String? {
        #if canImport(FoundationModels)
        switch SystemLanguageModel.default.availability {
        case .available: return nil
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Apple Intelligence is switched off in System Settings"
        case .unavailable(.modelNotReady):
            return "the model is still downloading"
        case .unavailable(.deviceNotEligible):
            return "this Mac cannot run it"
        case .unavailable: return "it is not available on this Mac"
        @unknown default: return "it is not available on this Mac"
        }
        #else
        return "this build has no on-device model"
        #endif
    }

    /// What one line holds, and whose it is.
    ///
    /// `fields` are the keys it may answer with and `people` the first names it
    /// may attribute to, so it cannot invent either. Returns nil when it cannot
    /// tell, which leaves the row for Moshe to sort out rather than guessing.
    static func read(line: String, fields: [(key: String, question: String)],
                     people: [(id: String, name: String)]) async -> (field: String, person: String?)? {
        #if canImport(FoundationModels)
        guard available else { return nil }
        let keys = fields.map(\.key).joined(separator: ", ")
        let names = people.map(\.name).joined(separator: ", ")
        let what = fields.map { "\($0.key) is \($0.question)" }.joined(separator: "; ")

        let session = LanguageModelSession(instructions: """
            You read one line from somebody's notes about their family's personal \
            details and say which field it holds and whose it is.

            The fields are: \(what).

            Judge it by the VALUE on the line, not by the words around it. A long \
            run of digits beside the word Visa or Mastercard is the card NUMBER, \
            not a name. A word that is a person's name is a name.

            Answer with exactly one of these keys: \(keys), or "unknown" when the \
            line is not one of them. The people are: \(names). Give a person only \
            when the line itself says who; otherwise leave it empty.
            """)
        guard let out = try? await session.respond(to: "The line is: \(line)",
                                                   generating: Line.self)
        else { return nil }

        let key = out.content.field.trimmingCharacters(in: .whitespaces)
        guard fields.contains(where: { $0.key == key }) else { return nil }

        // Only a name it was actually offered. It is asked for a first name, so
        // match on that rather than on the id.
        let said = out.content.person.trimmingCharacters(in: .whitespaces)
        let who = people.first { $0.name.caseInsensitiveCompare(said) == .orderedSame }
        return (key, who?.id)
        #else
        return nil
        #endif
    }
}
