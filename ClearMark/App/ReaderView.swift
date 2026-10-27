import SwiftUI
import WebKit

private let accent = Color(red: 0.16, green: 0.43, blue: 0.36)

struct ReaderView: View {
    @ObservedObject var model: WorkspaceModel
    @State private var sidebar: NavigationSplitViewVisibility = .all
    @State private var targeted = false
    @State private var selectedHeading: String?
    @FocusState private var findFocused: Bool

    var body: some View {
        NavigationSplitView(columnVisibility: $sidebar) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "doc.richtext").font(.system(size: 23, weight: .medium)).foregroundStyle(accent)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("ClearMark").font(.system(size: 16, weight: .semibold))
                        Text("A little clarity for your words.").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 20).padding(.top, 24).padding(.bottom, 26)

                Button(action: model.chooseFile) {
                    HStack {
                        Image(systemName: "folder")
                        Text("Open document")
                        Spacer()
                        Text("⌘O").foregroundStyle(.tertiary)
                    }.padding(.vertical, 8).padding(.horizontal, 10)
                }
                .buttonStyle(.plain).background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 7))
                .padding(.horizontal, 14)

                HStack {
                    Text("CONTENTS").font(.system(size: 10, weight: .semibold)).tracking(1.5)
                    Spacer()
                    Text("\(model.outline.count)").font(.system(size: 10, design: .monospaced))
                }.foregroundStyle(.secondary).padding(.horizontal, 22).padding(.top, 28).padding(.bottom, 9)

                ScrollView {
                    VStack(alignment: .leading, spacing: 3) {
                        if model.outline.isEmpty {
                            Text("Headings will appear here.").font(.system(size: 12)).foregroundStyle(.tertiary).padding(10)
                        }
                        ForEach(model.outline) { item in
                            Button {
                                selectedHeading = item.id
                                if model.mode == .source { model.mode = .read }
                                model.preview.scroll(to: item.id)
                            } label: {
                                HStack(spacing: 8) {
                                    if item.level <= 2 { Circle().fill(item.id == selectedHeading ? accent : Color.secondary.opacity(0.3)).frame(width: 4, height: 4) }
                                    Text(item.title).font(.system(size: 12, weight: item.id == selectedHeading ? .semibold : .regular)).lineLimit(2)
                                    Spacer(minLength: 0)
                                }
                                .foregroundStyle(item.id == selectedHeading ? accent : .primary.opacity(item.level > 2 ? 0.6 : 0.85))
                                .padding(.leading, CGFloat(max(0, item.level - 2) * 12 + 12)).padding(.trailing, 8).padding(.vertical, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .background(item.id == selectedHeading ? accent.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 6))
                        }
                    }.padding(.horizontal, 12)
                }

                if !model.recents.isEmpty {
                    Divider().padding(.horizontal, 20).padding(.vertical, 14)
                    Text("RECENT").font(.system(size: 10, weight: .semibold)).tracking(1.5).foregroundStyle(.secondary).padding(.horizontal, 22)
                    VStack(spacing: 2) {
                        ForEach(model.recents.prefix(3)) { item in
                            Button { model.openRecent(item) } label: {
                                Label(item.name, systemImage: "doc.text").font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading).padding(8)
                            }.buttonStyle(.plain).help(item.path)
                        }
                    }.padding(.horizontal, 14).padding(.vertical, 8)
                }

                HStack(spacing: 6) {
                    Image(systemName: "leaf").font(.system(size: 11))
                    Text("Local. Private. Yours.").font(.system(size: 10))
                }.foregroundStyle(.tertiary).padding(22)
            }
            .navigationSplitViewColumnWidth(min: 210, ideal: 238, max: 300)
        } detail: {
            VStack(spacing: 0) {
                if model.showFind { findBar }
                HSplitView {
                    if model.mode != .read {
                        ScrollView([.vertical, .horizontal]) {
                            Text(model.document.text)
                                .font(.system(size: max(12, model.fontSize - 3), design: .monospaced))
                                .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .topLeading).padding(28)
                        }
                        .frame(minWidth: 240, maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(nsColor: .textBackgroundColor))
                    }
                    // Keep WebKit mounted so switching modes preserves rendering and scroll position.
                    WebPreview(webView: model.preview.webView)
                        .frame(minWidth: model.mode == .source ? 0 : 280, maxWidth: model.mode == .source ? 0 : .infinity, maxHeight: .infinity)
                        .opacity(model.mode == .source ? 0 : 1)
                        .accessibilityHidden(model.mode == .source)
                }
                Divider()
                statusBar
            }
            .background(readerBackground)
            .navigationTitle(model.document.title)
            .toolbar { toolbar }
        }
        .tint(accent)
        .preferredColorScheme(model.theme == .dark ? .dark : model.theme == .light || model.theme == .paper ? .light : nil)
        .overlay {
            if targeted {
                RoundedRectangle(cornerRadius: 12).fill(accent.opacity(0.08)).overlay {
                    RoundedRectangle(cornerRadius: 12).strokeBorder(accent, style: StrokeStyle(lineWidth: 2, dash: [7]))
                    Label("Drop a Markdown document", systemImage: "doc.badge.plus").font(.title2).padding(28).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }.padding(10).allowsHitTesting(false)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { Task { @MainActor in model.open(url) } }
            }
            return true
        }
        .alert("Couldn’t complete that action", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
        .onChange(of: model.showFind) { _, shown in if shown { findFocused = true; if model.mode == .source { model.mode = .read } } }
        .onChange(of: model.document.url) { _, _ in selectedHeading = nil }
    }

    private var readerBackground: Color {
        switch model.theme {
        case .paper: return Color(red: 0.975, green: 0.956, blue: 0.916)
        default: return Color(nsColor: .textBackgroundColor)
        }
    }

    private var findBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Find in document", text: $model.query).textFieldStyle(.plain).focused($findFocused).onSubmit { model.find() }
                .onChange(of: model.query) { _, _ in model.find() }
            Button { model.find(backwards: true) } label: { Image(systemName: "chevron.up") }.help("Previous match (⇧⌘G)")
            Button { model.find() } label: { Image(systemName: "chevron.down") }.help("Next match (⌘G)")
            Button("Done") { model.showFind = false; model.preview.find("") }.keyboardShortcut(.escape, modifiers: [])
        }.padding(.horizontal, 20).padding(.vertical, 10).background(.bar)
    }

    private var statusBar: some View {
        HStack(spacing: 14) {
            Label(model.reloadIssue ?? (model.document.url == nil ? "Sample document" : "Live preview"), systemImage: model.reloadIssue != nil ? "exclamationmark.circle" : "circle.fill")
                .foregroundStyle(model.reloadIssue != nil ? Color.orange : .secondary)
            Spacer()
            Text("\(model.document.wordCount.formatted()) words")
            Text("\(model.document.readingMinutes) min read")
            Rectangle().fill(.quaternary).frame(width: 1, height: 11)
            Text("Markdown").foregroundStyle(accent)
        }.font(.system(size: 10)).foregroundStyle(.secondary).padding(.horizontal, 20).frame(height: 31).background(.bar)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Picker("View mode", selection: $model.mode) {
                ForEach(ReadingMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).frame(width: 185).help("Read, split, or source (⌘1–3)")
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button { model.showFind.toggle() } label: { Image(systemName: "magnifyingglass") }.help("Find in document (⌘F)")
            Menu {
                Picker("Appearance", selection: $model.theme) { ForEach(ReaderTheme.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                Divider()
                Button("Larger Text") { model.adjustFont(by: 1) }
                Button("Smaller Text") { model.adjustFont(by: -1) }
                Button("Reset Text Size") { model.fontSize = 17 }
                Divider()
                Toggle("Wide Layout", isOn: $model.wide)
            } label: { Image(systemName: "textformat.size") }.help("Reading appearance")
            Menu {
                Button("Export PDF…", action: model.exportPDF)
                Button("Export HTML…", action: model.exportHTML)
                Divider()
                Button("Copy Markdown", action: model.copyMarkdown)
                if let url = model.document.url { ShareLink(item: url) }
            } label: { Image(systemName: "square.and.arrow.up") }.help("Export and share").disabled(model.exporting)
        }
    }
}

private struct WebPreview: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
