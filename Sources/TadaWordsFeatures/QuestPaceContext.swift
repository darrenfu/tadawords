import TadaWordsDomain

extension WordPrompt {
    /// Current V1 input context. Pencil handwriting remains a separate future
    /// context and will not be mixed into today's finger-writing baseline.
    func paceContext(deviceClass: DeviceClass) -> PaceContext {
        PaceContext(
            learningMode: learningMode,
            deviceClass: deviceClass,
            inputMethod: learningMode == .read ? .speech : .fingerWriting,
            wordLength: normalizedText.count
        )
    }
}
