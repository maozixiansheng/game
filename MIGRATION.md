# 迁移指南 — 把《倒爷修仙传》跑起来

> 面向对象：另一个 AI 助手，或手动操作的人。
> 目标：把本目录复制进一个新项目，一次 build 成功启动游戏。
> 预计耗时：5 分钟。

---

## 0. 先决条件

你需要一个 **UrhoX（星火编辑器 / TapTap Code）项目**，且该环境的 AI 助手具备：

- `build` 工具（构建项目）
- 文件读写权限

如果还没有项目：**新建一个空项目**即可，任何模板都行（会被本包覆盖）。

---

## 1. 迁移步骤

### 第 1 步：复制 `scripts/`

把本目录的 `scripts/` **整个**复制到新项目的 `scripts/`：

```
新项目/scripts/
├── main.lua
├── config/
│   ├── Settings.lua
│   └── Theme.lua
├── game/
│   ├── Combat.lua
│   ├── Cultivation.lua
│   ├── Market.lua
│   └── Tutorial.lua
└── network/
    ├── Client.lua
    ├── Server.lua
    ├── Shared.lua
    ├── EntryFlow.lua
    ├── BattlefieldMap.lua
    ├── StrongholdPanel.lua
    ├── TitlePanel.lua
    ├── Quest.lua
    └── Activity.lua
```

**共 16 个文件，33,589 行。** 复制后请对照 `MANIFEST.txt` 逐个核对行数，确保没有截断。

> 如果新项目 `scripts/` 下已有模板文件（如 `main.lua`），**直接覆盖**。
> 如果模板还带了别的示例脚本（如 `Sample.lua`、`HelloWorld.lua`），可以删掉，它们不会被引用。

### 第 2 步：复制 `assets/`

把本目录的 `assets/` **整个**复制到新项目的 `assets/`：

```
新项目/assets/
├── Fonts/    (2 个 ttf)
├── audio/    (2 BGM + sfx/ 5 个音效)
└── image/    (14 张 png)
```

> ⚠️ **字体必须复制**。缺 `assets/Fonts/` 会导致所有 UI 文字渲染不出来。

### 第 3 步：配置 `.project/settings.json`

打开新项目的 `.project/settings.json`，确保存在以下内容（**合并**进去，不要整体覆盖文件，因为里面还有 `project_id` 等引擎生成的字段）：

```json
{
  "@runtime": {
    "multiplayer": {
      "enabled": true,
      "max_players": 100,
      "persistent_world": {
        "enabled": true
      }
    }
  }
}
```

同时确认构建配置：

```json
{
  "build": {
    "generate_fs_path": true,
    "output_dir": "../dist",
    "asset_dirs": ["../assets", "../scripts"],
    "asset_ignores": []
  }
}
```

### 第 4 步：配置 `.project/project.json`

确保入口是双端入口：

```json
{
  "entry": "main.lua",
  "entry@client": "main.lua",
  "entry@server": "main.lua"
}
```

### 第 5 步：构建

调用 `build` 工具：

```
build
  entry_client = main.lua
  entry_server = main.lua
  multiplayer = { enabled: true, max_players: 100, persistent_world: { enabled: true } }
```

**必须同时指定 `entry_client` 和 `entry_server`。** 只指定一个会导致 `IsServerMode()` 判断异常。

### 第 6 步：验证

构建成功后预览。预期表现：

1. 出现**欢迎页**（水墨风背景 + 印章样式标题）
2. 进入**创角 / 标题页**
3. 进入主游戏界面：左侧状态栏、场景描述区、底部功能按钮
4. 控制台日志出现 `[Main] 启动客户端模式` / `[Main] 启动服务端模式`

> **多人玩法需要至少 2 个客户端连入**。单人预览只能看到 UI 与 NPC 交互，交易阁、帮会、据点等系统需要多端才有效果。

---

## 2. 验收清单

复制完成后逐项打勾：

- [ ] `scripts/` 16 个文件齐全，行数与 `MANIFEST.txt` 一致
- [ ] `assets/Fonts/WenKai-Regular.ttf` 存在且大小 776,302 字节
- [ ] `assets/Fonts/WenKai-Light.ttf` 存在且大小 938,523 字节
- [ ] `assets/audio/` 7 个 ogg 齐全
- [ ] `assets/image/` 14 张 png 齐全
- [ ] `settings.json` 的 `multiplayer.enabled == true`
- [ ] `settings.json` 的 `multiplayer.persistent_world.enabled == true`
- [ ] `project.json` 的 `entry@client` 与 `entry@server` 均为 `main.lua`
- [ ] `build` 成功，无 Error
- [ ] 预览可见欢迎页

---

## 3. 架构速查（给接手开发的人）

### 3.1 入口

`main.lua`（23 行）是唯一入口，它只做一件事：

```lua
function Start()
    if IsServerMode() then
        require("network.Server").Start()
    else
        require("network.Client").Start()
    end
end
```

**玩法逻辑全部在 `network/Server.lua` 和 `network/Client.lua` 里，不要往 `main.lua` 加东西。**

### 3.2 依赖图

```
config.Settings ──┬─→ network.Shared ──┬─→ game.Combat      ──┐
                  │                    ├─→ game.Cultivation ──┤
                  │                    └─→ game.Market      ──┤
                  │                                         ├─→ network.Server
                  ├─→ network.Activity ─────────────────────┤
                  └─→ network.Quest ────────────────────────┘
                       └─→ network.Server (回引)

config.Theme ─────┬─→ network.EntryFlow ──┐
                  │                       ├─→ network.Client
                  ├─→ network.BattlefieldMap ─┤
                  ├─→ network.StrongholdPanel ┤
                  ├─→ network.TitlePanel ─────┘
                  └─→ game.Tutorial ──────────┘
```

**无循环依赖，整包自洽。**

### 3.3 通信机制

```lua
-- 客户端 → 服务端
SendToServer(Settings.EVENTS.REQ_XXX, { Key = value })

-- 服务端 → 客户端
conn:SendRemoteEvent(Settings.EVENTS.PUSH_XXX, true, variantMap)
```

> 🔴 **新增事件必须同时注册三处**，漏一处事件静默失效：
> 1. `config/Settings.lua` → `Settings.EVENTS.XXX = "EventName"`
> 2. `network/Shared.lua` → `SERVER_EVENTS` 表
> 3. `network/Shared.lua` → `CLIENT_EVENTS` 表

### 3.4 存档

使用引擎内置 `serverCloud`，无自建数据库：

| API | 用途 |
|---|---|
| `serverCloud.score` | 单值（玩家存档、属性） |
| `serverCloud.money` | 货币（silver / spirit_stone） |
| `serverCloud.list` | 列表（注册表、帮会、交易阁） |
| `serverCloud.rank` | 排行榜 |

> 云存档按 `app_id` 隔离 → **换新项目 = 全新存档**，属预期行为。

---

## 4. 常见问题

| 现象 | 原因 | 解决 |
|---|---|---|
| 构建报 `entry` 相关错误 | 只指定了单入口 | 同时传 `entry_client` 和 `entry_server` |
| UI 面板全黑 / 无文字 | 缺字体 | 复制 `assets/Fonts/` 下 2 个 ttf |
| 战斗界面无立绘 | 缺图片 | 复制 `assets/image/` 下 8 张战斗 png |
| 无声音 | 缺音频 | 复制 `assets/audio/` |
| 客户端起来了但玩法不动 | 多人模式未开启 | `settings.json` 里 `multiplayer.enabled = true` |
| 事件发了没反应 | 事件未注册 | 按 §3.3 检查三处注册 |
| `string.format("%d")` 报错 | Lua 5.4 整数要求 | 传参前 `math.floor()` |
| 玩家数据丢失 | 换了 app_id | 预期行为，新项目从零开始 |
| 单人预览没有交易/帮会效果 | 需要多端 | 至少 2 个客户端连入 |

---

## 5. 修改入口指引

| 想改什么 | 去哪里 |
|---|---|
| 数值平衡（境界、经验、价格、掉落） | `config/Settings.lua` |
| UI 配色 / 字体 / 贴图 | `config/Theme.lua` |
| 战斗公式 | `game/Combat.lua` |
| 修炼曲线 | `game/Cultivation.lua` |
| 交易阁规则 | `game/Market.lua` |
| 新增一个 UI 面板 | `network/Client.lua`（参考已有 `Build*Panel` 函数） |
| 新增一个服务端事件处理 | `network/Server.lua` + 三处事件注册 |
| 战场大地图 | `network/BattlefieldMap.lua` |
| 新手引导步骤 | `game/Tutorial.lua` |

> `Client.lua` 与 `Server.lua` 内部均按 `Build*Panel` / `On*` 函数组织，用编辑器搜索函数名即可定位。

---

## 6. 版本

| 项目 | 值 |
|---|---|
| 交付包 | v12.0 |
| 导出日期 | 2026-10-01 |
| 代码量 | 33,589 行 / 16 文件 |
| LSP 检查 | 0 Error / 766 Warning / 362 Hint |
