# 自签名 App 读钥匙串会弹框并卡死主线程

> **何时阅读：** 想给本项目加钥匙串（`SecItemCopyMatching` / `kSecClassGenericPassword`）存储时；
> 或 App 启动后菜单栏图标出现但完全不响应。

## 问题描述

钥匙串条目的 ACL 是按**代码签名**绑定的。本项目用自签名证书（`SIGN_IDENTITY=NetworkMonitor Local Signing`）
或 ad-hoc 回落，而 `build-app.sh` **每次重建都会重签**，签名身份（cdhash）随之变化。
身份一变，之前那条钥匙串条目的 ACL 就不匹配，系统弹出

> 「NetworkMonitor」想要使用你在钥匙串中的机密信息

并且**阻塞调用线程**直到用户点掉。菜单栏 App 是 `LSUIElement`，弹框可能出现在别的空间，
用户看到的现象是「App 启动了但完全没反应」。

## 实测

```bash
sample $(pgrep -f '^/Applications/一览.app/Contents/MacOS/一览') 1   # 旧包的可执行名是 NetworkMonitor
# 主线程停在：
#   KeychainSecretStore.secret(forKey:)
#   SecItemCopyMatching → SecKeychainItemCopyContent → ...
```

同时 `System Events` 里 `SecurityAgent` 有 1 个窗口。

## 解决方案

1. **不要**在签名身份不稳定时把钥匙串放进启动路径。本项目当前默认用
   `PreferencesSecretStore`（写回 `KeyValueStorage`），钥匙串仅作显式可选；
2. 真要启用钥匙串，前置条件是稳定签名身份：

   ```bash
   codesign -d -r- /Applications/一览.app   # designated requirement 不能含 cdhash
   ```

   `build-app.sh` 的 `assert_stable_signature` 已能拦这一条（ad-hoc 分支只警告，不拦）；
3. 顺手要区分「秘密存储是否与偏好共用底层」（`SecretStorage.sharesStorageWithPreferences`）：
   共用时把读到的值当「遗留明文」删掉等于**清空用户凭据**。
   这个标记必须是**协议要求**——写在协议扩展里的默认实现不进 witness table，
   通过 `any SecretStorage` 调用会静态解析到默认值。

## 如何识别

- App 进程存在但不响应，`sample` 里主线程在 `SecItemCopyMatching`；
- `ps` 里 `SecurityAgent` 有窗口，且能 `osascript` 数到 1；
- 换一次构建（重新签名）就复现，换成 `swift run` 直接跑二进制反而不复现。

## 参考文件

- `NetworkMonitorCore/Billing/KeychainSecretStore.swift`（`KeychainSecretStore` / `PreferencesSecretStore`）
- `NetworkMonitor/Scripts/build-app.sh`（`assert_stable_signature`）
