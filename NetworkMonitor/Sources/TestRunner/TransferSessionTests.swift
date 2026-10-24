import Foundation
import NetworkMonitorCore

// MARK: - 局域网互传 · 状态机 / 配对记忆 / 签名 / 错误码

// 测试函数放宽为 internal：由 TransferTests.swift 的 runTransferTests() 跨文件调度。

// MARK: - 状态机

func testSessionMachine() {
    print("\n🧪 Testing TransferSessionMachine 迁移...")

    let legal: [(TransferState, TransferState)] = [
        (.pending, .offering), (.pending, .failed), (.pending, .cancelled),
        (.offering, .awaitingConfirm), (.offering, .transferring),
        (.offering, .failed), (.offering, .cancelled),
        (.awaitingConfirm, .transferring), (.awaitingConfirm, .failed), (.awaitingConfirm, .cancelled),
        (.transferring, .verifying), (.transferring, .failed), (.transferring, .cancelled),
        (.verifying, .completed), (.verifying, .failed), (.verifying, .cancelled),
    ]
    var illegalCount = 0
    for pair in TransferSessionMachine.allTransitions {
        let expected = legal.contains { $0.0 == pair.from && $0.1 == pair.to }
        assertEqual(TransferSessionMachine.canTransition(from: pair.from, to: pair.to), expected,
                    "\(pair.from.rawValue) → \(pair.to.rawValue)")
        if !expected { illegalCount += 1 }
    }
    assertEqual(illegalCount, 64 - legal.count, "穷举 64 种状态对有 \(64 - legal.count) 种非法")

    // 非法迁移抛 4000（illegalTransition），且不改变状态
    assertThrows("completed → transferring", code: 4000) {
        _ = try TransferSessionMachine.transition(.completed, to: .transferring)
    }
    assertThrows("pending → completed", code: 4000) {
        _ = try TransferSessionMachine.transition(.pending, to: .completed)
    }
    assertThrows("failed → completed", code: 4000) {
        _ = try TransferSessionMachine.transition(.failed, to: .completed)
    }
    assertEqual(TransferSessionMachine.allowedTargets(from: .completed).isEmpty, true, "终结态无出口")

    // 会话推进器：正常链路
    let file = TransferFile(fileId: "f1", name: "a.bin", size: 100, sha256: "x")
    var runner = TransferSessionRunner(session: TransferSession(
        id: "s1", direction: .send, peerDeviceId: "and-1", token: "t",
        files: [file], state: .pending, createdAt: Date(timeIntervalSince1970: 0)))
    try? runner.advance(to: .offering)
    try? runner.advance(to: .transferring)
    try? runner.advance(to: .verifying)
    try? runner.advance(to: .completed)
    assertEqual(runner.session.state, .completed, "状态机可推进到完成")
    runner.updateFileProgress(fileId: "f1", transferred: 150)
    assertEqual(runner.session.files[0].transferred, 100, "进度按文件大小收敛")
    runner.updateFileProgress(fileId: "f1", transferred: -5)
    assertEqual(runner.session.files[0].transferred, 0, "负进度收敛为 0")
    assertEqual(runner.allFilesCompleted, false, "归零后未完成")

    // 非法迁移不改状态
    var pendingRunner = TransferSessionRunner(session: TransferSession(
        id: "s2", direction: .recv, peerDeviceId: "and-1", token: "t",
        files: [file], state: .pending, createdAt: Date()))
    do {
        try pendingRunner.advance(to: .completed)
        print("❌ 非法迁移未抛错")
        exit(1)
    } catch let error as TransferError {
        assertEqual(error.code, 4000, "非法迁移错误码")
        assertEqual(pendingRunner.session.state, .pending, "非法迁移后状态不变")
    } catch {
        print("❌ 抛出了非 TransferError")
        exit(1)
    }
}

func testPairingStore() {
    print("\n🧪 Testing PairingStore 配对记忆...")

    let storage = InMemoryStorage()
    let store = PairingStore(storage: storage)
    assertEqual(store.isPaired("and-1"), false, "初始未配对")

    let key = PairingStore.generateKey()
    assertEqual(key.count, 64, "配对 key 为 64 位 hex")
    assertEqual(key.allSatisfy { $0.isHexDigit }, true, "配对 key 仅含 hex 字符")

    store.save(key: key, for: "and-1")
    assertEqual(store.key(for: "and-1"), key, "保存后可读")
    assertEqual(store.isPaired("and-1"), true, "配对标记")

    // 持久化：新实例读同一份存储
    let second = PairingStore(storage: storage)
    assertEqual(second.key(for: "and-1"), key, "跨实例持久化")

    assertEqual(store.pairedDeviceIds(), ["and-1"], "设备 id 列表")

    store.remove(deviceId: "and-1")
    assertEqual(store.key(for: "and-1") == nil, true, "移除后回到未配对")
    assertEqual(PairingStore(storage: storage).key(for: "and-1") == nil, true, "移除已持久化")

    // PIN 格式
    let pin = PairingStore.generatePIN()
    assertEqual(pin.count, 4, "PIN 4 位")
    assertEqual(PairingStore.isValidPIN(pin), true, "生成的 PIN 合法")
    assertEqual(PairingStore.isValidPIN("1234"), true, "1234 合法")
    assertEqual(PairingStore.isValidPIN("123"), false, "3 位非法")
    assertEqual(PairingStore.isValidPIN("12a4"), false, "含字母非法")
}

// MARK: - offer 签名

func testOfferSignature() {
    print("\n🧪 Testing offer 清单签名...")

    let files = [
        OfferFile(fileId: "f1", name: "照片.jpg", size: 10, sha256: "BBB"),
        OfferFile(fileId: "f2", name: "文档.pdf", size: 20, sha256: "AAA"),
    ]
    let request = OfferRequest(senderDeviceId: "and-1", senderAlias: "小米14", files: files)
    assertEqual(TransferService.offerSignature(request), "and-1|aaa|bbb",
                "签名 = 设备 id + 排序后的 sha256 集合")

    // 重命名 / 顺序变化不影响复用判定
    let renamed = OfferRequest(senderDeviceId: "and-1", senderAlias: "小米14",
                               files: [OfferFile(fileId: "f9", name: "重命名.jpg", size: 10, sha256: "AAA")])
    let renamedAgain = OfferRequest(senderDeviceId: "and-1", senderAlias: "小米14",
                                    files: [OfferFile(fileId: "f9", name: "重命名.jpg", size: 10, sha256: "aaa")])
    assertEqual(TransferService.offerSignature(renamed), TransferService.offerSignature(renamedAgain),
                "sha256 大小写不敏感")

    let otherSender = OfferRequest(senderDeviceId: "and-2", senderAlias: "x", files: files)
    assertEqual(TransferService.offerSignature(otherSender).hasPrefix("and-2|"), true,
                "不同设备签名不同")

    // 重提 PIN 请求体字段
    let pinJSON = """
    {"senderDeviceId":"and-1","senderAlias":"小米14","sessionId":"s-1","pin":"1234",
     "files":[{"fileId":"f1","name":"a.jpg","size":10,"sha256":"BBB","mime":"image/jpeg"}]}
    """
    let decoded = try? OfferRequest.decode(Data(pinJSON.utf8))
    assertEqual(decoded?.sessionId, "s-1", "sessionId 字段")
    assertEqual(decoded?.pin, "1234", "pin 字段")
}

// MARK: - 错误码与信封

func testErrorCodesAndEnvelope() {
    print("\n🧪 Testing 错误码与响应信封...")

    assertEqual(TransferError.tokenMismatch.code, 4001, "4001 token")
    assertEqual(TransferError.sessionNotFound.code, 4002, "4002 会话")
    assertEqual(TransferError.offsetMismatch(expected: 1, received: 2).code, 4003, "4003 offset")
    assertEqual(TransferError.diskFull(required: 2, available: 1).code, 4004, "4004 磁盘")
    assertEqual(TransferError.checksumMismatch(expected: "a", actual: "b").code, 4005, "4005 校验")
    assertEqual(TransferError.denied.code, 4006, "4006 拒绝")
    assertEqual(TransferError.confirmTimeout.code, 4007, "4007 超时")
    assertEqual(TransferError.tokenMismatch.httpStatus, 400, "token 错误映射 400")
    assertEqual(TransferError.routeNotFound("/x").httpStatus, 404, "未知路由 404")
    assertEqual(TransferError.ioFailed("x").httpStatus, 500, "IO 错误 500")

    // pairingKey 只在存在时出现在 data 中（可选字段）
    let withKey = OfferResult(sessionId: "s", token: "t", state: .approved,
                              accepted: [], pairingKey: "abcdef")
    let withKeyText = String(data: ApiResponse<OfferResult>.success(withKey).encoded(), encoding: .utf8) ?? ""
    assertEqual(withKeyText.contains("\"pairingKey\":\"abcdef\""), true, "新配对返回 pairingKey")

    let withoutKey = OfferResult(sessionId: "s", token: "t", state: .approved, accepted: [])
    let withoutKeyText = String(data: ApiResponse<OfferResult>.success(withoutKey).encoded(), encoding: .utf8) ?? ""
    assertEqual(withoutKeyText.contains("pairingKey"), false, "已配对不返回 pairingKey")

    // 解码既有端响应（pending 分支 accepted 为空）
    let pendingJSON = #"{"code":0,"message":"ok","data":{"sessionId":"s","token":"t","state":"pending","accepted":[]}}"#
    let envelope = try? JSONDecoder().decode(ApiResponse<OfferResult>.self, from: Data(pendingJSON.utf8))
    assertEqual(envelope?.data?.state, .pending, "pending 响应可解码")
    assertEqual(envelope?.data?.pairingKey == nil, true, "pending 无 pairingKey")

    // 失败信封 data 为 null
    let failureText = String(data: ApiResponse<EmptyPayload>.failure(.denied).encoded(), encoding: .utf8) ?? ""
    assertEqual(failureText.contains(#""code":4006"#), true, "失败信封业务码")
    assertEqual(failureText.contains(#""data":null"#), true, "失败信封 data 为 null")
}
