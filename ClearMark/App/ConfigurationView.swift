import SwiftUI

private let accent = Color(red: 0.17, green: 0.43, blue: 0.34)

struct ConfigurationView: View {
    @ObservedObject var model: SettingsModel
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 16) {
                Image(nsImage: NSApplication.shared.applicationIconImage).resizable().frame(width: 70, height: 70)
                VStack(alignment: .leading, spacing: 6) {
                    Text("ClearMark").font(.system(size: 25, weight: .semibold))
                    Text(model.text("Markdown. Just press Space.")).font(.system(size: 14)).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "space").font(.system(size: 26, weight: .light))
                    .foregroundStyle(accent).frame(width: 56, height: 44)
                    .background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
                    .accessibilityLabel(model.text("Space bar"))
            }
            VStack(alignment: .leading, spacing: 12) {
                Label(model.text("Install once. Preview whenever."), systemImage: "sparkle").font(.system(size: 13, weight: .semibold)).foregroundStyle(accent)
                Text(model.text("Select a Markdown file in Finder and press Space. You can quit this app — Quick Look keeps working."))
                    .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 14) {
                    Text(model.text("If needed, enable ClearMark Preview in System Settings → Extensions → Quick Look."))
                        .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button(model.text("Quick Look Setup"), action: model.openExtensionSettings).controlSize(.small)
                }
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(accent.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 10) {
                Text(model.text("Reading")).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                VStack(spacing: 10) {
                    settingRow("Language") {
                        Picker(model.text("Language"), selection: $model.settings.language) {
                            Text(model.text("Follow system")).tag(InterfaceLanguage.system)
                            Text("English").tag(InterfaceLanguage.english)
                            Text("简体中文").tag(InterfaceLanguage.chinese)
                        }.labelsHidden().frame(width: 170)
                    }
                    settingRow("Appearance") {
                        Picker(model.text("Appearance"), selection: $model.settings.theme) {
                            Text(model.text("Follow system")).tag(PreviewTheme.system)
                            Text(model.text("Light")).tag(PreviewTheme.light)
                            Text(model.text("Dark")).tag(PreviewTheme.dark)
                            Text(model.text("Paper")).tag(PreviewTheme.paper)
                        }.labelsHidden().frame(width: 170)
                    }
                    settingRow("Text size") {
                        Text("\(Int(model.settings.fontSize)) pt").monospacedDigit().foregroundStyle(.secondary)
                        Stepper(model.text("Text size"), value: $model.settings.fontSize, in: 13...24, step: 1).labelsHidden()
                    }
                    toggleRow("Wide layout", isOn: $model.settings.wide)
                    toggleRow("Document outline", isOn: $model.settings.showOutline)
                }.padding(14).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                Text(model.text("Rendering")).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary).padding(.top, 6)
                VStack(spacing: 10) {
                    toggleRow("Code highlighting", isOn: $model.settings.highlightCode)
                    toggleRow("Math formulas", isOn: $model.settings.renderMath)
                    toggleRow("Mermaid diagrams", isOn: $model.settings.renderDiagrams)
                }.padding(14).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                Text(model.text("Only the features a document needs are loaded. Everything renders offline."))
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.toggleStyle(.switch).controlSize(.small).font(.system(size: 12))

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.text("Changes apply the next time you open a preview.")).font(.system(size: 11)).foregroundStyle(.secondary)
                    Text(model.text("No background app. No account. Free forever.")).font(.system(size: 10)).foregroundStyle(.tertiary)
                }
                Spacer()
                Button(model.text("Reset"), action: model.reset).buttonStyle(.link).font(.system(size: 11))
            }
        }
        .padding(28).frame(width: 580)
        .background(Color(nsColor: .windowBackgroundColor)).tint(accent)
        .alert(model.text("Couldn’t save settings"), isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button(model.text("OK"), role: .cancel) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }

    private func settingRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(model.text(title))
            Spacer()
            content()
        }.frame(minHeight: 20)
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        settingRow(title) {
            Toggle(model.text(title), isOn: isOn).labelsHidden()
        }
    }

}
