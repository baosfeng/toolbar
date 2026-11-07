# SQLite 绑定传 nil 等于不复制内容

> **何时阅读：** 写入数据库后偶尔读到上一次的内容、乱码、或字段互相串味；新增任何 `sqlite3_bind_text` 调用前。

## 问题描述

`sqlite3_bind_text` 的第四个参数是析构器（destructor），决定「SQLite 要不要复制这段文本」：

- `SQLITE_TRANSIENT`（`unsafeBitCast(-1, to: sqlite3_destructor_type.self)`）= **复制**，绑定后可以立刻释放原字符串；
- `nil`（= `SQLITE_STATIC`）= **只存指针，不复制**，调用方必须保证这块内存在语句 finalize 之前一直有效。

本仓库曾经 25 处全部传 `nil`，而真正的出处是这句写法：

```swift
sqlite3_bind_text(stmt, index, (value as NSString).utf8String, -1, nil)
```

`(value as NSString)` 是临时桥接对象，`.utf8String` 返回的缓冲区**随该对象释放即失效**。
表达式结束后指针就可能悬空，SQLite 写进库里的可能是上一次的字符串、乱码，或者干脆是空。

## 实测

把析构器改回 `nil` 后，剪贴板第一条插入就直接失败（写入后按 id 回读返回 `nil`），
不是「偶发」而是稳定复现——只是平时内存没被立刻复用时看不出来。

## 解决方案

统一走一个入口，禁止再直接调用 `sqlite3_bind_text`：

```swift
// DatabaseManager.swift
static var sqliteTransient: sqlite3_destructor_type {
    unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}

func sqlite3_bind_text_copy(_ stmt: OpaquePointer?, _ index: Int32, _ value: String) {
    sqlite3_bind_text(stmt, index, value, -1, Self.sqliteTransient)
}
```

`sqlite3_open` 的路径同理：用 `dbPath.withCString { sqlite3_open($0, &db) }`，
不要用 `(dbPath as NSString).utf8String` 传进去。

## 如何识别

- 回读到的文本与写入时不符、长度对但内容是别的行；
- 只在批量写入（同一语句反复 reset/rebind）时出现；
- 新增的写入路径「测试偶尔红」——先看这里，而不是怀疑并发。

## 参考文件

- `NetworkMonitorCore/DatabaseManager.swift`（`sqlite3_bind_text_copy` / `sqlite3_bind_text_or_null`）
- `TestRunner/ClipboardRepositoryTests.swift`（`runClipboardBindingLifetimeTests`：24 条不等长文本写入后逐条回读）
