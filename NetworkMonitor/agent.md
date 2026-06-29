# Agent Instructions

## 编译规则

每次完成代码功能修改后，**必须**执行编译验证：

```bash
swift build --disable-sandbox
```

确认编译通过（无 error）后再进行提交。如果编译失败，先修复问题再继续。

## 提交规范

提交信息使用中文，格式：`<type>: <描述>`

- `feat:` — 新功能
- `refactor:` — 重构
- `fix:` — 修复 bug
- `chore:` — 杂项
