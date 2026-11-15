import AppKit
import AVFoundation
import Foundation
import NetworkMonitorCore

// MARK: - 音效库

/// 音效库 — 内建设计音 + 系统音效清单 + 自定义音效的导入 / 试听 / 管理
///
/// 职责边界：
/// - 内建音由 CueSoundSynth 运行期合成、落盘到 App 目录（不打包任何音频资源），
///   系统通知那份副本由 NotificationSoundInstaller 从同一个目录取；
/// - 系统音效只读 /System/Library/Sounds；
/// - 自定义音效在导入时统一转成 AIFF（16-bit PCM）：系统通知只认 AIFF / WAV / CAF，
///   而用户手上多是 mp3 / m4a，转码一次比在 UI 里写「你这个格式系统通知用不了」更有用；
/// - 转码与校验都在这里，Store 只负责「自己目录内的文件」。
@MainActor
final class NotificationSoundLibrary {

    /// 自定义音效目录（设置页展示与清空也用它）
    let store: NotificationSoundFileStore
    /// 内建音生成文件目录
    let builtInStore: CueSoundFileStore
    private let logger: LoggingService
    private let fileManager: FileManager
    /// 系统音效目录
    private let systemSoundsDirectory: URL

    init(store: NotificationSoundFileStore,
         builtInStore: CueSoundFileStore = CueSoundFileStore(directory: CueSoundFileStore.defaultDirectory()),
         logger: LoggingService = AppContext.shared.logger,
         fileManager: FileManager = .default,
         systemSoundsDirectory: URL? = nil) {
        self.store = store
        self.builtInStore = builtInStore
        self.logger = logger
        self.fileManager = fileManager
        self.systemSoundsDirectory = systemSoundsDirectory
            ?? URL(fileURLWithPath: "/System/Library/Sounds", isDirectory: true)
    }

    /// 默认装配 — 两个音效目录都取出厂位置，并顺手把内建音铺好
    ///
    /// 预热放在这里而不是 init：装配是启动阶段的一次性动作，生成 11 份短音不过几十 KB，
    /// 却能让第一次「复制」不必等合成与写盘。
    static func makeDefault(logger: LoggingService) -> NotificationSoundLibrary {
        let library = NotificationSoundLibrary(
            store: NotificationSoundFileStore(directory: NotificationSoundFileStore.defaultDirectory()),
            builtInStore: CueSoundFileStore(directory: CueSoundFileStore.defaultDirectory()),
            logger: logger)
        library.prepareBuiltInSounds()
        return library
    }

    // MARK: - 内建音

    /// 内建音文件（首次调用时生成，之后直接复用磁盘上的那份）
    ///
    /// 加锁：播放路径与设置页试听可能撞在一起，两个 NSSound 读同一个半截文件会播不出来。
    /// 锁放在主线程 actor 之外没有必要——本类已是 @MainActor，这里靠串行调用即可，
    /// 但生成可能放在后台预热里，所以仍用 store 自己的锁守住写盘。
    func builtInURL(for cue: NotificationCue) -> URL? {
        guard let url = builtInStore.ensure(cue: cue) else {
            logger.warning("内建音效生成失败：\(cue.rawValue)")
            return nil
        }
        return url
    }

    /// 启动时铺好全部内建音并清掉旧配方留下的孤儿
    func prepareBuiltInSounds() {
        let written = builtInStore.ensureAll()
        builtInStore.sweepOrphans()
        // OSLog 一律 public：用户路径必须先脱敏
        logger.debug("内建音效已就位：\(written.joined(separator: "、"))（目录 \(LogRedaction.path(builtInStore.directory.path))）")
    }

    // MARK: - 系统音效

    /// 系统音效清单 — 扫描目录，扫描失败时回落到内置清单（设置页永远有东西可选）
    func systemSounds() -> [SystemSound] {
        let scanned = ((try? fileManager.contentsOfDirectory(atPath: systemSoundsDirectory.path)) ?? [])
            .filter { $0.hasSuffix(".aiff") }
            .map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent }
            .sorted()
        guard !scanned.isEmpty else { return SystemSoundCatalog.builtIn }
        return scanned.map { SystemSound(name: $0, title: SystemSoundCatalog.title(for: $0)) }
    }

    // MARK: - 自定义音效

    /// 自定义音效文件（排序后的文件名）
    func customFiles() -> [String] { store.files() }

    /// 文件名 → 展示名
    func displayTitle(for fileName: String) -> String { store.displayTitle(for: fileName) }

    /// 导入一个用户选取的音频文件，返回落盘后的文件名
    ///
    /// 流水线：扩展名 / 体积校验 → 解码探测（读不出来即拒）→ 时长校验（>30s 拒）
    /// → 转 AIFF（16-bit PCM，系统通知可用的唯一稳妥格式）→ 拷进音效目录。
    func importSound(from source: URL) throws -> String {
        let size = (try? fileManager.attributesOfItem(atPath: source.path)[.size] as? Int) ?? nil
        if let rejection = SoundFileValidator.validate(fileName: source.lastPathComponent,
                                                       byteCount: size ?? 0) {
            throw rejection
        }
        let prepared = try transcodeToAIFF(source: source)
        defer { try? fileManager.removeItem(at: prepared) }
        let fileName = try store.importPreparedFile(
            from: prepared,
            displayName: source.deletingPathExtension().lastPathComponent)
        logger.info("自定义音效已导入：\(fileName)")
        return fileName
    }

    /// 删除自定义音效
    func remove(_ fileName: String) throws {
        try store.remove(fileName)
        logger.info("自定义音效已删除：\(fileName)")
    }

    /// 重命名自定义音效，返回新文件名
    func rename(_ fileName: String, to newName: String) throws -> String {
        try store.rename(fileName, to: newName)
    }

    /// 音效文件 URL（试听与安装副本共用）
    func url(forCustomFile fileName: String) -> URL? { store.url(for: fileName) }

    // MARK: - 转码

    /// 解码 → 时长校验 → 写成 AIFF（返回临时文件 URL，调用方负责删）
    private func transcodeToAIFF(source: URL) throws -> URL {
        let input: AVAudioFile
        do {
            input = try AVAudioFile(forReading: source)
        } catch {
            logger.warning("音效解码失败：\(source.lastPathComponent)（\(error.localizedDescription)）")
            throw SoundFileRejection.unreadable
        }
        let format = input.processingFormat
        guard format.sampleRate > 0, input.length > 0 else { throw SoundFileRejection.unreadable }
        let duration = Double(input.length) / format.sampleRate
        guard duration <= SoundFileValidator.maxDurationSeconds else { throw SoundFileRejection.tooLong }

        let temp = fileManager.temporaryDirectory
            .appendingPathComponent("nm-sound-\(UUID().uuidString).aiff")
        // 16-bit 大端 PCM（AIFF 的原生像素格式）：系统通知与 NSSound 都能直接吃
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: true,
            AVLinearPCMIsNonInterleaved: false,
        ]
        do {
            let output = try AVAudioFile(forWriting: temp, settings: settings)
            let chunk: AVAudioFrameCount = 8192
            // 用 framePosition 判结束，不能靠「读到 0 帧就 break」：
            // AVAudioFile 在读完后再 read 会抛 -39 eofErr，而不是安静返回 0 帧
            while input.framePosition < input.length {
                let remaining = AVAudioFrameCount(min(Int64(chunk), input.length - input.framePosition))
                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: remaining) else {
                    throw SoundFileRejection.unreadable
                }
                try input.read(into: buffer, frameCount: remaining)
                guard buffer.frameLength > 0 else { break }
                try output.write(from: buffer)
            }
        } catch let rejection as SoundFileRejection {
            try? fileManager.removeItem(at: temp)
            throw rejection
        } catch {
            try? fileManager.removeItem(at: temp)
            logger.warning("音效转码失败：\(source.lastPathComponent)（\(error.localizedDescription)）")
            throw SoundFileRejection.unreadable
        }
        return temp
    }
}