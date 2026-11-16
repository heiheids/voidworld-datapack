# voidworld — Minecraft 26.3 虚空世界数据包

把主世界变成只有「一层平滑石台阶」的虚空世界，把末地变成只有「黑曜石柱 + 落脚平台」的虚空末地。末地不生成主岛，也不额外生成任何平台。

当前版本 **1.0.3**，支持 **Minecraft 26.3**（`pack_format = 121`，`data_version = 5023`）。

> English documentation: see [English](#english) below.

---

## 效果

| 维度 | 生成内容 |
| --- | --- |
| 主世界 | 仅 `y = -64` 一层 `minecraft:smooth_stone_slab`，其余全是空气；无地形、无熔岩、无植被、无矿脉、无结构方块 |
| 下界 | 仅 `y = 0` 一层平滑石台阶，其余空气 |
| 末地 | 虚空 + 黑曜石柱 + 落脚平台；**不生成主岛**，也**不额外生成任何平台** |

末地实测（种子 `-7318689163426405533`，±96 范围 289 个区块）：

```
minecraft:obsidian   40167   ← 黑曜石柱 + 落脚平台(25)
minecraft:bedrock        8   ← 8 个柱顶基岩帽
minecraft:fire           8   ← 柱顶火焰
```

主世界实测（同一份构建，1089 个区块）：

```
minecraft:air               106995456
minecraft:smooth_stone_slab     57600
```

> 关于末地祭坛：原版**不会**在世界生成时创建祭坛（返回传送门），它是**击杀末影龙之后**由游戏逻辑生成在柱子正中央的。本数据包不干预这一过程，所以打完龙，正中央会正常出现祭坛。
>
> 数据包曾用结构自己造过一座 7×7 末地石平台，但 `concentric_rings` 放置只能落在离原点约 7 个区块的位置（无法居中），在柱子环外看起来就是一个多余平台，因此 **v1.5 已移除**。

---

## 安装

1. 下载 `dist/voidworld_v26.3.zip`；
2. 放到存档的 `saves/<存档名>/datapacks/` 目录下；
3. **新建世界**（或只在未生成区块的区域活动），种子随意；
4. 进游戏后 `/datapack list` 确认 `voidworld.zip` 已启用。

数据包在**新区块生成时**生效，已生成的旧区块不会被改写。

---

## 三个关键实现

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

---

## 目录结构

```
build/                 生成器与工具（PowerShell 7）
  generate.ps1         主生成器：读 26.3.jar，产出 behavior/
  altar.ps1            末地祭坛结构生成器（当前 enabled=false，已停用）
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

想恢复自定义末地祭坛平台，把 `config.json` 里 `features.end_altar.enabled` 改回 `true` 即可——但注意它无法居中，只会落在原点附近约 7 个区块处。

---

## 已知限制

- **不适用于含世界生成类模组的整合包**：如果你是 NeoForge 等整合包，且装了自定义地形／结构生成的模组，那些模组的生成结果不受本数据包约束。
- 数据包只影响**新生成**的区块，旧存档已有地形不会消失。
- 末地黑曜石柱在虚空中会一直延伸到世界底部（`y=0`），因为原本托着它们的岛屿已经不生成。

---

## 版本历史

- **v1.5**（2026-11-16）移除自定义 7×7 末地石平台——它只能落在柱子环外约 7 个区块处，视觉上是多余平台；末地回到「只有黑曜石柱 + 落脚平台」，祭坛交由击杀末影龙后的原版逻辑在正中央生成。
- **v1.4**（2026-11-16）祭坛极简化为单层 7×7 末地石，去掉 3×3 黑曜石、四角基岩与龙蛋。
- **v1.3**（2026-11-16）熔岩根除（含水层全量中性化 + 清空 carvers）；末地主岛移除。
- **v1.2** 修正末地过度虚空化——此前 `floor_top = null` 把末地主岛也一并清空，导致「祭坛没有生成」。
- **v1.1** 剥离生物群系特性（熔岩湖、矿脉、植被等），并修正已放置特性的引用方式。
- **v1.0** 气候钉死根除冰山；主世界压成单层平滑石台阶。

---

<a id="english"></a>
# voidworld — Minecraft 26.3 Void World Datapack

Turn the Overworld into a void world with a single layer of smooth stone slabs, and the End into a void with only obsidian pillars and the landing platform. The End has no main island and no extra platform of any kind.

Supports **Minecraft 26.3** (`pack_format = 121`, `data_version = 5023`).

## What you get

| Dimension | Generated content |
| --- | --- |
| Overworld | Only one `minecraft:smooth_stone_slab` layer at `y = -64`; everything else is air — no terrain, no lava, no vegetation, no ores, no structure blocks |
| Nether | Only one smooth stone slab layer at `y = 0` |
| End | Void + obsidian pillars + landing platform; **no main island** and **no extra platform** |

Measured on the End (seed `-7318689163426405533`, 289 chunks across ±96):

```
minecraft:obsidian   40167   ← pillars + landing platform (25)
minecraft:bedrock        8   ← 8 pillar caps
minecraft:fire           8   ← pillar flames
```

Measured on the Overworld (same build, 1089 chunks):

```
minecraft:air               106995456
minecraft:smooth_stone_slab     57600
```

> About the End altar: vanilla does **not** create the altar (exit portal) during world generation — it is created by the game logic **after the Ender Dragon is defeated**, at the exact centre of the pillar ring. This datapack does not interfere, so the altar appears normally once the dragon dies.
>
> An earlier version built a 7×7 end stone platform as an altar, but `concentric_rings` placement can only land about 7 chunks from the origin (it cannot be centred), which looked like a stray platform outside the pillars — **removed in v1.5**.

## Installation

1. Download `dist/voidworld_v26.3.zip`;
2. Drop it into `saves/<your-world>/datapacks/`;
3. Create a **new world** (or only explore ungenerated chunks), any seed;
4. Run `/datapack list` in game to confirm `voidworld.zip` is enabled.

The datapack applies when **new chunks are generated**; existing chunks are never rewritten.

## The three key mechanisms

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

## Repository layout

```
build/                 Generators and tools (PowerShell 7)
  generate.ps1         Main generator: reads the 26.3 jar, writes behavior/
  altar.ps1            End altar structure generator (currently disabled via enabled=false)
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

To re-enable the custom altar platform, set `features.end_altar.enabled` back to `true` in `config.json` — note that it cannot be centred and will land roughly 7 chunks from the origin.

## Known limitations

- **Not effective with worldgen mods**: in a NeoForge-style modpack that ships its own terrain/structure generation, those mods' output is not constrained by this datapack.
- Only **newly generated** chunks are affected; existing terrain in old saves is untouched.
- The End's obsidian pillars extend all the way down to `y = 0` in the void, because the island that used to support them no longer generates.

## Version history

- **v1.5** (2026-11-16) Removed the custom 7×7 end stone platform — it could only land ~7 chunks outside the pillar ring, looking like a stray platform; the End is back to pillars + landing platform only, and the altar is left to vanilla's post-dragon logic at the exact centre.
- **v1.4** (2026-11-16) Altar reduced to a single 7×7 end stone layer (obsidian, corner bedrocks and dragon egg removed).
- **v1.3** (2026-11-16) Lava eliminated (full aquifer neutralization + emptied carvers); End main island removed.
- **v1.2** Fixed over-voiding of the End — `floor_top = null` had wiped the main island too, which was the real reason "the altar never generated".
- **v1.1** Stripped biome features (lava lakes, ores, vegetation); fixed placed-feature references.
- **v1.0** Climate pinning removed icebergs; Overworld flattened to a single smooth stone slab layer.

---

## v1.6 更新：祭坛生成高度修复

**问题**：击杀末影龙后，返回传送门（祭坛）生成在末地最底部。

**原因**：原版 `EnderDragonFight.setDragonKilled` 用 `getHeightmapPos(MOTION_BLOCKING, 祭坛中心)` 决定高度；虚空末地中心没有任何方块，高度图返回 0，于是祭坛落在世界底部。

**修复**：新增 `build/center_spike.ps1`，用一个**固定坐标**的 `minecraft:end_spike`（`centerX/centerZ = 0`）在末地正中心生成一根 1×1 黑曜石柱（y=0..61，y=62 基岩帽），把中心列高度图抬到 63。

**验证**（直接读取区块 NBT 的 `Heightmaps`，即原版读取的同一份数据）：

| 世界 | MOTION_BLOCKING | MOTION_BLOCKING_NO_LEAVES | WORLD_SURFACE |
| --- | --- | --- | --- |
| 修复前 | 0 | 0 | 0 |
| 修复后 | **63** | **63** | 64 |

打龙后祭坛/龙蛋即落在 **y≈63**（原版主岛地表高度）。

**副作用**：末地正中心会多一根 1×1 的细柱（视觉上是一条竖线），这是抬高高度图所必需的。不想保留可把 `build/config.json` 里 `features.center_spike.enabled` 改为 `false`，代价是祭坛回到最底部。

**注意**：数据包只影响新生成的区块；已有存档的末地中心没有这根柱子，必须新建世界。

## v1.6 Update: altar spawn height fixed

**Problem**: after killing the Ender Dragon, the exit portal (altar) spawned at the very bottom of the End.

**Cause**: vanilla `EnderDragonFight.setDragonKilled` derives the height from `getHeightmapPos(MOTION_BLOCKING, altar centre)`; in a void End there are no blocks at the centre, so the heightmap returns 0 and the altar lands at the world bottom.

**Fix**: new `build/center_spike.ps1` emits a **fixed-position** `minecraft:end_spike` (`centerX/centerZ = 0`) that places a 1×1 obsidian column at the End centre (y=0..61 plus a bedrock cap at y=62), raising the centre column's heightmap to 63.

**Verification** (reading the chunk NBT `Heightmaps` — the same data vanilla uses):

| World | MOTION_BLOCKING | MOTION_BLOCKING_NO_LEAVES | WORLD_SURFACE |
| --- | --- | --- | --- |
| before fix | 0 | 0 | 0 |
| after fix | **63** | **63** | 64 |

The altar/dragon egg therefore lands at **y≈63** (vanilla main-island surface height).

**Side effect**: a thin 1×1 column now stands at the very centre of the End (a vertical line visually); it is required to raise the heightmap. Disable it via `features.center_spike.enabled = false` in `build/config.json` (the altar then returns to the bottom).

**Note**: the datapack only affects newly generated chunks; existing saves lack the column and need a new world.

---

## v1.7 更新：清除中心祭坛的多余水晶

**问题**：中心柱为了让祭坛生成在正确高度而在末地中心建立，但原版 `EndSpikeFeature` 在该柱顶端会生成一颗**末影水晶**（`guarded=false` 时的固有行为），视觉多余，且会给末影龙回血。

**修复**：新增 tick 函数 `vw:center_crystal_cleanup`，每刻执行

```
execute in minecraft:the_end positioned 0 62 0 run kill @e[type=minecraft:end_crystal,distance=..8]
```

半径 8 只覆盖末地中心，**不碰**半径约 42 处的 10 个原版柱水晶。

**验证**（同一 tick 内先标记、后清理、再标记）：

| 检查点 | 结果 |
| --- | --- |
| 清理前中心 8 格内是否有水晶 | 有（红石块标记出现） |
| 清理后再检查 | 已消失（金块标记未出现） |
| 中心柱是否完好 | 完好：黑曜石 y=0..61、基岩 y=62、火焰 y=63 |
| 祭坛高度是否保持 | 保持：中心高度图 = 63 |

**说明**：清理是按刻进行的，因此**已有存档也会生效**（不同于中心柱本身需要新世界）。

## v1.7 Update: removing the extra crystal at the centre altar

**Problem**: the centre column exists so the altar spawns at the correct height, but vanilla `EndSpikeFeature` also spawns an **End Crystal** on top of it (inherent behaviour when `guarded=false`). It is visually superfluous and heals the Ender Dragon.

**Fix**: a new tick function `vw:center_crystal_cleanup` runs every tick:

```
execute in minecraft:the_end positioned 0 62 0 run kill @e[type=minecraft:end_crystal,distance=..8]
```

Radius 8 covers only the End centre and leaves the ten vanilla pillar crystals (radius ≈ 42) untouched.

**Verification** (mark → clean → mark again within one tick):

| Check | Result |
| --- | --- |
| Crystal within 8 blocks before cleaning | present (redstone marker placed) |
| Crystal after cleaning | gone (gold marker not placed) |
| Centre column intact | yes: obsidian y=0..61, bedrock y=62, fire y=63 |
| Altar height preserved | yes: centre heightmap = 63 |

**Note**: the cleanup runs every tick, so it also applies to **existing saves** (unlike the column itself, which needs a new world).
