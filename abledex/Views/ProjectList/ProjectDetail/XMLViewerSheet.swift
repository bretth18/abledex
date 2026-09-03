//
//  XMLViewerSheet.swift
//  abledex
//

import SwiftUI
import AppKit

struct XMLViewerSheet: View {
    let project: ProjectRecord
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @State private var xmlContent: String = ""
    @State private var isLoading: Bool = true
    @State private var errorMessage: String?
    @State private var xmlSize: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("XML: \(project.name)")
                    .font(.headline)
                if xmlSize > 0 {
                    Text("(\(ByteCountFormatter.string(fromByteCount: Int64(xmlSize), countStyle: .file)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(xmlContent, forType: .string)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .disabled(xmlContent.isEmpty)

                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()

            Divider()

            if isLoading {
                Spacer()
                ProgressView("Loading XML...")
                Spacer()
            } else if let error = errorMessage {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.orange)
                    Text(error)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else {
                XMLTextView(text: xmlContent, backgroundColor: theme.xmlBackground, foregroundColor: theme.xmlForeground)
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .background(theme.usesCustomBackground ? theme.background.ignoresSafeArea() : nil)
        .task {
            await loadXML()
        }
    }

    private func loadXML() async {
        let filePath = URL(fileURLWithPath: project.alsFilePath)

        // Run on background thread with low priority to avoid competing with scan I/O
        let result: Result<String, Error> = await Task.detached(priority: .background) {
            let parser = ALSParser()
            return Result { try parser.getRawXML(alsFilePath: filePath) }
        }.value

        switch result {
        case .success(let xml):
            xmlContent = xml
            xmlSize = xml.utf8.count
            isLoading = false
        case .failure(let error):
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
}

/// NSTextView wrapper for performant large text display.
/// Uses Coordinator to set text off the main layout pass to avoid UI stalls.
struct XMLTextView: NSViewRepresentable {
    let text: String
    var backgroundColor: NSColor = .textBackgroundColor
    var foregroundColor: NSColor = .textColor

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView

        textView.isEditable = false
        textView.isSelectable = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.backgroundColor = backgroundColor
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false

        // Disable word wrap for XML (horizontal scroll)
        textView.isHorizontallyResizable = true
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        // Disable layout during initial load
        textView.layoutManager?.allowsNonContiguousLayout = true

        context.coordinator.textView = textView

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let textView = context.coordinator.textView!
        textView.backgroundColor = backgroundColor

        guard context.coordinator.currentText != text else { return }
        context.coordinator.currentText = text

        // Set text content with layout temporarily disabled to avoid stalling
        textView.textStorage?.beginEditing()
        textView.textStorage?.setAttributedString(NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                .foregroundColor: foregroundColor
            ]
        ))
        textView.textStorage?.endEditing()
    }

    class Coordinator {
        var textView: NSTextView?
        var currentText: String = ""
    }
}
