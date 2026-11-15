# voidworld — Minecraft 26.3 虚空世界数据包

把主世界变成只有「一层平滑石台阶」的虚空世界，把末地变成只有「黑曜石柱 + 落脚平台 + 一座祭坛」的虚空末地。

支持 **Minecraft 26.3**（`pack_format = 121`，`data_version = 5023`）。

> English documentation: see [English](#english) below.

---

## 效果

| 维度 | 生成内容 |
| --- | --- |
| 主世界 | 仅 `y = -64` 一层 `minecraft:smooth_stone_slab`，其余全是空气；无地形、无熔岩、无植被、无矿脉、无结构方块 |
| 下界 | 仅 `y = 0` 一层平滑石台阶，其余空气 |
| 末地 | 虚空 + 黑曜石柱 + 落脚平台 + 唯一一座祭坛；**不生成主岛** |

末地实测（种子 `-7318689163426405533`，±400 全范围扫描）：

```
minecraft:obsidian   40176   ← 黑曜石柱 + 落脚平台(25) + 祭坛黑曜石(9)
minecraft:end_stone     49   ← 祭坛 7×7 基座（没有主岛）
minecraft:bedrock       12   ← 8 个柱顶基岩帽 + 4 个祭坛角
minecraft:fire           8   ← 柱顶火焰
minecraft:dragon_egg     1   ← 祭坛龙蛋
```

主世界实测（同一份构建，1089 个区块）：

```
minecraft:air               106995456
minecraft:smooth_stone_slab     57600
```

---

## 安装

1. 下载 `dist/voidworld_v26.3.zip`；
2. 放到存档的 `saves/<存档名>/datapacks/` 目录下；
3. **新建世界**（或只在未生成区块的区域活动），种子随意；
4. 进游戏后 `/datapack list` 确认 `voidworld.zip` 已启用。

数据包在**新区块生成时**生效，已生成的旧区块不会被改写。

---

## 四个关键实现

### 1. 含水层全量中性化（熔岩的根因）

只把 `aquifers.lava` 钉成常量 `-1` **并不够**：含水层的 `fluid_level_floodedness`、`fluid_level_spread`、`barrier` 仍然是噪声，仍会判定出流体位置，于是世界底部（`y = -63..-56`）照样灌出岩浆。

现在的做法是把四个密度函数全部改成常量 `-1.0`，并把 `surface_level` 钉成 `floor_top`，让整个含水层系统不再产生任何流体：

```json
"aquifers": {
  "lava":                    { "type": "minecraft:constant", "value": -1.0 },
  "fluid_level_floodedness": { "type": "minecraft:constant", "value": -1.0 },
  "fluid_level_spread":      { "type": "minecraft:constant", "value": -1.0 },
  "barrier":                 { "type": "minecraft:constant", "value": -1.0 },
  "surface_level":           { "type": "minecraft:constant", "value": -64.0 }
}
```

实测：熔岩 `3423` → `0`。

### 2. 清空生物群系的 `carvers`

洞穴／峡谷雕刻器会在世界底部灌岩浆。剥离特性时要连 `carvers` 一起清空：

```json
"carvers": []
```

### 3. 气候钉死（冰山的根因）

冰山不是特性生成的，而是「选到了寒冷生物群系」的结果。把气候噪声钉成常量，`multi_noise` 就选不到寒冷群系：

```
noise_router.temperature -> vw:climate/temperature  (constant 1.0)
noise_router.vegetation  -> vw:climate/vegetation   (constant 0.0)
```

带 `temperature` 字段存在性判据，下界／末地不受影响。

### 4. 末地祭坛：自定义 jigsaw 结构

原版**不会**在世界生成时创建祭坛——它由击杀末影龙后的游戏逻辑生成，纯原版全新末地中心只有末地石。所以这里用结构自己造一座：

- 模板 `altar.nbt`（7×5×7）：7×7 末地石基座 + 3×3 黑曜石 + 四角基岩 + 龙蛋
- 结构 `vw:end_altar`（jigsaw，`biomes = minecraft:the_end`，`start_height = 60`）
- 放置 `minecraft:concentric_rings`（原版要塞同款），`count = 1, distance = 0, spread = 1`

> **坑**：`spread = 0` 会让整个放置**静默失效**——没有报错日志，也不生成任何东西。必须 `spread >= 1`。

---

## 目录结构

```
build/                 生成器与工具（PowerShell 7）
  generate.ps1         主生成器：读 26.3.jar，产出 behavior/
  altar.ps1            末地祭坛结构与模板生成
  config.json          全部可调参数（维度、保留/剥离的特性、结构等）
  validate.ps1         JSON / NBT 校验
  backup.ps1           改动前自动备份（写入 voidworld工程备份.txt）
  blockcount.ps1       按方块种类 / Y 层统计存档方块
  blockat.ps1          按坐标范围统计存档方块
  lib/                 NBT 与 region 解析
behavior/              生成出的数据包源目录（可直接当数据包用）
dist/                  成品数据包
README.md              本文件（中英）
打包说明.md             打包内容与使用说明
voidworld工程备份.txt    每次改动的记录
```

`test/`、`test2/`、`backup/`、`verify/` 是本地验证产物与备份，未纳入版本库。

---

## 重新生成

需要 **Java 25**（26.3 的 class 版本是 69.0）与 **PowerShell 7**。

```powershell
pwsh -NoProfile -File .\build\generate.ps1
```

生成器会读取本机的 `26.3.jar` 注册表，把所有特性／已放置特性／生物群系／结构改写成虚空版本，输出到 `behavior/`，并打成 `dist/voidworld_v26.3.zip`。

---

## 已知限制

- **祭坛位置取决于种子**：`concentric_rings` 的环半径算法决定了落点会偏离原点若干区块（本种子落在 `(16, 59, -112)`，约 7 个区块外）。纯数据包无法把结构钉到精确 `(0, 0)`。
- **不适用于含世界生成类模组的整合包**：如果你是 NeoForge 等整合包，且装了自定义地形／结构生成的模组，那些模组的生成结果不受本数据包约束。
- 数据包只影响**新生成**的区块，旧存档已有地形不会消失。

---

## 版本历史

- **v1.3**（2026-11-16）熔岩根除（含水层全量中性化 + 清空 carvers）；末地主岛移除；新增自定义末地祭坛结构。
- **v1.2** 修正末地过度虚空化——此前 `floor_top = null` 把末地主岛也一并清空，导致「祭坛没有生成」。
- **v1.1** 剥离生物群系特性（熔岩湖、矿脉、植被等），并修正已放置特性的引用方式。
- **v1.0** 气候钉死根除冰山；主世界压成单层平滑石台阶。

---

<a id="english"></a>
# voidworld — Minecraft 26.3 Void World Datapack

Turn the Overworld into a void world with a single layer of smooth stone slabs, and the End into a void with only obsidian pillars, the landing platform and one altar.

Supports **Minecraft 26.3** (`pack_format = 121`, `data_version = 5023`).

## What you get

| Dimension | Generated content |
| --- | --- |
| Overworld | Only one `minecraft:smooth_stone_slab` layer at `y = -64`; everything else is air — no terrain, no lava, no vegetation, no ores, no structure blocks |
| Nether | Only one smooth stone slab layer at `y = 0` |
| End | Void + obsidian pillars + landing platform + exactly one altar; **no main island** |

Measured on the End (seed `-7318689163426405533`, full ±400 scan):

```
minecraft:obsidian   40176   ← pillars + landing platform (25) + altar obsidian (9)
minecraft:end_stone     49   ← the altar's 7×7 base (no island)
minecraft:bedrock       12   ← 8 pillar caps + 4 altar corners
minecraft:fire           8   ← pillar flames
minecraft:dragon_egg     1   ← altar dragon egg
```

Measured on the Overworld (same build, 1089 chunks):

```
minecraft:air               106995456
minecraft:smooth_stone_slab     57600
```

## Installation

1. Download `dist/voidworld_v26.3.zip`;
2. Drop it into `saves/<your-world>/datapacks/`;
3. Create a **new world** (or only explore ungenerated chunks), any seed;
4. Run `/datapack list` in game to confirm `voidworld.zip` is enabled.

The datapack applies when **new chunks are generated**; existing chunks are never rewritten.

## The four key mechanisms

### 1. Fully neutralizing the aquifer (root cause of lava)

Setting only `aquifers.lava` to a constant `-1` is **not** enough: `fluid_level_floodedness`, `fluid_level_spread` and `barrier` are still noise functions, so the aquifer keeps deciding where fluid belongs and still floods the world bottom (`y = -63..-56`) with lava.

All four density functions are now constant `-1.0`, and `surface_level` is pinned to `floor_top`, so the aquifer produces no fluid at all. Measured: lava `3423` → `0`.

### 2. Emptying biome `carvers`

Cave/canyon carvers also pour lava at the world bottom. When stripping features, `carvers` must be emptied too:

```json
"carvers": []
```

### 3. Pinning the climate (root cause of icebergs)

Icebergs are not feature-driven — they appear because a cold biome was selected. Pinning the climate noise makes `multi_noise` unable to pick cold biomes:

```
noise_router.temperature -> vw:climate/temperature  (constant 1.0)
noise_router.vegetation  -> vw:climate/vegetation   (constant 0.0)
```

Gated on the presence of a `temperature` field, so the Nether and the End are unaffected.

### 4. End altar: a custom jigsaw structure

Vanilla does **not** create the altar during world generation — it is produced by the game logic after the Ender Dragon is defeated, and a fresh vanilla End has only end stone at the centre. So the datapack builds one:

- Template `altar.nbt` (7×5×7): 7×7 end stone base + 3×3 obsidian + four corner bedrocks + dragon egg
- Structure `vw:end_altar` (jigsaw, `biomes = minecraft:the_end`, `start_height = 60`)
- Placement `minecraft:concentric_rings` (the vanilla stronghold placement), `count = 1, distance = 0, spread = 1`

> **Gotcha**: `spread = 0` makes the whole placement **fail silently** — no error in the log, nothing generated. It must be `spread >= 1`.

## Repository layout

```
build/                 Generators and tools (PowerShell 7)
  generate.ps1         Main generator: reads the 26.3 jar, writes behavior/
  altar.ps1            End altar structure and template generator
  config.json          All tunables (dimensions, kept/stripped features, structures)
  validate.ps1         JSON / NBT validation
  backup.ps1           Auto-backup before edits (appends to voidworld工程备份.txt)
  blockcount.ps1       Count blocks in a save by type / Y layer
  blockat.ps1          Count blocks in a save by coordinate range
  lib/                 NBT and region parsing
behavior/              Generated datapack source (usable directly as a datapack)
dist/                  Finished datapack
README.md              This file (Chinese + English)
```

`test/`, `test2/`, `backup/` and `verify/` are local verification artifacts and are not tracked.

## Regenerating

Requires **Java 25** (26.3 classes are version 69.0) and **PowerShell 7**.

```powershell
pwsh -NoProfile -File .\build\generate.ps1
```

The generator reads the local `26.3.jar` registry, rewrites all features / placed features / biomes / structures into void variants, writes `behavior/`, and packs `dist/voidworld_v26.3.zip`.

## Known limitations

- **The altar position depends on the seed**: the `concentric_rings` radius algorithm offsets it from the origin by a few chunks (this seed: `(16, 59, -112)`, about 7 chunks out). A datapack alone cannot pin a structure to exactly `(0, 0)`.
- **Not effective with worldgen mods**: in a NeoForge-style modpack that ships its own terrain/structure generation, those mods' output is not constrained by this datapack.
- Only **newly generated** chunks are affected; existing terrain in old saves is untouched.

## Version history

- **v1.3** (2026-11-16) Lava eliminated (full aquifer neutralization + emptied carvers); End main island removed; custom End altar structure added.
- **v1.2** Fixed over-voiding of the End — `floor_top = null` had wiped the main island too, which was the real reason "the altar never generated".
- **v1.1** Stripped biome features (lava lakes, ores, vegetation); fixed placed-feature references.
- **v1.0** Climate pinning removed icebergs; Overworld flattened to a single smooth stone slab layer.
