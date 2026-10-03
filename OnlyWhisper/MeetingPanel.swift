import AppKit
import SwiftUI

// MARK: - Chat

struct MeetingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        Group {
            if model.meetingCollapsed, model.meetingActive {
                collapsedBar
            } else {
                expanded
            }
        }
        .frame(
            minWidth: model.meetingCollapsed && model.meetingActive ? 280 : 340,
            minHeight: model.meetingCollapsed && model.meetingActive ? 64 : 420
        )
        .glassWindow()
        .onAppear { model.prepareMeetingAudioChoice() }
    }

    private var expanded: some View {
        VStack(spacing: 0) {
            header
            HairlineDivider()
            if model.meetingScreenCaptureMissing {
                notice(t(
                    "Screen recording is off, so only the microphone is captured.",
                    "Bildschirmaufnahme ist aus, deshalb wird nur das Mikrofon aufgenommen."
                ))
            } else if model.meetingAppAudioMissing {
                notice(t(
                    "That app's audio could not be separated, so only the microphone is captured.",
                    "Der Ton dieser App ließ sich nicht trennen, deshalb wird nur das Mikrofon aufgenommen."
                ))
            } else if model.meetingBrowserAudio {
                notice(t(
                    "Other browser tabs are included. Pause anything loud.",
                    "Andere Browser-Tabs sind dabei. Laute Tabs pausieren."
                ))
            } else if model.meetingFullMix, model.meetingActive {
                notice(t("Capturing all system audio.", "Nimmt den ganzen Systemton auf."))
            }
            MeetingChatList(
                turns: model.meetingTurns,
                names: model.speakerNames,
                separatesLocalVoice: model.separatesLocalVoice,
                notes: model.meetingNotes,
                onRename: model.meetingTurns.isEmpty ? nil : { id, name in
                    model.renameMeetingSpeaker(id, to: name)
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                if model.meetingPreparing {
                    preparingState
                } else if model.meetingTurns.isEmpty, model.meetingNotes == nil {
                    EmptyStateView(
                        symbol: "waveform",
                        title: model.meetingActive ? t("Listening…", "Hört zu…") : t("No transcript yet", "Noch kein Transkript"),
                        message: model.meetingActive
                            ? t("Text appears after a short pause.", "Text erscheint nach einer kurzen Pause.")
                            : t("Press Record. Speakers are labeled as they talk.", "Drücke Aufnehmen. Sprecher werden beim Sprechen zugeordnet.")
                    )
                }
            }
            footer
        }
    }

    private var header: some View {
        HStack(spacing: DS.spacingS) {
            MeetingClock(
                active: model.meetingActive,
                paused: model.meetingPaused,
                elapsed: model.meetingElapsed,
                sliceStart: model.meetingSliceStart,
                now: model.meetingNow,
                reduceMotion: reduceMotion
            )
            Text(statusLine)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: DS.spacingS)
            if model.meetingActive {
                symbolButton(
                    model.meetingPaused ? "play.fill" : "pause.fill",
                    label: model.meetingPaused ? t("Resume", "Fortsetzen") : t("Pause", "Pause")
                ) {
                    if model.meetingPaused {
                        Task { await model.resumeMeeting() }
                    } else {
                        model.pauseMeeting()
                    }
                }
                symbolButton("stop.fill", label: t("Stop", "Beenden"), tint: .red) {
                    Task { await model.stopMeeting() }
                }
                symbolButton(
                    "rectangle.compress.vertical",
                    label: t("Collapse", "Einklappen")
                ) {
                    model.toggleMeetingCollapsed()
                }
            }
            symbolButton("xmark", label: t("Hide", "Ausblenden")) {
                dismissWindow(id: "meeting")
            }
        }
        .padding(.horizontal, DS.spacingM)
        .padding(.vertical, DS.spacingS)
        .contentShape(Rectangle())
    }

    private var collapsedBar: some View {
        HStack(spacing: DS.spacingS) {
            MeetingClock(
                active: model.meetingActive,
                paused: model.meetingPaused,
                elapsed: model.meetingElapsed,
                sliceStart: model.meetingSliceStart,
                now: model.meetingNow,
                reduceMotion: reduceMotion
            )
            Text(model.meetingPaused ? t("Paused", "Pausiert") : t("Recording", "Aufnahme"))
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
            Spacer(minLength: DS.spacingS)
            symbolButton(
                model.meetingPaused ? "play.fill" : "pause.fill",
                label: model.meetingPaused ? t("Resume", "Fortsetzen") : t("Pause", "Pause")
            ) {
                if model.meetingPaused {
                    Task { await model.resumeMeeting() }
                } else {
                    model.pauseMeeting()
                }
            }
            symbolButton("stop.fill", label: t("Stop", "Beenden"), tint: .red) {
                Task { await model.stopMeeting() }
            }
            symbolButton("rectangle.expand.vertical", label: t("Expand", "Aufklappen")) {
                model.toggleMeetingCollapsed()
            }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: DS.spacingS) {
            audioAppMenu
            HStack(spacing: DS.spacingS) {
                if !model.meetingActive {
                    Button(model.meetingPreparing ? t("Preparing…", "Wird vorbereitet…") : recordTitle) {
                        Task { await model.startMeeting() }
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(model.meetingPreparing)
                }
                Spacer(minLength: DS.spacingS)
                Button(t("Copy Transcript", "Transkript kopieren")) {
                    model.copy(model.meetingTranscript())
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .disabled(model.meetingTurns.isEmpty)
            }
        }
        .padding(.horizontal, DS.spacingM)
        .padding(.vertical, DS.spacingS)
    }

    private var audioAppMenu: some View {
        Menu {
            Button {
                model.selectMeetingAudio(nil)
            } label: {
                audioAppRow(
                    title: t("Microphone only", "Nur Mikrofon"),
                    chosen: model.meetingAudioApp == nil
                )
            }
            let apps = MeetingDetector.openApps()
            let suggested = apps.filter(\.suggested)
            let others = apps.filter { !$0.suggested }
            if !suggested.isEmpty {
                Section(t("Suggested", "Vorgeschlagen")) {
                    ForEach(suggested) { app in
                        Button {
                            model.selectMeetingAudio(app)
                        } label: {
                            audioAppRow(title: audioAppTitle(app), chosen: model.meetingAudioApp?.bundleID == app.bundleID)
                        }
                    }
                }
            }
            if !others.isEmpty {
                Section(t("All apps", "Alle Apps")) {
                    ForEach(others) { app in
                        Button {
                            model.selectMeetingAudio(app)
                        } label: {
                            audioAppRow(title: audioAppTitle(app), chosen: model.meetingAudioApp?.bundleID == app.bundleID)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "macwindow")
                Text(menuTitle)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 12, weight: .medium))
        }
        .menuStyle(.borderlessButton)
        .disabled(model.meetingPreparing)
        .accessibilityLabel(t("App to record", "App für die Aufnahme"))
    }

    private var menuTitle: String {
        if let app = model.meetingAudioApp {
            return app.browser ? audioAppTitle(app) : app.name
        }
        return t("Microphone only", "Nur Mikrofon")
    }

    private func audioAppTitle(_ app: MeetingAudioApp) -> String {
        guard app.browser else { return app.name }
        return "\(app.name) · \(t("whole browser", "ganzer Browser"))"
    }

    private func audioAppRow(title: String, chosen: Bool) -> some View {
        HStack {
            if chosen {
                Image(systemName: "checkmark")
            }
            Text(title)
        }
    }

    private var preparingState: some View {
        VStack(spacing: DS.spacingM) {
            ProgressView()
                .controlSize(.large)
            Text(t("Preparing…", "Wird vorbereitet…"))
                .font(.system(size: 16, weight: .semibold))
            Text(t(
                "Loading speech and speaker recognition. This can take a moment.",
                "Sprache und Sprecher werden geladen. Das kann einen Moment dauern."
            ))
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .accessibilityElement(children: .combine)
    }

    private var statusLine: String {
        if !model.meetingStatus.isEmpty { return model.meetingStatus }
        if let name = model.detectedMeeting?.kind.localizedName, !model.meetingActive {
            return t("\(name) call", "\(name)-Anruf")
        }
        return t("Transcript with speakers", "Transkript mit Sprechern")
    }

    private var recordTitle: String {
        if let name = model.meetingAudioApp?.name {
            return t("Record \(name)", "\(name) aufnehmen")
        }
        return t("Record", "Aufnehmen")
    }

    private func notice(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DS.spacingM)
            .padding(.vertical, DS.spacingS)
            .background(Color.orange.opacity(0.12))
    }

    private func symbolButton(_ symbol: String, label: String, tint: Color = .primary, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(Color.primary.opacity(0.06), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .help(label)
    }
}

struct MeetingChatList: View {
    var turns: [MeetingTurn]
    var names: [String: String]
    var separatesLocalVoice: Bool
    var notes: MeetingNotes?
    var scrolls = true
    var onRename: ((String, String) -> Void)?
    @State private var renameID: String?
    @State private var renameText = ""

    var body: some View {
        Group {
            if scrolls {
                ScrollViewReader { proxy in
                    ScrollView { content }
                        .onChange(of: turns.last?.text) { _, _ in scroll(proxy) }
                        .onChange(of: turns.count) { _, _ in scroll(proxy) }
                }
            } else {
                content
            }
        }
        .alert(t("Rename speaker", "Sprecher umbenennen"), isPresented: renamePresented) {
            TextField(t("Name", "Name"), text: $renameText)
            Button(t("Save", "Sichern")) {
                if let renameID {
                    onRename?(renameID, renameText)
                }
            }
            Button(t("Cancel", "Abbrechen"), role: .cancel) {}
        }
    }

    private var content: some View {
        LazyVStack(alignment: .leading, spacing: DS.spacingM) {
            ForEach(turns) { turn in
                bubble(turn)
                    .id(turn.id)
            }
            if let notes, !notes.summary.isEmpty || !notes.decisions.isEmpty || !notes.tasks.isEmpty {
                MeetingNotesBlock(notes: notes)
            }
        }
        .padding(DS.spacingL)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var renamePresented: Binding<Bool> {
        Binding(get: { renameID != nil }, set: { if !$0 { renameID = nil } })
    }

    private func scroll(_ proxy: ScrollViewProxy) {
        if let id = turns.last?.id {
            withAnimation(.snappy(duration: 0.2)) {
                proxy.scrollTo(id, anchor: .bottom)
            }
        }
    }

    private func bubble(_ turn: MeetingTurn) -> some View {
        let name = MeetingMerger.displayName(
            speakerID: turn.speakerID,
            isLocal: turn.isLocal,
            names: names,
            separatesLocalVoice: separatesLocalVoice
        )
        let local = turn.isLocal && separatesLocalVoice
        return HStack(alignment: .top, spacing: DS.spacingS) {
            if local { Spacer(minLength: 36) }
            if !local {
                MeetingAvatar(name: name, speakerID: turn.speakerID)
            }
            VStack(alignment: local ? .trailing : .leading, spacing: 3) {
                HStack(spacing: DS.spacingS) {
                    nameButton(name, turn: turn)
                    Text(Duration.seconds(turn.start).formatted(.time(pattern: .minuteSecond)))
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
                Text(turn.text)
                    .font(.system(size: 13))
                    .textSelection(.enabled)
                    .multilineTextAlignment(local ? .trailing : .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(MeetingAvatar.tint(for: turn.speakerID).opacity(local ? 0.22 : 0.14), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .frame(maxWidth: 280, alignment: local ? .trailing : .leading)
            }
            if !local { Spacer(minLength: 36) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name), \(Duration.seconds(turn.start).formatted(.time(pattern: .minuteSecond))), \(turn.text)")
    }

    @ViewBuilder
    private func nameButton(_ name: String, turn: MeetingTurn) -> some View {
        if onRename != nil {
            Button(name) {
                renameID = turn.speakerID
                renameText = name
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .semibold))
            .accessibilityHint(t("Rename speaker", "Sprecher umbenennen"))
        } else {
            Text(name)
                .font(.system(size: 12, weight: .semibold))
        }
    }
}

private struct MeetingClock: View {
    var active: Bool
    var paused: Bool
    var elapsed: TimeInterval
    var sliceStart: Date?
    var now: Date
    var reduceMotion: Bool

    var body: some View {
        let running = active && !paused ? now.timeIntervalSince(sliceStart ?? now) : 0
        HStack(spacing: 6) {
            Image(systemName: paused ? "pause.fill" : "circle.fill")
                .font(.system(size: 8))
                .foregroundStyle(active ? (paused ? Color.orange : Color.red) : Color.secondary)
                .symbolEffect(.pulse, isActive: active && !paused && !reduceMotion)
            Text(Duration.seconds(max(0, elapsed + running)).formatted(.time(pattern: .minuteSecond)))
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background((active && !paused ? Color.red : Color.primary).opacity(0.12), in: Capsule())
        .accessibilityLabel(paused ? t("Paused", "Pausiert") : t("Recording", "Aufnahme läuft"))
    }
}

struct MeetingAvatar: View {
    var name: String
    var speakerID: String
    private static let tints: [Color] = [.blue, .orange, .green, .pink, .purple, .teal, .indigo]

    var body: some View {
        Text(letter)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 26, height: 26)
            .background(Self.tint(for: speakerID).gradient, in: Circle())
            .accessibilityHidden(true)
    }

    private var letter: String {
        name.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "?"
    }

    static func tint(for speakerID: String) -> Color {
        if speakerID == MeetingMerger.localSpeakerID { return .blue }
        let seed = speakerID.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return tints[abs(seed) % tints.count]
    }
}

struct MeetingNotesBlock: View {
    var notes: MeetingNotes

    var body: some View {
        VStack(alignment: .leading, spacing: DS.spacingM) {
            if !notes.summary.isEmpty {
                VStack(alignment: .leading, spacing: DS.spacingS) {
                    Label(t("Summary", "Zusammenfassung"), systemImage: "text.quote")
                        .font(.headline)
                    Text(notes.summary).textSelection(.enabled)
                }
                .card()
            }
            if !notes.decisions.isEmpty {
                list(t("Decisions", "Entscheidungen"), symbol: "checkmark.seal", items: notes.decisions)
            }
            if !notes.tasks.isEmpty {
                list(t("Tasks", "Aufgaben"), symbol: "checklist", items: notes.tasks)
            }
        }
    }

    private func list(_ title: String, symbol: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: DS.spacingS) {
            Label(title, systemImage: symbol).font(.headline)
            ForEach(items, id: \.self) { item in
                Text(item).textSelection(.enabled)
            }
        }
        .card()
    }
}

private struct HairlineDivider: View {
    var body: some View {
        Rectangle().fill(DS.hairline).frame(height: 1)
    }
}
