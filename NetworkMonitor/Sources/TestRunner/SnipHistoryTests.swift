import Foundation
import NetworkMonitorCore

// MARK: - 选区历史

func runSnipHistoryTests() {
    print("🧪 Testing Snip selection history...")

    let a = CGRect(x: 0, y: 0, width: 100, height: 100)
    let b = CGRect(x: 10, y: 10, width: 200, height: 150)
    let c = CGRect(x: 20, y: 20, width: 300, height: 200)

    // 新记录插到最前
    var history: [CGRect] = []
    history = SnipSelectionHistoryCoding.push(a, into: history)
    history = SnipSelectionHistoryCoding.push(b, into: history)
    assertEqual(history, [b, a], "新记录排在最前")

    // 重复记录去重并提到最前
    history = SnipSelectionHistoryCoding.push(a, into: history)
    assertEqual(history, [a, b], "重复选区去重并提前")

    // 容量上限
    var capped: [CGRect] = []
    for index in 0..<12 {
        capped = SnipSelectionHistoryCoding.push(CGRect(x: CGFloat(index), y: 0, width: 10, height: 10),
                                                  into: capped,
                                                  capacity: 3)
    }
    assertEqual(capped.count, 3, "超出容量被截断")
    assertEqual(capped.first?.origin.x, 11, "保留最新三条")

    // 编码往返
    let encoded = SnipSelectionHistoryCoding.encode([a, b, c])
    assertEqual(SnipSelectionHistoryCoding.decode(encoded), [a, b, c], "历史编码往返一致")
    assertEqual(SnipSelectionHistoryCoding.decode("") == [], true, "空串得空历史")
    assertEqual(SnipSelectionHistoryCoding.decode(nil) == [], true, "nil 得空历史")
    assertEqual(SnipSelectionHistoryCoding.decode("1,2,3;bad;0,0,50,50"),
                [CGRect(x: 0, y: 0, width: 50, height: 50)], "非法条目被跳过")
    assertEqual(SnipSelectionHistoryCoding.push(CGRect(x: 0, y: 0, width: 0, height: 10), into: [a]),
                [a], "零宽不进历史")
}
