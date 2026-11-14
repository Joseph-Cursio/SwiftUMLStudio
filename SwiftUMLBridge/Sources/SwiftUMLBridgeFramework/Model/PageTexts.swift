/// Descriptive texts you can add around your diagram
public struct PageTexts: Codable, Sendable {
    internal init(
        header: String? = nil,
        title: String? = nil,
        legend: String? = nil,
        caption: String? = nil,
        footer: String? = nil
    ) {
        self.header = header
        self.title = title
        self.legend = legend
        self.caption = caption
        self.footer = footer
    }

    public var header: String?
    public var title: String?
    public var legend: String?
    public var caption: String?
    public var footer: String?

    func plantuml() -> String? {
        if header == nil, title == nil, legend == nil, caption == nil, footer == nil {
            return nil
        }
        var text = ""
        if let header {
            text.appendAsNewLine("header")
            text.appendAsNewLine(header)
            text.appendAsNewLine("end header")
        }
        if let title {
            text.appendAsNewLine("title")
            text.appendAsNewLine(title)
            text.appendAsNewLine("end title")
        }
        if let legend {
            text.appendAsNewLine("legend")
            text.appendAsNewLine(legend)
            text.appendAsNewLine("end legend")
        }
        if let caption {
            text.appendAsNewLine("caption")
            text.appendAsNewLine(caption)
            text.appendAsNewLine("end caption")
        }
        if let footer {
            text.appendAsNewLine("footer")
            text.appendAsNewLine(footer)
            text.appendAsNewLine("end footer")
        }
        return text
    }
}
