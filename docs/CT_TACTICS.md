# CT/T BOT 战术调度与回滚

`BetterBots CT Tactical Director` 是叠加在 BetterBots 1.4.4 上的可选调度层，控制 CT BOT 在没有交火时的移动目标和到位后的防守朝向。瞄准精度、射击、原有投掷物、语音、皮肤和身份等功能仍由原插件负责。BOT 购买逻辑增加双方共用的逐人装备分类和协调层；真人购买不受限制。

`BetterBots T Tactical Director` 使用相同的可选桥接，但拥有独立状态、配置和开关；两方不会共享战术命令。

## 战术行为

- 标准局：根据地图 A、B 包点、T 出生方向和 NAV 掩体自动形成 A/B 防守与中间回防位；5 名 CT 通常是 2A、2B、1 名机动位。BOT 到位后由双方共用的架点规划器按武器距离、局部 NAV、视线和不同防守扇区选择主要进攻方向，接敌时立即交还原战斗 AI。
- CT 开局守点：到达目标 128 单位内视为入位，原地架点时屏蔽原生 AI 的小范围闲逛；偏离超过 256 单位才重新寻路。发现或靠近敌人、使用投掷物、执行紧急撤离，以及下包后的回防均不受此静止保护限制。
- 上下半场手枪局：固定采用标准 2A、2B、1 名机动位，不把 `$800` 手枪局误判为 Eco 后执行非常规前压。
- Eco/强起：从非手枪局开始提高单点前压或堵点重防的概率；单点前压最多派 2 名 CT，最远目标限制在包点朝 T 方 950 单位以内，并保留另一包点至少 2 名防守者；堵点按 3–2 分布，不再出现 5 人同守一处。
- C4 掉落：最多调 3 名存活 CT 从不同 NAV 掩体守包，其他 BOT 保持原生 AI。
- 炸弹安装：清除前期接敌留下的调度锁定，先从不同方向建立回防接近位；至少半数 BOT 到达接近位（或达到硬超时）后再统一压向炸弹，超时后释放给原生 AI，避免路径死循环。
- CT 掉人补防：下包前有 CT 阵亡时，从仍有余量的防区调 1 名 CT BOT 补向阵亡位置对应包点；不会抽走另一包点的最后一名防守者。
- 发现敌人报点：CT BOT 看到存活 T 时使用无线电并向 CT 队伍聊天报告 NAV 区域名（无法取得区域名时报告 A/B）；同一包点默认 5 秒内只报一次，避免刷屏。
- 接敌补防：报点者立即解除阵型命令并交还 BetterBots 战斗逻辑，另调 1 名可用 CT BOT 靠近接触点补防；不会抽走另一包点的最后一名防守者。
- 补防命令默认最多持续 12 秒，随后自动释放给原生 AI，避免旧情报造成长期卡位。
- 非爆破图、单包点图、缺少包点坐标或 NAV 数据时不下达命令，自动保持原行为。

经济分类不再直接使用全队平均现金。每名存活玩家会根据当前主武器价值、护甲、头盔以及购买本方最低价步枪后补甲所需现金，分别归类为完整购买、强起或 Eco；低于本方最低价步枪价值的 SMG 等主武器只计为强起装备。系统再以队内多数人的分类决定本回合战术和 BOT 购买方向。默认概率如下：

| 经济 | 单点前压 | 堵点重防 | 标准阵型 |
| --- | ---: | ---: | ---: |
| 完整购买 | 10% | 15% | 75% |
| 强起 | 35% | 45% | 20% |
| Eco | 35% | 55% | 10% |

## 起枪、发枪与捡枪协调

- 非纯存局的 BOT 买主武器前优先购买可负担的护甲；持有保下主武器时仍可补甲。
- 完整购买或强起由逐人装备分类汇总，不会再因一名满钱玩家把全队平均值拉高而让所有 BOT 盲目起枪。
- 冻结时间内，无主武器且自身买不起“最低价步枪＋所缺护甲”的队友会进入发枪队列；真人优先，其次按现金从少到多分配。
- 发枪 BOT 必须能在重买同一主武器后保留补甲预算；CT 缺少拆弹器时还会额外预留 `$400`，避免为了发枪裸甲或丢掉关键装备。
- 全队判定为 Eco 时不会发掉少数队员保下的长枪，避免该 BOT 的重买命令被存局规则拦截后白白损失武器。
- 没有常规发枪者时，原 BetterBots 的 FAMAS/Galil、MP9/MAC-10 便宜替代路径仍会使用，但同样执行装备预算检查；捐枪者把保下枪交给缺枪队友，自己保留新买的便宜枪。
- 每名缺枪玩家每回合最多安排一次发枪。实际丢枪前会再次确认接收者仍然存活、同队且没有主武器；若其已经自行购买或捡到长枪，立即取消该次购买，避免重复发枪和出生点枪堆。
- 有战术命令的持枪 BOT 继续执行阵型；没有主武器的 BOT 可临时拾取可见、可达且优于当前装备的地面武器，然后继续战术。

服务器控制台可检查当前分类和可发枪人数：

```text
sm_bot_equipment_status
```

输出中的 `team_state` 为 `0=Eco`、`1=强起`、`2=完整购买`。

## T 方战术行为

- 默认进攻：持包者进入随机选择的 A/B 包点，主攻队靠近目标，另有中路控制和另一包点牵制位。
- 开局集合：持包者优先取得正面中心集合位，其他人分布在目标包点朝 T 出生方向的两侧，不再把持包者固定分到最左侧翼。前期行进采用直接路线，减少危险权重造成的跨区绕路。
- Rush：全队使用最快路线集中冲击随机包点，Eco 和强起时默认出现概率更高。
- 分推：从包点的 T 方两侧形成夹击；不在包点背后的 CT 区域随机选进攻入口。
- 录制投掷点优先：T BOT 带有对应道具且靠近 BetterBots 已配置的投掷点时，先完成原有的开局烟、闪、火录制（例如 Mirage 的 VIP/窗口烟），再恢复战术移动；遇敌仍由原战斗逻辑中断投掷。
- 同步进攻：冻结结束后先前往目标外侧的不同集合位；进入目标 128 单位内即视为到位并停止原生 AI 的小范围游走，只有偏离超过 256 单位才重新寻路。默认至少等待 3 秒且 60% 的仍受调度 BOT 到位后统一进入包点。10 秒仍未满足时强制执行，任何 T 在集合阶段接敌、受伤或阵亡也会让其他人立即跟进。该到位保持只作用于进攻集合阶段，不影响录制投掷点、掉包回收、下包后站位或接敌战斗。
- 持包保护：初始目标 0 固定优先分配给持有 C4 的 BOT，避免持包者被随机派到牵制位；即使持包者在集合阶段因开火或受伤临时退出站位，正式进攻开始时也会重新加入主攻路线，其他正在交火的 BOT 仍保持原生战斗控制。
- 掉包回收：一名 BOT 直接取包，另派最多两名 BOT 占据周围接应位置。
- 下包后：存活 T（包括进点时曾因交火释放战术控制的 BOT）会重新编组，分散到炸弹周围 NAV 掩体，并以 CT 出生方向作为主要回防方向，由共用架点规划器按中央、左右 35°、左右 70°分配扇区；每个扇区再对附近角度做视线检测和 NAV 投影。AWP/狙击枪优先约 950 单位，步枪约 750 单位，SMG/霰弹枪约 500 单位。下包事件会取消尚未完成的进攻阶段预录投掷路线，且下包后不再选择需要离开守包区域的新预录点；围绕 C4 的燃烧弹、手雷等本地拖延投掷仍然保留。到达目标 128 单位内停止闲逛，偏离超过 256 单位才重新寻路；发现敌人、开火或受伤后立即解除个人站位和固定朝向，恢复原战斗 AI。

T 方默认概率：

| 经济 | Rush | 分推 | 默认进攻 |
| --- | ---: | ---: | ---: |
| 完整购买 | 10% | 45% | 45% |
| 强起 | 40% | 30% | 30% |
| Eco | 65% | 10% | 25% |

### 路线与道具编排边界

当前桥接保证已有录制投掷点优先于战术移动：BOT 在投掷点 250 单位内且持有对应道具时会暂停路线、完成录像并恢复最新战术目标。不过投掷点数据尚无包点、路线和执行阶段标签，因此它不是严格的“选择 A 分推后自动分配 A 烟、连接烟和两颗闪”。完整编排可以实现，但应先扩展数据格式，再由回合计划一次性分配投掷者、关键烟依赖和失败回退；仅根据距离强行关联会使路过 BOT 误用道具，并可能让同步进攻等待错误目标。

### 架点生成边界与改进方向

CT 初始防守和 T 守包共用一个无状态规划模块，但保留各自独立的回合状态机。规划器从站位向主要威胁方向生成五个互不相同的扇区，在每个扇区内尝试有限的角度修正，按当前主武器选择距离，同时比较直接目标和 NAV 投影目标的视线比例；结果在战术分配时生成并缓存，不在每帧扫描 NAV。该方法无需逐地图配置且能安全回退，但无法识别“宫、A1、连接、市场”等语义入口。进一步提高质量需要为每张地图保存入口锚点、优先级、适用包位和交叉火力关系；运行时再结合存活敌人的最后情报动态重新分配，且必须保留接敌立即释放固定朝向的规则。

## 地图适用范围

当前服务器内已通过实际切图、NAV 和包点几何检查的双包点地图：

```text
de_ancient  de_anubis  de_cache    de_canals  de_cbble
de_dust2    de_inferno de_mirage   de_nuke    de_overpass
de_train    de_tuscan  de_vertigo
```

以下单包点地图会明确保持原 BetterBots 行为，不启用 A/B 阵型、报点补防或掉人补防：

```text
de_bank       de_boyard     de_chalice   de_lake
de_safehouse  de_shortdust  de_shortnuke de_stmarc  de_sugarcane
```

人质、军备竞赛、危险地带和训练地图同样不启用该调度层。自定义地图无需硬编码名称；只要存在至少两个真实炸弹目标、有效 A/B 包点中心、T 出生点并能被 NavMesh 插件解析，就会自动启用，否则安全回退。

T 方配置：

```text
sm_bot_t_tactics_enable 1
sm_bot_t_tactics_debug 0
sm_bot_t_tactics_initial_hold 28.0
sm_bot_t_tactics_sync_enable 1
sm_bot_t_tactics_sync_stage_min 3.0
sm_bot_t_tactics_sync_stage_timeout 10.0
sm_bot_t_tactics_sync_min_ready 60
sm_bot_t_tactics_postplant_hold 35.0
sm_bot_t_tactics_bomb_escort_count 2
sm_bot_t_full_rush_chance 10
sm_bot_t_full_split_chance 45
sm_bot_t_force_rush_chance 40
sm_bot_t_force_split_chance 30
sm_bot_t_eco_rush_chance 65
sm_bot_t_eco_split_chance 10
```

运行时检查或重新抽取本回合战术：

```text
sm_t_tactics_status
sm_t_tactics_replan
```

## 控制与检查

服务器控制台可用：

```text
sm_ct_tactics_status
sm_ct_tactics_replan
sm_bot_ct_tactics_debug 1
```

常用 CVar：

```text
sm_bot_ct_tactics_enable 1
sm_bot_ct_tactics_initial_hold 70.0
sm_bot_ct_tactics_retake_stage 6.0
sm_bot_ct_tactics_retake_commit 14.0
sm_bot_ct_tactics_retake_stage_timeout 12.0
sm_bot_ct_tactics_sync_min_ready 50
sm_bot_ct_tactics_guard_count 3
sm_bot_ct_tactics_reinforce_on_death 1
sm_bot_ct_tactics_reinforce_on_contact 1
sm_bot_ct_tactics_contact_cooldown 5.0
sm_bot_ct_tactics_reinforce_hold 12.0
sm_bot_ct_tactics_radio_report 1
sm_bot_ct_tactics_navigation_stall_timeout 3.0
sm_bot_ct_tactics_full_push_chance 10
sm_bot_ct_tactics_full_stack_chance 15
sm_bot_ct_tactics_force_push_chance 35
sm_bot_ct_tactics_force_stack_chance 45
sm_bot_ct_tactics_eco_push_chance 35
sm_bot_ct_tactics_eco_stack_chance 55
```

首次启动后 SourceMod 会生成 `csgo/addons/sourcemod/cfg/sourcemod/bot_ct_tactics.cfg`。若两个概率之和超过 100，插件会把堵点概率压到剩余区间。

`sm_bot_ct_tactics_navigation_stall_timeout` 是寻路保护：CT 接到战术移动命令后，如果超过该秒数仍没有至少 48 单位的有效进展，插件只释放这个 Bot 给原生 BetterBots，避免其在不可达 NAV 转角持续原地旋转；不会取消其他 CT 的阵型或回防。

核心桥接不会再每 0.5 秒无条件重置寻路，也不会只下达一次后任由原生 AI 覆盖目标。新目标会立即提交；之后仅在 1.5 秒检查点内没有向目标推进至少 64 单位时才重新提交一次，从而兼顾阵型保持与旧版 NAV 转角稳定性。
已入位 CT 的 128/256 单位缓冲与调度器的卡点保护保持一致，避免刚站稳又被判定寻路停滞而解除阵型。

BetterBots 的原生导航在精确目标附近可能持续发送跳跃输入。桥接层只在 CT 架点、T 集结点和 T 守包位已经到达后清除残留跳跃，不限制移动途中的跳跃或碰撞脱困。该保护不修改战术路线、目标、阶段计时或订单状态；NAV 明确标记的跳跃区域、梯子、逃火/逃炸弹以及 BotMimic 道具轨迹不受限制。

## 回滚

不重启的即时回滚：

```text
sm_bot_ct_tactics_enable 0
sm_bot_t_tactics_enable 0
```

这会分别清除 CT/T 战术命令；BetterBots 原行为立即恢复。重新启用后下一回合开始生效。
若要跨重启保持关闭，请编辑生成的 `bot_ct_tactics.cfg` 或 `bot_t_tactics.cfg`。

完整移除需要先关闭目标服务器，然后在仓库运行：

```powershell
.\rollback_ct_tactics.ps1 -ServerDir "D:\GameServers\CSGOLegacy"
```

安装器首次接入前会保存原始 `bot_stuff.sp`、`bot_stuff.smx` 和 `bot_stuff.cfg` 到 `csgo/addons/sourcemod/data/ct-tactics-rollback`。完整回滚会恢复源码、插件及反应参数配置，并删除调度器插件、源码和生成的配置，但保留备份供审计或再次恢复。

重新接入：

```powershell
.\mods\install_ct_tactics.ps1 -ServerDir "D:\GameServers\CSGOLegacy"
```

接入脚本先在临时构建目录同时编译调度器与 BetterBots 桥接，两个都成功后才替换运行文件；编译失败不会用半成品覆盖现有 SMX。

## 建议测试

1. 在 `de_mirage` 启动一局 5v5，打开 debug，并执行 `sm_ct_tactics_status` 确认 `geometry=1` 且有活动命令。
2. 分别制造完整购买、强起和 Eco，使用 `sm_ct_tactics_replan` 多次观察标准、防守重叠和单点前压。
3. T 丢下 C4，确认部分 CT 守包；T 拾回后确认命令释放。
4. 下包前击杀 A/B 防守 CT，确认只调 1 名可用 BOT 补向对应点，且另一包点不会被完全抽空。
5. 让 CT BOT 首次看到 T，确认 CT 无线电/聊天出现报点且仅调 1 人补防；同一点 5 秒内重复看到敌人不刷屏。
6. T 冻结结束后确认先进入 `attack-stage`；60% 到位、首次接敌或 10 秒超时后应一起切换为 `attack-commit`。
7. 下包后确认 CT 先分路靠近；50% 到位、首次接敌或 12 秒超时后再同步进入拆包区域，且仍能正常瞄准、开火和投掷。
8. 在冻结时间制造一名无主武器低现金队友和一名有主武器高现金 BOT，执行 `sm_bot_equipment_status`，确认发枪后前者获得主武器、后者能重买且没有因发枪放弃甲/拆弹器；同一接收者不得触发第二次发枪，若接收者提前获得长枪则应取消购买。
9. 让受战术调度但没有主武器的 BOT 附近出现可达步枪，确认其能够拾枪；已有主武器的 BOT 不应为捡枪偏离阵型。
10. 执行即时回滚，下一回合确认 BOT 恢复原路径；停服后执行完整回滚并验证插件列表。
11. 观察 CT 到达初始防守位后的 10 秒：无敌人时不应在架点周围反复踱步；出现敌人、投掷物或下包时仍应正常移动和战斗。
12. 观察移动和入位后的跳跃：正常 NAV 跨越和道具跳投应保留；普通路线不应连续跳，已入位的 CT/T 不应原地反复起跳。
13. 让持包 BOT 在集合阶段开火或受伤，确认同步进攻开始时仍沿目标 0 加入主攻方向，而不是转为牵制或单走；持续接敌时应继续优先战斗。
14. 在有 BOT 正准备或正在执行开局预录烟/闪时完成下包，确认该 BOT 立即取消旧投掷跑位并加入守包站位；CT 接近炸弹时，T 仍可在守包区域使用燃烧弹或手雷拖延拆包。
