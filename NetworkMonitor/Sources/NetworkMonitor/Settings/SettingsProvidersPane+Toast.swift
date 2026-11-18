import AppKit

// MARK: - 额度 Provider 设置页（操作回执 toast）

/// 页内 toast —— 从主文件拆出（主文件贴着 15 KiB 上限，toast 与实例 / 凭据逻辑无关）
///
/// 只记录「刚做完什么」这类瞬时回执（保存凭据 / 清凭据 / 改窗口勾选 / 改阈值），
/// 1.8 秒自动收起；视图与手势条数恒定，不随调用次数增长。
extension SettingsProvidersPane {

    func buildToast() {
        toastView.translatesAutoresizingMaskIntoConstraints = false
        toastView.wantsLayer = true
        toastView.layer?.cornerRadius = 12
        toastView.layer?.backgroundColor = NSColor(white: 0.16, alpha: 0.94).cgColor
        toastView.isHidden = true
        toastLabel.translatesAutoresizingMaskIntoConstraints = false
        toastView.addSubview(toastLabel)
        addSubview(toastView)
        NSLayoutConstraint.activate([
            toastLabel.leadingAnchor.constraint(equalTo: toastView.leadingAnchor, constant: 12),
            toastLabel.trailingAnchor.constraint(equalTo: toastView.trailingAnchor, constant: -12),
            toastLabel.topAnchor.constraint(equalTo: toastView.topAnchor, constant: 6),
            toastLabel.bottomAnchor.constraint(equalTo: toastView.bottomAnchor, constant: -6),
            toastView.centerXAnchor.constraint(equalTo: centerXAnchor),
            toastView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])
    }

    func showToast(_ text: String) {
        toastLabel.stringValue = text
        toastView.isHidden = false
        toastTask?.cancel()
        toastTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            guard !Task.isCancelled else { return }
            self?.toastView.isHidden = true
        }
    }
}
