# 内嵌字体

随应用分发，启动时由 `src/main.cpp` 从可执行文件旁的 `fonts/` 目录加载。文件未经修改。

| 文件 | 来源 | 许可 |
|---|---|---|
| `NotoSansSC-Regular.otf`、`-Medium.otf`、`-Bold.otf` | https://github.com/notofonts/noto-cjk （`Sans/SubsetOTF/SC`） | SIL OFL 1.1，见 `LICENSE-NotoSansSC.txt` |
| `JetBrainsMono-Regular.ttf`、`-Bold.ttf` | https://github.com/JetBrains/JetBrainsMono （`fonts/ttf`） | SIL OFL 1.1，见 `LICENSE-JetBrainsMono.txt` |

界面字重只有三档：Regular、Medium、Bold。请求 DemiBold 时 Qt 会落到 Bold，所以界面层级只用这三档。
