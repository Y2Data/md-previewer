import SwiftUI
import AppKit

@main
struct ClearMarkApp: App {
    @StateObject private var model = WorkspaceModel()

    var body: some Scene {
        Window("ClearMark", id: "reader") {
            ReaderView(model: model)
                .frame(minWidth: 760, minHeight: 520)
                .onOpenURL { model.open($0) }
        }
        .defaultSize(width: 1160, height: 820)
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open…", action: model.chooseFile).keyboardShortcut("o")
                Menu("Open Recent") {
                    ForEach(model.recents) { recent in Button(recent.name) { model.openRecent(recent) } }
                    Divider()
                    Button("Clear Recent Documents", action: model.clearRecents).disabled(model.recents.isEmpty)
                }
                Button("Allow Images from Folder…", action: model.allowImageFolder).disabled(model.document.url == nil)
            }
            CommandGroup(replacing: .saveItem) {
                Button("Export PDF…", action: model.exportPDF).keyboardShortcut("e", modifiers: [.command, .shift])
                Button("Export HTML…", action: model.exportHTML)
            }
            CommandGroup(replacing: .printItem) {
                Button("Print…", action: model.printDocument).keyboardShortcut("p")
            }
            CommandGroup(after: .textEditing) {
                Button("Find in Document…") { model.showFind = true }.keyboardShortcut("f")
                Button("Find Next") { model.find() }.keyboardShortcut("g")
                Button("Find Previous") { model.find(backwards: true) }.keyboardShortcut("g", modifiers: [.command, .shift])
                Divider()
                Button("Copy Markdown", action: model.copyMarkdown).keyboardShortcut("c", modifiers: [.command, .shift])
            }
            CommandGroup(after: .toolbar) {
                ForEach(Array(ReadingMode.allCases.enumerated()), id: \.element) { index, mode in
                    Button(mode.rawValue) { model.mode = mode }.keyboardShortcut(KeyEquivalent(Character(String(index + 1))))
                }
                Divider()
                Button("Increase Text Size") { model.adjustFont(by: 1) }.keyboardShortcut("+")
                Button("Decrease Text Size") { model.adjustFont(by: -1) }.keyboardShortcut("-")
                Button("Reset Text Size") { model.fontSize = 17 }.keyboardShortcut("0")
            }
            CommandGroup(replacing: .help) {
                Button("ClearMark on GitHub") { NSWorkspace.shared.open(URL(string: "https://github.com/Y2Data/md-previewer")!) }
                Button("Quick Look Setup") { NSWorkspace.shared.open(URL(string: "https://github.com/Y2Data/md-previewer#finder-quick-look")!) }
            }
        }
    }
}
