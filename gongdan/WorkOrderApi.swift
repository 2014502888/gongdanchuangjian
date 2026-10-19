import Foundation

/// 下工单网络层：同工号两用（复用 Neiwang 的 sessionId + xmToken）
/// 流程：getMailDetail → getMailType → checkWorkOrderCreate → checkMailTicketHistory → submitWorkOrder
/// ⚠️ URL 为按 Python 参考实现（inner_repo.py）推断的模型，待抓包校准后替换（见 TODO）
final class WorkOrderApi {

    static let shared = WorkOrderApi()
    private let baseURL = "http://211.156.201.20:8012"
    private let userId = "E00000097801"   // 同工号两用：与 Neiwang 的查询工号一致
    private let from = "xm"

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        return URLSession(configuration: config)
    }()

    private var sessionId: String { NeiwangHarConfig.shared.sessionId }

    // MARK: - 邮件详情（收件人/寄件人省市区代码）

    /// 返回 recvrProCode/recvrCityCode/senderProCode/senderCityCode
    func getMailDetail(mailNo: String) async throws -> [String: Any] {
        // TODO: 抓包校准 URL
        let url = "\(baseURL)/so-novel-biz/mail/getMailDetail?userId=\(userId)&from=\(from)"
        let body: [String: Any] = ["userId": userId, "from": from, "mailNo": mailNo, "webType": "creation_create"]
        return try await post(url, body: body, uaOf: .ios)
    }

    // MARK: - 邮件类型（客服标准 mailType/serviceType/mailTypeName/serviceTypeName）

    func getMailType(mailNo: String) async throws -> [String: Any] {
        // TODO: 抓包校准 URL
        let url = "\(baseURL)/so-novel-biz/mail/getMailType?userId=\(userId)&from=\(from)&mailNo=\(mailNo)"
        return try await post(url, body: [String: Any](), uaOf: .ios)
    }

    // MARK: - 校验是否允许创建工单

    /// body 参考 inner_repo.py check_work_order_create
    func checkWorkOrderCreate(mailNo: String, appealType: String, bizType: String,
                              mailType: String, inoutFlag: String,
                              detail: [String: Any]) async throws -> Bool {
        // TODO: 抓包校准 URL
        let url = "\(baseURL)/so-novel-biz/workOrder/checkWorkOrderCreate?userId=\(userId)&from=\(from)"
        var body: [String: Any] = [
            "configCreateType": "3,4,5",
            "appealType": appealType,
            "bizType": bizType,
            "appealFrom": "21",
            "mailNo": mailNo,
            "mailType": mailType,
            "inoutFlag": inoutFlag,
            "contactsNo": "",
            "groupTypeId": "1",
            "deliveryProvince": detail["recvrProCode"] ?? "",
            "deliveryCity": detail["recvrCityCode"] ?? "",
            "arriveCity": detail["recvrCityCode"] ?? "",
            "arriveProvince": detail["recvrProCode"] ?? "",
            "postProvince": detail["senderProCode"] ?? "",
            "postCity": detail["senderCityCode"] ?? "",
            "innerName": "",
            "webType": "creation_create",
            "originalDelivery": "",
            "sendGround": "",
            "serviceType": ""
        ]
        if let v = detail["recvrProCode"] as? String { body["deliveryProvince"] = v }
        if let v = detail["recvrCityCode"] as? String { body["deliveryCity"] = v; body["arriveCity"] = v }
        if let v = detail["recvrProCode"] as? String { body["arriveProvince"] = v }
        if let v = detail["senderProCode"] as? String { body["postProvince"] = v }
        if let v = detail["senderCityCode"] as? String { body["postCity"] = v }

        let json = try await post(url, body: body, uaOf: .ios)
        let code = json["code"] as? Int
        if code == 0 {
            return (json["data"] as? Bool) ?? false
        }
        let msg = json["msg"] as? String ?? ""
        if msg.contains("session") || msg.contains("验证") {
            throw SessionExpiredError(message: msg)
        }
        throw WorkOrderError(msg.isEmpty ? "校验工单失败" : msg)
    }

    // MARK: - 校验是否已存在同类型工单

    /// 返回 (allowed, msg, ticketId)
    func checkMailTicketHistory(mailNo: String, appealType: String, bizType: String,
                                mailType: String, inoutFlag: String) async throws -> (Bool, String, String) {
        // TODO: 抓包校准 URL
        let url = "\(baseURL)/so-novel-biz/workOrder/checkMailTicketHistory?userId=\(userId)&from=\(from)"
        let body: [String: Any] = [
            "userId": userId,
            "from": from,
            "mailNo": mailNo,
            "mailType": mailType,
            "appealType": appealType,
            "bizType": bizType,
            "serviceType": "appealworkflow",
            "inoutFlag": inoutFlag,
            "appealFrom": "21",
            "webType": "creation_create",
            "urgentDegree": 2
        ]
        let json = try await post(url, body: body, uaOf: .ios)
        let code = json["code"] as? Int
        if code == 0 {
            let inner = json["data"] as? [String: Any] ?? [:]
            let successStr = String(describing: inner["success"] ?? "").lowercased()
            let ticketId = inner["ticketId"] as? String ?? ""
            let errorMsg = inner["errorMsg"] as? String ?? ""
            if successStr == "true" {
                return (true, "允许创建工单", "")
            }
            return (false, errorMsg.isEmpty ? "此邮件已存在该投诉类型的工单" : errorMsg, ticketId)
        }
        let msg = json["msg"] as? String ?? ""
        if msg.contains("session") || msg.contains("验证") {
            throw SessionExpiredError(message: msg)
        }
        throw WorkOrderError(msg.isEmpty ? "校验工单历史失败" : msg)
    }

    // MARK: - 提交工单

    func submitWorkOrder(mailNo: String, appealType: String, bizType: String,
                         mailType: String, inoutFlag: String,
                         innerName: String, innerCount: String, innerDetail: String,
                         packageFeature: String, senderPhone: String, recverPhone: String) async throws -> String {
        // TODO: 抓包校准 URL
        let url = "\(baseURL)/so-novel-biz/workOrder/submitWorkOrder?userId=\(userId)&from=\(from)"
        let body: [String: Any] = [
            "userId": userId,
            "from": from,
            "mailNo": mailNo,
            "mailType": mailType,
            "appealType": appealType,
            "bizType": bizType,
            "serviceType": "appealworkflow",
            "inoutFlag": inoutFlag,
            "innerName": innerName,
            "innerCount": innerCount,
            "innerDetail": innerDetail,
            "packageFeature": packageFeature,
            "senderPhone": senderPhone,
            "recverPhone": recverPhone
        ]
        let json = try await post(url, body: body, uaOf: .ios)
        let code = json["code"] as? Int
        if code == 0 || (json["success"] as? Bool) == true {
            return json["msg"] as? String ?? "工单提交成功"
        }
        let msg = json["msg"] as? String ?? ""
        if msg.contains("session") || msg.contains("验证") {
            throw SessionExpiredError(message: msg)
        }
        throw WorkOrderError(msg.isEmpty ? "工单提交失败" : msg)
    }

    // MARK: - 底层 POST（headers 与 Neiwang 一致：iOS 形态）

    private func post(_ urlString: String, body: [String: Any], uaOf mode: UAMode) async throws -> [String: Any] {
        guard let url = URL(string: urlString) else { throw WorkOrderError("URL错误") }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json;charset=UTF-8", forHTTPHeaderField: "Content-Type")
        let cfg = NeiwangHarConfig.shared
        if !cfg.userAgent.isEmpty {
            request.setValue(cfg.userAgent, forHTTPHeaderField: "User-Agent")
        }
        request.setValue("http://211.156.201.20:8012", forHTTPHeaderField: "Origin")
        if cfg.isIOS || mode == .ios {
            request.setValue("http://211.156.201.20:8012/so-novel-xm/", forHTTPHeaderField: "Referer")
            request.setValue("zh-CN,zh-Hans;q=0.9", forHTTPHeaderField: "Accept-Language")
        } else {
            request.setValue("http://211.156.201.20:8012/sowebx/", forHTTPHeaderField: "Referer")
            request.setValue("com.holly.android.holly.uc_test", forHTTPHeaderField: "X-Requested-With")
            request.setValue("zh-CN,zh;q=0.9,en-US;q=0.8,en;q=0.7", forHTTPHeaderField: "Accept-Language")
        }
        let token = try await Neiwang.shared.getToken()
        request.setValue("sessionId=\(sessionId); xmToken=\(token)", forHTTPHeaderField: "Cookie")
        if !body.isEmpty {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw WorkOrderError("HTTP错误")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw WorkOrderError("响应解析失败")
        }
        // 会话失效检测（与 Neiwang.query 一致）
        if let msg = json["msg"] as? String,
           msg.contains("登录") || msg.contains("会话") || msg.contains("失效") || msg.contains("过期") || msg.contains("未登录") {
            throw SessionExpiredError(message: msg)
        }
        return json
    }

    private enum UAMode { case ios, android }
}

/// 工单业务错误（非会话失效）
struct WorkOrderError: Error, LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
