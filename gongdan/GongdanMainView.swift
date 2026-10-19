import SwiftUI
import UIKit

/// 下工单独立 App 主界面：导入 HAR 会话 → 进入工单申请
struct GongdanMainView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var showWorkOrder = false
    @State private var showImportAlert = false
    @State private var sessionSummary = ""

    private let blue = Color(red: 0.10, green: 0.46, blue: 0.82)

    var body: some View {
        VStack(spacing: 0) {
            // 抬头：居中
            ZStack {
                Text("下工单")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(colorScheme == .dark ? Color.black : Color.white)

            VStack(spacing: 20) {
                // 会话状态卡片
                VStack(alignment: .leading, spacing: 8) {
                    Text("会话状态")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    HStack(spacing: 8) {
                        Circle()
                            .fill(isConfigured ? blue : Color.red)
                            .frame(width: 8, height: 8)
                        Text(isConfigured ? "已导入会话" : "未导入会话")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.primary)
                        Spacer()
                    }
                    if isConfigured {
                        Text("会话：\(sessionSummary)")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    } else {
                        Text("请先导入「醒目」App 抓包文件（HAR），才能提交工单")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(colorScheme == .dark ? Color(UIColor.systemGray6) : Color.white)
                .cornerRadius(12)

                // 导入按钮
                Button {
                    importHar()
                } label: {
                    Text(isConfigured ? "重新导入抓包" : "导入抓包文件")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(blue)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(blue, lineWidth: 1)
                        )
                        .cornerRadius(10)
                }

                // 进入下工单
                Button {
                    if isConfigured {
                        showWorkOrder = true
                    } else {
                        showImportAlert = true
                    }
                } label: {
                    Text("进入下工单")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(blue)
                        .cornerRadius(10)
                }

                Spacer()

                Text("同工号两用：复用醒目登录会话（sessionId），提交工单")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.bottom, 20)
            }
            .padding(.horizontal, 16)
            .padding(.top, 24)
        }
        .background(colorScheme == .dark ? Color.black : Color(UIColor.systemGroupedBackground))
        .sheet(isPresented: $showWorkOrder) {
            WorkOrderView()
        }
        .alert("请先导入抓包", isPresented: $showImportAlert) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text("需要先导入「醒目」App 的 HAR 抓包文件获取会话")
        }
        .onAppear { refreshSummary() }
    }

    private var isConfigured: Bool {
        NeiwangHarConfig.shared.isConfigured
    }

    private func refreshSummary() {
        let sid = NeiwangHarConfig.shared.sessionId
        sessionSummary = sid.isEmpty ? "" : String(sid.prefix(12)) + "…"
    }

    private func importHar() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.delegate = GongdanImportDelegate.shared
        picker.allowsMultipleSelection = false
        UIApplication.shared.windows.first?.rootViewController?.present(picker, animated: true)
    }
}

/// HAR 导入回调（静态单例保持强引用，避免 delegate 释放导致选择器无响应）
class GongdanImportDelegate: NSObject, UIDocumentPickerDelegate {
    static let shared = GongdanImportDelegate()
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        NeiwangHarImporter.importHar(from: url)
    }
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        controller.dismiss(animated: true)
    }
}
