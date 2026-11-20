import NetworkMonitorFeatureBilling

// MARK: - 额度提醒兜底音适配

/// 额度服务层的兜底音端口由真实播放器适配 —— 通知未授权时用同一套「事件配置 → 声音」逻辑
extension NotificationSoundPlayer: BillingAlertSoundPlaying {}
