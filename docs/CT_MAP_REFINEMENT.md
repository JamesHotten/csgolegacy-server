# Overpass、Mirage、Nuke CT 专项

对应 CT 调度器 `0.1.14`。这些开关默认开启且仅影响对应地图；关闭后，下一回合按原战术。未替换购买、经济、BetterBots 的射击/反应逻辑或 T 调度。

| 地图 | 开关 | 行为 |
| --- | --- | --- |
| Overpass | `sm_bot_ct_overpass_teamwork 1` | 交火/减员后找与该包点同层、可站、可达、不过度暴露的补防位，不对同一 BOT 重复下令，普通补防保留另一点最后一名守员。见到包匪或确认大规模强攻的已有全队回防优先级不变。已下包时，A 尝试 `BackofA/UnderA/Stairs`，B 尝试 `Construction/Bridge/Water`；要求从当前守员到入口、再由入口到炸弹均可走，并限制绕路距离。无合适入口时保留通用选点。 |
| Mirage | `sm_bot_ct_mirage_crossfire 1` | 标准阵型保留点内锚点，试配一名独立掩体的近侧守员。从两处都能打到共同射界才配对；若需要换站位，不牺牲已有命名枪线或增加双向暴露。收到同伴真实报点且实际枪线通畅时，最多短暂转向，不强迫移动或开火。 |
| Nuke | `sm_bot_ct_nuke_route_cover 1` | 开局确认停滞或反复摔落时尝试一个同层、可达的小绕行点，到达后恢复原职责；失败仍交回原生 AI。B 点内守员掉人时优先用 B 点附近且未在交火的人补原站位，不抽走 A 点内守员。B 开局点内位优先分给实际导航路径更短的队员。 |

## 验证

- 只在监听 `127.0.0.1` 的独立服运行测试插件。`tests/ct_map_refinement_runtime_probe.sp` 覆盖 Overpass 补位与弱侧保留、Mirage 同伴接应和 Nuke 下层补位、重复跌落绕行与原目标恢复。探针定位好角色后才给受控场景，不用于衡量自然对抗胜率。
- `tests/plant_route_runtime_probe.sp` 的 `-ctrefinelive` 启用正常速度的真实下包/拆包矩阵，`-ctrefineend <map>` 用来切分批次；每图涵盖 A/B。`tests/ct_opening_position_runtime_probe.sp` 的 `-ctrefineopening` 可检查 Nuke A/B 守员实际到位。测试开关在这些插件不加载时不生效。
- 使用 `tests/check_ct_map_refinement_runtime.ps1` 验收定点与旧版对照，`tests/check_tactical_live_matrix.ps1` 验收十图真正的结果事件。自由对抗用固定阵容和真实半场换边，不改经济或对枪参数；短样本单独记录，不保证地图胜率达到五五开。

2026-11-16：十图 A/B 正常速度回归共 20/20 真实下包并由 CT 拆除，20 场有道具爆开和预设的掉人条件；另有 36 项已有静态/数据检查通过。在每图 6 回合、真实换边的自由对抗中，Overpass 平均下包到回防推进时间从 9.7 秒降至 4.6 秒，CT 胜场为 3→1；Mirage 新版发出 3 次开局配对，真实交火样本未观测到同伴接应信号（受控报点用例已验证），CT 胜场为 2→1；Nuke 导航停滞释放从 3 次降到 0 次，出现 3 次局部绕行，CT 胜场仍为 0。功能回归与短局胜负分开判定，未证明整体胜率改善，后续应扩大正常对局样本观测。

完整回滚：停服后，从正式服 `csgo/addons/sourcemod/data/ct-map-refinement-rollback-20261116` 恢复同相对路径的 CT 插件和源码两个文件。无须还原配置或数据库。
