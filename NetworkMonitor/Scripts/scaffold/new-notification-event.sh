#!/bin/bash
# 新增「通知事件」脚手架 —— 生成事件表守卫测试 + 打印必须人工改的 7 处
#
# 用法：
#   bash NetworkMonitor/Scripts/scaffold/new-notification-event.sh <rawValue> <中文名> [--dry-run] [--out <目录>] [--force]
#
# rawValue 是偏好键的组成部分（notify.<rawValue>.enabled / .sound / .presentation / .haptic），
# 发布后不可变更；改名会丢掉用户已经调好的声音与提醒方式。

source "$(cd "$(dirname "$0")" && pwd)/_common.sh"

usage() {
    echo "用法：new-notification-event.sh <rawValue> <中文名> [选项]"
    echo ""
    echo "  rawValue camelCase（小写字母开头、只含字母数字），如 diskHealth"
    echo "  中文名   设置页事件行标题，如「磁盘健康」"
    usage_common
}

POSITIONAL=()
parse_common_args "$@"

if [ "${#POSITIONAL[@]}" -lt 2 ]; then
    usage >&2
    exit 2
fi

RAW_VALUE="${POSITIONAL[0]}"
LABEL="${POSITIONAL[1]}"
# 事件 rawValue 用 camelCase：与既有 billingAlert / snipCaptured 一致，且直接进偏好键
if ! printf "%s" "${RAW_VALUE}" | grep -Eq "^[a-z][A-Za-z0-9]*$"; then
    echo "❌ 事件 rawValue 必须是 camelCase（小写字母开头、只含字母数字）：${RAW_VALUE}" >&2
    exit 2
fi

PASCAL="$(pascal_case "${RAW_VALUE}")"
TARGET_DIR="${OUT_DIR:-${NM_DIR}/Sources/TestRunner}"
TEST_PATH="${TARGET_DIR}/NotificationEvent${PASCAL}Tests.swift"

echo "通知事件脚手架：rawValue=${RAW_VALUE} / 中文名=${LABEL} / 测试套件=runNotificationEvent${PASCAL}Tests"

render_test() {
    sed -e "s/__PASCAL__/${PASCAL}/g" -e "s/__RAW_VALUE__/${RAW_VALUE}/g" -e "s|__LABEL__|${LABEL}|g" <<'SWIFT'
import Foundation
import NetworkMonitorCore

// MARK: - 通知事件表守卫：__LABEL__

/// __LABEL__（rawValue __RAW_VALUE__）事件表守卫 —— 由
/// Scripts/scaffold/new-notification-event.sh 生成。
///
/// 存在理由：NotificationEvent 是设置页事件表、偏好键、默认开关与系统通知能力的唯一来源，
/// 加一个 case 会牵动五个 switch 与两处硬编码计数。这里把「新事件必须自洽」变成断言：
/// 漏了任一 switch 分支编译就报错，漏了默认值 / 能力声明在这里判红。
///
/// 注意时序：**加 case 之前这个套件是红的**（guard 会判红并提示先做人工步骤 1），
/// 这是引导你把人工步骤 1–4 做完；做完即转绿，不需要改本文件。
func runNotificationEvent__PASCAL__Tests() {
    print("🧪 Testing 通知事件表：__LABEL__...")

    guard let event = NotificationEvent(rawValue: "__RAW_VALUE__") else {
        assertNotNil(nil as NotificationEvent?,
                     "NotificationEvent.__RAW_VALUE__ 尚未登记（先做人工步骤 1）")
        return
    }

    assertEqual(event.label, "__LABEL__", "事件行标题")
    assertEqual(event.detail.isEmpty, false, "事件行必须有一句副标题说明")
    assertEqual(NotificationEvent.allCases.contains(event), true, "事件表包含该事件")
    assertEqual(NotificationEvent.allCases.filter { $0 == event }.count, 1, "事件表里不重复")

    // 提醒方式只对发系统通知的事件可用；不发系统通知的事件 UI 会把这一列置灰
    assertEqual(event.postsSystemNotification, false,
                "默认不发系统通知（操作反馈类）；改成 true 时须同时接系统通知出口")

    // 默认开关口径：提醒类开、操作反馈类关。新事件默认按操作反馈（关）
    assertEqual(event.defaultEnabled, false, "默认开或者关必须显式决定，不要留成意外")
    assertEqual(event.defaultConfig.enabled, event.defaultEnabled, "默认配置与默认开关同源")

    print("✅ 通知事件表：__LABEL__ works")
}
SWIFT
}

emit_file "${TEST_PATH}" "$(render_test)"

print_step_header 7


echo ""
echo "1. 加枚举 case"
echo "   Sources/NetworkMonitorCore/Notifications/NotificationEvent.swift:13  enum NotificationEvent: String, CaseIterable, Sendable"
echo "     · 加 case ${RAW_VALUE}"
echo "     · rawValue 进偏好键，**发布后不可再改**"

echo ""
echo "2. 补 5 个 switch（少一个就编译不过）"
echo "   Sources/NetworkMonitorCore/Notifications/NotificationEvent.swift"
echo "     :36 label                    → 「${LABEL}」"
echo "     :49 detail                   → 一句话说明（设置页行副标题）"
echo "     :69 postsSystemNotification  → 是否发系统通知（操作反馈类 false，UI 把提醒方式列置灰）"
echo "     :79 defaultEnabled           → 提醒类 true / 操作反馈类 false"
echo "     :96 defaultHaptic            → 关 / 轻 / 标准 / 有力"

echo ""
echo "3. 补应用内 cue（否则没有兜底提示音）"
echo "   Sources/NetworkMonitorCore/Notifications/NotificationCue.swift:10  加 case ${RAW_VALUE}"
echo "     同文件 :35 event 映射 → return .${RAW_VALUE}"
echo "     同文件 :40 音色族（crisp / thud / chime / swipe / alert）"
echo "     · CueSoundSynth 按音色族确定性合成 AIFF，新增 cue 自动生成音频（无需素材）"

echo ""
echo "4. 偏好键：rawValue 派生，通常无需改"
echo "   Sources/NetworkMonitorCore/Notifications/NotificationPreferences.swift:51-60"
echo "     · 键名 = notify.<rawValue>.{enabled,sound,presentation,haptic}，由 allCases 自动遍历"
echo "     · 只有当本事件需要迁移旧键时才在这里加一次性迁移（参照 notify.sound.builtinMigrated）"

echo ""
echo "5. 挂到设置页（事件跟着功能走，不集中在一页）"
echo "   Sources/NetworkMonitor/Settings/SettingsNotificationEventCard.swift:44  组件已就绪，不要新写卡片"
echo "   现成五处用法（照抄最接近的一处）："
echo "     SettingsProvidersPane.swift:73  额度三行"
echo "     SettingsClipboardPane.swift:74  剪贴板动作"
echo "     SettingsCapturePane.swift:82    截图完成"
echo "     SettingsTransferPane.swift:47   传输完成"
echo "     SettingsGeneralPane.swift:67    面板展开收起"
echo "     → 对应功能页加：self.notificationCard = SettingsNotificationEventCard(events: [.${RAW_VALUE}], …)"

echo ""
echo "6. 测试（硬编码计数会红，这是设计如此）"
echo "   Sources/TestRunner/NotificationTests.swift:21    NotificationEvent.allCases.count 7 → 8"
echo "   Sources/TestRunner/SoundStoreTests.swift:131/133/144  NotificationCue.allCases.count 相关数字同步"
echo "   Sources/TestRunner/NotificationPreferenceTests.swift  若新事件有专用默认值，补一条"

echo ""
echo "7. 登记测试入口 + 文档"
echo "   Sources/TestRunner/TestSuites+Core.swift  加 runNotificationEvent${PASCAL}Tests()"
echo "     · 忘登记会被 TestSuiteRegistrationTests 判红"
echo "   AGENTS.md「通知与音效」行：七类事件 → 八类，写清这一行的位置与默认档"
echo "   规范出处：docs/开发指南/扩展点清单.md「通知事件」一节"

echo ""
echo "生成后可立刻编译；做完步骤 1–4 后该套件转绿："
echo "  cd NetworkMonitor && swift build --disable-sandbox --build-system native"
echo "  swift run --disable-sandbox --build-system native TestRunner"
