import SwiftUI
import UIKit

/// 下工单申请页：同工号两用（复用内网查询的 sessionId + userId）
/// 流程（已按 2026-10-20 安卓抓包校准）：
///   详情 → 类型 → 特征 → 校验 → 查重 → 提交
struct WorkOrderView: View {
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.colorScheme) private var colorScheme

    // 单号 + 投诉类型（两级，来自 getAppType 字典）
    @State private var mailNo = ""
    @State private var appealTypeId = ""      // 一级 codeId（如 CR_XQ）
    @State private var bizTypeId = ""         // 二级 codeId（如 CR_XQ006）
    @State private var appealOptions: [[String: Any]] = []
    @State private var bizOptions: [[String: Any]] = []
    @State private var groupTypeId = "1"      // 收寄人类型（收件人1/寄件人2/第三方5/主动客服9）
    @State private var groupOptions: [[String: Any]] = []

    // 服务端带出的邮件类型
    @State private var mailType = ""
    @State private var inoutFlag = ""
    @State private var mailTypeName = ""
    @State private var serviceTypeName = ""
    @State private var typeFetched = false

    // 内件信息（字段名对齐 getPoint：senderPhone/senderName/recverName/recverAddr/recverPhone/innerCount/innerName）
    @State private var innerName = ""
    @State private var innerCount = ""
    @State private var senderName = ""
    @State private var senderPhone = ""
    @State private var recverName = ""
    @State private var recverPhone = ""
    @State private var recverAddr = ""

    // 状态
    @State private var isWorking = false
    @State private var progressLog: [String] = []
    @State private var showResult = false
    @State private var resultOK = false
    @State private var resultMsg = ""
    @State private var showSessionExpired = false

    private let blue = Color(red: 0.10, green: 0.46, blue: 0.82)
    private var isConfigured: Bool { NeiwangHarConfig.shared.isConfigured }

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

                    // 投诉类型（一级）
                    pickerRow("投诉类型", options: appealOptions, nameKey: "codeName", idKey: "codeId",
                              selection: Binding(get: { appealTypeId }, set: { new in
                                  appealTypeId = new
                                  bizTypeId = ""
                                  bizOptions = appealOptions.first { ($0["codeId"] as? String) == new }?["listAppType"] as? [[String: Any]] ?? []
                              }))

                    // 具体原因（二级，跟随一级）
                    if !bizOptions.isEmpty {
                        pickerRow("具体原因", options: bizOptions, nameKey: "codeName", idKey: "codeId",
                                  selection: $bizTypeId)
                    }

                    // 收寄人类型
                    pickerRow("收寄人类型", options: groupOptions, nameKey: "name", idKey: "id", selection: $groupTypeId)

                    // 查询类型按钮
                    Button {
                        Task { await fetchType() }
                    } label: {
                        Text(typeFetched ? "重新查询邮件信息" : "查询邮件信息")
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
                    field("寄件人姓名", text: $senderName, keyboard: .default)
                    field("寄件人手机号", text: $senderPhone, keyboard: .numbersAndPunctuation)
                    field("收件人姓名", text: $recverName, keyboard: .default)
                    field("收件人手机号", text: $recverPhone, keyboard: .numbersAndPunctuation)
                    field("收件人地址", text: $recverAddr, keyboard: .default)

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
        .onAppear { loadDictionaries() }
        .alert(isPresented: $showResult) {
            Alert(title: Text(resultOK ? "提交成功" : "提交失败"),
                  message: Text(resultMsg),
                  dismissButton: .default(Text("确定")))
        }
        .alert("会话已失效", isPresented: $showSessionExpired) {
            Button("重新导入抓包") { presentationMode.wrappedValue.dismiss() }
            Button("知道了", role: .cancel) {}
        } message: {
            Text("当前登录会话已失效，请到主界面重新导入 HAR 抓包")
        }
    }

    // MARK: - 字典加载（投诉类型 / 收寄人类型）
    private func loadDictionaries() {
        guard isConfigured else { return }
        Task {
            do {
                let types = try await WorkOrderApi.shared.getAppType()
                await MainActor.run { appealOptions = types }
                let groups = try await WorkOrderApi.shared.getGroupTypes()
                await MainActor.run { groupOptions = groups }
            } catch {
                // 字典加载失败不阻塞界面（提交/查询时会再提示）
            }
        }
    }

    // MARK: - 邮件信息卡片
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

    private func pickerRow(_ title: String, options: [[String: Any]],
                           nameKey: String, idKey: String, selection: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
            Menu {
                ForEach(Array(options.enumerated()), id: \.offset) { _, opt in
                    let name = opt[nameKey] as? String ?? ""
                    let id = opt[idKey] as? String ?? ""
                    Button(name) { selection.wrappedValue = id }
                }
            } label: {
                HStack {
                    Text(selectedName(options: options, nameKey: nameKey, idKey: idKey, selection: selection.wrappedValue))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .background(colorScheme == .dark ? Color.black : Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(colorScheme == .dark ? Color.white.opacity(0.25) : Color.black.opacity(0.12), lineWidth: 1)
                )
                .cornerRadius(8)
            }
            .disabled(options.isEmpty)
            .opacity(options.isEmpty ? 0.5 : 1)
        }
    }

    private func selectedName(options: [[String: Any]], nameKey: String, idKey: String, selection: String) -> String {
        if selection.isEmpty { return "请选择" }
        for opt in options {
            if (opt[idKey] as? String) == selection {
                return opt[nameKey] as? String ?? "请选择"
            }
        }
        return "请选择"
    }

    // MARK: - 查类型 + 特征信息
    private func fetchType() async {
        isWorking = true
        progressLog = ["查询邮件信息…"]
        do {
            // 1. 类型
            let tj = try await WorkOrderApi.shared.getMailType(mailNo: mailNo.trimmingCharacters(in: .whitespaces))
            if let code = tj["code"] as? Int, code == 0, let inner = tj["data"] as? [String: Any] {
                mailType = inner["mailType"] as? String ?? ""
                inoutFlag = inner["serviceType"] as? String ?? ""
                mailTypeName = inner["mailTypeName"] as? String ?? ""
                serviceTypeName = inner["serviceTypeName"] as? String ?? ""
                typeFetched = true
                progressLog = ["✓ 类型：\(mailTypeName) - \(serviceTypeName)"]
            } else {
                let msg = tj["msg"] as? String ?? "查询失败"
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

            // 3. 特征信息（号段特征，是否可直接创建）
            progressLog.append("3/5 查询邮件特征…")
            let feature = try await WorkOrderApi.shared.getMailFeatureMessage(mailNo: no)
            if let fdata = feature["data"] as? [String: Any] {
                let fmsg = fdata["msg"] as? String ?? "无特征信息"
                if (fdata["done"] as? String) == "true" {
                    progressLog.append("✓ 特征匹配：\(fmsg)")
                } else {
                    progressLog.append("⚠ \(fmsg)")
                }
            } else {
                progressLog.append("⚠ 未返回特征信息")
            }

            // 4. 校验能否创建
            progressLog.append("4/5 校验创建资格…")
            let allowed = try await WorkOrderApi.shared.checkWorkOrderCreate(
                mailNo: no, appealType: appealTypeId, bizType: bizTypeId,
                mailType: mailType, inoutFlag: inoutFlag,
                groupTypeId: groupTypeId, detail: detail)
            if !allowed {
                throw WorkOrderError("不允许创建工单（校验未通过）")
            }
            progressLog.append("✓ 校验通过")

            // 5. 查是否已有同类型工单
            progressLog.append("5/5 检查已有工单…")
            let (canCreate, histMsg, ticketId) = try await WorkOrderApi.shared.checkMailTicketHistory(
                mailNo: no, appealType: appealTypeId, bizType: bizTypeId,
                mailType: mailType, inoutFlag: inoutFlag)
            if !canCreate {
                let extra = ticketId.isEmpty ? "" : "（工单号 \(ticketId)）"
                throw WorkOrderError("\(histMsg)\(extra)")
            }
            progressLog.append("✓ 无重复工单")

            // 6. 提交（接口待补抓校准）
            progressLog.append("提交工单…")
            let okMsg = try await WorkOrderApi.shared.submitWorkOrder(
                mailNo: no, appealType: appealTypeId, bizType: bizTypeId,
                mailType: mailType, inoutFlag: inoutFlag,
                innerName: innerName, innerCount: innerCount, innerDetail: recverAddr,
                packageFeature: "", senderPhone: senderPhone, recverPhone: recverPhone)
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
