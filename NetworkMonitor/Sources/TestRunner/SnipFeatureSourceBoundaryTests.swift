import Foundation

// MARK: - 截图服务层边界（源码层：拆干净 / 不反向依赖 / 依赖方向）

/// 与 SnipFeatureBoundaryTests 同属截图服务层边界测试，但断言对象是**源码树与包清单**而不是
/// 运行期行为：哪些文件搬走了、哪些 UI 必须留下、新 target 还能 import 什么、Core 与 UI 的
/// 依赖方向有没有被这次拆分破坏。
///
/// 单独成文件的理由：两组断言（运行期口径 + 源码边界）合起来超过单文件 15 KiB 门禁，
/// 而它们回答的是不同问题——一组证行为没变，一组证结构没歪。
@MainActor
func testSnipFeatureSourceBoundaries() {

    let sourcesRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // TestRunner
        .deletingLastPathComponent()   // Sources

    let movedFiles = ["ScreenCaptureService.swift", "SnipPasteboardImageWriter.swift",
                      "SnipFileWriter.swift", "VisionTextRecognizer.swift",
                      "SnipHotKeyPreferences.swift", "SnipPreferenceKey.swift",
                      "SnipKeyBridge.swift", "HotKeyRegistry.swift",
                      // 文字样式的偏好读写：要用 SnipPreferenceKey，只能在功能层
                      "SnipTextStylePreference.swift"]

    // 1) App target 里不再有这些文件，新 target 里只此一份
    let appSnipFiles = Set(snipFeatureSwiftFiles(in: sourcesRoot.appendingPathComponent("NetworkMonitor/Snip")))
    for moved in movedFiles {
        assertEqual(appSnipFiles.contains(moved), false, "App target 里不再有 " + moved)
    }
    // 覆盖层 UI 与 NSApp 接线必须留下（4,774 行里绝大多数是 UI，不能迁）
    for kept in ["SnipTextEditing.swift", "SnipOverlayView.swift", "SnipToolBarView.swift",
                 "SnipToolPanelView.swift", "SnipForegroundPolicy.swift"] {
        assertEqual(appSnipFiles.contains(kept), true, "UI / NSApp 接线留在 App：" + kept)
    }

    let featureDirectory = sourcesRoot.appendingPathComponent("NetworkMonitorFeatureSnip")
    let featureFiles = snipFeatureSwiftFiles(in: featureDirectory).sorted()
    assertEqual(featureFiles.count, movedFiles.count,
                "新 target \(featureFiles.count) 个文件（全部整搬，未夹带 UI）")
    for moved in movedFiles {
        assertEqual(featureFiles.contains(moved), true, moved + " 在新 target 里只此一份")
    }

    let featureTexts = snipFeatureTexts(in: featureDirectory)

    // 2) 功能层不取 AppContext.shared（logger / storage 一律由调用方注入）
    // 只看代码行：文件头注释会写「不取 AppContext.shared」，那是说明不是调用
    let appContextUsers = featureTexts.filter { entry in
        snipFeatureCodeLines(entry.text).contains { $0.contains("AppContext.shared") }
    }
    assertEqual(appContextUsers.map(\.file), [], "新 target 不出现 AppContext.shared（logger / storage 显式注入）")

    // 3) 不反向依赖 App 的 UI / 编排类型
    let appLayerTypes = ["final class SnipController", "final class SnipOverlayView",
                         "final class SnipOverlayWindow", "final class SnipToolBarView",
                         "final class SnipToolPanelView", "final class PinWindowController",
                         "class AppCoordinator", "enum SnipForegroundPolicy"]
    let appLayerLeaks = featureTexts.filter { entry in
        appLayerTypes.contains { snipFeatureCodeLines(entry.text).contains($0) }
    }
    assertEqual(appLayerLeaks.map(\.file), [], "新 target 不定义 / 不引用 App 的 UI 与编排类型")

    // 4) AppKit 依赖集中在抓屏 / 按键桥 / 写剪贴板三处（其余只碰 Foundation / CoreGraphics / Vision）
    let appKitFiles = featureTexts
        .filter { $0.text.contains("import AppKit") }
        .map(\.file)
        .sorted()
    assertEqual(appKitFiles, ["ScreenCaptureService.swift", "SnipKeyBridge.swift",
                              "SnipPasteboardImageWriter.swift"],
                "AppKit 依赖集中在抓屏 / 按键桥 / 写剪贴板三处")

    // 5) 依赖方向：只 import Core / UI 与系统框架，不 import App target
    let importedModules = Set(featureTexts.flatMap { entry in
        snipFeatureCodeLines(entry.text).compactMap { line -> String? in
            let prefix = "import "
            guard line.hasPrefix(prefix) else { return nil }
            return String(line.dropFirst(prefix.count))
        }
    })
    assertEqual(importedModules.contains("NetworkMonitor"), false, "新 target 不反向 import App target")
    assertEqual(importedModules.isSubset(of: ["Foundation", "AppKit", "CoreGraphics", "ImageIO",
                                              "UniformTypeIdentifiers", "Vision", "ScreenCaptureKit",
                                              "Carbon", "NetworkMonitorCore", "NetworkMonitorUI"]),
                true, "新 target 只依赖白名单模块（Core / UI / 系统框架）")

    // 6) 包清单：target 登记 + 框架按需链接 + App 与 TestRunner 都依赖它
    let manifest = (try? String(contentsOf: sourcesRoot.deletingLastPathComponent()
        .appendingPathComponent("Package.swift"), encoding: .utf8)) ?? ""
    assertContains(manifest, "name: \"NetworkMonitorFeatureSnip\"", "包清单里登记了新 target")
    for framework in ["Vision", "ScreenCaptureKit", "AppKit", "Carbon", "CoreGraphics"] {
        assertContains(manifest, ".linkedFramework(\"\(framework)\")",
                       "按需链接 " + framework)
    }
    assertEqual(manifest.components(separatedBy: "NetworkMonitorFeatureSnip").count >= 4, true,
                "新 target 被登记 + 被 App 与 TestRunner 依赖（三处以上出现）")

    // 7) Core 仍不依赖 Carbon：组合键展示因此落在 UI（HotKeyCombo 只有一份定义）
    let coreTexts = snipFeatureTexts(in: sourcesRoot.appendingPathComponent("NetworkMonitorCore"))
    let carbonUsers = coreTexts.filter { $0.text.contains("import Carbon") }.map(\.file)
    assertEqual(carbonUsers, [], "Core 不 import Carbon（组合键展示放 UI）")
    let appKitCoreUsers = coreTexts.filter { $0.text.contains("import AppKit") }.map(\.file)
    assertEqual(appKitCoreUsers, [], "Core 不 import AppKit")

    let uiCombo = (try? String(contentsOf: sourcesRoot
        .appendingPathComponent("NetworkMonitorUI/HotKeyCombo.swift"), encoding: .utf8)) ?? ""
    assertContains(uiCombo, "public struct HotKeyCombo", "组合键值类型只在 UI 定义一次")
    let appHotKeyFile = (try? String(contentsOf: sourcesRoot
        .appendingPathComponent("NetworkMonitor/Clipboard/GlobalHotKey.swift"), encoding: .utf8)) ?? ""
    assertContains(appHotKeyFile, "extension HotKeyCombo", "App 只留 NSEvent → Carbon 的适配")
    assertNotContains(appHotKeyFile, "struct HotKeyCombo", "App 不再重复定义组合键类型")
    // 只看代码行：文件头注释里写着「本 target 不 import AppKit」，那是说明不是依赖
    assertEqual(snipFeatureCodeLines(uiCombo).contains { $0 == "import AppKit" }, false,
                "UI target 不 import AppKit（组合键展示只借 Carbon 常量）")

    // 8) 权限判据守卫的白名单跟着迁移走（否则源码扫描把新 target 当越界）
    let permissionGuard = (try? String(contentsOf: sourcesRoot
        .appendingPathComponent("TestRunner/PermissionSourceGuardTests.swift"), encoding: .utf8)) ?? ""
    assertContains(permissionGuard, "NetworkMonitorFeatureSnip/ScreenCaptureService.swift",
                   "抓屏权限预检的白名单指向迁移后的路径")

    // 9) 默认实现在组合根装配，服务层构造器必须显式带 logger
    let controller = (try? String(contentsOf: sourcesRoot
        .appendingPathComponent("NetworkMonitor/Snip/SnipController.swift"), encoding: .utf8)) ?? ""
    for construction in ["ScreenCaptureService(logger: logger)",
                         "HotKeyRegistry(logger: logger)",
                         "VisionTextRecognizer(logger: logger)"] {
        assertContains(controller, construction, "默认实现由 App 装配并注入 logger：" + construction)
    }
    assertNotContains(controller, "VisionTextRecognizer()", "不再用无参构造（那会去取 AppContext.shared）")
}


// MARK: - 测试辅助（目录扫描）


private func snipFeatureSwiftFiles(in directory: URL) -> [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
        .filter { $0.hasSuffix(".swift") }
}

/// 读一目录下的 Swift 正文（相对文件名 + 内容，供源码层断言用）
private func snipFeatureTexts(in directory: URL) -> [(file: String, text: String)] {
    snipFeatureSwiftFiles(in: directory).sorted().map { name in
        let text = (try? String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)) ?? ""
        return (name, text)
    }
}

/// 只取代码行（去掉整行注释与空行）：注释里提到某个类型名不算依赖
private func snipFeatureCodeLines(_ text: String) -> [String] {
    text.split(separator: "\n", omittingEmptySubsequences: false)
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty && !$0.hasPrefix("//") }
}
