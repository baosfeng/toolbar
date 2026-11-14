import Foundation

// MARK: - 音效文件校验

/// 音效文件被拒原因（文案直接给用户看）
public enum SoundFileRejection: String, Error, Sendable, CaseIterable {
    /// 扩展名不在白名单
    case unsupportedFormat
    /// 超过 10 MB
    case tooLarge
    /// 文件名清洗后为空
    case invalidName
    /// 空文件 / 读不出音频
    case unreadable
    /// 超过 30 秒（系统通知音上限）
    case tooLong

    /// 中文说明
    public var message: String {
        switch self {
        case .unsupportedFormat: return "不支持的格式，请选 wav / aiff / caf / mp3 / m4a"
        case .tooLarge: return "文件超过 10 MB，请换一段更短的音频"
        case .invalidName: return "文件名不可用，请重命名后再上传"
        case .unreadable: return "文件读不出音频内容，可能已损坏"
        case .tooLong: return "音频超过 30 秒，系统通知音不支持更长时长"
        }
    }
}

// MARK: - 校验

/// 音效文件校验 — 纯逻辑，导入链与设置页共用同一份判据
///
/// 三道闸门：
/// 1. 扩展名白名单（wav / aiff / caf / mp3 / m4a）——挡掉把任意文件当音效塞进来；
/// 2. 体积上限 10 MB——挡住误选整张专辑；
/// 3. 文件名清洗——挡路径穿越（../../etc/passwd 只留 passwd）与隐藏文件。
public enum SoundFileValidator {

    /// 允许的扩展名（小写，不含点）
    public static let allowedExtensions: Set<String> = ["wav", "aiff", "aif", "caf", "mp3", "m4a"]

    /// 体积上限（10 MB）
    public static let maxBytes = 10 * 1024 * 1024

    /// 时长上限（秒）——超出部分在导入时裁掉，这里用于提示
    public static let maxDurationSeconds: Double = 30

    /// 文件名长度上限（字符）
    public static let maxNameLength = 48

    /// 小写扩展名（不含点；无扩展名返回空串）
    public static func fileExtension(of fileName: String) -> String {
        let url = URL(fileURLWithPath: fileName)
        return url.pathExtension.lowercased()
    }

    /// 清洗用户输入的名字或选取的文件名：只留最后一段、去掉隐藏前缀与非法字符
    ///
    /// 返回 nil 表示这个名字不可用（空、全是非法字符、或只剩 . / ..）。
    public static func sanitizedDisplayName(_ raw: String) -> String? {
        // 先按两种分隔符取最后一段：既挡 POSIX 路径，也挡 Windows 风格路径
        let lastComponent = raw
            .split(whereSeparator: { $0 == "/" || $0 == "\\" })
            .last
            .map(String.init) ?? ""
        var name = lastComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        // 去掉扩展名（自定义音效统一存成 .aiff，名字只做展示与文件主名）
        if !fileExtension(of: name).isEmpty {
            name = (name as NSString).deletingPathExtension
        }
        // 去掉控制字符与保留字符
        let banned = CharacterSet.controlCharacters
            .union(CharacterSet(charactersIn: ":\0<>|?*"))
        name = name.components(separatedBy: banned).joined()
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != ".", name != ".." else { return nil }
        // 隐藏文件一律拒（.DS_Store 一类的东西不配当音效）
        if name.hasPrefix(".") { return nil }
        if name.count > maxNameLength {
            name = String(name.prefix(maxNameLength))
        }
        return name.isEmpty ? nil : name
    }

    /// 校验（扩展名 + 体积）；通过返回 nil
    public static func validate(fileName: String, byteCount: Int) -> SoundFileRejection? {
        guard allowedExtensions.contains(fileExtension(of: fileName)) else {
            return .unsupportedFormat
        }
        guard byteCount > 0 else { return .unreadable }
        guard byteCount <= maxBytes else { return .tooLarge }
        return nil
    }
}
