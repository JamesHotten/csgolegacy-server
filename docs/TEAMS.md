# BOT 队伍与选手清单

本文档记录当前 CS:GO Legacy 服务器 `bot_rosters.txt` 中的全部队伍、Logo 代码和队内选手。队伍名称必须按表格中的完整名称输入；名称包含空格时必须使用英文双引号。

## 使用方法

在服务器控制台或 RCON 中执行：

```text
team "G2 Esports" ct
team "Team Vitality" t
```

- `ct`：将该阵容设置到 CT。
- `t`：将该阵容设置到 T。
- 指令目前不支持简称。`team G2 ct` 会提示 `Unknown team: G2`，正确写法是 `team "G2 Esports" ct`。
- Logo 代码是插件内部写入 `mp_teamlogo_1/2` 的值，不能代替完整队名作为 `team` 指令参数。
- 可用 `sm_validate_bots` 在服务器控制台检查阵容选手是否存在于 BOT 数据库。

## 已知数据问题

以下 8 名选手当前不在 `bot_info.json` 中，对应阵容可能无法完整添加 5 名 BOT：

- Fake do Biru：`detr0ittJ`
- LargadosyPelados：`zmb`、`happ`、`Leomonster`
- Tianjin E9 Esports：`wiwi`、`T3rry`、`see`、`Jah`

此外，Fake do Biru 的 `fdb` 和 LargadosyPelados 的 `larg` 当前缺少队名 `.cfg` 与 Logo `.svg` 文件，可能无法显示正确的队名和 Logo。

## 全部队伍

共 129 支队伍，每支配置 5 名选手。

| # | 完整队伍名称 | Logo 代码 | 选手 |
|---:|---|---|---|
| 1 | 100 Thieves | `100t` | rain、poiii、sirah、Ag1l、dev1ce |
| 2 | 1w Team | `1w` | lattykk、oz1k、cronuss、Qikert、reyoz |
| 3 | 33 | `33` | kinqie、executor、KIRO、z1Nny、bluewh1te |
| 4 | 3DMAX | `3dmax` | Lucky、Ex3rcice、Maka、Graviti、misutaaa |
| 5 | 9INE | `nein` | raalz、kraghen、cej0t、bnox、Flayy |
| 6 | 9z Team | `nine` | max、HUASOPEEK、luchov、meyern、dgt |
| 7 | AM Gaming | `am` | k1to、Altekz、Kyuubii、L00m1、myltsi |
| 8 | ARCRED | `arc` | DSSj、Get_Jeka、Ryujin、Raijin、synyx |
| 9 | AaB esport | `aab` | bekker、Maze、n1Xen、sSen、anber |
| 10 | Akimbo Esports | `aki` | N2o、obi、laxiee、Marro、mason |
| 11 | Alliance | `alli` | avid、twist、upE、eraa、MaiL09 |
| 12 | Alter Ego | `alter` | b1lal、BnTeT、Gratisfaction、Polbandana、BOROS |
| 13 | Astralis | `astr` | Staehr、jabbi、HooXi、phzy、ryu |
| 14 | Aurora Gaming | `aur` | XANTARES、MAJ3R、Wicadia、woxic、soulfly |
| 15 | Aurora Young Blud | `ayb` | r1pa4、meetyoxanaji、k1nco、starmie、redzed |
| 16 | B8 | `b8` | npl、esenthial、alex666、kensizor、s1zzi |
| 17 | BAKS Esports | `baks` | Sa1nTy、xdENiSZERA、turbo、Meepff、mecry |
| 18 | BESTIA | `best` | tomaszin、cass1n、timo、buda、nacho |
| 19 | BIG | `big` | tabseN、JDC、gr1ks、blameF、faveN |
| 20 | BIG Academy | `biga` | w1dow、JBOEN、prosus、D0nii、tripex17 |
| 21 | BIG EQUIPA | `bige` | Hanka、Emmsan、ASTRA、sosya、aiM |
| 22 | BRUTE | `brut` | realzen、mASKED、hfah、nbqq、majky |
| 23 | Bekescsabai E-Sport Egyesulet | `bee` | RIP、baiano、daneelo、marcipan、Gyhufaaa |
| 24 | BetBoom Team | `bet` | s1ren、zorte、Magnojez、Boombl4、d1Ledez |
| 25 | Betclic Apogee Esports | `bae` | Prism、Demho、hades、eskyy、Dr3nquu |
| 26 | Bounty Hunters Esports | `bhe` | KAISER、zock、fREQ、ponter、pepe |
| 27 | Bushido Wildcats | `bw` | darendeli、Vej、cadnyx、eNs、scolleN |
| 28 | CYBERSHOKE Esports | `cyber` | bl1x1、glowiing、alpha、Mokuj1n、fluffy |
| 29 | Change The Game | `ctg` | LaiKeXu、957、Hack1ng、VanceKK、ProKiller |
| 30 | Chinggis Warriors | `ching` | ROUX、efire、cool4st、Tikuak、ligroo |
| 31 | Coalesce | `coal` | f0cus、onder、Fizzy、Flicky、Abyss |
| 32 | ENCE | `ence` | teme、millert、Schwarz、Cliqq、HENU |
| 33 | EYEBALLERS | `eye` | JW、dex、Ro1f、maxster、bobeksde |
| 34 | Entropy Gaming | `entro` | Luzzel、mikanix、berryS、nativ、Tevsii |
| 35 | Eternal Fire | `eter` | rigoN、DemQQ、jottAAA、regali、MisteM |
| 36 | Eternal Fire Academy | `etera` | Hydro2K、GAYEW、Swexsy、preiz、EMSTAR |
| 37 | FAVBET Team | `fav` | bondik、Smash、j3kie、Marix、s4ltovsk1yy |
| 38 | FURIA | `furi` | yuurih、KSCERATO、FalleN、molodoy、YEKINDAR |
| 39 | FURIA Female | `furif` | kaahSENSEI、izaa、gabs、bizinha、lulitenz |
| 40 | FUT Esports | `fut` | dem0n、Krabeni、cmtry、dziugss、lauNX |
| 41 | Fake do Biru | `fdb` | hardzao、PKL、detr0ittJ、ckzao、Tuurtle |
| 42 | FengDa Gaming | `feng` | p5p、3gl、Biuckmt、Trash、salmon |
| 43 | Fire Flux Esports | `ff` | Cizzx、Quality、xEternaLxx、zemix、zer0UKY |
| 44 | Fisher College | `fisher` | AlekS、ReFuZR、CrePoW、corn、TH0R |
| 45 | FlyQuest | `flyq` | INS、Vexite、nettik、jks、story |
| 46 | FlyQuest RED | `flyqr` | BiBiAhn、emy、vanessa、marie、Fawx |
| 47 | Fnatic | `fntc` | KRIMZ、fear、jambo、jackasmo、Br4tkO |
| 48 | G2 Ares | `g2a` | tAk、hitori、Junyme、yksjupe、SHiNE |
| 49 | G2 Esports | `g2` | huNter-、HeavyGod、SunPayus、matys、NertZ |
| 50 | Gaimin Gladiators | `gg` | JOTA、NEKIZ、HEN1、Luken、fer |
| 51 | Galorys | `galo` | tomate、nython、gbb、destiny、k1not1 |
| 52 | GamerLegion | `gl` | Tauson、PR、REZ、hypex、Snax |
| 53 | Gentle Mates | `gent` | mopoz、dav1g、sausol、alex、Martinez |
| 54 | Ground Zero Gaming | `gzg` | apocdud、pz、vision、Omichella、sliimey |
| 55 | HAVU | `havu` | uli、puuha、ottob、p3kko、Alxc |
| 56 | HEROIC | `heroi` | xfl0ud、nilo、Alkaren、Chr1zN、susp |
| 57 | IC Esports | `ic` | onic、Dawy、zeRRoFIX、cptkurtka023、headtr1ck |
| 58 | INFINITE | `infi` | mhN1、kreaz、Dytor、sl3nd、Blytz |
| 59 | Imperial Esports | `imper` | VINI、noway、chelo、levi、decenty |
| 60 | InControl | `inc` | TyRa、jsfeltner、Scorchyy、aelor、ayaneuu |
| 61 | Isurus | `isur` | deco、atarax1a、Hezz、dott1、BK1 |
| 62 | JANO Esports | `jano` | Khelaa、Moroara、S4MI、Tumpsukka、3ikk4 |
| 63 | Johnny Speeds | `speed` | Sapec、Lekr0、HEAP、jocab、nawwk |
| 64 | K27 | `k27` | kashl1d、xeedo、qw1nk1、X5G7V、fame |
| 65 | Kaleido Gaming | `kale` | SPine、rage、suki、SasiKi、chuzhongT |
| 66 | Keyd Stars | `keyds` | CutzMeretz、lash、matios、xureba、zede |
| 67 | Kitsune Esports | `kits` | Doru、wilj、Triton、March、FROZ3N |
| 68 | LargadosyPelados | `larg` | zmb、happ、Leomonster、divine、Alisson |
| 69 | Legacy | `leg` | latto、dumau、saadzin、n1ssim、arT |
| 70 | Leo Team | `leo` | OneUn1que、marat2k、kL1o、Malkiss、amster |
| 71 | Life's A Game | `lag` | Sandman、consti、djay、kmrn、Cryptic |
| 72 | Lynn Vision Gaming | `lynn` | westmelon、z4kr、EmiliaQAQ、Starry、C4LLM3SU3 |
| 73 | M80 | `m80` | Swisher、slaxz-、s1n、Lake、JBa |
| 74 | MANA eSports | `mana` | ammar、Caleyy、BledarD、cerber、SENER1 |
| 75 | MASONIC | `maso` | Noruyp、Botman、KralleJ、Avou、b0RUP |
| 76 | MIBR | `mibr` | brnz4n、insani、kl1m、LNZ、venomzera |
| 77 | MIBR Academy | `mibra` | brn$、stormzyn、lkz、fl4sh、Jerr1 |
| 78 | MIBR Female | `mibrf` | dani、GaBi、yungher、poppins、olga |
| 79 | MOUZ | `mouz` | torzsi、xertioN、Spinx、xelex、jL |
| 80 | Made in Thailand | `mith` | MAIROLLS、ROLEX、SeveN89、AumMaloDy2K、Anony |
| 81 | Marsborne | `mars` | Grizz、ogwizard、freshie、marekiew、WUMBO |
| 82 | Misa Esports | `misa` | Zuedsta、Mertowsk1、Ckanic、rim3、souv |
| 83 | Monte | `mont` | Gizmy、afro、AZUWU、Bymas、Rainwaker |
| 84 | Mythic | `myth` | fl0m、Cooper、Trucklover86、hyza、PwnAlone |
| 85 | NRG | `nr` | oSee、nitr0、br0、Sonic、Grim |
| 86 | Natus Vincere | `navi` | b1t、Aleksib、iM、w0nderful、makazze |
| 87 | Natus Vincere Junior | `navij` | kodak、Yoki、FAZERY、MahaR、skizzyee |
| 88 | Nemiga Gaming | `nem` | 1eeR、khaN、Sowalio、SYPH0、KaiR0N- |
| 89 | Ninjas in Pyjamas | `nip` | sjuush、Snappi、xKacpersky、cairne、stavn |
| 90 | Nuclear TigeRES | `nt` | senka、flouzer、z1k4、m1QUSE、ayuki |
| 91 | OG | `og` | spooke、adamb、arrozdoce、cadiaN、bodyy |
| 92 | PARIVISION | `pari` | BELCHONOKK、Jame、nota、xiELO、zweih |
| 93 | Partizan Esports | `parti` | m1traa、zecco、DotlA、rajkeza、dyrod |
| 94 | Passion UA | `pass` | Kvem、JT、nicx、try、Senzu |
| 95 | Playing Ducks | `pduc` | OneLion、MYS、Miku、frozeN、UN1TY |
| 96 | QUAZAR | `qua` | gehji、kaiori、1zz、newt、Ne1XXX |
| 97 | RUSTEC | `rustec` | Brilliance、jakekeS、supra、anttzz、youka |
| 98 | Rare Atom | `rar` | Summer、L1haNg、ChildKing、TiGeR、chengking |
| 99 | Rebels Gaming | `reb` | Icarus、snapy、NOPEEj、TMKj、stadodo |
| 100 | Rooster | `roos` | chelleos、ju1ces、rekonz、SkulL、ADK |
| 101 | SINNERS Esports | `sinn` | beastik、SHOCK、kisserek、stressarN、MoDo |
| 102 | Sashi Esport | `sas` | Cabbi、Zyphon、Beccie、MistR、acoR |
| 103 | SemperFi Esports | `semp` | SaVage、keen、shadiy、HaZR、ADDICT |
| 104 | Sharks Esports | `shark` | gafolo、rdnzao、doc、koala、maxxkor |
| 105 | Shimmer | `shim` | empathy、Stx、Serendipity、alicerawr、AVA174 |
| 106 | ShindeN | `shin` | abizz、ivz、naz、tom1jed、FraGuTy |
| 107 | Sissi State Punks | `ssp` | farmaG、Cl34v3rs、oli、fADE、kinQ |
| 108 | Steel Helmet | `sh` | captainMo、AE、18yM、DD、AiM |
| 109 | THUNDERdOWNUNDER | `thun` | aliStair、dexter、Liazz、asap、TjP |
| 110 | TYLOO | `tyl` | JamYoung、Moseyuh、Mercury、Jee、zero |
| 111 | Team Falcons | `fal` | NiKo、TeSeS、m0NESY、kyousuke、karrigan |
| 112 | Team LEISURE | `leis` | BischeR、julz、DREAd、zDragZzz、Pano |
| 113 | Team Liquid | `liq` | NAF、ultimate、siuhy、EliGE、malbsMd |
| 114 | Team Nemesis | `tn` | SELLTER、Sdaim、tex1y、mag1k3Y、r3salt |
| 115 | Team Spirit | `spir` | magixx、zont1x、donk、sh1ro、tN1R |
| 116 | Team Spirit Academy | `spira` | mazay、Kiryasoo、kidofpain、VILBy、s1nside |
| 117 | Team Vitality | `vita` | apEX、ZywOo、flameZ、mezii、ropz |
| 118 | Team Voca | `voca` | snav、nosraC、Infinite、junior、Jeorge |
| 119 | The Huns Esports | `hun` | nin9、Bart4k、xerolte、sk0R、controlez |
| 120 | The MongolZ | `mongo` | bLitz、Techno4K、910、mzinho、cobrazera |
| 121 | Tianjin E9 Esports | `te` | neverland、wiwi、T3rry、see、Jah |
| 122 | Tricked Esport | `trick` | Leakz、salazar、NickyB、IceBerg、Boye |
| 123 | UNiTY esports | `unit` | NEOFRAG、woozzzi、MoriiSko、M1key、KWERTZZ |
| 124 | Virtus.pro | `vp` | tO0RO、b1st、mir、AquaRS、F0R3VER |
| 125 | WOPA Esport | `wop` | Zanto、thamlike、Patti、kwezz、sL1m3 |
| 126 | Wildcard | `wc` | reck、mhL、HexT、nEMANHA、Cxzi |
| 127 | against All authority | `aaa` | AsI0K、Saax、SLIE9000、Tarkky、Rain |
| 128 | magic | `magic` | MaSvAl、tENZY、sFade8、AW、mo0N |
| 129 | paiN Gaming | `pain` | biguzera、snow、piriajr、v$m、saffee |
