import AppKit
import SwiftUI

struct SelectableMemoTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var selectedRange: NSRange

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder

        let textView = NSTextView()
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.allowsUndo = true
        textView.font = .systemFont(ofSize: 14)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.delegate = context.coordinator
        textView.string = text
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SelectableMemoTextEditor

        init(_ parent: SelectableMemoTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            parent.selectedRange = textView.selectedRange()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.selectedRange = textView.selectedRange()
        }
    }
}

struct MemoReaderTextView: NSViewRepresentable {
    let content: String
    let ranges: [CopyableRange]
    var onCopy: (String) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder

        let textView = ClickableMemoTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.textContainer?.widthTracksTextView = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? ClickableMemoTextView else { return }
        textView.content = content.replacingOccurrences(of: "\r\n", with: "\n")
        textView.ranges = TextRangeHelpers.normalize(ranges, content: content)
        textView.onCopy = onCopy
        textView.applyAttributedContent()
    }
}

final class ClickableMemoTextView: NSTextView {
    var content = ""
    var ranges: [CopyableRange] = []
    var onCopy: (String) -> Void = { _ in }

    override func mouseDown(with event: NSEvent) {
        let localPoint = convert(event.locationInWindow, from: nil)
        guard
            let layoutManager,
            let textContainer
        else {
            super.mouseDown(with: event)
            return
        }

        var containerPoint = localPoint
        containerPoint.x -= textContainerOrigin.x
        containerPoint.y -= textContainerOrigin.y

        let glyphIndex = layoutManager.glyphIndex(for: containerPoint, in: textContainer)
        let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)

        if let range = ranges.first(where: { characterIndex >= $0.start && characterIndex < $0.end }) {
            let text = TextRangeHelpers.substring(content, in: range)
            if !text.isEmpty {
                onCopy(text)
                return
            }
        }

        super.mouseDown(with: event)
    }

    func applyAttributedContent() {
        let normalizedContent = content.replacingOccurrences(of: "\r\n", with: "\n")
        let nsString = normalizedContent as NSString
        let fullRange = NSRange(location: 0, length: nsString.length)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 4
        paragraphStyle.paragraphSpacing = 8

        let attributed = NSMutableAttributedString(
            string: normalizedContent,
            attributes: [
                .font: NSFont.systemFont(ofSize: 15),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraphStyle
            ]
        )

        for range in ranges {
            let start = max(0, min(range.start, nsString.length))
            let end = max(0, min(range.end, nsString.length))
            guard start < end else { continue }
            attributed.addAttributes(
                [
                    .backgroundColor: NSColor.controlAccentColor.withAlphaComponent(0.18),
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                    .foregroundColor: NSColor.controlAccentColor
                ],
                range: NSRange(location: start, length: end - start)
            )
        }

        if fullRange.length == 0 {
            textStorage?.setAttributedString(NSAttributedString(string: ""))
        } else {
            textStorage?.setAttributedString(attributed)
        }
    }
}
