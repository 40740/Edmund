import SwiftUI
import AppKit

struct AdvancedSettingsView: View {
    @AppStorage(AppSettings.Key.automaticallyChecksForUpdates)
    private var autoCheckUpdates = true
    @AppStorage(AppSettings.Key.blockExternalImages) private var blockExternalImages = true
    @AppStorage(AppSettings.Key.diagnosticLogging) private var diagnosticLogging = false
    @AppStorage(AppSettings.Key.verboseEditorDiagnostics) private var verboseEditorDiagnostics = false
    @AppStorage(AppSettings.Key.logRetention) private var logRetention = AppSettings.LogRetention.twoWeeks
    // Crash-log sending is dormant until the receiving server exists — the toggle
    // is hidden (commented out below) so it isn't offered with nowhere to send to.
    // Uncomment this and the "Crash reports:" GridRow once the server is live.
    // @AppStorage(AppSettings.Key.sendCrashLogs) private var sendCrashLogs = false

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, verticalSpacing: 18) {
            GridRow {
                Text("软件更新:")
                    .gridColumnAlignment(.trailing)
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("自动检查更新", isOn: $autoCheckUpdates)
                }
            }
            
            GridRow {
                Divider().gridCellColumns(2)
            }
            
            GridRow {
                Text("隐私与安全:")
                    .gridColumnAlignment(.trailing)
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("阻止外部图片", isOn: $blockExternalImages)
                        .onChange(of: blockExternalImages) { refreshOpenReadViews() }
                    // Parsed rather than left to `Text`'s own literal markdown
                    // handling, so `settingsLinkTinted()` can bring the link in
                    // line with every other link in Settings.
                    Text(AttributedString(
                        inlineMarkdown: "具体的安全影响请参阅[此提案](https://github.com/opencloud-eu/opencloud/issues/1145)。"
                    ).settingsLinkTinted())
                        .foregroundStyle(.secondary)
                        .controlSize(.small)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: 380, alignment: .leading)
                        .padding(.leading, 20)
                        
                    // TODO: Add a "Enable HTTP whitelist" toggle here
                    // with a short scrollable view of the whitelist that allows user addition
                    // with +/- signs at the bottom-right corner
                    // Implement later
                }
            }

            GridRow {
                Divider().gridCellColumns(2)
            }

            GridRow {
                Text("诊断:")
                    .gridColumnAlignment(.trailing)
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("保存诊断日志", isOn: $diagnosticLogging)
                        .onChange(of: diagnosticLogging) { AppSettings.applyLogging() }
                    HStack(spacing: 6) {
                        Text("日志保留时长:")
                        Picker("", selection: $logRetention) {
                            ForEach(AppSettings.LogRetention.allCases) { Text($0.label).tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize()
                        .onChange(of: logRetention) { AppSettings.applyLogging() }
                    }
                    .disabled(!diagnosticLogging)
                    .padding(.leading, 20)
                    Text("日志保存在本地 ~/.edmund/logs 文件夹,除非你主动移动,否则不会离开该文件夹。它们仅在你需要改进错误报告 / GitHub issue 时有用。")
                        .foregroundStyle(.secondary)
                        .controlSize(.small)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: 380, alignment: .leading)
                        .padding(.leading, 20)
                    Toggle("详细编辑器跟踪", isOn: $verboseEditorDiagnostics)
                        .onChange(of: verboseEditorDiagnostics) { AppSettings.applyLogging() }
                        .disabled(!diagnosticLogging)
                        .padding(.leading, 20)
                    Text("记录每次按键、光标移动和同步——用于重现棘手的编辑器 bug（光标漂移）。信息量很大;除非需要,请保持关闭。")
                        .foregroundStyle(.secondary)
                        .controlSize(.small)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: 360, alignment: .leading)
                        .padding(.leading, 40)
}
            }

            // Dormant until the crash-report server exists (see note above and
            // CrashReporter). The launch-time upload path and the `sendCrashLogs`
            // setting stay in place but inert (default off); only this UI is hidden.
            // GridRow {
            //     Text("Crash reports:")
            //         .gridColumnAlignment(.trailing)
            //     VStack(alignment: .leading, spacing: 6) {
            //         Toggle("Automatically send crash logs", isOn: $sendCrashLogs)
            //         Text("Crash logs are sent only to us and will be used and stored for crash fix purposes only.")
            //             .foregroundStyle(.secondary)
            //             .controlSize(.small)
            //             .fixedSize(horizontal: false, vertical: true)
            //             .frame(width: 380, alignment: .leading)
            //             .padding(.leading, 20)
            //     }
            // }
        }
        .settingsPanePadding()
    }

    /// Pushes the toggle to every open document's editor (Edit mode's inline
    /// image overlay) and Read view, so the change takes effect immediately.
    private func refreshOpenReadViews() {
        for case let document as Document in NSDocumentController.shared.documents {
            document.editor?.allowRemoteImages = !blockExternalImages
            document.refreshReadView()
        }
    }
}
