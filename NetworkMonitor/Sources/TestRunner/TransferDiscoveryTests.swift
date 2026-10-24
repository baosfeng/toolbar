import Foundation
import NetworkMonitorCore

// MARK: - 局域网互传 · 发现消息 / 版本 / 离线 / 扫描 / 设备表

// 测试函数放宽为 internal：由 TransferTests.swift 的 runTransferTests() 跨文件调度。

// MARK: - 发现消息编解码

func testDiscoveryMessageCodec() {
    print("\n🧪 Testing DiscoveryMessage 编解码...")

    let original = DiscoveryMessage(type: .announce,
                                    deviceId: "and-7f3a9c",
                                    alias: "小米14",
                                    deviceType: "android",
                                    port: 53319,
                                    proto: "http",
                                    caps: ["send", "recv"],
                                    appVersion: "1.0.0",
                                    ts: 1_760_000_000)
    guard let encoded = original.encoded(), let decoded = DiscoveryMessage.decode(encoded) else {
        print("❌ DiscoveryMessage announce 编解码失败")
        exit(1)
    }
    // 每个协议字段一条断言
    assertEqual(decoded.v, 1, "字段 v")
    assertEqual(decoded.type, .announce, "字段 type")
    assertEqual(decoded.deviceId, "and-7f3a9c", "字段 deviceId")
    assertEqual(decoded.alias, "小米14", "字段 alias")
    assertEqual(decoded.deviceType, "android", "字段 deviceType")
    assertEqual(decoded.port, 53319, "字段 port")
    assertEqual(decoded.proto, "http", "字段 proto")
    assertEqual(decoded.caps, ["send", "recv"], "字段 caps")
    assertEqual(decoded.appVersion, "1.0.0", "字段 appVersion")
    assertEqual(decoded.ts, 1_760_000_000, "字段 ts")

    // discover 只带 v/type：编码时不输出空字段
    let discover = DiscoveryMessage.discover(ts: Date(timeIntervalSince1970: 0))
    guard let discoverData = discover.encoded(),
          let json = try? JSONSerialization.jsonObject(with: discoverData) as? [String: Any] else {
        print("❌ discover 编码失败")
        exit(1)
    }
    assertEqual(json.count, 2, "discover 仅含 v/type 两个字段")
    assertEqual(json["type"] as? String, "discover")
    if let roundTrip = DiscoveryMessage.decode(discoverData) {
        assertEqual(roundTrip.type, .discover, "discover 往返")
        assertEqual(roundTrip.deviceId, "", "discover 缺省字段为空")
    } else {
        print("❌ discover 往返失败")
        exit(1)
    }

    // 未知字段忽略（向前兼容）
    let extra = #"{"v":1,"type":"announce","deviceId":"and-1","port":53319,"futureField":{"a":1}}"#
    let extraMessage = DiscoveryMessage.decode(Data(extra.utf8))
    assertEqual(extraMessage?.deviceId, "and-1", "未知字段不影响解码")
    assertEqual(extraMessage?.port, 53319, "未知字段后仍能读到 port")

    // 非法报文
    assertEqual(DiscoveryMessage.decode(Data("not json".utf8)), nil, "非 JSON 返回 nil")
    assertEqual(DiscoveryMessage.decode(Data("[]".utf8)), nil, "非对象返回 nil")
    assertEqual(DiscoveryMessage.decode(Data(#"{"v":1}"#.utf8)), nil, "缺 type 返回 nil")
    assertEqual(DiscoveryMessage.decode(Data(#"{"type":"announce"}"#.utf8)), nil, "缺 v 返回 nil")
    assertEqual(DiscoveryMessage.decode(Data(#"{"v":1,"type":"bogus"}"#.utf8)), nil, "未知 type 返回 nil")
}

// MARK: - 版本兼容

func testDiscoveryVersionCompat() {
    print("\n🧪 Testing DiscoveryMessage 版本兼容...")

    let v0 = #"{"v":0,"type":"announce","deviceId":"and-1","port":53319}"#
    assertEqual(DiscoveryMessage.decode(Data(v0.utf8)), nil, "v=0 不兼容")

    let v2 = #"{"v":2,"type":"announce","deviceId":"and-1","port":53319}"#
    assertEqual(DiscoveryMessage.decode(Data(v2.utf8)), nil, "v=2 高于当前版本不兼容")

    let v1 = #"{"v":1,"type":"offer","deviceId":"and-1","port":53319}"#
    let decoded = DiscoveryMessage.decode(Data(v1.utf8))
    assertNotNil(decoded, "v=1 兼容")
    assertEqual(decoded?.isSupportedVersion, true, "isSupportedVersion")

    // 身份消息判据：缺 deviceId 或端口非法不算可入库消息
    let noIdentity = DiscoveryMessage(type: .announce, port: 53319)
    assertEqual(noIdentity.carriesIdentity, false, "缺 deviceId 不算身份消息")
    let noPort = DiscoveryMessage(type: .announce, deviceId: "and-1")
    assertEqual(noPort.carriesIdentity, false, "缺 port 不算身份消息")
    let complete = DiscoveryMessage(type: .announce, deviceId: "and-1", port: 53319)
    assertEqual(complete.carriesIdentity, true, "完整消息可入库")
}

// MARK: - 离线判定

func testDeviceLiveness() {
    print("\n🧪 Testing DeviceLiveness 离线判定...")

    let base = Date(timeIntervalSince1970: 1_760_000_000)
    assertEqual(DeviceLiveness.evaluate(now: base, lastSeenAt: base), .online, "0s 在线")
    assertEqual(DeviceLiveness.evaluate(now: base.addingTimeInterval(14.9), lastSeenAt: base), .online, "14.9s 仍在线")
    assertEqual(DeviceLiveness.evaluate(now: base.addingTimeInterval(15), lastSeenAt: base), .offline, "15s 转离线")
    assertEqual(DeviceLiveness.evaluate(now: base.addingTimeInterval(59.9), lastSeenAt: base), .offline, "59.9s 离线")
    assertEqual(DeviceLiveness.evaluate(now: base.addingTimeInterval(60), lastSeenAt: base), .removed, "60s 移除")
}

// MARK: - /24 扫描地址生成

func testSubnetScan() {
    print("\n🧪 Testing SubnetScan /24 地址生成...")

    let hosts = SubnetScan.hosts(inSubnetOf: "192.168.1.23")
    assertEqual(hosts.count, 253, "排除网络/广播地址后 253 个")
    assertEqual(hosts.first, "192.168.1.1", "首个地址 .1")
    assertEqual(hosts.last, "192.168.1.254", "末个地址 .254")
    assertEqual(hosts.contains("192.168.1.23"), false, "排除本机地址")
    assertEqual(hosts.contains("192.168.1.0"), false, "排除网络地址")
    assertEqual(hosts.contains("192.168.1.255"), false, "排除广播地址")

    assertEqual(SubnetScan.hosts(inSubnetOf: "10.0.0.1").contains("10.0.0.1"), false, "10.x 段排除本机")
    assertEqual(SubnetScan.hosts(inSubnetOf: "192.168.1").isEmpty, true, "段数不足返回空")
    assertEqual(SubnetScan.hosts(inSubnetOf: "192.168.1.256").isEmpty, true, "越界段返回空")
    assertEqual(SubnetScan.hosts(inSubnetOf: "").isEmpty, true, "空串返回空")
    assertEqual(SubnetScan.hosts(inSubnetOf: "::1").isEmpty, true, "IPv6 返回空")

    let batches = SubnetScan.batches(hosts)
    assertEqual(batches.map(\.count), [128, 125], "按 128 并发切批")
    assertEqual(SubnetScan.batches([], size: 128).isEmpty, true, "空地址不切批")
}

// MARK: - 设备表

func testDeviceRegistry() {
    print("\n🧪 Testing DeviceRegistry 设备表...")

    let registry = DeviceRegistry(callbackQueue: DispatchQueue(label: "transfer.test.registry"))
    let base = Date(timeIntervalSince1970: 1_760_000_000)
    let announce = DiscoveryMessage(type: .announce, deviceId: "and-1", alias: "小米14",
                                    deviceType: "android", port: 53319, appVersion: "1.0.0")

    let stored = registry.upsert(message: announce, ip: "192.168.1.8", now: base)
    assertNotNil(stored, "announce 可入库")
    assertEqual(registry.count, 1, "设备数 1")
    assertEqual(registry.snapshot().first?.ip, "192.168.1.8", "记录来源 IP")
    assertEqual(registry.snapshot().first?.isOnline, true, "默认在线")

    // discover 缺身份字段：不写入设备表
    let ignored = registry.upsert(message: DiscoveryMessage.discover(), ip: "192.168.1.9", now: base)
    assertEqual(ignored, nil, "discover 不入库")
    assertEqual(registry.count, 1, "设备数不变")

    // 同一设备再次公告：更新 IP 与端口，不新增条目
    let moved = DiscoveryMessage(type: .announce, deviceId: "and-1", alias: "小米14",
                                 deviceType: "android", port: 53320)
    registry.upsert(message: moved, ip: "192.168.1.18", now: base.addingTimeInterval(5))
    assertEqual(registry.count, 1, "同设备只保留一条")
    assertEqual(registry.snapshot().first?.port, 53320, "端口随公告更新")
    assertEqual(registry.snapshot().first?.ip, "192.168.1.18", "IP 随公告更新")

    // 在线优先排序
    registry.upsert(message: DiscoveryMessage(type: .announce, deviceId: "and-2", alias: "AAA 手机",
                                              deviceType: "android", port: 53319),
                    ip: "192.168.1.9", now: base.addingTimeInterval(12))
    _ = registry.applyLiveness(now: base.addingTimeInterval(20))
    let ordered = registry.snapshot()
    assertEqual(ordered.count, 2, "两台设备")
    assertEqual(ordered.first?.deviceId, "and-2", "在线设备排在前面")
    assertEqual(ordered.first?.isOnline, true, "在线设备标记在线")

    // 15s 离线、60s 移除
    assertEqual(registry.applyLiveness(now: base.addingTimeInterval(30)), true, "首次推进存活有变化")
    assertEqual(registry.applyLiveness(now: base.addingTimeInterval(31)), false, "状态未变时不重复通知")

    // 配对标记
    registry.setPaired(true, deviceId: "and-1")
    assertEqual(registry.device(deviceId: "and-1")?.isPaired, true, "配对标记写入")

    registry.remove(deviceId: "and-2")
    assertEqual(registry.count, 1, "移除生效")

    // baseURL 供发现层异常时手动探测
    let device = registry.device(deviceId: "and-1")
    assertEqual(device?.baseURL?.absoluteString, "http://192.168.1.18:53320/api/v1", "baseURL 拼接")
}
