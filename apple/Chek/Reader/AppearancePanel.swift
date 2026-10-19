import ChekReader
import SwiftUI

/// Text size, theme, font, spacing and margins, changed while you read.
struct AppearancePanel: View {
    var body: some View {
        NavigationStack {
            ReaderAppearanceForm()
                .navigationTitle("Appearance")
                .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        // The page stays visible behind the panel, so changes show as you make them.
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
    }
}

/// The reading settings, shared by the reader's panel and Settings.
struct ReaderAppearanceForm: View {
    @Environment(ReaderSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                TextSizeControl()
                ThemePicker(selection: $settings.theme)
            }
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
            Section {
                Button("Reset to Original", role: .destructive) {
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
