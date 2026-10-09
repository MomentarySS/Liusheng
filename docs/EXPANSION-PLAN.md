# 流声拓展计划

长期跟踪文档。**状态总览 → 每条改法与语义边界 → 验证清单 → 变更记录**。

本文件在 `docs/` 根目录，**不受 `.gitignore` 排除**。注意 `docs/design/*-plan.md` 一类通配规则会把计划文档排除在仓库外，写在这里才可追溯。

对应产品版本：2.2.3

---

## 一、已定决策（不要再讨论）

| 决策 | 内容 | 日期 | 落点 |
| --- | --- | --- | --- |
| 不上架 Google Play | 签名 APK 手动分发 + Inno Setup。`targetSdk` 保持 Flutter 默认，`minSdk` 保持 23 | 2026-10-05 | `PRODUCT.md` Binding bans、`.cursor/rules/00-project-context.mdc` |
| 不整体复刻 Apple Music / Spotify | 保持 Material 3 系统语言 + 已采用的 Spotify 式**交互**范式，不复刻任一家的**视觉** | 2026-10-05 | 本文件第二节 |
| 新版本走 GitHub Release | `dist/` 产物上传到 GitHub Release，tag 跟随版本号 | 2026-10-05 | `README.md` 打包章节、`.cursor/rules/00-project-context.mdc` |

### 决策推论（防止被反复重提）

- **不要**为满足 Play 的 API 36 要求去升 Flutter 或抬高 `minSdk`。Android 16 的行为变化（edge-to-edge / predictive back / 大屏方向锁）按 `targetSdk` 开关，不选 36 就不触发。
- **16 KB 页对齐已实测通过**（`zipalign -c -P 16` 对 `dist/liusheng-2.2.2.apk` 返回 `Verification successful`，四套 ABI 全 OK，NDK 27.0.12077973）。不需要处理。
- Apple Music 方向撞三处硬约束：`.cursor/rules/00-project-context.mdc:10`、`PRODUCT.md` Operating Context（`do not adapt to Fluent or Cupertino per OS`）、`DESIGN.md:150`（明确拒绝 Cupertino 控件）。且它的视觉骨架围绕版权曲库构建，与「公开直播流 + RSS」的产品形态不匹配。

---

## 二、视觉执行度审计（2026-10-05）

**结论：结构层执行到位，品牌层与排版层缺失。** 缺的不是"参照物"，是品牌色的 chroma 和排版 scale 的落地。

### 执行到位的（不要动）

`DESIGN.md` 作为约束在结构层真实生效，逐条核对通过：

- 形状：按钮 `StadiumBorder`、卡片半径 12、对话框 28、芯片 8、迷你条 12
- 阴影：迷你条 `elevation: 6` + `shadow @ 0.22`，与 `DESIGN.md:218` 一致
- 间距：迷你条 `EdgeInsets.fromLTRB(8, 0, 8, 8)`，与 `DESIGN.md:203` 一致
- 布局：`home_shell.dart:154` 为 `SafeArea(bottom: false)` 且 `MiniPlayer` 是 `Column` 的一部分，符合 `DESIGN.md:209/211` 两条硬规则
- 种子色：`theme.dart:83` 与 `DESIGN.md` 一致
- 输入框、Divider、IconButton 最小触控 48 均已落地

### 偏差清单（按影响排序）

| # | 偏差 | 位置 | 状态 | 影响 | 解法 |
| --- | --- | --- | --- | --- | --- |
| A | **浅色 primary chroma 偏低** | `theme.dart` 用 `ColorScheme.fromSeed` 默认 `tonalSpot` | **已完成** | 种子 `#1565C0` 被压成 `primary #405F90`，浅色界面里品牌蓝基本看不见 | 采用方案 B：**仅浅色 `vibrant`**，深色保留 `tonalSpot` |
| B | **typography scale 未落地** | `theme.dart` 缺 `textTheme` | **已完成** | 设计文档定好的 scale 全靠各处手写，必然漂移 | 已显式写全 10 个角色，见下方「B 的实现陷阱」 |
| C | **`DESIGN.md` 自身矛盾** | 6 处 | **已定稿** | 实现者无从判断该听哪句 | 已按代码现值写回 `DESIGN.md` |
| D | 文档版本滞后 | `DESIGN.md:3` / `:134` | **已修** | 仍写"对应产品 2.1.0" | 已更新为 2.2.2，并注明 2.1.1–2.2.2 未改动这些 token |

#### A 的实测对比（探针实测，非推断）

种子 `#1565C0`，各 `DynamicSchemeVariant` 在 `ColorScheme.fromSeed` 下生成的真实色值：

| variant | 浅色 primary | 判断 |
| --- | --- | --- |
| `tonalSpot`（**现状**） | `#405F90` | 灰蓝，品牌不可见 |
| **`vibrant`** | **`#005DB7`** | **最接近种子，仍是品牌蓝 —— 推荐** |
| `fidelity` | `#004D99` | 更深的蓝，可用 |
| `content` | `#004D99` | 同 `fidelity` |
| `rainbow` | `#285EA7` | 饱和度中等 |
| `neutral` | `#595E6C` | 更灰，方向相反 |
| `expressive` | `#3A6931` | **变成绿色，违背品牌** |
| `fruitSalad` | `#006876` | **变成青色，违背品牌** |

**⚠️ 对初版结论的修正。** 初版写"深色模式所有蓝色系 variant 的 `primary` 同为 `#A9C7FF`，完全相同，所以只影响浅色模式"——**这是错的**。实测色卡（`docs/color-scheme-cards.png`）显示只有 `primary` 一列相同，**其余角色在深色下都变**：

| 深色角色 | tonalSpot | vibrant |
| --- | --- | --- |
| `primary` | `#A9C7FF` | `#A9C7FF` ← 唯一相同 |
| `onPrimary` | `#08305F` 深蓝 | `#003063` 深蓝 |
| `primaryContainer` | `#274777` | `#00468C` |
| `secondary` | `#C2C7D0` | `#BFC4EB` |
| `surfaceContainerHigh` | `#282A2F` | `#282A33` |
| `outline` | `#8E9099` | `#8B919F` |

**⚠️ 二次勘误（2026-10-09）。** 上表 vibrant 列的 `onPrimary` 原记为 "`#003D03` 深绿 ⚠️"——**这不成立**。用当前 Flutter 对种子 `#1565C0` 实算并采样色卡第 3 行色块，vibrant 深色 `onPrimary` 是 `#003063`（深蓝，色卡图注里那句 "flips to #003D03 (green)" 也是同一处误记）。当初实测的 `#003D03` 应为旧版 Flutter 产物或誊写错误；"深色保留 tonalSpot" 的决策不变，理由修正为：深色 `primary` 本就是清晰的浅蓝，换 `vibrant` 无收益且连带改动整套深色角色。

`DESIGN.md` 规定主播放键用 `primary` + `onPrimary`；`onPrimary` 保持深蓝即可保证播放键图标可读。

**采用方案 B：仅浅色 `vibrant`，深色保留 `tonalSpot`。** 理由：这条改法的动机是"浅色品牌蓝不可见"，而深色 `primary` 本来就是清晰的浅蓝、不存在该问题；保留 `tonalSpot` 改动最小、深色观感零风险。`theme.dart` 里拆成 `lightVariant` / `darkVariant` 两个常量并加了 `variantFor()`，另有一条测试钉住深色 `onPrimary` 的当前取值。

浅色侧的实际收益：`primary` `#405F90` → `#005DB7`（最接近种子 `#1565C0`），`secondary` / `surfaceContainerHigh` / `outline` 同步偏蓝。`primaryContainer` / `surface` / `error` 不变。

`expressive`（变绿 `#3A6931`）与 `fruitSalad`（变青 `#006876`）会让品牌色相被换掉，**不可选**。

#### B 的实现陷阱（重要）

**不能只基于 `Typography.material2021()` 的角色做 `copyWith`。** Material 3 把早期版本下沉的字号与字重从角色样式里移走了，那些角色只带 `color` / `family` / `decoration`，**`fontSize` 是 `null`**。只补 `fontWeight` 会得到"看起来设置了、其实字号一个都没落"的假实现——本次第一版就是这样，测试立刻报 `Expected: <24> Actual: <null>` 才暴露。

修法：字号、字重、行高比例**全部显式写全**，不依赖任何基底。行高取 `DESIGN.md` 的比例（headline 1.33、title 1.5、body 1.43、label 1.33）。

#### 验证结果（2026-10-05）

- `dart format --output=none --set-exit-if-changed lib test` → 0 changed（幂等）
- `flutter analyze` → No issues found
- `flutter test` → **191 项全过**（基线 180 + `design_tokens_test.dart` 新增 11）。既有 180 项无一被破坏，说明字号真正落地后没有布局溢出
- 新增 `test/design_tokens_test.dart` 锁定种子、生成色、变体策略、浅色色相、深色 `onPrimary`、排版 scale、形状与断点，防止 token 被无意改动
- 色卡 `docs/color-scheme-cards.png` 为人工目视证据：第 1 行是实际采用的浅色 `vibrant`，第 2 行是实际采用的深色 `tonalSpot`，第 3 行是被否决的深色 `vibrant`（**图注文案有误**——它写 `onPrimary flips to #003D03 (green)`，实际色块与标签是 `#003063` 深蓝，见上方二次勘误；图片无生成脚本入库，以文本层勘误为准），第 4 行是改动前的浅色 `tonalSpot` 供对照

> 渲染色卡时踩过的坑：先试过渲染完整界面，结果测试默认字体是 Ahem（方块）导致布局爆炸（"overflowed by 800957 pixels"），图片只有左上角一小块有效。**纯色块才是 widget 测试截图的可靠载体**——没有字体宽度依赖，也就不会溢出。若日后还要出图，优先铺色块而不是排界面。

**C 的偏差明细（已定稿，2026-10-05 全部采用代码现值）：**

| 项 | DESIGN.md 原写 | 代码现值（已定稿） | 位置 |
| --- | --- | --- | --- |
| 迷你条播放键触控 | `:227` 48 / `:236` 52（文档自相矛盾） | **48** | `mini_player.dart:229` |
| Now Playing 渐变淡出位置 | 45% | **62%** | `app_skin.dart:50` |
| Now Playing 渐变 wash 强度 | 55% | **36%** | `app_skin.dart:55` |
| 封面光晕 blur | 32 | **28** | `radio_now_playing.dart:190`、`podcast_now_playing.dart:168` |
| 封面光晕 下偏 | 16 | **12** | 同上 `offset: Offset(0, 12)` |
| 封面光晕 透明度 | 35% | **28%** | 同上 `alpha: 0.28` |

> **对上一版审计的修正**：初版把 `DESIGN.md:215` 的 55% 与 `:219` 的 35% 当成同一处矛盾，这是错的——55% 指渐变 wash 的混合强度，35% 指光晕阴影的透明度，是两个独立参数。查证后展开为上表的 3–6 行。**渐变 wash 才是文档写 55% 而代码 36% 的那一处；光晕是三项参数全部不符。**

**附带发现**：光晕三项参数在 `radio_now_playing.dart:188` 与 `podcast_now_playing.dart:166` 重复硬编码，值完全相同。宜收敛到 `LiushengSkinTheme`（那里已有 `nowPlayingWash`），否则下次调整要改两处。已记入 `DESIGN.md:219`。

### 语义边界

- A 与 B 是**独立**的两项，不要合并成一次改动。A 改色、B 改排版，合做无法定位是哪个引起的观感变化。
- 修 A 之前**不要**改种子色。种子 `#1565C0` 是启动器与图标叙事色，动了会牵连 Android 自适应图标、legacy tile、Windows 可执行文件与托盘（见 `DESIGN.md:146`）。
- 修 B 时**不要**引入独立品牌字体，`DESIGN.md:199` The Platform Face Rule 禁止。
- 修 C 属于改文档，不需要测试，但**必须先于 A/B 定稿**，否则 A/B 无从验收。

### 验证清单

- [ ] **A（待拍板后才做）**：`flutter analyze` 无新增问题；浅色与深色各截一次"电台 + 迷你条 + Now Playing"三处，确认品牌蓝可辨且未过饱和
- [ ] **A（待拍板后才做）**：确认「壁纸 / 系统配色」开关开启时走平台色、关闭时回流声蓝，两条路径都验
- [ ] **A（待拍板后才做）**：确认 Android 12+ Material You 动态色未被 A 破坏
- [x] B：grep 全库手写 `fontSize:`，确认无与 scale 冲突的残留 → 仅 4 处，其中 1 处是刻度数字例外、3 处是导航标签，均已记入 `DESIGN.md`
- [x] B：`ThemeData.textTheme` 落地，10 个角色字号/字重/行高显式写全
- [ ] B：四个目的地（电台 / 播客 / 收听 / 设置）+ 迷你条 + Now Playing + 全部 sheet 浅深色各过一遍（**待人工目视**）
- [x] C：6 处矛盾各自定稿并写回 `DESIGN.md`，采用值与理由已记录
- [x] D：`DESIGN.md` 版本标注更新为 2.2.2
- [x] 全部改动后 `dart format --output=none --set-exit-if-changed lib test` → 0 changed
- [x] 全部改动后 `flutter analyze` → No issues found
- [x] 全部改动后 `flutter test` → 188 项全过（基线 180）

---

## 三、功能候选（待办池）

推荐执行顺序已定，按序推进。**不要跳序。**

| 顺序 | 项 | 状态 | 预估 |
| --- | --- | --- | --- |
| 1 | **播客订阅分组** | **已完成** | 小 |
| 2 | **Windows 新一集通知** | **已完成** | 中 |
| 3 | **跨设备同步** | 待立项 | 大 |
| 4 | **架构重构** | 顺手做 | 中 |
| 5 | **本机个性化推荐** | 备选 | 中 |

### 1. 播客订阅分组（已完成 2026-10-05）

RSS 本身没有文件夹概念，此前订阅平铺。中文播客用户按新闻 / 商业 / 科技分组是刚需。

**落地方式**：分组是**筛选维度，不是嵌套文件夹**——一个订阅最多属于一个分组，列表仍平铺。搜索框下方出现筛选行（全部 + 各分组带订阅数 + 未分组 + 管理），长按订阅或 Windows 右键 →「移动到分组」，管理里可新建 / 重命名 / 删除。**不建分组时整行不渲染**，未改动的安装与此前完全一致。搜索与分组筛选是 AND 关系。

**关键取舍**：分组定义与 `feedId -> groupId` 映射放在**两个独立 SharedPreferences key**（`podcast_feed_groups_json` / `podcast_feed_group_map_json`），**不写进 `PodcastFeed`、不动 `subscribed_podcast_feeds` 结构**。代价是删订阅/删分组要手动清孤儿；换来的是既有数据与旧备份**零迁移**，`feed_cache` 更是完全无关。分组关系随既有的 prefs 全量快照自动进备份，不需要改 `device_backup.dart`。

- 边界：不引入云端分类，不抓取第三方分类结果；分组只存在本机
- 边界：不得改动 `feed_cache` 的缓存键结构，否则会静默丢失既有缓存
- 边界：删分组不是删订阅——已用测试钉住（`删分组把订阅放回未分组，而不是丢订阅`）
- 边界：分组被删或从备份恢复后，失效的筛选由 `resolvedGroupFilterProvider` **纯派生**回落成"全部"，不在 provider 里写另一个 provider 的 state
- 验证：新分组可建可改可删、重名与空名被拒；移动订阅后仍出现在"未听"和自动下载范围内（分组只是筛选维度，不触碰这两条链路）；备份导出再导入后分组关系不丢；删订阅会清掉映射里的孤儿键

**⚠️ 实现中被测试抓出的真 bug**：`FeedGroupLogic.filter` 原本写成 `if (groupId.isEmpty) return feeds;`，而 `ungrouped` 本身就是空串——于是"只看未分组"会悄悄变成"看全部"；同时 `allGroups`（`'__all__'`）没被特殊处理，反而掉进过滤分支返回**空列表**。也就是说筛选行点任何一个分组，列表都会坏掉。已改为 `if (groupId == allGroups) return feeds;`，并把三个语义不同的取值（`allGroups` / `ungrouped` / 具体 id）在 `FeedGroupLogic` 顶层显式分开，避免再撞车。

### 2. Windows 新一集通知（已完成 2026-10-05）

Android 已有 `workmanager` 后台检查，Windows 此前完全没有触发源。

**先查清再动手**：`local_notifications.dart` 里 **Windows 的初始化一直都在**（`WindowsInitializationSettings` + `appUserModelId` + `guid`），也就是说通知能力本来就通，缺的只是"什么时候调"。所以这不是"加通知支持"，是"加触发源"——实现量比预想小得多。

**落地方式**：新增 `core/platform/new_episode_poller.dart`（31 行），用 `Timer.periodic` 每小时调一次既有的 `checkNewEpisodesIfDue`。6 小时节流与"首次只记 guid 不提醒"全部沿用 `NewEpisodeLogic`，没有另起一套。

- 边界：轮询生命周期**跟随「新一集通知」开关**——关着就不起轮询，与 Android `cancelByUniqueName` 的行为一致。`syncBackgroundSchedule` 在非 Android 直接返回，所以设置页的 `onChanged` 里要另起/另停 poller
- 边界：**不依赖 Riverpod**。`checkNewEpisodesIfDue` / `runNewEpisodeScan` 从 `NewEpisodeChecker` 抽成顶层函数，否则 `main.dart` 里没有 Provider 上下文，只能挂一个手动 `ProviderContainer`
- 边界：防重入标志是**模块级**而非实例级——Windows 定时器与 Riverpod 侧的手动检查各持一个 `NewEpisodeChecker`，共用一个标志才不会并发打同一批 feed
- 边界：**通知关着也照扫**。扫描同时刷新 feed cache，播客页「未听」列表靠它；若因为开关关就跳过，Windows 上的未听列表会永远不更新
- 边界：Windows 不支持 `periodicallyShow`（会抛 `UnsupportedError`），所以走一次性 `show`，不碰 `cancel` / `getActiveNotifications`（非 MSIX 打包下这两个本来就无效）
- 验证：节流判据（未到期不扫 / 超 6 小时才扫 / `force` 绕过）有测试；`pollInterval` 短于 6 小时但不低于 15 分钟；`start` 幂等不叠定时器；`stop` 后可再 `start`
- **未覆盖**：真机上的 toast 实际弹出效果、退出应用后不残留通知、通知不打断正在播放的音频——这些需要跑起来看，测试环境代替不了

### 3. 跨设备同步

补的是产品自身声明却未实现的那块：`PRODUCT.md` 原则 4 说"手机和桌面是同一个产品"，但数据层完全断开。

- **形态已被"不上架"锁定**：只能是用户自己的 WebDAV / 自建服务器，不存在官方账号体系。省掉服务器、运维与账号安全整套成本
- 边界：端到端加密，密钥不随备份走
- 边界：必须改隐私文案（`PRIVACY.md` 与 `core/privacy.dart` 共用同一份）
- 边界：冲突合并策略要先定（进度 / 已听 / 收藏 / 订阅 / 书签各自的取舍）
- 验证：双端各自改同一集进度后能收敛到确定结果；断网时本地功能完全不受影响

### 4. 架构重构

四个巨型文件，任何触及播客或电台的功能第一刀都会切进去：

| 文件 | 大小 |
| --- | --- |
| `lib/features/podcast/podcast_screen.dart` | 68.5 KB |
| `lib/features/podcast/podcast_providers.dart` | 38 KB |
| `lib/features/radio/radio_providers.dart` | 38 KB |
| `lib/core/providers/app_providers.dart` | 36.6 KB |

- 边界：不做大爆炸重写。每个新功能顺手拆对应那一层即可
- 边界：重命名与搬迁不得与功能改动混在同一个 commit
- 验证：`flutter test` 180 项基线不得下降

---

## 四、GitHub Release 分发

- tag 跟随版本号（`v2.2.3`），产物为 `liusheng-2.2.3.apk`、`liusheng-windows-2.2.3.zip`、`liusheng-windows-2.2.3.exe`
- `scripts/pack.ps1` 只负责产出到 `dist/`，**不负责上传**；发布是独立步骤
- 升版本需同步（2026-10-05 实测补全，原清单漏了 5 个文件）：`pubspec.yaml`、`lib/core/brand.dart`（`AppBrand.version` 与三个 userAgent）、`scripts/pack.ps1`、`scripts/liusheng-windows.iss`（`AppVersion` 与 `OutputBaseFilename`）、`README.md`、`CHANGELOG.md`、`ROADMAP.md`、`PRODUCT.md`、`PRIVACY.md`（仓库文档里的 User-Agent 字面量）、`DESIGN.md`（frontmatter 与「对应产品版本」标注）、`docs/EXPANSION-PLAN.md`（本行）
- **只有 `lib/core/brand.dart` ↔ `pubspec.yaml` 有自动门**（`test/layer_test.dart` 的 `AppBrand version matches pubspec and user agents`）。其余文档字面量全部无测试覆盖，只能靠上面这份清单人工核。`test/layer_test.dart` 里断言的 `PrivacyCopy` 是应用内隐私文案，与仓库的 `PRIVACY.md` 是两处，后者不受该测试保护
- **注意**：`/dist/` 在 `.gitignore` 内，产物不走 git 提交，只作为 Release 附件
- **注意**：`ADULT_SOURCES.md` 与 `SOURCES.md` 是 local-only（`.gitignore` 第 71-72 行），不要带进 Release 说明
- **注意**：Release 附件即公开可下载。`README.md` 写明"丢失签名配置后无法再发同一个 App 的更新"，公开发布后需要考虑 apk 的公开面

---

## 变更记录

| 日期 | 内容 |
| --- | --- |
| 2026-10-05 | 建档。记录三条决策（上架 / 视觉方向 / 分发）、视觉执行度审计结论、5 项功能候选与推荐顺序 |
| 2026-10-05 | 偏差 C、D 定稿并写回 `DESIGN.md`（6 处矛盾采用代码现值 + 版本号更新为 2.2.2 + 记录 2 处 scale 外例外） |
| 2026-10-05 | 偏差 B 完成：`theme.dart` 补 `ThemeData.textTheme`，10 个角色显式写全；新增 `test/design_tokens_test.dart`（8 项）。三道门全绿：format 幂等、analyze No issues found、test 188 项全过 |
| 2026-10-05 | 偏差 A 实测并定案：浅色 `primary` `#405F90` → `#005DB7`（`vibrant`）。**同时推翻了初版"深色不受影响"的结论**——深色下 `onPrimary` 会变深绿，播放键图标会变绿，故采用方案 B（仅浅色 `vibrant`，深色保留 `tonalSpot`），并加测试钉住 |
| 2026-10-05 | A 落地后复跑三道门：format 幂等、analyze No issues found、test **191 项全过**。色卡存档 `docs/color-scheme-cards.png`（旧图已替换，旧图把被否决的深色 `vibrant` 标成 "AFTER"，会误导） |
| 2026-10-09 | OCR 审查勘误：深色 vibrant 的 `onPrimary` 实为 `#003063`（深蓝），非 `#003D03`（绿）——用当前 Flutter 实算 + 色卡第 3 行色块采样双证；色卡图注同源误记，图片无脚本不入库，以文本层为准。同步修掉 `theme.dart` / `DESIGN.md` / `CHANGELOG` 相关表述与失效引用 `variant-color-cards.png`；"深色保留 tonalSpot" 决策不变，理由改为"无收益" |
| 2026-10-05 | **P2 播客订阅分组完成**：新增 `core/podcast/feed_groups.dart`（127 行纯逻辑）、`features/podcast/feed_group_providers.dart`（127 行）、`features/podcast/feed_group_ui.dart`（364 行）、`test/feed_groups_test.dart`（250 行）。既有文件的实测增量（`git diff --stat`）：`podcast_screen.dart` 65 行、`theme.dart` 75 行、`app_storage.dart` 24 行、`podcast_providers.dart` 5 行——两个巨型文件都只被"调用"而没有被塞进实现。分组存独立 key，`subscribed_podcast_feeds` 与 `feed_cache` 零改动。三道门：format 幂等、analyze No issues found、test **210 项全过**（新增 19 项）。测试抓出 `filter` 的 `isEmpty` / `allGroups` 判据 bug，会让筛选行任何一次点击都坏掉 |
| 2026-10-05 | **P3 Windows 新一集通知完成**：新增 `core/platform/new_episode_poller.dart`（31 行）与 `test/new_episode_poller_test.dart`（126 行）；既有文件实测增量 `new_episode_checker.dart` 63 行、`playback_screen.dart` 18 行、`main.dart` 12 行。**动手前先查清 `local_notifications.dart` 早已初始化 Windows**——所以这是补触发源而非加通知支持。三道门：format 幂等、analyze No issues found、test **220 项全过**（新增 10 项） |
| 2026-10-05 | 四条线收口为 4 个 commit（`7ff7829` 视觉 / `47b9a89` P2 / `3de2ecf` P3 / `1437136` 文档），相对 `main` 合计 21 文件 +1878/−40，**未 push** |
| 2026-10-05 | **发版 2.2.3+44**：全仓版本字面量同步（`pubspec.yaml` / `brand.dart` / `pack.ps1` / `liusheng-windows.iss` + 6 份 md）。发现两处历史遗留的不一致并修掉：① `DESIGN.md` 那句「2.1.1–2.2.2 未改动这些 token」在本版已不成立（2.2.3 改了浅色 `primary` 与 typography scale），已补记例外；② 第四节「升版本需同步」清单漏列 5 个文件（`pack.ps1`、`PRIVACY.md`、`PRODUCT.md`、`ROADMAP.md`、`DESIGN.md`），已补全并标注这些字面量无测试覆盖 |
