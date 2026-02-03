//
//  ProjectDetailView.swift
//  abledex
//
//  Created by Brett Henderson on 12/14/25.
//

import SwiftUI
import AppKit

struct ProjectDetailView: View {
    let project: ProjectRecord
    @Environment(AppState.self) private var appState
    @Environment(\.theme) private var theme
    @AppStorage("useCamelotNotation") private var useCamelotNotation = false
    @State private var editingNotes: String = ""
    @State private var newTag: String = ""
    @State private var showTagSuggestions: Bool = false
    @State private var isEditingNotes: Bool = false
    @State private var previewableAudio: [AudioPreviewService.PreviewableAudio] = []
    @State private var sectionOrder: [DetailSection] = DetailOrderStorage.order
    @State private var showXMLViewer: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header (always first)
                headerSection

                // Dynamic sections based on stored order
                ForEach(sectionOrder) { section in
                    if shouldShowSection(section) {
                        Divider()
                        sectionView(for: section)
                    }
                }
            }
            .padding()
        }
        .frame(minWidth: 300)
        .onAppear {
            editingNotes = project.userNotes ?? ""
            loadPreviewableAudio()
        }
        .onChange(of: project.id) {
            editingNotes = project.userNotes ?? ""
            isEditingNotes = false
            appState.audioPreview.stop()
            loadPreviewableAudio()
        }
        .onDisappear {
            appState.audioPreview.stop()
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            sectionOrder = DetailOrderStorage.order
        }
    }

    // MARK: - Section Visibility

    private func shouldShowSection(_ section: DetailSection) -> Bool {
        switch section {
        case .status, .color, .actions, .tags, .details, .notes:
            return true
        case .plugins:
            return !project.plugins.isEmpty
        case .keys:
            return !project.musicalKeys.isEmpty
        case .audioPreview:
            return !previewableAudio.isEmpty
        case .samples:
            return !project.samplePaths.isEmpty
        case .versionTimeline:
            return appState.versionsInSameFolder(as: project).count > 1
        }
    }

    // MARK: - Section Router

    @ViewBuilder
    private func sectionView(for section: DetailSection) -> some View {
        switch section {
        case .status:
            statusSection
        case .color:
            colorLabelSection
        case .actions:
            actionsSection
        case .tags:
            tagsSection
        case .details:
            detailsSection
        case .plugins:
            pluginsSection
        case .keys:
            keysSection
        case .audioPreview:
            audioPreviewSection
        case .samples:
            samplesSection
        case .versionTimeline:
            VersionTimelineSection(project: project)
        case .notes:
            notesSection
        }
    }

    private func loadPreviewableAudio() {
        let folderPath = project.folderPath
        let audioService = appState.audioPreview
        Task.detached {
            let audio = await audioService.findPreviewableAudio(in: folderPath)
            await MainActor.run {
                previewableAudio = audio
            }
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "music.note")
                    .font(.title)
                    .foregroundStyle(.tint)

                VStack(alignment: .leading) {
                    Text(project.name)
                        .font(.title2)
                        .fontWeight(.semibold)

                    HStack {
                        Label(project.sourceVolume, systemImage: "externaldrive")
                        if project.hasMissingSamples {
                            Label("Missing samples", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                        if appState.hasDuplicates(project) {
                            Label("Has duplicates", systemImage: "doc.on.doc")
                                .foregroundStyle(.red)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            // BPM and time signature badges
            HStack(spacing: 8) {
                if let bpm = project.bpm {
                    BadgeView(label: "\(Int(bpm)) BPM", icon: "metronome")
                }
                if let timeSig = project.timeSignature {
                    BadgeView(label: timeSig, icon: "clock")
                }
                if let duration = project.formattedDuration {
                    BadgeView(label: duration, icon: "timer")
                }
            }
        }
    }

    private var actionsSection: some View {
        HStack(spacing: 12) {
            Button {
                appState.openProject(project)
            } label: {
                Label("Open", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)

            Button {
                appState.revealProject(project)
            } label: {
                Label("Reveal", systemImage: "folder")
            }
            .buttonStyle(.bordered)

            Button {
                showXMLViewer = true
            } label: {
                Label("XML", systemImage: "doc.text")
            }
            .buttonStyle(.bordered)
            .sheet(isPresented: $showXMLViewer) {
                XMLViewerSheet(project: project)
            }

            Spacer()
        }
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Status")
                .font(.headline)

            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 56, maximum: 80), spacing: 6)
            ], spacing: 6) {
                ForEach(CompletionStatus.allCases, id: \.self) { status in
                    statusButton(for: status)
                }
            }
        }
    }

    @ViewBuilder
    private func statusButton(for status: CompletionStatus) -> some View {
        let isSelected = project.completionStatus == status
        let color = theme.statusColor(for: status)

        Button {
            Task {
                try? await appState.updateProjectStatus(project, status: status)
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: status.icon)
                    .font(.body)
                Text(status.label)
                    .font(.caption2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(minWidth: 56, maxWidth: .infinity, minHeight: 48)
            .background(isSelected ? color.opacity(0.2) : theme.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        isSelected ? color : (theme.showsBorder ? theme.border : .clear),
                        lineWidth: isSelected ? 2 : 0.5
                    )
            )
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? color : theme.textSecondary)
    }

    private var tagSuggestions: [String] {
        let query = newTag.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return [] }
        return appState.uniqueTags.filter {
            $0.lowercased().hasPrefix(query) && !project.userTags.contains($0)
        }
    }

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tags")
                .font(.headline)

            FlowLayout(spacing: 6) {
                ForEach(project.userTags, id: \.self) { tag in
                    HStack(spacing: 4) {
                        Text(tag)
                        Button {
                            removeTag(tag)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                    }
                    .themedBadge(.accent)
                }

                // Add tag field
                HStack(spacing: 4) {
                    TextField("Add tag", text: $newTag)
                        .textFieldStyle(.plain)
                        .frame(width: 80)
                        .onSubmit {
                            addTag()
                        }
                        .onChange(of: newTag) {
                            showTagSuggestions = !tagSuggestions.isEmpty
                        }
                        .popover(isPresented: $showTagSuggestions, arrowEdge: .bottom) {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(tagSuggestions, id: \.self) { suggestion in
                                    Button {
                                        selectTagSuggestion(suggestion)
                                    } label: {
                                        Text(suggestion)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .frame(minWidth: 120)
                            .padding(.vertical, 4)
                        }
                    Button {
                        addTag()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(theme.surfacePrimary)
                .clipShape(Capsule())
            }
        }
    }

    private func addTag() {
        let tag = newTag.trimmingCharacters(in: .whitespaces)
        guard !tag.isEmpty, !project.userTags.contains(tag) else {
            newTag = ""
            return
        }
        var newTags = project.userTags
        newTags.append(tag)
        Task {
            try? await appState.updateProjectTags(project, tags: newTags)
        }
        newTag = ""
        showTagSuggestions = false
    }

    private func selectTagSuggestion(_ tag: String) {
        var newTags = project.userTags
        newTags.append(tag)
        Task {
            try? await appState.updateProjectTags(project, tags: newTags)
        }
        newTag = ""
        showTagSuggestions = false
    }

    private func removeTag(_ tag: String) {
        var newTags = project.userTags
        newTags.removeAll { $0 == tag }
        Task {
            try? await appState.updateProjectTags(project, tags: newTags)
        }
    }

    private var colorLabelSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Color")
                .font(.headline)

            HStack(spacing: 8) {
                ForEach(ColorLabel.allCases, id: \.self) { label in
                    colorLabelButton(for: label)
                }
            }
        }
    }

    @ViewBuilder
    private func colorLabelButton(for label: ColorLabel) -> some View {
        let isSelected = project.colorLabel == label
        let color = theme.colorLabel(for: label)

        Button {
            Task {
                try? await appState.updateProjectColorLabel(project, colorLabel: label)
            }
        } label: {
            if label == .none {
                Image(systemName: isSelected ? "circle.slash" : "circle.slash")
                    .font(.title2)
                    .foregroundStyle(isSelected ? theme.textPrimary : theme.textTertiary)
            } else {
                Image(systemName: isSelected ? "circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(color)
            }
        }
        .buttonStyle(.plain)
        .padding(4)
        .background(isSelected ? theme.surfacePrimary : Color.clear)
        .clipShape(Circle())
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Details")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    Text("Path")
                        .foregroundStyle(.secondary)
                    Text(project.folderPath)
                        .textSelection(.enabled)
                        .lineLimit(2)
                }

                if let version = project.abletonVersion {
                    GridRow {
                        Text("Ableton Version")
                            .foregroundStyle(.secondary)
                        Text(version)
                    }
                }

                GridRow {
                    Text("Audio Tracks")
                        .foregroundStyle(.secondary)
                    Text("\(project.audioTrackCount)")
                }

                GridRow {
                    Text("MIDI Tracks")
                        .foregroundStyle(.secondary)
                    Text("\(project.midiTrackCount)")
                }

                if project.returnTrackCount > 0 {
                    GridRow {
                        Text("Return Tracks")
                            .foregroundStyle(.secondary)
                        Text("\(project.returnTrackCount)")
                    }
                }

                if let created = project.createdDate {
                    GridRow {
                        Text("Created")
                            .foregroundStyle(.secondary)
                        Text(created, style: .date)
                    }
                }

                GridRow {
                    Text("Last Modified")
                        .foregroundStyle(.secondary)
                    Text(project.modifiedDate ?? project.filesystemModifiedDate, style: .date)
                }

                GridRow {
                    Text("Last Indexed")
                        .foregroundStyle(.secondary)
                    Text(project.lastIndexedAt, style: .relative)
                }
            }
            .font(.callout)
        }
    }

    private var pluginsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Plugins (\(project.plugins.count))")
                .font(.headline)

            FlowLayout(spacing: 6) {
                ForEach(project.plugins, id: \.self) { plugin in
                    Text(plugin)
                        .themedBadge(.neutral)
                }
            }
        }
    }

    private var keysSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Keys (\(project.musicalKeys.count))")
                .font(.headline)

            FlowLayout(spacing: 6) {
                ForEach(project.musicalKeys, id: \.self) { key in
                    HStack(spacing: 4) {
                        Image(systemName: "music.note")
                            .font(.caption2)
                        Text(displayKey(key))
                    }
                    .themedBadge(.tinted(.pink))
                }
            }
        }
    }

    private func displayKey(_ key: String) -> String {
        if useCamelotNotation, let camelot = CamelotConverter.toCamelot(key) {
            return camelot
        }
        return key
    }

    private var audioPreviewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Audio Preview")
                    .font(.headline)

                Spacer()

                Button {
                    appState.audioPreview.stop()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .opacity(appState.audioPreview.isPlaying ? 1 : 0)
                .disabled(!appState.audioPreview.isPlaying)
            }

            let recordedAudio = previewableAudio.filter { $0.isRecorded }
            let otherAudio = previewableAudio.filter { !$0.isRecorded }

            if !recordedAudio.isEmpty {
                Text("Recorded")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ForEach(recordedAudio.prefix(5)) { audio in
                    audioRow(audio)
                }

                if recordedAudio.count > 5 {
                    Text("+ \(recordedAudio.count - 5) more recordings")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            if !otherAudio.isEmpty {
                if !recordedAudio.isEmpty {
                    Text("Samples")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }

                ForEach(otherAudio.prefix(5)) { audio in
                    audioRow(audio)
                }

                if otherAudio.count > 5 {
                    Text("+ \(otherAudio.count - 5) more samples")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    @ViewBuilder
    private func audioRow(_ audio: AudioPreviewService.PreviewableAudio) -> some View {
        let isCurrentlyPlaying = appState.audioPreview.currentlyPlayingURL == audio.url
        let isPlaying = isCurrentlyPlaying && appState.audioPreview.isPlaying
        let audioDuration = isCurrentlyPlaying ? appState.audioPreview.duration : (audio.duration ?? 0)

        HStack(spacing: 8) {
            Button {
                appState.audioPreview.togglePlayPause(url: audio.url)
            } label: {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(isCurrentlyPlaying ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(audio.name)
                        .font(.caption)
                        .lineLimit(1)
                        .foregroundStyle(isCurrentlyPlaying ? Color.primary : Color.secondary)

                    Spacer()

                    if audio.isRecorded {
                        Image(systemName: "mic.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }

                    Text(formatTime(isCurrentlyPlaying ? appState.audioPreview.playbackProgress : 0, total: audioDuration))
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                }

                AsyncWaveformView(
                    url: audio.url,
                    progress: isCurrentlyPlaying ? appState.audioPreview.playbackProgress : 0,
                    duration: audioDuration,
                    isActive: isCurrentlyPlaying,
                    onSeek: { time in
                        if isCurrentlyPlaying {
                            appState.audioPreview.seek(to: time)
                        } else {
                            // Start playing and seek
                            appState.audioPreview.play(url: audio.url)
                            appState.audioPreview.seek(to: time)
                        }
                    }
                )
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(isCurrentlyPlaying ? theme.accentSubtle : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func formatTime(_ current: Double, total: Double) -> String {
        let currentMins = Int(current) / 60
        let currentSecs = Int(current) % 60
        let totalMins = Int(total) / 60
        let totalSecs = Int(total) % 60
        return String(format: "%d:%02d / %d:%02d", currentMins, currentSecs, totalMins, totalSecs)
    }

    private var samplesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Samples (\(project.samplePaths.count))")
                    .font(.headline)

                if project.hasMissingSamples {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                ForEach(project.samplePaths.prefix(10), id: \.self) { path in
                    Text(path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if project.samplePaths.count > 10 {
                    Text("... and \(project.samplePaths.count - 10) more")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Notes")
                    .font(.headline)
                Spacer()
                if isEditingNotes {
                    Button("Save") {
                        saveNotes()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    Button("Cancel") {
                        editingNotes = project.userNotes ?? ""
                        isEditingNotes = false
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else {
                    Button("Edit") {
                        isEditingNotes = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            if isEditingNotes {
                TextEditor(text: $editingNotes)
                    .font(.callout)
                    .frame(minHeight: 100)
                    .padding(8)
                    .background(theme.surfaceSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Text(project.userNotes?.isEmpty == false ? project.userNotes! : "No notes added")
                    .font(.callout)
                    .foregroundStyle(project.userNotes?.isEmpty == false ? .primary : .tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(theme.surfaceSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func saveNotes() {
        Task {
            try? await appState.updateProjectNotes(project, notes: editingNotes)
            isEditingNotes = false
        }
    }
}

// MARK: - Supporting Views

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
            // Header
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

            // Content
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

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    struct CachedLayout {
        var size: CGSize
        var frames: [CGRect]
    }

    func makeCache(subviews: Subviews) -> CachedLayout? {
        nil
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout CachedLayout?) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        cache = result
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout CachedLayout?) {
        let result = cache ?? arrange(proposal: proposal, subviews: subviews)

        for (index, frame) in result.frames.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> CachedLayout {
        let width = proposal.width ?? .infinity
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if x + size.width > width && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }

            frames.append(CGRect(x: x, y: y, width: size.width, height: size.height))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        let totalHeight = y + rowHeight
        return CachedLayout(size: CGSize(width: width, height: totalHeight), frames: frames)
    }
}
