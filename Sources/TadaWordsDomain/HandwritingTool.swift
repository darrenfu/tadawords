/// Child-selectable writing tools. The stable raw values are shared by the
/// feature and audio layers so each tool can keep its own visual and sound.
public enum HandwritingTool: String, CaseIterable, Codable, Hashable, Sendable {
    case pencil
    case crayon
    case chalk
    case brush
}
