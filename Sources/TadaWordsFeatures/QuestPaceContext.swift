import TadaWordsDomain

extension WordPrompt {
    /// Creates a comparable pace bucket without changing the shared learning
    /// mode. Typed spelling and handwriting therefore contribute to the same
    /// word mastery while keeping independent timing baselines.
    func paceContext(
        deviceClass: DeviceClass,
        writeInputMethod: WriteQuestInputMethod = .handwriting
    ) -> PaceContext {
        PaceContext(
            learningMode: learningMode,
            deviceClass: deviceClass,
            inputMethod: learningMode == .read
                ? .speech
                : writeInputMethod.defaultLearningInputMethod,
            wordLength: normalizedText.count
        )
    }
}
