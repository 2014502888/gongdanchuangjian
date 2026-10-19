import SwiftUI
import UIKit

/// 下工单申请页：同工号两用（复用内网查询的 sessionId）
/// 流程：填单号 → 查类型 → 填投诉信息 → 提交（五步：detail/type/check/history/submit）
struct WorkOrderView: View {
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.colorScheme) private var colorScheme

    // 单号 + 投诉类型
    @State private var mailNo = ""
    @State private var appealType = ""
    @State private var bizType = ""

    // 服务端带出的邮件类型
    @State private var mailType = ""
    @State private var inoutFlag = ""
    @State private var mailTypeName = ""
    @State private var serviceTypeName = ""
    @State private var typeFetched = false

    // 内件信息
    @State private var innerName = ""
    @State private var innerCount = ""
    @State private var innerDetail = ""
    @State private var packageFeature = ""
    @State private var senderPhone = ""
    @State private var recverPhone = ""

    // 状态
    @State private var isWorking = false
    @State private var progressLog: [String] = []
    @State private var showResult = false
    @State private var resultOK = false
    @State private var resultMsg = ""
    @State private var showSessionExpired = false

    private let blue = Color(red: 0.10, green: 0.46, blue: 0.82)

    var body: some View {
        VStack(spacing: 0) {
            // 抬头：居中（返回按钮占位）
            ZStack {
                Text("下工单")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                HStack {
                    Button {
                        presentationMode.wrappedValue.dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.body)
                            .foregroundColor(blue)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    Spacer()
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
            .background(colorScheme == .dark ? Color.black : Color.white)

            ScrollView {
                VStack(spacing: 12) {
                    // 单号
                    field("单号", text: $mailNo, keyboard: .numbersAndPunctuation)
                    // 投诉类型 / 具体原因（codeId，后续抓包后做下拉选择）
                    field("投诉类型 codeId", text: $appealType, keyboard: .numbersAndPunctuation)
                    field("具体原因 codeId", text: $bizType, keyboard: .numbersAndPunctuation)

                    // 查询类型按钮
                    Button {
                        Task { await fetchType() }
                    } label: {
                        Text(typeFetched ? "重新查询类型" : "查询邮件类型")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(typeFetched ? blue : .white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(typeFetched ? Color.clear : blue)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(typeFetched ? blue : Color.clear, lineWidth: 1)
                            )
                            .cornerRadius(8)
                    }
                    .disabled(isWorking || mailNo.trimmingCharacters(in: .whitespaces).isEmpty)
                    .opacity((isWorking || mailNo.trimmingCharacters(in: .whitespaces).isEmpty) ? 0.5 : 1)

                    if typeFetched {
                        infoCard
                    }

                    Divider().padding(.vertical, 4)

                    field("内件品名", text: $innerName, keyboard: .default)
                    field("内件数量", text: $innerCount, keyboard: .numbersAndPunctuation)
                    field("内件情况", text: $innerDetail, keyboard: .default)
                    field("外包装特征", text: $packageFeature, keyboard: .default)
                    field("寄件人电话", text: $senderPhone, keyboard: .numbersAndPunctuation)
                    field("收件人电话", text: $recverPhone, keyboard: .numbersAndPunctuation)

                    // 提交按钮
                    Button {
                        Task { await submit() }
                    } label: {
                        Text(isWorking ? "提交中…" : "提交工单")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(blue)
                            .cornerRadius(10)
                    }
                    .disabled(isWorking || mailNo.trimmingCharacters(in: .whitespaces).isEmpty)
                    .opacity((isWorking || mailNo.trimmingCharacters(in: .whitespaces).isEmpty) ? 0.5 : 1)
                    .padding(.top, 4)

                    // 进度日志
                    if !progressLog.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(progressLog.reversed(), id: \.self) { line in
                                Text(line)
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(colorScheme == .dark ? Color(UIColor.systemGray6) : Color(UIColor.systemGray6))
                        .cornerRadius(8)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(colorScheme == .dark ? Color.black : Color(UIColor.systemGroupedBackground))
        }
        .navigationBarHidden(true)
        .alert(isPresented: $showResult) {
            Alert(title: Text(resultOK ? "提交成功" : "提交失败"),
                  message: Text(resultMsg),
                  dismissButton: .default(Text("确定")))
        }
        .alert("会话已失效", isPresented: $showSessionExpired) {
            Button("重新导入抓包") { presentationMode.wrappedValue.dismiss() }
            Button("知道了", role: .cancel) {}
        } message: {
            Text("当前登录会话已失效，请到内网查询页重新导入 HAR 抓包")
        }
    }

    // MARK: - 邮件类型卡片
    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !mailTypeName.isEmpty {
                Text("类型：\(mailTypeName)")
                    .font(.system(size: 14))
                    .foregroundColor(.primary)
            }
            if !serviceTypeName.isEmpty {
                Text("服务：\(serviceTypeName)")
                    .font(.system(size: 14))
                    .foregroundColor(.primary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(colorScheme == .dark ? Color(UIColor.systemGray6) : Color.white)
        .cornerRadius(8)
    }

    private func field(_ title: String, text: Binding<String>, keyboard: UIKeyboardType) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
            TextField(title, text: text)
                .keyboardType(keyboard)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .background(colorScheme == .dark ? Color.black : Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(colorScheme == .dark ? Color.white.opacity(0.25) : Color.black.opacity(0.12), lineWidth: 1)
                )
                .cornerRadius(8)
        }
    }

    // MARK: - 查类型
    private func fetchType() async {
        isWorking = true
        progressLog = ["查询邮件类型…"]
        do {
            let json = try await WorkOrderApi.shared.getMailType(mailNo: mailNo.trimmingCharacters(in: .whitespaces))
            let code = json["code"] as? Int
            if code == 0, let inner = json["data"] as? [String: Any] {
                mailType = inner["mailType"] as? String ?? ""
                inoutFlag = inner["serviceType"] as? String ?? ""
                mailTypeName = inner["mailTypeName"] as? String ?? ""
                serviceTypeName = inner["serviceTypeName"] as? String ?? ""
                typeFetched = true
                progressLog = ["✓ 类型：\(mailTypeName) - \(serviceTypeName)"]
            } else {
                let msg = json["msg"] as? String ?? "查询失败"
                typeFetched = false
                progressLog = ["✗ \(msg)"]
            }
        } catch let e as SessionExpiredError {
            showSessionExpired = true
        } catch {
            progressLog = ["✗ \(error.localizedDescription)"]
        }
        isWorking = false
    }

    // MARK: - 提交（五步）
    private func submit() async {
        isWorking = true
        progressLog = []
        let no = mailNo.trimmingCharacters(in: .whitespaces)
        do {
            // 1. 详情（省市区代码）
            progressLog.append("1/5 获取邮件详情…")
            let detail = try await WorkOrderApi.shared.getMailDetail(mailNo: no)
            progressLog.append("✓ 详情获取成功")

            // 2. 类型（若还没查过自动查）
            if mailType.isEmpty || inoutFlag.isEmpty {
                progressLog.append("2/5 查询邮件类型…")
                let tj = try await WorkOrderApi.shared.getMailType(mailNo: no)
                if let code = tj["code"] as? Int, code == 0, let inner = tj["data"] as? [String: Any] {
                    mailType = inner["mailType"] as? String ?? ""
                    inoutFlag = inner["serviceType"] as? String ?? ""
                    mailTypeName = inner["mailTypeName"] as? String ?? ""
                    serviceTypeName = inner["serviceTypeName"] as? String ?? ""
                    typeFetched = true
                    progressLog.append("✓ 类型：\(mailTypeName) - \(serviceTypeName)")
                } else {
                    throw WorkOrderError(tj["msg"] as? String ?? "查询类型失败")
                }
            } else {
                progressLog.append("2/5 类型已就绪")
            }

            // 3. 校验能否创建
            progressLog.append("3/5 校验创建资格…")
            let allowed = try await WorkOrderApi.shared.checkWorkOrderCreate(
                mailNo: no, appealType: appealType, bizType: bizType,
                mailType: mailType, inoutFlag: inoutFlag, detail: detail)
            if !allowed {
                throw WorkOrderError("不允许创建工单（校验未通过）")
            }
            progressLog.append("✓ 校验通过")

            // 4. 查是否已有同类型工单
            progressLog.append("4/5 检查已有工单…")
            let (canCreate, histMsg, ticketId) = try await WorkOrderApi.shared.checkMailTicketHistory(
                mailNo: no, appealType: appealType, bizType: bizType,
                mailType: mailType, inoutFlag: inoutFlag)
            if !canCreate {
                let extra = ticketId.isEmpty ? "" : "（工单号 \(ticketId)）"
                throw WorkOrderError("\(histMsg)\(extra)")
            }
            progressLog.append("✓ 无重复工单")

            // 5. 提交
            progressLog.append("5/5 提交工单…")
            let okMsg = try await WorkOrderApi.shared.submitWorkOrder(
                mailNo: no, appealType: appealType, bizType: bizType,
                mailType: mailType, inoutFlag: inoutFlag,
                innerName: innerName, innerCount: innerCount, innerDetail: innerDetail,
                packageFeature: packageFeature, senderPhone: senderPhone, recverPhone: recverPhone)
            progressLog.append("✓ 提交成功")
            resultOK = true
            resultMsg = okMsg
            showResult = true
        } catch let e as SessionExpiredError {
            showSessionExpired = true
        } catch {
            progressLog.append("✗ \(error.localizedDescription)")
            resultOK = false
            resultMsg = error.localizedDescription
            showResult = true
        }
        isWorking = false
    }
}
