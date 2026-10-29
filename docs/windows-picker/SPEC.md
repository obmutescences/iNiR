# 窗口选择器（Windows Picker）实现规范

> 状态：设计冻结，按本文实现
> 参考稿：本目录 `demo.html`（行为与参数的唯一基准）
> 适用：iNiR / Quickshell（Niri 会话）

本文约束后续 QML 实现。参数与 `demo.html` 一一对应；若两者冲突，以 demo 的观感为准，并同步修改本文，禁止只改一边。

---

## 1. 范围

**做**：一个全屏窗口选择器。按下触发键后，当前输出上的所有窗口缩小、铺成网格，每张卡片顶部正中有一个字母键帽；按字母聚焦对应窗口；Esc / 点击空白关闭。

**不做**：

- 不修改现有的 `modules/overview`（它是实时的 workspace 总览，与本功能独立）。
- 不做背景的“压暗 / 模糊”多档；背景固定为毛玻璃（见 7.5）。
- 不做窗口拖拽、调整大小、多选；只聚焦。

---

## 2. 交互契约

| 输入 | 行为 |
|---|---|
| 触发键（niri bind → IPC） | 打开；再次触发或 Esc 关闭 |
| 字母键 | 单字母模式：按下即跳转；双字母模式：先按首字母缩小候选，再按第二字母跳转（见 3.2） |
| 首字母按下后 800ms 无第二键 | 取消前缀，恢复全部候选 |
| 单击卡片 | 同字母 |
| 单击空白 | 关闭 |
| Esc | 有前缀时清空前缀；无前缀时关闭 |
| 关闭后 | 所有卡片沿原路散开回窗口位置 |

- 打开期间面板必须独占键盘焦点，否则字母会被 niri 的 bind 截走。
- 编码容量见 3.2：配置的字母不够时自动升级为双字母码；超出容量（`|L| × (|L| − 1)`）的窗口只能鼠标选择，网格仍然显示。

---

## 3. 数据与集成（已存在的 API）

| 需求 | 现成实现 |
|---|---|
| 窗口列表（布局序） | `NiriService.windows`，已由 `sortWindowsByLayout()` 按 output → workspace → column → row 排序 |
| 窗口 ↔ Wayland toplevel | `NiriService.sortToplevels([...ToplevelManager.toplevels.values])`，返回带 `niriWindowId` / `_sourceToplevel` 的富集对象 |
| 缩略图 | `ScreencopyView { captureSource: toplevel }`，用法见 `modules/overview/OverviewWindow.qml` |
| 聚焦 | `NiriService.focusWindow(windowId)` |
| 图标兜底 | `AppSearch.getIconSource(appId)` |

`sortToplevels` 只返回有 niri 窗口对应的 toplevel（自动丢弃 stale handle），直接用它作为卡片数据源，不要再自行按 appId/title 匹配。

**卡片数据模型**：

```qml
// 由 sortToplevels() 产出
{
    niriWindowId: int,
    appId: string,
    title: string,
    activated: bool,        // 当前焦点窗口
    _sourceToplevel: Toplevel
}
```

**缩略图**：`ScreencopyView { captureSource: toplevel }` 在本机返回 `non captureable object`（compositor 未暴露 toplevel 图像捕获），因此改用仓库既有的 `WindowPreviewService`：打开时 `captureForTaskView(ids, 15000)` 后台刷新，卡片直接读 `getPreviewUrl(id)` 缓存。代价是**离屏窗口可能截到空白帧**（niri 只渲染可见窗口），见 10.5。

**字母分配**：由配置的字母集合决定，见 3.2；不再固定为 A–H。

**排序稳定性**：窗口列表变化（打开/关闭/移动）时不要在打开状态下重排卡片；打开瞬间取一次快照，关闭时丢弃。

### 3.1 `fly` 的窗口矩形（已落地为近似值）

`fly` 需要每个窗口在**当前输出上的屏幕矩形**（逻辑像素）。niri 的 `windows` IPC 只给 `layout.pos_in_scrolling_layout` 与 `layout.tile_size`，没有 view 滚动偏移，也拿不到输出内绝对坐标；`tile_pos_in_workspace_view` 在当前版本对平铺窗口恒为 `null`。

当前实现（`PickerMath.windowStartRect`）：

- 按 workspace 汇总每列的 `tile_size[0]` 与每行的 `tile_size[1]`，累加得到列起点与行偏移。
- 把**焦点窗口所在列**居中到输出宽度，其余列相对平移；非当前 workspace 的窗口按同一规则以第 1 列为锚点。
- 浮动窗口用 `layout.window_size` 居中。
- 结果只用于入场起点，误差不影响落点（落点始终是槽位）。

如果后续 fork 在 IPC 里补 `screen_rect`，只替换 `pickerMath.windowStartRect`，其余动画代码不动。

### 3.2 字母与编码

配置项 `windowsPicker.letters`：参与选择的字母集合，字符串，例如 `"asdfghjkl"`。

**规范化**：

- 只保留 `a–zA–Z`，统一大写，去重，保持配置顺序。
- 为空，或去重后少于 2 个字母 → 视为配置错误，回落到默认值。
- 规范化结果就是单字母模式的顺序，不要额外打乱。

**分配**（打开时一次性算好，快照期间不变）：

设 `L` 为规范化后的字母数组，`N` 为窗口数。

| 条件 | 编码方式 |
|---|---|
| `N ≤ L.length` | 单字母：第 i 个窗口取 `L[i]`，按配置顺序 |
| `N > L.length` | 双字母：**所有**窗口都用两位码，禁止长短混排 |

双字母码：

- 候选池 = 所有两位互不相同的组合 `(a, b), a ≠ b`，共 `|L| × (|L| − 1)` 个（9 个字母 → 72 个）。
- 打开时打乱候选池，按窗口顺序取前 `N` 个；随机只生成一次，关闭前复用。
- 池子不够（`N > |L| × (|L| − 1)`）：多出的窗口没有编码，只能鼠标点击，并 `warn` 一次。
- 键帽显示大写；双字母显示成 `AE`，宽度按文本自适应（最小 36px），不需要额外样式。

**输入**：

```
单字母模式：按下某字母 → 立即跳转

双字母模式：
  首字母        → 记录前缀，非匹配卡片降到 35% 不透明度（仍可点击）
  第二字母      → 命中则跳转；不命中清空前缀
  800ms 无第二键 → 清空前缀，不跳转
  Esc           → 有前缀时只清前缀；无前缀时关闭面板
```

前缀期间在标题下方显示已输入内容（如 `A…`）；该提示与「面板」配置组无关，始终可用。

> demo 只演示固定的 A–H 单字母；字母配置与双字母编码以本节为准，demo 不覆盖这部分。

**示例**：

| 配置 | 窗口数 | 结果 |
|---|---|---|
| `asdfghjkl` | 8 | `A S D F G H J K` |
| `asdfghjkl` | 12 | 12 个双字母码，从 72 个组合中随机取 |
| `ae` | 8 | 只有 `AE`、`EA` 两个码，其余 6 个窗口无编码 |

---

## 4. 视觉 Token

| Token | 值 | 说明 |
|---|---|---|
| `wpPrimary` | 主色 `L=0.30` | 卡片底色 / 信息条底色（深色，暗一档） |
| `wpPrimaryHover` | 主色 `L=0.36` | hover 提亮一档 |
| `wpPrimaryStrong` | 主色 `L=0.42` | 键帽渐变上端 |
| `wpAccent` | 主色 `L=0.84` | 聚焦环 / 辉光 / 标题（同色相亮色） |
| `wpInk` | `IrisStyle.secondaryAccent` | 标题、副标题、键帽字母（= 中心面板内存卡的颜色） |
| 页面底色 | 壁纸模糊 + 渐变 scrim | 见 6.5 |

**信息条不得叠加白色高光**：早期实现用 `rgba(255,255,255,.22)` 的 sheen 盖在信息条上，会把深色主色洗成白色，已删除。

壁纸取色完成后，只替换上面 4 个颜色；其余保持不变。文字与主色必须保持对比，取色结果过亮/过暗时按 4.1 归一化，不要引入第二套配色。

### 4.1 主色亮度归一化（必须）

壁纸主色直接当背景会失控：亮黄、荧光色、近黑都会让整条信息栏难看。取到壁纸主色后，**丢弃原亮度，固定 L**，只保留色相：

1. 主色转 HSL，色相 `H` 原样保留。
2. 饱和度 `S` 夹到 `[0.20, 0.40]`（阈值：再高刺眼，再低发灰）。
3. 亮度 `L` 固定为深色档：

| Token | L | 说明 |
|---|---|---|
| `wpPrimary` | `0.30` | 卡片 / 信息条底色（固定亮度，不随壁纸明暗变化） |
| `wpPrimaryHover` | `0.36` | hover 提亮 |
| `wpPrimaryStrong` | `0.42` | 键帽渐变上端 |
| `wpAccent` | `0.84` | 同色相亮色，仅用于聚焦环/辉光/标题 |

4. 文字用**中心面板内存卡的颜色**：`IrisStyle.secondaryAccent`，原样使用，不做 HSL 归一化。它会随主题/高亮配置变化（默认橙），在深色主色底上始终醒目。

```qml
const s = Math.min(0.40, Math.max(0.20, primary.hslSaturation))
const primaryDeep = Qt.hsla(wallpaperDominant.hslHue, s, 0.30, 1)
const ink = IrisStyle.secondaryAccent
```

- 只在壁纸/主题色变化时计算一次并缓存，不要在 `onPaint` 或动画里重复换算。
- 取色失败（透明、无效）时回落写死值。
- 深底 + 浅字，对比度稳定；不要再用白色 sheen 提亮信息条。

---

## 5. 布局与几何

### 5.0 多窗口布局（自适应，必须实现）

窗口经常超过 10 个，固定 4 列×固定卡片会溢出。规则：

1. **列数不是常量**：在 4–8 之间搜索，对每个列数算出能让卡片最大的宽度，取最大值；同等宽度取列数更少者（卡片更大、更好扫视）。
2. **卡片宽度** = `min(上限, 按宽度, 按高度)`，下限 140px：
   - 按宽度 = `(可用宽 − 间距 × (列−1)) / 列`
   - 按高度 = `((可用高 − 行距 × (行−1)) / 行 − 信息条高) / 0.625`
   - 上限由 `cardSize` 决定（见 7.1）；`auto` 上限 = `0.9 × clamp(屏宽 16%, 260, 420)`。
3. **行数** = `ceil(N / 列)`；不足一行的最后一行**不拉伸网格**，按实际用到的列数居中。
4. **放不下时滚动**：卡片已到 140px 下限仍超过可用高（约 64 个窗口以上）时，网格放进 `Flickable`，滚轮纵向滚动；键盘命中不要求先滚动（快照已含全部卡片）。
5. 头部只有一行 `Windows <数量>`，水平居中置顶；不显示操作提示、不显示前缀文字（前缀靠卡片压暗反馈）。

实测（2560×1440，`cardSize=auto`）：

| 窗口数 | 列×行 | 卡片宽 | 是否滚动 |
|---|---|---|---|
| 1 | 4×1（单卡居中） | 369 | 否 |
| 4 | 4×1 | 369 | 否 |
| 8 | 4×2 | 369 | 否 |
| 12 | 4×3 | 369 | 否 |
| 16 | 4×4 | 369 | 否 |
| 20 | 5×4 | 369 | 否 |
| 28 | 7×4 | 318 | 否 |
| 36 | 8×5 | 271 | 否 |
| 48 | 8×6 | 202 | 否 |
| 56+ | 8×N | 触底 140 | 是 |

| 项 | 值 |
|---|---|
| 网格列数 | 4–8（自适应，见 5.0） |
| 列间距 | 24px |
| 行间距 | 44px（必须 > 21px，给键帽外露让位） |
| 外边距 | 左右 `clamp(36px, 5vw, 96px)`，上下 `clamp(32px, 5vh, 64px)` |
| 网格最大宽 | 1140px |
| 卡片圆角 | 14px |
| 缩略图 | 宽高比 16:10，铺满卡片上半部分，顶角 13px（= 14 − 1px 边框） |
| 信息条 | 内边距 10px 14px 12px |
| 标题 | 12.5px / 570，红色 |
| 副标题 | 10px 等宽，红色 62% 不透明 |
| 卡片边框 | 1px `wpPrimaryStrong`（主色，不允许白色） |
| 卡片阴影 | **默认无**；只有聚焦卡片有主色阴影/辉光 |
| 缩略图顶部压暗 | 76px，`rgba(0,0,0,.42)` → 透明 |

**自动适配**：卡片宽度按可用区域计算，若 `4 列 × 卡片高` 超出可用高度，等比缩小卡片宽度直到放下。8 个窗口时目标卡片宽约 270px。

### 5.1 字母键帽

骑在卡片顶边上：**外露 21px，压在缩略图上 11px**（32px 高的 1/3 在内）。

| 项 | 值 |
|---|---|
| 尺寸 | 宽 `max(36, 文本+18)`，高 32 |
| 圆角 | 10px |
| 位置 | 水平居中；相对卡片顶边 `top: -22px`（含 1px 边框后外露 21） |
| 底色 | 渐变 `wpPrimaryStrong → wpPrimary`（深色主色），1px `rgba(0,0,0,.22)` 描边 |
| 文字 | 等宽 700 / 15px，`wpInk`（副色） |
| 阴影 | `0 2px 0 rgba(0,0,0,.32)`（键帽厚度）+ `0 10px 22px -10px rgba(0,0,0,.8)` |
| hover | `scale 1.04`、上移 1px |
| 聚焦 | 反相：副色底 `wpInk → darker(wpInk)`，深主色字 `wpPrimary`，外发光 `wpAccent`，`scale 1.08` |

卡片**不能裁切**键帽（`clip: false`）；缩略图自己 `clip: true` 并保留顶角圆角。

双字母码（如 `AE`）不需要额外样式：键帽宽度按文本自适应（`max(36, 文本+18)`），不要为了塞下两个字母去缩小字号。

### 5.2 卡片状态

| 状态 | 变换 | 阴影 |
|---|---|---|
| 常态 | 无 | 见上表 |
| hover | `translateY(-4px) scale(1.03)`，180ms | 无 |
| 聚焦（字母命中/点击） | `translateY(-3px) scale(1.02)`，180ms | `0 0 0 2px wpAccent` + 主色辉光（无黑色阴影） |

- **打开时默认聚焦当前窗口**：`focusId` 取快照里 `is_focused` 的窗口，它的卡片直接进入聚焦态（与 hover 相同的 `-4px / 1.03` + 主色辉光）。
- 其余卡片**没有任何阴影**；只有聚焦卡片有主色辉光。
- 聚焦是**状态**，不是动画层；它只改卡片自身的属性。

---

## 6. 动画规范

所有时长可被调试用「慢放 ×3」整体缩放，生产环境固定 1×。

### 6.1 出现（可配置，5 种效果 + 随机）

| 模式 | 起始状态 | 时长 / 曲线 | 透明度 |
|---|---|---|---|
| `fly`（默认） | 真实窗口矩形：平移 + 非等比缩放，原点左上 | 560ms `[0.16,1,0.3,1]` | 240ms |
| `slide_up` | 下移 56px | 560ms `[0.16,1,0.3,1]` | 300ms |
| `zoom_rotate` | `scale .34` + 旋转 −10° | 640ms `[0.34,1.56,0.44,1]`（回弹） | 300ms |
| `flip` | `rotateX(82°)` + 下移 26px，原点底边 | 620ms `[0.25,.9,.35,1.04]` | 220ms |
| `unfold` | 裁剪 `inset(0 0 100% 0 round 14px)` | 560ms `[0.16,1,0.3,1]` | **无**（保持不透明） |
| `random`（配置值） | 每次打开等概率抽上面 5 种之一 | 同抽中的模式 | 同抽中的模式 |

- `fly` 的起始矩形必须在打开前测量好并直接写入卡片（不做过渡），下一帧再启动动画，否则会从网格位置“跳”一下。
- `unfold` 只靠裁剪，关闭态 `opacity` 保持 1，不能淡出。
- 五种模式共用同一套 stagger 延迟。
- `random` 不是第 6 种效果，而是**选择器**：只在打开时抽一次，抽中的模式在本次打开→关闭期间固定；散开必须复用同一种。重新打开才重抽，禁止每帧或每卡重抽。
- 与 6.3 的 `random`（打乱延迟）是两个独立维度，可以同时启用。

```qml
const pool = ["fly", "slide_up", "zoom_rotate", "flip", "unfold"]
resolvedAppearance = appearanceMode === "random"
    ? pool[Math.floor(Math.random() * pool.length)]
    : appearanceMode
```

### 6.2 散开（关闭）

- 反向回到 6.1 的起始状态，时长 460ms，曲线 `[0.65,0,0.35,1]`。
- 透明度延迟淡出：`delay = 该卡 stagger 延迟 + 280ms`，时长 150ms，线性。
- `unfold` 关闭时同样走裁剪（反向卷回），不做透明度。
- 关闭后必须把 `ScreencopyView.captureSource` 置空，释放采集。

### 6.3 聚集（可配置，4 选 1）

只决定每张卡的 `delay`（毫秒），不影响时长与曲线。

| 模式 | 公式 | 8 卡实测范围 |
|---|---|---|
| `cascade`（默认） | `(row + col) × 90` | 0–360 |
| `circular` | `centerDistance × 200` | 100–320 |
| `random` | `rand(0..1) × 400` | 0–400 |
| `wave` | `col × 120 + row × 60` | 0–420 |

- `row`/`col` 是卡片在网格中的行列；`centerDistance` 以网格中心归一化。
- `random` 的随机值在打开时生成一次，关闭时复用同一组，不要每次重算。
- 延迟小于 100ms 的差异人眼基本看不出，禁止把系数改小。

### 6.4 面板（可配置，3 选 1）

面板层 = 覆盖层容器 + 标题/提示文字 + 网格容器。

| 模式 | 标题（`Windows <数量>`）行为 |
|---|---|
| `none`（默认） | 随状态瞬时显示/隐藏，无过渡 |
| `late` | 打开后延迟 340ms，再 140ms 淡入；关闭时立即消失 |
| `sync` | 与窗口同时开始，280ms 淡入（仅作对比，不建议） |

**硬性规则**：

- 容器**禁止**做 `opacity` 或 `transform` 动画。容器透明度会与卡片透明度相乘，压平 8 张卡的 stagger；容器变换会与卡片变换复合，扭曲飞行轨迹。
- 关闭时容器不能整体淡出，否则散开飞行会被一起透明掉。
- 背景层（7.5）可以过渡，因为它永远在窗口后面，且不参与卡片合成。

### 6.5 背景（固定毛玻璃，不可配置）

| 项 | 值 |
|---|---|
| 遮罩渐变 | `linear-gradient(180deg, rgba(20,28,41,.52), rgba(8,11,17,.74))` |
| 模糊 | 34px，饱和度 1.1 |
| 过渡 | 透明度 200ms `[0.25,.46,.45,.94]`；模糊 280ms 同曲线 |
| 高光 | 115° 白色斜向扫光，6% → 透明 → 3% |

Quickshell 没有 CSS 的 `backdrop-filter`：毛玻璃 = 一张全屏画面 + 模糊。

- 触发时先对当前输出做一次静态截屏（`ScreencopyView` / 一次性截图），在截屏层上叠 `FastBlur` / `MultiEffect` 模糊，再显示面板。
- **必须先截屏再显示面板**，否则截到的画面里含面板自身，会出现递归拖影。
- 截屏不可用（权限/性能）时，降级为纯渐变遮罩，不显示模糊；不要用半透明窗口假装玻璃。

---

## 7. 配置（必须实现）

三组可配置项，背景不配置。

### 7.1 Schema（`modules/common/Config.qml`）

```qml
property JsonObject windowsPicker: JsonObject {
    property bool enable: true
    property string appearance: "fly"   // fly | slide_up | zoom_rotate | flip | unfold | random
    property string gather: "cascade"   // cascade | circular | random | wave
    property string panel: "none"       // none | late | sync
    property string cardSize: "auto"     // auto | compact | large（卡片宽度上限）
    property string letters: "asdfghjkl" // 参与选择的字母，规范化后去重大写
}
```

### 7.2 默认值（`defaults/config.json`）

```json
"windowsPicker": {
  "enable": true,
  "appearance": "fly",
  "gather": "cascade",
  "panel": "none",
  "cardSize": "auto",
  "letters": "asdfghjkl"
}
```

### 7.3 消费端读取

```qml
readonly property string appearanceMode: Config.options?.windowsPicker?.appearance ?? "fly"
readonly property string gatherMode: Config.options?.windowsPicker?.gather ?? "cascade"
readonly property string panelMode: Config.options?.windowsPicker?.panel ?? "none"
readonly property string lettersSpec: Config.options?.windowsPicker?.letters ?? "asdfghjkl"
readonly property string cardSize: Config.options?.windowsPicker?.cardSize ?? "auto"

// 规范化：只留 A–Z，去重，保持顺序；不足 2 个字母时回落默认
readonly property var letters: {
    const raw = [...lettersSpec.toUpperCase()].filter(ch => ch >= "A" && ch <= "Z")
    const uniq = [...new Set(raw)]
    return uniq.length >= 2 ? uniq : [..."ASDFGHJKL"]
}
```

非法值必须回落到默认值（`includes` 校验），不要让未知字符串进入动画代码；字母同样必须走上面的规范化，不能直接 `split("")`。

### 7.4 Settings UI

在拥有 Overview/Windows 分区的 Settings 家族里添加三项 `kind: "choice"` 与一项字母输入（示例为 Iris 家族，`modules/iris/settings/IrisOptions.qml` 的 `{section, group, label, path, fallback, choices, keywords}` 描述符）：

| 标签 | path | 控件 |
|---|---|---|
| 出现动画 | `windowsPicker.appearance` | `choice`：归位 / 向上滑入 / 缩放旋转 / 翻转 / 卷帘 / 随机 |
| 聚集方式 | `windowsPicker.gather` | `choice`：网格级联 / 圆形扩散 / 随机 / 波浪 |
| 面板 | `windowsPicker.panel` | `choice`：无 / 延后 / 同步 |
| 卡片大小 | `windowsPicker.cardSize` | `choice`：自适应 / 紧凑 / 大 |
| 参与字母 | `windowsPicker.letters` | `text`：如 `asdfghjkl`；说明写“窗口多于字母时自动两两组合” |

其他家族若已有对应分区，同步添加；没有则不加，不要为它新建分区。

### 7.5 写配置

只能通过：

```qml
Config.setNestedValue("windowsPicker.appearance", "flip")
```

直接写 `Config.options.windowsPicker.appearance = ...` 只在内存生效，是已知 bug 来源。

配置改动在下一次打开时生效（不要求热重播）；`Config` 本身会在 50ms 内刷新。

---

## 8. QML 实现要点

### 8.1 结构

建议落地目录 `modules/windowsPicker/`：

```
WindowsPicker.qml   // PanelWindow + 状态机（打开/关闭/快照）
WindowCard.qml      // 单卡：缩略图 + 键帽 + 信息条 + 动画
qmldir
```

挂载到现有 shell 的 overlay 层（与 `modules/overview` 同级），由 IPC/快捷键触发，不常驻可见。

```
PanelWindow（layer: overlay, keyboardFocus: OnDemand, 当前输出）
├─ 背景层：静态截屏 + 模糊 + 渐变遮罩          // 不参与动画，只过渡透明度/模糊
├─ 标题 / 提示                                // 只随 panel 模式改变可见性
└─ 卡片容器 Item
   └─ Repeater → WindowCard（绝对定位）
```

**不要用 GridLayout / GridView 摆放卡片**：`fly` 需要从任意矩形出发、再落到槽位。用 JS 计算槽位矩形（4 列、间距、上限 1140px），卡片直接设置 `x / y / width / height`。

### 8.2 槽位计算

```
cardW = min(280, (min(availW, 1140) - 3*gapX) / 4)
cardH = cardW * 10/16 + metaH
x = col * (cardW + gapX)
y = row * (cardH + gapY)
```

若 `rows * (cardH + gapY) - gapY > availH`，按比例缩小 `cardW` 后重算。

### 8.3 FLIP（fly）

1. 面板显示前：记录每张卡片的槽位矩形与对应窗口的屏幕矩形。
2. 卡片先按**源矩形**摆好（`x/y/width/height` 直接赋值，禁用动画）。
3. 下一帧启用动画，目标设为槽位矩形；透明度同时 0 → 1。
4. 关闭时反向：目标设为源矩形，透明度延迟淡出。

### 8.4 曲线映射

CSS `cubic-bezier(x1,y1,x2,y2)` → QML：

```qml
easing.type: Easing.Bezier
easing.bezierCurve: [0.16, 1, 0.3, 1]
```

| 名称 | 值 |
|---|---|
| ease-out-quad | `[0.25, 0.46, 0.45, 0.94]` |
| ease-out-expo | `[0.16, 1, 0.3, 1]` |
| ease-in-out-cubic | `[0.65, 0, 0.35, 1]` |
| spring-soft | `[0.25, 0.9, 0.35, 1.04]` |
| spring-bouncy | `[0.34, 1.56, 0.44, 1]` |

### 8.5 翻转（flip）

```qml
transform: Rotation {
    axis { x: 1; y: 0; z: 0 }
    angle: card.revealed ? 0 : 82
    origin { x: card.width / 2; y: card.height }
}
```

Qt Quick 对 3D transform 走场景图投影，观感以 demo 为准；若太平，优先换 `scaleY` 之外的近似方案前先确认角度方向（正负号）正确。

### 8.6 卷帘（unfold）

外层固定槽位大小，内层 `clip: true`，动画 `height` 0 → 卡片高；卡片内容 `anchors.top` 固定，只显示顶部开始的部分。不要用 `scaleY`（会把内容压扁）。

### 8.7 键帽

```qml
Item {                       // 卡片根：clip: false
    Rectangle { id: thumb; clip: true; topLeftRadius: 13; topRightRadius: 13 }
    Item {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: -22   // 外露 21px，内部 11px
    }
}
```

`topLeftRadius/topRightRadius` 需 Qt 6.7+；更低版本用圆角 Mask（仓库里 `OverviewWindow.qml` 已有 `OpacityMask` 先例）。

### 8.8 性能与降级

- 缩略图用 `live: false`（一次性帧），折叠后 `captureSource: null`；不要 8 个 live capture 常驻。
- 动画期间禁止重算缩略图；`GameMode` / 录制中不保留采集。
- `Appearance.animationsEnabled` 为 false 时：跳过出现/散开动画，直接切状态（stagger 也置 0）。
- 单屏 8 窗口目标 60fps；超过 16 窗口允许降低缩略图分辨率。

---

## 9. 验收清单

- [ ] 触发键打开，所有窗口铺成网格，键帽居中骑在卡片顶边（外露 21 / 内部 11）。
- [ ] 顶部只有居中的 `Windows <数量>`，没有其他提示文字。
- [ ] 12 个窗口在 2560×1440 下排成 4×3，卡片宽 369，间距 24/44，不滚动、不重叠。
- [ ] `letters="asdfghjkl"` + 8 窗口：单字母按配置顺序 `A S D F G H J K`。
- [ ] `letters="asdfghjkl"` + 12 窗口：全部换成互不相同的双字母码，随打开随机、关闭前不变。
- [ ] 双字母输入：首字母后 800ms 无第二键则清空前缀；第二键不命中清空前缀；Esc 先清前缀再关闭。
- [ ] 字母配置去重/大写/非法字符剔除；少于 2 个字母回落默认；超出组合容量的窗口只能鼠标点击。
- [ ] 5 种出现模式与 4 种聚集模式在配置里可切换，下一次打开生效，行为与 demo 一致。
- [ ] `appearance="random"`：每次打开抽一次，本次关闭沿用同一种；不会每卡/每帧重抽。
- [ ] 壁纸主色为亮黄/荧光/近黑时，信息栏亮度仍固定 L=0.84、S 夹在 0.20–0.40，红字对比稳定。
- [ ] 3 种面板模式可切换；`none` 时文字瞬切；容器在任何模式下都没有 opacity/transform 动画。
- [ ] 背景始终是毛玻璃（34px），没有压暗/模糊选项。
- [ ] 按字母高亮卡片、180ms 后聚焦并关闭；Esc 与点击空白关闭。
- [ ] 关闭时卡片散开回窗口位置，透明度延迟到 280ms 后才淡出（`unfold` 不淡出）。
- [ ] 信息条底色 = 壁纸主色固定 `L=0.30`（深色），标题/副标题/键帽字母 = `IrisStyle.secondaryAccent`；条上不得有白色高光。
- [ ] 未聚焦卡片没有阴影；聚焦卡片阴影/辉光是主色，不是黑色。
- [ ] 打开瞬间，当前聚焦窗口的卡片已处于聚焦态（抬起 + 主色辉光），不需要先按键或移动鼠标。
- [ ] 卡片边框是主色细线，不是白色。
- [ ] 配置写入落盘（重启后保留），直接改 `Config.options` 的写法不存在。
- [ ] 关闭后无残留采集（`captureSource` 已置空）。
- [ ] `animationsEnabled=false` 时不播放动画且功能正常。

---

## 10. 已知限制

1. `fly` 依赖 fork 暴露窗口屏幕矩形（3.1）；未提供时只能降级。
2. 双字母模式的容量是 `|L| × (|L| − 1)`（9 个字母 → 72 个窗口）；超出部分没有编码。双字母模式下不存在“按一个字母直接跳”的快捷。
3. 毛玻璃背景依赖一次静态截屏；截屏失败时退化为纯渐变。
4. 打开期间不跟随窗口增删（快照语义）。
5. 缩略图来自 `WindowPreviewService` 缓存；niri 只渲染可见窗口，**离屏/其它 workspace 的窗口可能截到空白帧**。可见窗口正常。
6. `fly` 的起点是近似矩形（3.1），对平铺布局误差通常在一列以内；落点不受影响。
