import Foundation

enum IOSLegalSafetyPolicy {
    static func crisisRefusal(for text: String) -> String? {
        let normalized = text
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
        let crisisSignals = [
            "suicide",
            "kill myself",
            "end my life",
            "harm myself",
            "hurt myself",
            "self harm",
            "self-harm",
            "take my own life",
            "want to die",
            "no quiero vivir",
            "quiero morir",
            "suicid",
            "hacerme dano",
            "autolesion",
            "quitarme la vida"
        ]
        guard crisisSignals.contains(where: { normalized.contains($0) }) else { return nil }
        return """
        I can't help handle a crisis or self-harm situation as an assistant.

        If you or someone nearby may be in immediate danger, contact local emergency services now. In the US you can call or text 988 for crisis support. In the EU you can call 112 for emergency help. If you are outside those areas, contact your local emergency number or a trusted local crisis resource.

        Clawix is not an emergency service and does not provide therapy, diagnosis, treatment, or crisis counseling.
        """
    }
}
