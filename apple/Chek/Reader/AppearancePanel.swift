import ChekReader
import SwiftUI

/// Text size, theme, font, spacing and margins, changed while you read.
struct AppearancePanel: View {
    var showsTextSettings = true
    /// Whether comments apply, which they do to chapters from sources.
    var showsCommentSettings = false
    /// What a reading mode chosen here applies to, nil to offer none.
    var modeKey: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ReaderAppearanceForm(showsTextSettings: showsTextSettings, showsCommentSettings: showsCommentSettings, modeKey: modeKey)
                .navigationTitle("Appearance")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    // The same Close as the other reader panels.
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close", systemImage: "xmark") {
                            dismiss()
                        }
                    }
                }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        // The page stays visible behind the panel, so changes show as you make them.
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
    }
}

/// The reading settings, shared by the reader's panel and Settings.
struct ReaderAppearanceForm: View {
    /// Whether the settings for reflowing text apply, which they don't to
    /// comics and PDFs.
    var showsTextSettings = true
    /// Whether to offer turning comments off and showing hidden
    /// commenters again, which applies to chapters from sources and Settings.
    var showsCommentSettings = true
    /// What a reading mode chosen here applies to, usually a series. Nil
    /// in Settings, where there's nothing open to choose it for, and for
    /// text, which follows its language.
    var modeKey: String?
    @Environment(ReaderSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            if showsTextSettings {
                Section {
                    TextSizeControl()
                    ThemePicker(selection: $settings.theme)
                }
            }
            if let modeKey {
                Section {
                    Picker("Read As", selection: Binding(
                        get: { settings.readingMode(for: modeKey) },
                        set: { settings.setReadingMode($0, for: modeKey) }
                    )) {
                        Text("Auto").tag(ReadingMode.automatic)
                        Text("Comic").tag(ReadingMode.comic)
                        Text("Manga").tag(ReadingMode.manga)
                        Text("Webtoon").tag(ReadingMode.webtoon)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                } header: {
                    Text("Read As")
                } footer: {
                    switch settings.readingMode(for: modeKey) {
                    case .automatic: Text("Follows the file or site, then the shape of the pages. Applies to this series.")
                    case .comic: Text("Pages turn left to right. Applies to this series.")
                    case .manga: Text("Pages turn right to left. Applies to this series.")
                    case .webtoon: Text("Pages scroll down in one column. Applies to this series.")
                    }
                }
            }
            // A webtoon scrolls, so there's no page turn to choose.
            if modeKey.map({ settings.readingMode(for: $0) }) != .webtoon {
                Section("Page Turn") {
                    Picker("Page Turn", selection: $settings.pageTransition) {
                        // The default first.
                        Text("Slide").tag(ReaderPreferences.PageTransition.slide)
                        Text("Curl").tag(ReaderPreferences.PageTransition.curl)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }
            if showsTextSettings {
                Section("Text") {
                    Picker("Font", selection: $settings.font) {
                        Text("Original").tag(ReaderPreferences.Font.original)
                        Text("New York").tag(ReaderPreferences.Font.serif)
                        Text("San Francisco").tag(ReaderPreferences.Font.sansSerif)
                    }
                    Picker("Line Spacing", selection: $settings.lineSpacing) {
                        Text("Original").tag(ReaderSettings.LineSpacing.original)
                        Text("Compact").tag(ReaderSettings.LineSpacing.compact)
                        Text("Regular").tag(ReaderSettings.LineSpacing.regular)
                        Text("Relaxed").tag(ReaderSettings.LineSpacing.relaxed)
                    }
                    Picker("Margins", selection: $settings.margins) {
                        Text("Narrow").tag(ReaderSettings.Margins.narrow)
                        Text("Regular").tag(ReaderSettings.Margins.regular)
                        Text("Wide").tag(ReaderSettings.Margins.wide)
                    }
                }
            }
            if showsCommentSettings {
                Section {
                    Toggle("Show Comments", isOn: $settings.showsComments)
                    NavigationLink {
                        HiddenCommentersView()
                    } label: {
                        LabeledContent("Hidden Commenters") {
                            // A count only when there's someone to count.
                            let hidden = settings.hiddenCommenters.values.reduce(0) { $0 + $1.count }
                            if hidden > 0 {
                                Text(hidden, format: .number)
                            }
                        }
                    }
                } header: {
                    Text("Comments")
                } footer: {
                    Text("Comments come from each site and are read-only. To report one, use its menu to open it on its site.")
                }
            }
            Section {
                // Not destructive: nothing is lost but a few choices.
                Button("Reset Appearance") {
                    settings.reset()
                }
            }
        }
    }
}

/// Smaller and larger text buttons either side of the current size.
private struct TextSizeControl: View {
    @Environment(ReaderSettings.self) private var settings

    var body: some View {
        HStack(spacing: 12) {
            Button("Smaller Text", systemImage: "textformat.size.smaller") {
                settings.makeTextSmaller()
            }
            .disabled(!settings.canMakeTextSmaller)
            Spacer()
            Text(settings.fontScale, format: .percent.precision(.fractionLength(0)))
                .font(.body.monospacedDigit())
                .contentTransition(.numericText(value: settings.fontScale))
                .animation(.snappy, value: settings.fontScale)
            Spacer()
            Button("Larger Text", systemImage: "textformat.size.larger") {
                settings.makeTextLarger()
            }
            .disabled(!settings.canMakeTextLarger)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .controlSize(.large)
    }
}

/// The four themes as page swatches.
private struct ThemePicker: View {
    @Binding var selection: ReaderPreferences.Theme

    var body: some View {
        HStack {
            ForEach(ReaderPreferences.Theme.allCases, id: \.self) { theme in
                ThemeSwatch(theme: ReaderTheme(theme), isSelected: theme == selection)
                    .onTapGesture { selection = theme }
                    .accessibilityAddTraits(theme == selection ? [.isButton, .isSelected] : .isButton)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ThemeSwatch: View {
    let theme: ReaderTheme
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 6) {
            Text("Aa")
                .font(.system(.title3, design: .serif))
                .foregroundStyle(theme.text)
                .frame(width: 56, height: 56)
                .background(theme.background, in: .circle)
                .overlay {
                    Circle()
                        .strokeBorder(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.separator), lineWidth: isSelected ? 3 : 1)
                }
            Text(theme.name)
                .font(.caption)
                .foregroundStyle(isSelected ? .primary : .secondary)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}
