# 应用图标生成

唯一设计源为 [icon_rounded.svg](../../assets/icon/icon_rounded.svg)。保留白色圆角底和黑色 az 标识，不修改其比例。

需要 Node.js、npm 和项目使用的 FVM / Flutter。首次安装或依赖变更后：

```bash
npm ci --prefix tool/icons
npm run generate --prefix tool/icons
```

脚本先调用 icons_launcher 更新各平台资源目录及引用，再用 resvg 从 SVG 按每个目标尺寸直接栅格化，避免用已栅格化的 PNG 再次缩小。后续重新生成请使用此命令，而不是仅运行 icons_launcher，否则会恢复工具默认的位图缩放输出。

- Windows ICO 含 16、24、32、48、64、96、128、256px，每层独立渲染。
- iOS 从同一个 SVG 铺白底输出 RGB PNG，避免透明角变黑。
- Linux 桌面图标输出 1024px，避免原来 256px 在高分屏上放大。
- UI 使用独立的 128px 基础图和 2x / 3x / 4x 密度变体，Flutter 自动选择。
- Android、iOS、macOS 的目标尺寸由 icons_launcher 生成的资源决定。
- 生成后会检查输出尺寸、iOS RGB 格式及 ICO 各层尺寸。平台外观/缓存仍需在重新构建、安装后确认。
