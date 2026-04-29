# Godot 开发前检查清单

## 1) 引擎与环境

- [ ] 已安装 Godot 4.x（建议 4.2+）
- [ ] 命令行可用：`godot4 --version` 或 `godot --version`
- [ ] 显卡驱动已更新（Windows 建议保持最新稳定版）

## 2) 项目结构

- [x] 存在 `project.godot`
- [x] 主场景已配置：`res://scenes/Main.tscn`
- [x] 主场景脚本存在：`res://scripts/Main.gd`
- [x] 资源图标存在：`res://icon.svg`
- [x] 已配置 `.gitignore`（忽略 `.godot/` 等缓存目录）

## 3) 仓库状态

- [ ] `git status` 无冲突
- [ ] 分支命名符合团队规范

## 4) 运行前快速验证

- [ ] `godot4 --headless --path . --quit`（或 `godot --headless --path . --quit`）可正常退出
- [ ] 首次打开编辑器时无解析错误
- [ ] 运行主场景后控制台输出 `Godot project bootstrap is ready.`

## 5) 下一步建议

1. 在 `scenes/` 下补齐 `Boot.tscn`、`Battle.tscn`、`UIRoot.tscn`
2. 明确资源目录：`assets/art`、`assets/audio`、`assets/config`
3. 建立自动化检查脚本（启动检查 + 关键场景加载检查）
