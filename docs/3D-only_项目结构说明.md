# 3D-only 项目结构说明

## 1. 当前基线
- 项目当前仅保留 3D 交互验证链路。
- 默认启动场景为 `res://scenes/Main3D.tscn`。
- 主交互脚本为 `res://scripts/MainInteractive3D.gd`。

## 2. 场景与脚本
- 场景：`scenes/Main3D.tscn`
  - 包含 `Camera3D`、方向光、环境、网格容器与状态 UI。
- 脚本：`scripts/MainInteractive3D.gd`
  - 场景装配层（网格构建、边界计算、状态UI刷新）。
- 脚本：`scripts/CameraController3D.gd`
  - 边缘滚屏
  - 左键长按拖拽平移
  - 右键长按拖拽旋转（`yaw/pitch`）
  - 鼠标滚轮缩放（`distance`）
  - 角度与距离边界限制（禁止底部视角）

## 3. 已清理的旧内容
- 已移除旧 2D 测试场景与脚本：
  - `scenes/Main.tscn`
  - `scripts/MainInteractive.gd`
- 已移除不再使用的旧演示脚本：
  - `scripts/Main.gd`

## 4. 后续约定
- 新交互功能优先在 `MainInteractive3D.gd` 上迭代。
- 若拆分模块，建议新增目录 `scripts/camera/`，将相机控制抽为可复用组件。
