import Foundation

// MARK: - 索引主流程

/// HarnessUsageService 的索引执行侧 —— 从主文件拆出
///
/// 分工：主文件负责「请求怎么排队 / 状态怎么发布」，本文件负责「一轮索引怎么跑完」。
/// 一轮 = （可选）按范围清理 → 发现会话 → 按 (size, mtime) 挑出变更 → 逐会话解析落库
/// → 一次聚合 → 回执。清理与重建绑在同一轮里，避免「清完了但没扫」的中间态。
extension HarnessUsageService {

    /// 跑一轮索引并返回回执（块外的 drain 循环负责把回执交给全部排队者的 completion）
    func runIndexing(batch: HarnessIndexBatch) -> HarnessRebuildReceipt? {
        let startedAt = Date()
        let availability = scanner.availability

        guard availability.isAvailable else {
            // 降级：明确状态 + 保留已有快照，不崩溃、不返回静默空数据
            logger.warning(availability.displayMessage)
            fail(with: availability.displayMessage, availability: availability)
            return nil
        }
        guard store.migrateHarnessSchema() else {
            fail(with: "Harness 索引表不可用（数据库可能未就绪）", availability: availability)
            return nil
        }
        let token = resetCancellationToken()

        // 清理范围（nil = 增量）；清理失败不往下扫：否则会把「没清掉」说成「已重建」
        var eventsDeleted = 0
        if let scope = batch.scope {
            logger.info("Harness token 索引：清理 " + scope.displayName + " 后重建")
            let deleted = store.harnessPurge(scope: scope, now: nowProvider())
            guard deleted >= 0 else {
                fail(with: "清理索引失败（数据库写入失败）", availability: availability)
                return nil
            }
            eventsDeleted = deleted
            markSnapshotStale()
        }

        // 冷启动先把上一轮落库结果读进内存缓存，UI 打开面板即可渲染，不必等本轮索引
        seedSnapshotIfNeeded(availability: availability)

        let files: [HarnessSessionFile]
        do {
            files = try scanner.discoverSessions()
        } catch let error as HarnessTokenError {
            if case .sessionsDirectoryUnreadable = error {
                fail(with: error.errorDescription ?? "会话目录不可读", availability: availability)
            } else {
                fail(with: "发现会话文件失败：" + String(describing: error), availability: availability)
            }
            return nil
        } catch {
            fail(with: "发现会话文件失败：" + String(describing: error), availability: availability)
            return nil
        }

        let records = store.harnessScanRecords()
        let changed = files.filter { file in
            guard let record = records[file.path] else { return true }
            return !record.matches(size: file.size, mtimeMs: file.mtimeMs)
        }
        let skipped = files.count - changed.count

        // 正在写入的会话文件 size 会变，下次刷新按 (size, mtime) 重扫属预期行为
        if changed.isEmpty {
            logger.info("Harness token 增量刷新：无变更文件（共 " + String(files.count) + " 个）")
            setState(.ready)
            // 无变更：不重算聚合（缓存快照已覆盖全部已提交数据），只在还没有缓存时补算一次
            publishSnapshot(availability: availability, totalSessions: files.count,
                            now: nowProvider(), force: false)
            return HarnessRebuildReceipt(scope: batch.scope,
                                         eventsDeleted: eventsDeleted,
                                         eventsIndexed: 0,
                                         sessionsScanned: 0,
                                         sessionsSkipped: skipped,
                                         sessionsFailed: 0,
                                         elapsed: Date().timeIntervalSince(startedAt),
                                         waitedForRunningRun: false)
        }

        var completed = 0
        var totalEvents = 0
        var malformedLines = 0
        var failedFiles = 0
        setState(.indexing(HarnessIndexProgress(
            completedFiles: 0,
            totalFiles: changed.count,
            currentFile: "",
            parsedSessions: 0
        )))

        for file in changed {
            if token.isCancelled {
                logger.info("Harness token 索引已取消（完成 " + String(completed) + "/" + String(changed.count) + "）")
                setState(.idle)
                return nil
            }
            let result: HarnessSessionScanResult
            // 进度回调要在并发闭包里用，先取当前进度的值快照（避免捕获可变变量）
            let completedSnapshot = completed
            let totalFiles = changed.count
            let sessionID = file.sessionID
            do {
                // 进度回调接上：读到的行数直接推给状态机（此前恒传 nil，UI 只能看到会话级进度）
                result = try scanner.scan(
                    file: file,
                    isCancelled: { token.isCancelled },
                    onLinesRead: { [weak self] lines in
                        self?.reportLinesRead(lines: lines, completed: completedSnapshot,
                                              total: totalFiles, sessionID: sessionID)
                    }
                )
            } catch let error as HarnessTokenError where error == .cancellationRequested {
                logger.info("Harness token 索引已取消（完成 " + String(completed) + "/" + String(changed.count) + "）")
                setState(.idle)
                return nil
            } catch {
                // 单文件失败只跳过该文件，不影响整体；不写扫描记录，下一轮会重试
                failedFiles += 1
                logger.warning("Harness 会话文件解析失败，已跳过: " + LogRedaction.path(file.path) + " — " + String(describing: error))
                continue
            }

            // 扫描记录的 sessionID 取**解析器给出的真实会话 id**（result.sessionID），
            // 与事件里的 session_id 必须一致：写入/删除都按 (session_id, source) 定位，
            // 两者不一致时删除会删空、每轮都追加一份（实测同一会话被记 3 次）。
            let record = HarnessSessionScanRecord(
                path: file.path,
                sessionID: result.sessionID,
                size: file.size,
                mtimeMs: file.mtimeMs,
                scannedAt: nowProvider().timeIntervalSince1970,
                source: file.source
            )
            // 来源跟着扫描单元走：record 的 source 由扫描器给出，写入时按它落库，
            // 删除也按 (session_id, source) 定位，跨来源同名会话不会互相误删
            if store.harnessReplaceSession(record: record, events: result.events,
                                           cwd: result.cwd, source: record.source) {
                // 落库即脏：中途取消时也要让下一次按需重算把新数据算进去
                markSnapshotStale()
            } else {
                failedFiles += 1
                logger.warning("Harness 会话落库失败: " + LogRedaction.path(file.path))
            }
            completed += 1
            totalEvents += result.events.count
            malformedLines += result.malformedLines
            setState(.indexing(HarnessIndexProgress(
                completedFiles: completed,
                totalFiles: changed.count,
                currentFile: file.sessionID,
                parsedSessions: completed
            )))
        }

        setState(.ready)
        // 索引结束算一次聚合 —— 本流程里唯一一次全表重算
        publishSnapshot(availability: availability, totalSessions: files.count,
                        now: nowProvider(), force: true)

        let elapsed = Date().timeIntervalSince(startedAt)
        logger.info(String(
            format: "Harness token 索引完成：%d 个变更文件（跳过 %d / 失败 %d）/ %d 条事件 / %d 条坏行，耗时 %.2fs",
            changed.count, skipped, failedFiles, totalEvents, malformedLines, elapsed
        ))
        // 按来源分一行：多来源后「总数对了但某个源没跑」是最难查的哑巴故障
        let perSource = Dictionary(grouping: changed, by: \.source)
        let sourceSummary = perSource.keys.sorted { $0.rawValue < $1.rawValue }.map { source in
            source.rawValue + " " + String(perSource[source]?.count ?? 0)
        }
        logger.info("Harness token 索引来源分布：" + sourceSummary.joined(separator: " / "))
        return HarnessRebuildReceipt(scope: batch.scope,
                                     eventsDeleted: eventsDeleted,
                                     eventsIndexed: totalEvents,
                                     sessionsScanned: changed.count,
                                     sessionsSkipped: skipped,
                                     sessionsFailed: failedFiles,
                                     elapsed: elapsed,
                                     waitedForRunningRun: false)
    }

    /// 单文件已读行数进度（scanner 每 500 行回调一次，这里只更新当前文件的读数）
    private func reportLinesRead(lines: Int, completed: Int, total: Int, sessionID: String) {
        setState(.indexing(HarnessIndexProgress(
            completedFiles: completed,
            totalFiles: total,
            currentFile: sessionID,
            parsedSessions: completed,
            linesRead: lines
        )))
    }
}
