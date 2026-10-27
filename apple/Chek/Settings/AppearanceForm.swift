import SwiftUI

/// The app's theme and home screen icon.
struct AppearanceForm: View {
    @Environment(AppearanceSettings.self) private var appearance

    var body: some View {
        Form {
            Section {
                ForEach(AppTheme.allCases) { theme in
                    Button {
                        appearance.theme = theme
                    } label: {
                        LabeledContent {
                            if appearance.theme == theme {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        } label: {
                            Label {
                                Text(theme.name)
                            } icon: {
                                Circle()
                                    .fill(theme.tint)
                                    .frame(width: 22, height: 22)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                    .accessibilityAddTraits(appearance.theme == theme ? .isSelected : [])
                }
            } header: {
                Text("Theme")
            } footer: {
                Text("The color of buttons, links and selections throughout Chek.")
            }
            if appearance.canChangeIcon {
                Section {
                    ForEach(AppIcon.allCases) { icon in
                        Button {
                            Task { await appearance.setIcon(icon) }
                        } label: {
                            LabeledContent {
                                if appearance.icon == icon {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            } label: {
                                Label {
                                    Text(icon.name)
                                } icon: {
                                    Image(icon.previewImageName)
                                        .resizable()
                                        .frame(width: 44, height: 44)
                                        .clipShape(.rect(cornerRadius: 10))
                                        .accessibilityHidden(true)
                                }
                                .labelStyle(AppIconLabelStyle())
                            }
                        }
                        .foregroundStyle(.primary)
                        .accessibilityAddTraits(appearance.icon == icon ? .isSelected : [])
                    }
                } header: {
                    Text("App Icon")
                } footer: {
                    Text("The icon on your Home Screen. Chibi Manga’s cat can stay with any theme.")
                }
            }
        }
    }
}

/// A label with an icon larger than a form's usual symbol, for the app
/// icon previews.
private struct AppIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 14) {
            configuration.icon
            configuration.title
        }
    }
}
