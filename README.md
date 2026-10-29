# Mistbound · 雾境寻宝者

Godot 4 的 2D 俯视合作刷宝框架，采用**共享营地／野外 + 可重复小副本 + 角色长期成长**。面向个人开发的可运行起点，使用 GDScript 和 Godot 原生节点，无第三方依赖。

## 打开与运行

使用 Godot 4 导入本目录的 `project.godot`，按 **F5**。本项目已在 **Godot 4.7.2 / Windows** 验证，使用 Compatibility 渲染器。

也可以在本目录运行：

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\run.ps1
# 打开编辑器
powershell -ExecutionPolicy Bypass -File .\tools\run.ps1 -Editor
```

脚本会尝试 PATH、环境变量 `MISTBOUND_GODOT` 和各盘常用 Steam 库路径。未找到时显式传入 `-Godot 'C:\path\Godot.exe'`。项目目录可以移动，不依赖本机绝对路径。

## 现在可以玩什么

- 从余烬营地进入低语林地，再进入琥珀矿井或回声地窟；各区域有碰撞、入口和独立视觉。
- WASD 移动，鼠标瞄准，按住左键攻击，空格闪避，Q 切换剑与弩；敌人会追击并预警攻击。
- 旅人短刃进行近身扇形攻击；猎人手弩发射有飞行时间的箭矢，箭矢命中首个敌人或地形后消失。两把武器都随初始角色提供。
- 击败普通敌人与首领获得经验和个人战利品；靠近按 E 拾取金币和遗物。
- 矿井首领掉落余烬遗物，地窟首领掉落风暴遗物。I / Esc 打开背包，武器与遗物各占一个独立槽位，可自由组合或卸下遗物。
- 余烬遗物让武器命中施加 3 秒灼烧，每 0.5 秒造成 4 点伤害；再次命中刷新时长，不叠加层数。
- 风暴遗物每累计 3 次武器命中触发连锁闪电，主目标及最多两个邻近目标各受到 12 点额外伤害。灼烧和闪电不会递归触发遗物。
- 首领交替使用冲锋与范围重击：冲锋先锁定方向显示走廊，重击先显示圆形范围；闪避可穿过伤害窗口，恢复阶段适合输出。
- 每 40 经验提升一级，最多 20 级；提升基础伤害与生命。死亡损失最多 5 金币，在本区域入口重生，装备保留。
- 返回营地恢复生命。离开再进入副本会刷新敌人；切换区域会清除尚未拾取的掉落。
- 单人探索、创建好友房间、通过 IP/端口加入；设计上限 4 人。

操作：**WASD 移动 / 左键攻击 / 空格闪避 / Q 切换武器 / E 交互 / I 或 Esc 背包**。界面右上角可保存、离开。

地图里的铁匠、帐篷等目前是视觉占位。两种武器与两种遗物效果已经实现；更多技能、随机词条、任务、营地升级、自由建造等留作后续内容。

## 联机规则

公共地图指**当前房间内共享的地图**。房主的进程负责模拟战斗、验证拾取和切换区域，其他人发送操作。入口由房主靠近后按 E，全队一起进入。支持游戏开始后加入；断线后可从主菜单重新加入。

1. 房主点击“创建好友房间”，默认 UDP 端口为 `24570`。
2. 同一局域网的朋友填写房主的局域网 IP，点击“加入房间”。同一台电脑测试可填 `127.0.0.1`。
3. 公网直连需要可达的公网地址、UDP 端口映射和相应防火墙规则；运营商 CGNAT 下不能只靠路由器端口映射。当前没有 Steam 邀请、自动 NAT 穿透或网络中继。

房主退出会结束房间，客人回到主菜单并保存已确认的角色进度。没有房主迁移。客户端目前使用位置插值，尚未实现本地预测，高延迟下操作会有延迟。

本机双开应使用**不同存档目录**，避免两个进程写入同一份角色：

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\run.ps1 -Mode host -SaveDir 'D:\Code\mistbound\test-results\host'
powershell -ExecutionPolicy Bypass -File .\tools\run.ps1 -Mode join -Address 127.0.0.1 -SaveDir 'D:\Code\mistbound\test-results\guest'
```

## 存档

默认目录为 Godot 的 `user://saves`；在编辑器中通过“项目 → 打开用户数据文件夹”定位。设置绝对路径环境变量 `MISTBOUND_SAVE_DIR` 可覆盖它。

| 文件 | 保存内容 | 保存者 |
| --- | --- | --- |
| `character.json` | 名称、经验、金币、物品数量、武器槽和遗物槽 | 各玩家保存自己的角色 |
| `world.json` | 到访区域、累计首领击杀次数 | 单人或房主 |

关键进度变化和退出时保存；另有每 5 秒检查。文件采用临时写入与有效旧档备份，损坏主档可回退 `.bak`。世界现场敌人、地面掉落、玩家坐标未持久化，重新开始从营地出发。

本地角色文件可编辑，入房时只做结构和范围校验。这是好友合作的信任模型，尚不适合可信交易经济、排行榜或公共 MMO。

角色存档已升级为 v2。旧版单槽 `equipped` 会按物品类型自动迁入武器槽或遗物槽，并补齐初始剑与弩；金币、经验和已有物品保留。首次迁移保存保留原始 v1 备份。世界存档仍为 v1。未知未来版本会拒绝覆盖；新版联机协议为 v2，队友需使用相同版本项目。

## 项目结构与扩展

```text
scenes/main.tscn                 项目入口
scripts/main.gd                 输入、镜头、模块组装
scripts/systems/game_session.gd  ENet / RPC / 房间生命周期
scripts/systems/world_simulation.gd  战斗、掉落、区域实例、快照
scripts/systems/combat_rules.gd  武器命中、箭矢、灼烧、连锁闪电
scripts/systems/enemy_brain.gd   敌人追击与首领招式状态机
scripts/systems/save_store.gd    角色 / 世界存档
scripts/systems/item_*.gd        物品 Resource 与注册表
scripts/world/zone_view.gd       四片地图、碰撞、入口与出生点
scripts/actors/                 玩家、敌人、掉落、弹体与战斗特效
scripts/ui/game_ui.gd           主菜单、HUD、背包
data/items/                    可在 Godot 编辑器调整的 .tres
tests/                         存档、玩法、真实双进程联机、截图
tools/                         启动与引擎定位
```

具体数据协议和扩展方式见 [docs/architecture.md](docs/architecture.md)。下一步可打磨双人战斗平衡、地图探索奖励和副本目标；增加真实公共服务器、多区域并行或跨服角色需要单独扩展架构。

## 验证

```powershell
powershell -ExecutionPolicy Bypass -File .\tests\run_tests.ps1
# 指定引擎和日志目录
powershell -ExecutionPolicy Bypass -File .\tests\run_tests.ps1 -Godot 'C:\path\Godot.exe' -ResultsPath 'D:\Code\mistbound\test-results'
```

测试使用各自隔离的存档目录，不修改真实游戏存档。包含 Godot 导入、旧档迁移与存档完整性、玩法权限与快照排序、武器/遗物判定、首领招式，以及两个独立进程通过 ENet 验证加入、移动、战斗、拾取、切图、重连和断线保存。

界面截图脚本 `tests/capture_preview.gd` 需要普通渲染模式及 `MISTBOUND_CAPTURE_DIR`、`MISTBOUND_SAVE_DIR` 两个隔离路径，运行结束自动退出。追加用户参数 `-- --phase1` 可生成双槽背包、剑弩、燃烧/连锁及首领预警的受控展示截图。没有外部美术素材，当前地图与角色均由代码绘制。
