import Foundation

/// 下工单网络层：同工号两用（复用 Neiwang 的 sessionId + xmToken + userId）
/// 流程（已按 2026-10-20 安卓抓包校准）：
///   getMailDetailInfo → getMailTypeByMailNo → getMailFeatureMessage
///   → checkMailNoTicketHistory → isOrTicketCreateCondsConfigValidSuceess → (提交接口待补抓)
/// 字典：getAppType(投诉类型两级) / dictionaryData(收寄人类型) / getPCCById(省市县) / getPoint(动态表单字段)
final class WorkOrderApi {

    static let shared = WorkOrderApi()
    private let baseURL = "http://211.156.201.20:8012"
    private let from = "xm"

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        return URLSession(configuration: config)
    }()

    private var sessionId: String { NeiwangHarConfig.shared.sessionId }
    private var userId: String { NeiwangHarConfig.shared.userId }

    // MARK: - 邮件详情（收件人/寄件人省市区代码）
    // 抓包：POST /so-novel-biz/mail/getMailDetailInfo?userId=..&from=xm
    // body: {"userId","from","mailNo","webType":"creation_create"}
    func getMailDetail(mailNo: String) async throws -> [String: Any] {
        let url = "\(baseURL)/so-novel-biz/mail/getMailDetailInfo?userId=\(userId)&from=\(from)"
        let body: [String: Any] = ["userId": userId, "from": from, "mailNo": mailNo, "webType": "creation_create"]
        return try await post(url, body: body)
    }

    // MARK: - 邮件类型（mailType/serviceType/mailTypeName/serviceTypeName）
    // 抓包：POST /so-novel-biz/mail/getMailTypeByMailNo?userId=..&from=xm&mailNo=..  （无 body）
    func getMailType(mailNo: String) async throws -> [String: Any] {
        let url = "\(baseURL)/so-novel-biz/mail/getMailTypeByMailNo?userId=\(userId)&from=\(from)&mailNo=\(mailNo)"
        return try await post(url, body: [String: Any]())
    }

    // MARK: - 邮件特征信息（号段特征，判断是否可直接创建）
    // 抓包：POST /so-novel-biz/mail/getMailFeatureMessage?userId=..&from=xm
    // body: {"userId","from","mailNo"} → data{done,msg,ticketId}
    func getMailFeatureMessage(mailNo: String) async throws -> [String: Any] {
        let url = "\(baseURL)/so-novel-biz/mail/getMailFeatureMessage?userId=\(userId)&from=\(from)"
        let body: [String: Any] = ["userId": userId, "from": from, "mailNo": mailNo]
        return try await post(url, body: body)
    }

    // MARK: - 校验是否允许创建工单
    // 抓包：POST /so-novel-biz/baseTicket/isOrTicketCreateCondsConfigValidSuceess?from=xm&userId=..
    func checkWorkOrderCreate(mailNo: String, appealType: String, bizType: String,
                              mailType: String, inoutFlag: String,
                              groupTypeId: String = "1",
                              detail: [String: Any]) async throws -> Bool {
        let url = "\(baseURL)/so-novel-biz/baseTicket/isOrTicketCreateCondsConfigValidSuceess?from=\(from)&userId=\(userId)"
        var body: [String: Any] = [
            "configCreateType": "3,4,5",
            "appealType": appealType,
            "bizType": bizType,
            "appealFrom": "21",
            "mailNo": mailNo,
            "mailType": mailType,
            "inoutFlag": inoutFlag,
            "contactsNo": "",
            "groupTypeId": groupTypeId,
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

        let json = try await post(url, body: body)
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
    // 抓包：POST /so-novel-biz/mail/checkMailNoTicketHistory?from=xm&userId=..
    func checkMailTicketHistory(mailNo: String, appealType: String, bizType: String,
                                mailType: String, inoutFlag: String) async throws -> (Bool, String, String) {
        let url = "\(baseURL)/so-novel-biz/mail/checkMailNoTicketHistory?from=\(from)&userId=\(userId)"
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
        let json = try await post(url, body: body)
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
    // ⚠️ 提交接口未在抓包中出现（抓包止于表单填写），URL 为待定占位，需补抓"提交"动作后替换
    func submitWorkOrder(mailNo: String, appealType: String, bizType: String,
                         mailType: String, inoutFlag: String,
                         innerName: String, innerCount: String, innerDetail: String,
                         packageFeature: String, senderPhone: String, recverPhone: String) async throws -> String {
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
        let json = try await post(url, body: body)
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

    // MARK: - 字典接口（投诉类型 / 收寄人类型 / 省市县 / 表单字段）

    /// 投诉类型两级字典
    /// 抓包：GET /so-novel-biz/dict/getAppType?userId=..&from=xm&type=lw_type_cr&webType=creation_create
    /// data: [{codeId, codeName, parentId, listAppType:[{codeId, codeName}]}]
    func getAppType() async throws -> [[String: Any]] {
        let url = "\(baseURL)/so-novel-biz/dict/getAppType?userId=\(userId)&from=\(from)&type=lw_type_cr&webType=creation_create"
        let json = try await post(url, body: [String: Any]())
        return (json["data"] as? [[String: Any]]) ?? []
    }

    /// 投诉人类型字典（谁投诉的）
    /// 抓包：GET /so-novel-biz/dict/dictionaryData?userId=..&from=xm&dictionaryId=CC.GROUP_TYPE
    /// data: [{name:"收件人",id:"1"},{name:"寄件人",id:"2"},{name:"第三方",id:"5"},{name:"主动客服",id:"9"}]
    func getGroupTypes() async throws -> [[String: Any]] {
        let url = "\(baseURL)/so-novel-biz/dict/dictionaryData?userId=\(userId)&from=\(from)&dictionaryId=CC.GROUP_TYPE"
        let json = try await post(url, body: [String: Any]())
        return (json["data"] as? [[String: Any]]) ?? []
    }

    /// 省市县字典（parentId=0 取省，省 code 取市，市 code 取县）
    /// 抓包：GET /so-novel-biz/dict/getPCCById?userId=..&from=xm&parentId=35&type=os.code.province.city
    /// data: [{codeName:"泉州市", codeValue:"350500"}...]
    func getPCC(parentId: String) async throws -> [[String: Any]] {
        let url = "\(baseURL)/so-novel-biz/dict/getPCCById?userId=\(userId)&from=\(from)&parentId=\(parentId)&type=os.code.province.city"
        let json = try await post(url, body: [String: Any]())
        return (json["data"] as? [[String: Any]]) ?? []
    }

    /// 动态表单字段定义（不同投诉类型字段不同）
    /// 抓包：POST /so-novel-biz/common/getPoint?from=xm&userId=..
    /// body: {"pageName":"innerCustomer","mailType","inoutFlag","appealType","bizType"}
    /// data: [{pointName, pointNameCn, isRequired, isShow}...]
    func getPoint(pageName: String, mailType: String, inoutFlag: String,
                  appealType: String, bizType: String) async throws -> [[String: Any]] {
        let url = "\(baseURL)/so-novel-biz/common/getPoint?from=\(from)&userId=\(userId)"
        let body: [String: Any] = [
            "pageName": pageName,
            "mailType": mailType,
            "inoutFlag": inoutFlag,
            "appealType": appealType,
            "bizType": bizType
        ]
        let json = try await post(url, body: body)
        return (json["data"] as? [[String: Any]]) ?? []
    }

    // MARK: - 底层 POST（headers 与 Neiwang 一致：禁用安卓特征头）

    private func post(_ urlString: String, body: [String: Any]) async throws -> [String: Any] {
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
        request.setValue("http://211.156.201.20:8012/so-novel-xm/", forHTTPHeaderField: "Referer")
        request.setValue("zh-CN,zh-Hans;q=0.9", forHTTPHeaderField: "Accept-Language")
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
}

/// 工单业务错误（非会话失效）
struct WorkOrderError: Error, LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
