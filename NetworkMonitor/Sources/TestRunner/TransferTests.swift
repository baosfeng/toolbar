import Foundation
import NetworkMonitorCore

// MARK: - 局域网互传测试组

/// 局域网互传测试入口 — 由 main.swift 顶层调用
///
/// 覆盖设计文档 §9 要求的纯逻辑用例：发现消息编解码与版本兼容、设备离线判定、
/// `/24` 扫描地址生成、状态机非法迁移、文件名去重、offset 校验。
func runTransferTests() {
    testDiscoveryMessageCodec()
    testDiscoveryVersionCompat()
    testDeviceLiveness()
    testSubnetScan()
    testDeviceRegistry()
    testHttpRequestParser()
    testHttpResponseWriter()
    testOfferRequestDecode()
    testFileNameResolver()
    testUploadPlanner()
    testFileStream()
    testSessionMachine()
    testPairingStore()
    testOfferSignature()
    testErrorCodesAndEnvelope()
    runTransferIntegrationTests()
    runTransferPolicyTests()
    print("✅ 局域网互传测试组完成")
}
