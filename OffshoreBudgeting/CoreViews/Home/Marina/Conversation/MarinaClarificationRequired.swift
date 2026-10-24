/// Stops model generation after verified ambiguity has been saved and published.
/// The runtime treats this marker as a completed clarification, including when wrapped by a tool error.
nonisolated struct MarinaClarificationRequired: Error, Sendable {}
