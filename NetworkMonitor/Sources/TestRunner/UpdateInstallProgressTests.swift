import Foundation
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 安装进度纯逻辑（节流 / 速度 / 剩余 / 阶段清单）

/// 断言「下载进度 → 界面口径」这条链上的纯函数：节流闸门、滑动窗口速度、
/// 阶段清单四态、百分比与详情文案。全部不碰 AppKit、不联网、不写盘。
func runUpdateInstallProgressTests() {
    print("🧪 Testing 安装进度：节流 / 滑动窗口速度 / 剩余时间 / 阶段清单 / 详情文案...")

    testProgressBasics()
    testProgressThrottle()
    testSpeedometer()
    testStepsForStage()
    testStepsForFailure()
    testDetailText()
    testStateCarriesProgress()

    print("✅ 安装进度纯逻辑 works")
}

// MARK: - 值类型

private func testProgressBasics() {
    let known = UpdateDownloadProgress(receivedBytes: 6_200_000, totalBytes: 12_200_000)
    assertEqual(known.percent, 50, "6200000/12200000 向下取整 50%")
    assertEqual(known.isComplete, false, "未收满")
    assertEqual(Int((known.fraction ?? 0) * 100), 50, "比例与百分比一致")

    // 分母缺失：比例与百分比都必须是 nil —— 界面据此走不定态，而不是画 0%
    let unknown = UpdateDownloadProgress(receivedBytes: 1024, totalBytes: nil)
    assertEqual(unknown.fraction == nil, true, "没有分母时不给假比例")
    assertEqual(unknown.percent == nil, true, "没有分母时不给假百分比")

    // 分母为 0 / 负数一律当缺失（Content-Length: 0 是「不知道」而不是「已经下完」）
    assertEqual(UpdateDownloadProgress(receivedBytes: 5, totalBytes: 0).fraction == nil, true,
                "总量 0 视为未知")
    assertEqual(UpdateDownloadProgress(receivedBytes: 5, totalBytes: -1).totalBytes == nil, true,
                "总量负数视为未知")

    // 超过总量：比例夹到 1（进度条不越界），且判完成
    let over = UpdateDownloadProgress(receivedBytes: 200, totalBytes: 100)
    assertEqual(over.fraction, 1, "超过总量时比例夹到 1")
    assertEqual(over.isComplete, true, "超过总量算收满")

    // 负数已收、NaN 速度、无穷剩余：全部归一，不让异常值漏到界面
    let weird = UpdateDownloadProgress(receivedBytes: -10, totalBytes: 100,
                                       bytesPerSecond: .nan, estimatedSecondsRemaining: .infinity)
    assertEqual(weird.receivedBytes, 0, "负数已收归零")
    assertEqual(weird.bytesPerSecond, 0, "NaN 速度归零")
    assertEqual(weird.estimatedSecondsRemaining == nil, true, "无穷剩余时间置 nil")

    assertEqual(UpdateDownloadProgress.remainingSeconds(received: 2, total: 10,
                                                       bytesPerSecond: 4), 2, "剩余 = (10-2)/4")
    assertEqual(UpdateDownloadProgress.remainingSeconds(received: 10, total: 10,
                                                       bytesPerSecond: 4) == nil, true,
                "已收满时不给剩余时间")
    assertEqual(UpdateDownloadProgress.remainingSeconds(received: 2, total: nil,
                                                       bytesPerSecond: 4) == nil, true,
                "没有分母时不给剩余时间")
}

// MARK: - 节流

private func testProgressThrottle() {
    let t0 = Date(timeIntervalSince1970: 1_000)
    assertEqual(UpdateProgressThrottle.shouldEmit(last: nil, now: t0), true, "首次恒上报")
    assertEqual(UpdateProgressThrottle.shouldEmit(last: t0, now: t0.addingTimeInterval(0.05)),
                false, "50ms 内仍在上一个窗口里 → 丢弃")
    assertEqual(UpdateProgressThrottle.shouldEmit(last: t0, now: t0.addingTimeInterval(0.1)),
                true, "整 100ms 放行（边界含）")
    assertEqual(UpdateProgressThrottle.shouldEmit(last: t0, now: t0.addingTimeInterval(2)),
                true, "间隔久了照常放行")
    // 时钟回退：系统时间被改回后差值恒为负，若照常拒绝进度会永久冻住
    assertEqual(UpdateProgressThrottle.shouldEmit(last: t0, now: t0.addingTimeInterval(-30)),
                true, "时钟回退时放行（否则进度永久冻住）")
    assertEqual(UpdateProgressThrottle.shouldEmit(last: t0, now: t0, interval: 0), true,
                "interval 0 视为不节流")
    assertEqual(UpdateProgressThrottle.defaultInterval, 0.1, "默认节流 100ms")
}

// MARK: - 滑动窗口速度

private func testSpeedometer() {
    var meter = UpdateDownloadSpeedometer(window: 1.5)
    let t0 = Date(timeIntervalSince1970: 2_000)

    // 第一个点：只有起点，速度必然是 0、剩余时间必须是 nil（不给假数字）
    let first = meter.record(received: 0, total: 10_000_000, at: t0)
    assertEqual(first.bytesPerSecond, 0, "单点速度 0")
    assertEqual(first.estimatedSecondsRemaining == nil, true, "单点不给剩余时间")

    // 1 秒收了 5MB → 约 5MB/s
    let second = meter.record(received: 5_000_000, total: 10_000_000,
                              at: t0.addingTimeInterval(1))
    assertEqual(abs(second.bytesPerSecond - 5_000_000) < 1, true,
                "1 秒 5MB → 5MB/s（实测 \(second.bytesPerSecond)）")
    let remaining = second.estimatedSecondsRemaining ?? -1
    assertEqual(remaining > 0.9 && remaining < 1.1, true, "剩余约 1 秒")

    // 第 3 个点落在窗口外：旧采样全部滑走 → 速度回到 0，
    // 不会拿 3 秒前的首点去算「总平均」（那正是首尾平均的病）
    let third = meter.record(received: 5_000_000, total: 10_000_000,
                             at: t0.addingTimeInterval(3))
    assertEqual(third.bytesPerSecond, 0, "窗口外的旧采样被丢弃后不产生速度")

    // 停滞：窗口内字节没涨 → 速度 0、剩余时间 nil（而不是算出一个巨大的剩余秒数）
    var stuck = UpdateDownloadSpeedometer(window: 1.5)
    _ = stuck.record(received: 1_000, total: 100_000, at: t0)
    let stalled = stuck.record(received: 1_000, total: 100_000, at: t0.addingTimeInterval(0.5))
    assertEqual(stalled.bytesPerSecond, 0, "字节没涨 → 速度 0")
    assertEqual(stalled.estimatedSecondsRemaining == nil, true, "速度 0 时不给剩余时间")
}

// MARK: - 阶段清单

private func testStepsForStage() {
    assertEqual(UpdateInstallProgressText.steps(stage: .idle).isEmpty, true,
                "idle 时整块隐藏（空数组）")

    let downloading = UpdateInstallProgressText.steps(stage: .downloading)
    assertEqual(downloading.count, 5, "五段固定")
    assertEqual(downloading.first?.state, .current, "下载段是当前行")
    assertEqual(downloading.dropFirst().allSatisfy { $0.state == .pending }, true,
                "下载时后面四段都还没到")

    // 校验（子步骤 nil）与展开（有子步骤）是两行：把 16MB 的挂载/拷贝藏进「校验」里就成了假进度
    let verifying = UpdateInstallProgressText.steps(stage: .verifying, subStep: nil)
    assertEqual(verifying[0].state, .done, "校验时下载段已打勾")
    assertEqual(verifying[1].kind, .verify, "第二行是校验")
    assertEqual(verifying[1].state, .current, "第二行是当前")
    let expanding = UpdateInstallProgressText.steps(stage: .verifying, subStep: .copyingApp)
    assertEqual(expanding[1].state, .done, "展开子步骤出现时校验段已打勾")
    assertEqual(expanding[2].kind, .expand, "第三行是展开")
    assertEqual(expanding[2].state, .current, "展开段是当前")

    let replacing = UpdateInstallProgressText.steps(stage: .installing)
    assertEqual(replacing[3].state, .current, "替换段是当前行")
    assertEqual(replacing.prefix(3).allSatisfy { $0.state == .done }, true, "前三个阶段都打勾")

    let relaunching = UpdateInstallProgressText.steps(stage: .readyToRelaunch)
    assertEqual(relaunching.last?.state, .current, "待重启是最后一行当前")
    assertEqual(relaunching.prefix(4).allSatisfy { $0.state == .done }, true, "重启前四段全打勾")
}
private func testStepsForFailure() {
    // 失败保留「卡在哪」：卡住那行标红，前面照常打勾，后面仍旧灰
    let failedAtDownload = UpdateInstallProgressText.steps(stage: .failed, failedAt: .downloading)
    assertEqual(failedAtDownload.count, 5, "失败时清单仍在（不是整块消失）")
    assertEqual(failedAtDownload[0].state, .failed, "下载失败 → 第一行标红")
    assertEqual(failedAtDownload.dropFirst().allSatisfy { $0.state == .pending }, true,
                "后面四段未开始")

    let failedAtReplace = UpdateInstallProgressText.steps(stage: .failed, failedAt: .installing)
    assertEqual(failedAtReplace[3].state, .failed, "换包失败 → 第四行标红")
    assertEqual(failedAtReplace.prefix(3).allSatisfy { $0.state == .done }, true,
                "前三个阶段已完成（打勾保留）")
    assertEqual(failedAtReplace.last?.state, .pending, "重启段未开始")

    // 展开段失败（子步骤带上才有「展开」这一行）
    let failedAtExpand = UpdateInstallProgressText.steps(stage: .failed,
                                                         subStep: .copyingApp,
                                                        failedAt: .verifying)
    assertEqual(failedAtExpand[2].state, .failed, "带子步骤时展开段标红")

    // 不知道卡在哪：不标红任何一行（宁可不标，也不要指错）
    let unknown = UpdateInstallProgressText.steps(stage: .failed, failedAt: nil)
    assertEqual(unknown.allSatisfy { $0.state == .pending }, true, "没有阶段信息时不乱标红")
}

// MARK: - 文案

private func testDetailText() {
    assertEqual(UpdateInstallProgressText.detailText(nil) == nil, true, "没有进度 → 不出详情行")
    let zero = UpdateDownloadProgress(receivedBytes: 0, totalBytes: 100)
    assertEqual(UpdateInstallProgressText.detailText(zero) == nil, true,
                "0 字节 → 不出详情行（避免开局闪一行 0 B）")

    let full = UpdateInstallProgressText.detailText(
        UpdateDownloadProgress(receivedBytes: 6_200_000, totalBytes: 12_200_000,
                               bytesPerSecond: 2_100_000, estimatedSecondsRemaining: 3))
    let fullText = full ?? ""
    assertEqual(fullText.contains("已下载"), true, "详情行含「已下载」")
    assertEqual(fullText.contains(" / 12.2 MB"), true, "详情行含总量")
    assertEqual(fullText.contains("/s"), true, "详情行含速度")
    assertEqual(fullText.contains("剩余约 3 秒"), true, "详情行含剩余时间")
    assertEqual(fullText.components(separatedBy: " · ").count, 3, "三段用 · 分隔")

    // 没有分母 / 没有速度：只写已有的，不拼占位符
    let bare = UpdateInstallProgressText.detailText(
        UpdateDownloadProgress(receivedBytes: 1_000_000, totalBytes: nil)) ?? ""
    assertEqual(bare.contains("/"), false, "没有分母时不出斜杠")
    assertEqual(bare.contains("/s"), false, "没有速度时不出速度")

    let onePercent = UpdateDownloadProgress(receivedBytes: 1, totalBytes: 100)
    assertEqual(UpdateInstallProgressText.percentText(onePercent), "1%", "百分比文案")
    let noTotal = UpdateDownloadProgress(receivedBytes: 1, totalBytes: nil)
    assertEqual(UpdateInstallProgressText.percentText(noTotal) == nil, true, "无分母无百分比")
    assertEqual(UpdateInstallProgressText.isIndeterminate(noTotal), true, "无分母 → 不定态")
    assertEqual(UpdateInstallProgressText.isIndeterminate(onePercent), false, "有分母 → 确定态")

    // 展开段子步骤文案：三段必须各不相同（否则用户看不出停在挂载还是拷贝）
    let mount = UpdateInstallProgressText.stepDetail(stage: .verifying, subStep: .mountingDiskImage)
    let copy = UpdateInstallProgressText.stepDetail(stage: .verifying, subStep: .copyingApp)
    let detach = UpdateInstallProgressText.stepDetail(stage: .verifying, subStep: .detachingDiskImage)
    assertEqual(mount != copy && copy != detach && mount != detach, true, "三段子步骤文案互不相同")
    assertEqual(UpdateInstallProgressText.stepDetail(stage: .downloading, subStep: nil) == nil, true,
                "下载段不需要子步骤说明（那行已由详情行负责）")
}

// MARK: - 状态对象

private func testStateCarriesProgress() {
    let progress = UpdateDownloadProgress(receivedBytes: 100, totalBytes: 200)
    let downloading = UpdateInstallState(stage: .downloading, progress: progress)
    // 换阶段必须保留已下载进度：清掉会让进度条从满格跳回空，用户以为重头开始
    let verifying = downloading.moving(to: .verifying)
    assertEqual(verifying.progress, progress, "换阶段时保留下载进度")
    assertEqual(verifying.stage, .verifying, "阶段已切换")

    let failed = UpdateInstallState.failing("解压失败", at: .verifying, progress: progress)
    assertEqual(failed.stage, .failed, "失败态")
    assertEqual(failed.failedAt, .verifying, "失败保留卡在哪一段")
    assertEqual(failed.progress, progress, "失败时保留已下载进度（进度条不回零）")
    assertEqual(failed.failureReason, "解压失败", "失败原因原样保留")

    // 旧的初始化方式必须仍然可用（既有调用点与测试不受影响）
    let legacy = UpdateInstallState(stage: .failed, failureReason: "旧口径")
    assertEqual(legacy.progress == nil && legacy.failedAt == nil, true, "旧初始化保持零进度")
}
