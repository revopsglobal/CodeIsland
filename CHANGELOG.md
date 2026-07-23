# Changelog

## [v1.0.64] - 2026-07-23

### English
- Fix Buddy-created tasks getting stranded in "Needs you" after the Mac app restarts. CodeIsland now learns and retains workspaces that appear after login, starts a pending task only once when its workspace becomes available, and closes an interrupted run with an explicit restart reason instead of pretending the provider session is still active.
- Stop repeated workspace refreshes from appending duplicate "Choose an available Mac workspace" or provider-unavailable receipts.

### 中文
- 修复 Mac 应用重启后，Buddy 创建的任务长期卡在「需要你」的问题。CodeIsland 现在会识别并保留登录后出现的工作区，在工作区可用时仅启动一次待处理任务，并以明确的重启原因关闭被中断的运行，不再假装提供商会话仍处于活动状态。
- 防止重复的工作区刷新反复追加「选择可用的 Mac 工作区」或提供商不可用回执。

## [v1.0.63] - 2026-07-21

### English
- Fix a cancelled "Needs you" task lingering on the Now tab, with its badge stuck, when the paired Mac was offline or had just restarted. Cancelling a task now clears it from the card, the Now badge, the signal tiles, and the Live Activity immediately instead of waiting for a round-trip the Mac may be unable to confirm. The optimistic cancel reconciles automatically once the Mac catches up, and never permanently hides a task the Mac later resurrects.

### 中文
- 修复配对的 Mac 离线或刚重启时，已取消的「需要你」任务仍停留在 Now 标签页、且角标不清零的问题。取消任务后，卡片、Now 角标、信号磁贴与实时活动会立即清除，不再等待 Mac 可能无法确认的往返请求。乐观取消会在 Mac 恢复后自动对账，也不会永久隐藏 Mac 之后重新恢复的任务。

## [v1.0.62] - 2026-07-20

### English
- Make CodeIsland Buddy the single away-attention channel. Native APNs notifications and Live Activities/Dynamic Island now carry approvals, questions, needs-you decisions, and task failures without duplicate bot alerts.
- Keep push payloads opaque and private. Buddy receives only request identity and state, then fetches exact details from the paired Mac over authenticated Tailscale HTTPS; decisions still require short-lived, single-use action tokens.
- Remove the Telegram sender, approval sheet, bot credentials, settings, and readiness checks so the product has one predictable notification and action path.
- The type split now reaches the words. Prompts and chat prose render in SF Pro; only machine content (commands, IDs, paths) and the `$` sigil stay monospaced in their wells. Reading a session no longer feels like reading a terminal. (M2)
- Approval buttons are risk-aware. The old four-colour button row is gone: on a destructive command (rm, force-push, DROP) Deny is the single filled action and the rest recede; on a safe command Allow leads. One emphasis, matched to consequence. (M3)
- The Today (Glances) and Tools (Hub) surfaces join the design-token system for the first time. They were 113 inline colour literals with two different ad-hoc accents; they now route through one signal amber, the white-opacity ink ramp, and pinned on-accent foregrounds. This fixes the hardcoded black-on-amber button text and drops the alert colour from the Now/Today/Tools nav, which now reads in neutral ink so amber means only "needs you". (M5)

### 中文
- 将 CodeIsland Buddy 设为唯一的离线注意力通道。原生 APNs 通知与实时活动／灵动岛统一承载审批、问题、需要你的决定和任务失败，不再产生重复的机器人提醒。
- 推送载荷保持不透明和私密。Buddy 只接收请求标识与状态，再通过已认证的 Tailscale HTTPS 从配对 Mac 获取精确详情；决定仍需短时、一次性操作令牌。
- 移除 Telegram 发送器、审批页面、机器人凭据、设置项和就绪检查，让产品只保留一条清晰可预测的通知与操作路径。
- 字体分工现已延伸到正文。提示词与对话正文改用 SF Pro 渲染；仅机器内容（命令、ID、路径）与 `$` 记号仍在凹槽中保持等宽。阅读会话不再像在读终端。(M2)
- 审批按钮现按风险区分。旧的四色按钮排已移除：对破坏性命令（rm、强制推送、DROP），仅「拒绝」为实心动作，其余弱化；对安全命令则「允许」为主。强调唯一，且与后果匹配。(M3)
- 「今天」(Glances) 与「工具」(Hub) 界面首次接入设计令牌系统。此前为 113 处内联色值、两套各异的强调色；现统一走同一琥珀信号色、白色不透明度墨阶与固定的强调前景色。这修复了硬编码的琥珀底黑字按钮文字，并让 Now/Today/Tools 导航不再使用警示色（改为中性墨色），使琥珀仅表示「需要你」。(M5)

## [v1.0.61] - 2026-07-20

### English
- Fix the expanded notch panel overflowing the screen and pushing the Now/Today/Tools nav off the top when several sessions are open. The panel height is now clamped to the screen below the menu bar, the per-session height estimate is realistic for multi-line rows, and the session list always scrolls to fit instead of only scrolling above the visible-sessions setting.

### 中文
- 修复多个会话打开时展开的刘海面板超出屏幕、把 Now/Today/Tools 导航挤出顶部的问题。面板高度现固定在菜单栏以下的屏幕范围内，每会话高度估算更贴合多行内容，会话列表始终滚动以适配，而非仅在超过可见会话设置时才滚动。

## [v1.0.60] - 2026-07-20

### English
- Revert the notch-panel light mode shipped in 1.0.59. It rendered unreadable on the real notch (the headless render did not reproduce the problem), so the panel is pinned back to always-dark, exactly as before. The token structure and the SF Pro / SF Mono type split are kept; a light mode will only return once it can be verified on a physical notch.

### 中文
- 回退 1.0.59 中的刘海面板浅色模式。它在真实刘海上渲染后无法阅读（无窗口的离屏渲染未能复现该问题），因此面板固定回始终深色，与此前完全一致。保留令牌结构与 SF Pro / SF Mono 字体分工；浅色模式将在能于物理刘海上验证后再行加入。

## [v1.0.59] - 2026-07-20

### English
- Light mode for the notch panel: the expanded panel now follows the system appearance instead of being hardcoded black. Muted foregrounds resolve white-on-dark / near-black-on-light, and the accent colours that fail WCAG on white (bright green, amber) darken to contrast-checked variants while fills keep one hex in both modes. The collapsed island stays dark, since it abuts the physical notch (#145)
- Fix a Mac crash when reviewing Open Settings and other Tools actions from the auto-collapsing notch panel. Tools now uses stable in-panel review, rack-editor, and camera-preflight surfaces instead of SwiftUI sheets attached to the transient panel (#144)

### 中文
- 刘海面板浅色模式：展开的面板现跟随系统外观，不再硬编码为黑色。次要前景色按「深色底白字／浅色底近黑字」解析，在白底上不达 WCAG 的强调色（亮绿、琥珀）降为经过对比度校验的深色变体，而填充色在两种模式下保持同一色值。收起的小岛因紧贴物理刘海仍保持深色（#145）
- 修复从自动收起的刘海面板中审核「打开设置」及其他工具操作时可能发生的 Mac 崩溃。工具审核、模块编辑器和相机预检现改为稳定的面板内界面，不再使用附着于临时面板的 SwiftUI 弹窗（#144）

## [v1.0.58] - 2026-07-20

### English
- Attention-first notch panel: the expanded session list is ordered by who needs you, not by session identifier, and grouped into Needs you / Working / Idle bands. The routing was already computed for the collapsed pill; the panel now reads from the same source. Within the waiting band the session blocked longest sorts first, so it cannot be buried under a decision that just arrived (#142)
- The row time badge now measures time since last activity, not session age, and reads "Blocked 41m" when a session is waiting on you. Session age looked like it answered that question and did not (#142)
- The collapsed island names the blocked project (with "+N" when several wait) instead of a bare bell, so you can triage without expanding (#142)
- The approval card shows a DESTRUCTIVE risk tier and the project it lands in; a classifier that only lived in the hook shims now reaches the UI. rm -rf and reading a config file no longer render identically. Approve/deny button order is unified between the card and the session list, and the iPhone flips button emphasis by risk (#142)
- Reduce Motion is honoured at the transition itself, so every blur-fade in the companion — including the approval surface — degrades to a plain cross-fade rather than only the status dot (#142)
- The Mac panel gains a real empty state, and the question card's option numbers are now working keyboard shortcuts. Removed the orphaned IdleIndicatorBar and other verified-dead code (#142)
- iPhone Now states the answer ("Needs you" / "All clear") rather than the date, keeps attention above weather in the fallback, and shows the attention queue as rows instead of a dropdown (#142)
- Design-token system with a light-mode-aware palette and the SF Pro / SF Mono split — project names read as human content in SF Pro, commands stay monospaced in their wells (#143)

### 中文
- 注意力优先的灵动岛面板：展开的会话列表按「谁需要你」而非会话 ID 排序，并分为「需要你 / 工作中 / 空闲」三段。该排序此前只用于收起的小岛，现在面板读取同一来源。等待段内阻塞最久的会话排在最前，不会被刚到达的请求淹没（#142）
- 行内时间标签改为显示距上次活动的时间，而非会话总时长，会话等待时显示「阻塞 41m」（#142）
- 收起的灵动岛直接显示被阻塞的项目名（多个等待时附「+N」），无需展开即可分诊（#142）
- 审批卡片显示「破坏性」风险等级与目标项目；此前只存在于 hook 中的分类器现已进入 UI。rm -rf 与读取配置文件不再渲染相同。卡片与会话列表的批准/拒绝按钮顺序统一，iPhone 按风险切换按钮强调（#142）
- 「减弱动态效果」在过渡处生效，companion 的所有模糊淡入（含审批界面）降级为普通交叉淡入（#142）
- Mac 面板新增空状态，问答卡片的选项编号成为可用的键盘快捷键。移除已确认失效的 IdleIndicatorBar 等死代码（#142）
- iPhone Now 直接给出答案（「需要你」/「全部完成」）而非日期，回退顺序中注意力优先于天气，注意力队列以行而非下拉显示（#142）
- 设计令牌系统与感知浅色模式的配色，以及 SF Pro / SF Mono 分工——项目名以 SF Pro 呈现为人类内容，命令保留等宽字体（#143）

## [v1.0.30] - 2026-07-10

### English
- Add ZCode (Z.ai) integration — hooks written silently to ~/.zcode/cli/config.json with a strict event-name whitelist; restart ZCode after enabling (#245, thanks @JamesJian-tech for the plugin-structure intel)
- Add QoderWork integration — Qoder's standalone desktop assistant, Claude-format hooks in ~/.qoderwork/settings.json; restart QoderWork after enabling (#249)
- Add Traditional Chinese (zh-Hant) localization, hand-tuned Taiwan wording for all 287 strings (#251, thanks @hongyinull)
- Add Quiet Hours — mute all event sounds inside a configured window (spans midnight); a small moon on the collapsed pill explains the silence
- Add git branch / worktree indicator on session cards (⎇ branch, ⧉ for linked worktrees) — made for parallel-worktree agent workflows
- Add Glance completion mode — on completion, light a green dot on the collapsed island instead of expanding; clears the moment you expand (three-way setting: expand / glance / off)
- Add Claude token-usage footer under the session list — 5-hour and today windows aggregated from local transcripts (no API calls) with a 12-hour activity sparkline and cache-detail tooltip
- Add Terax terminal click-to-jump (#253, thanks @wangmian0)
- Complete cursor-cli / qoder-cli routing: dedicated process matching, real project names for Cursor sessions, grouped under their IDEs in the CLI tab; remote cwd filters honor workspace_roots and never drop lifecycle/approval hooks of tracked sessions (#248/#240/#255, thanks @zephyr110)
- Every CLI row in settings now has an icon — pixel-mascot icons for Kiro & OpenClaw, deterministic monogram tiles for the rest (including custom CLIs)
- Fix Codex "Always Allow" writing broken Starlark rules for multiline commands — newlines are now escaped, existing broken files need the bad rule removed once (#250/#252, thanks @hexsean)
- Fix blocking AskUserQuestion cards staying collapsed under Smart Suppress — OMP (and every provider) waits on the island, so the card now always opens (#256, thanks @haixing23)
- Fix legitimate dot-named repos (.dotfiles, .config) displaying their parent folder's name
- Fix remote SSH sessions showing the local machine's git branch when directory layouts match
- Fix zellij-inside-Terax losing precise pane focus on click-to-jump
- Fix the ZCode installer flipping a user's explicit hooks master switch back on
- Usage scanning is incremental (per-file byte offsets) — day-long multi-MB transcripts are read once, not on every panel expansion
- Claude sessions running in $HOME keep model detection; Cursor project-path decoding moved off the render path

### 中文
- 新增 ZCode（智谱 Z.ai）集成——hooks 静默写入 ~/.zcode/cli/config.json，严格事件名白名单防御；勾选后需重启 ZCode 生效（#245，感谢 @JamesJian-tech 提供插件结构情报）
- 新增 QoderWork 集成——Qoder 生态的独立桌面助手，Claude 格式 hooks 写入 ~/.qoderwork/settings.json；勾选后需重启 QoderWork（#249）
- 新增繁体中文本地化，287 条文案逐条采用台湾用语校对（#251，感谢 @hongyinull）
- 新增「静默时段」——设定时间段内静音全部音效（支持跨午夜）；静默期间收起的岛上会显示小月亮说明为何无声
- 会话卡片新增 Git 分支 / worktree 指示器（⎇ 分支名，linked worktree 附 ⧉ 标记）——为并行 worktree 跑多 agent 的工作流而生
- 新增 Glance 完成模式——任务完成时不弹面板，只在收起的岛上亮起绿点，展开即熄灭（完成提醒三选一：展开 / 绿点 / 无动作）
- 会话列表底部新增 Claude 用量统计——本地 transcript 聚合 5 小时窗口与今日用量（零网络请求），附 12 小时活动迷你柱状图与缓存明细悬浮提示
- 新增 Terax 终端点击跳转（#253，感谢 @wangmian0）
- 补全 cursor-cli / qoder-cli 路由：独立进程匹配、Cursor 会话显示真实项目名、CLI 分组归入所属 IDE；远程目录过滤识别 workspace_roots，且不再误拦已跟踪会话的生命周期/审批 hook（#248/#240/#255，感谢 @zephyr110）
- 设置里每个 CLI 行都有图标了——Kiro 与 OpenClaw 使用像素吉祥物图标，其余（含自定义 CLI）使用稳定配色的首字母图标
- 修复 Codex「始终允许」对多行命令写出损坏的 Starlark 规则——换行符现已转义，已损坏的规则文件需手动删除坏段一次（#250/#252，感谢 @hexsean）
- 修复智能抑制下阻塞式 AskUserQuestion 卡片不展开——OMP（及所有 provider）都在等岛上作答，卡片现在始终弹出（#256，感谢 @haixing23）
- 修复合法的 dot 开头仓库（.dotfiles、.config）显示成父目录名的问题
- 修复远程 SSH 会话在两端目录结构相同时显示本机 Git 分支的问题
- 修复 Terax 内运行 zellij 时点击跳转丢失精确 pane 聚焦的问题
- 修复 ZCode 安装器会把用户显式关闭的 hooks 总开关重新打开的问题
- 用量扫描改为增量式（按文件记录字节偏移）——日级长会话的大 transcript 只读一次，不再每次展开面板重读
- 在 $HOME 下直接运行的 Claude 会话保留模型识别；Cursor 项目路径解码移出渲染路径

## [v1.0.29] - 2026-07-06

### English
- Add OpenClaw integration — TypeScript plugin pack auto-installed and registered in ~/.openclaw/openclaw.json, with the new Molty space-lobster mascot 🦞 (#235)
- Add Claude Code Desktop support — local Code-tab sessions are recognized, tagged, and click-to-jump activates the right desktop window; terminal CLI sessions keep jumping to their terminal (#211)
- Add per-host working-directory filter for remote SSH hosts — on shared accounts, only sessions under your own project paths are shown (#240)
- Bridge the OMP / pi `ask` tool into the island's question UI: answer on the Mac (or iPhone/Watch) and the answer flows back to the agent; skipping falls through to the terminal dialog (#244)
- Auto-dodge third-party menu bar icons (e.g. Bartender) on external screens — the island slides into the nearest clear gap; a manually dragged position always wins (#219)
- Refine notch hover: a light "acknowledged" micro-expansion first, full panel only after dwelling 0.5s — quick mouse pass-throughs no longer pop the panel; width slider now steps by 1% (#208, thanks @Lucker-QY)
- Motion-polish across all 18 mascots: natural irregular blinks, asymmetric breathing, dream twitches, humanized typing with "reading the output" pauses, and de-synced float rhythms per character (#15)
- Add a Kiro pixel-ghost mascot (previously fell back to Clawd) and complete the settings mascot gallery (Molty, Kiro, Google Antigravity)
- Show enabled approve/deny shortcut bindings as badges on the approval card buttons
- Document keyboard shortcuts in the README (#31)
- Cut idle CPU by ~38% (8.5% → 5.3%): every mascot's frame loop now pauses while the panel is hidden or the Mac sleeps (previously only Clawd's did), idle scenes render at 8fps, and wake no longer replays missed frames (#225 follow-up)
- Fix launchd-managed daemons (e.g. the Hermes gateway) being SIGTERM'd in a restart loop by orphan cleanup — only true terminal orphans are ever terminated (#243)
- Fix the Watch companion crash-on-launch loop: tolerant payload decoding across app versions plus self-healing of poisoned persisted state (#246; ships with the next App Store companion build)
- Fix remote SSH install wiping user-authored hooks on every connect — managed entries now merge after yours, idempotently (#242)
- Fix cursor-cli / qoder-cli sessions showing the wrong mascot (#248, thanks @zephyr110)
- Fix Bluetooth permission being requested at launch for users who never enabled the iPhone companion
- Plus everything landed since v1.0.28: native iPad companion layout (#238), German localization (#234), Google Antigravity approval details (#233), host-GUI-client jump (#237), pi/omp mascot setting (#228)

### 中文
- 新增 OpenClaw 集成——自动安装 TypeScript 插件包并注册到 ~/.openclaw/openclaw.json，附全新太空龙虾吉祥物 Molty 🦞（#235）
- 新增 Claude Code 桌面版支持——本地 Code 标签会话可识别、可跳转到对应窗口；终端 CLI 会话仍跳回终端（#211）
- 远程 SSH 主机新增「工作目录过滤」——共享账号下只显示你自己项目路径下的会话（#240）
- OMP / pi 的 `ask` 提问接入灵动岛问答 UI：在 Mac（或 iPhone/手表）上作答后自动回填给 agent，跳过则回落到终端选择框（#244）
- 外接显示器自动避开第三方菜单栏图标（如 Bartender）——灵动岛平移到最近空档，手动拖动的位置始终优先（#219）
- 优化 hover 手感：先给一个轻量"已感知"微扩张，停留 0.5 秒才完整展开——快速划过不再误弹面板；宽度滑块步长改为 1%（#208，感谢 @Lucker-QY）
- 全部 18 个吉祥物动画质感升级：不规则自然眨眼、非对称呼吸、睡梦小动作、带"读输出"停顿的拟人打字、各角色漂浮节奏去同步（#15）
- 新增 Kiro 像素幽灵吉祥物（此前沿用 Clawd 造型），设置图鉴补全（Molty、Kiro、Google Antigravity）
- 审批卡片按钮上直接显示已启用的批准/拒绝快捷键
- README 补充键盘快捷键文档（#31）
- 空闲 CPU 降低约 38%（8.5% → 5.3%）：所有吉祥物的帧循环在面板隐藏/睡眠时暂停（此前只有 Clawd 生效），空闲动画降至 8fps，唤醒不再回放积压帧（#225 后续）
- 修复 launchd 托管守护进程（如 Hermes gateway）被孤儿清理反复 SIGTERM 导致重启风暴——现在只终止真正的终端孤儿进程（#243）
- 修复手表端启动即崩溃循环：跨版本容错解码 + 坏数据自愈（#246；随下次 App Store companion 版本生效）
- 修复远程 SSH 每次连接都覆盖用户自定义 hooks——托管条目现在合并追加且幂等（#242）
- 修复 cursor-cli / qoder-cli 会话显示错误吉祥物（#248，感谢 @zephyr110）
- 修复从未启用 iPhone 配件的用户启动时被请求蓝牙权限的问题
- 以及 v1.0.28 以来的全部改进：iPad 原生 companion 布局（#238）、德语本地化（#234）、Google Antigravity 审批详情（#233）、宿主 GUI 客户端跳转（#237）、pi/omp 吉祥物设置项（#228）

## [v1.0.28] - 2026-06-15

### English
- Add Code Island Buddy companion app for iPhone & Apple Watch — Live Activity / Dynamic Island / Lock Screen / StandBy, with opt-in Mac broadcasting (off by default) (#218)
- Add support for Pi / Oh My Pi sessions with a dedicated mascot (#222)
- Add support for Google Antigravity (Gemini-based) hooks as a new agent source (#215)
- Detect Superset terminal sessions (window-level focus; Superset exposes no per-tab focus API) (#213)
- Surface Codex Desktop plan-mode user-input questions as interactive prompts (#209)
- Fix Hermes hooks never firing at runtime — install to ~/.hermes/config.yaml (where Hermes actually reads) instead of settings.json (#226)
- Fix "Always allow" not sticking for MCP tools, which kept re-prompting the same approval (#224)
- Fix Claude Code shown with the Cursor icon when run inside Cursor's integrated terminal (#220)
- Fix the approval panel not auto-dismissing after you approve a request in the terminal (#216)
- Fix the global shortcut silently breaking after switching apps — now uses a Carbon hotkey that needs no Accessibility permission (#217)
- Fix CPU spiking to 100% after sleep/wake by pausing the idle mascot animation while hidden or asleep (#225)
- Fix remote SSH reconnection failing (ssh exited 255) by clearing the stale forwarding socket first (#206)
- Fix Warp tab activation across multiple windows and tabs (#205)

### 中文
- 新增 Code Island Buddy iPhone / Apple Watch 伴侣 App——Live Activity / 灵动岛 / 锁屏 / 待机显示，Mac 端可选开启镜像广播（默认关闭）(#218)
- 新增 Pi / Oh My Pi 会话支持，配专属吉祥物 (#222)
- 新增 Google Antigravity（基于 Gemini）hooks 支持，作为独立 agent 来源 (#215)
- 识别 Superset 终端会话（窗口级聚焦；Superset 未提供单 tab 聚焦接口）(#213)
- 把 Codex 桌面版 plan 模式的用户询问渲染成可交互弹窗 (#209)
- 修复 Hermes hooks 运行时不触发——改为写入 Hermes 真正读取的 ~/.hermes/config.yaml 而非 settings.json (#226)
- 修复 MCP 工具"始终允许"不生效、同一审批反复弹出 (#224)
- 修复在 Cursor 集成终端里运行 Claude Code 被错误显示为 Cursor 图标 (#220)
- 修复在终端里批准后审批面板不自动消失 (#216)
- 修复全局快捷键切换应用后静默失效——改用免辅助功能权限的 Carbon 热键 (#217)
- 修复休眠唤醒后 CPU 飙到 100%——隐藏或休眠时暂停空闲吉祥物动画 (#225)
- 修复 remote SSH 重连失败（ssh exited 255）——连接前先清理残留转发 socket (#206)
- 修复 Warp 跨多窗口 / 标签页的标签激活 (#205)

## [v1.0.27] - 2026-05-30

### English
- Fix Cursor / Trae / Qoder / Factory click-to-jump raising the most-recently-used window instead of the one running the clicked session — now matches the workspace window by project folder (#199)
- Install custom CLI hooks on SSH remote hosts too (claude / nested hook formats) — previously only the built-in CLIs were configured remotely (#192)

### 中文
- 修复 Cursor / Trae / Qoder / Factory 点击灵动岛跳到"最近用过的窗口"而不是正在对话的那个——现在按项目目录匹配对应 workspace 窗口 (#199)
- SSH 远程主机也会安装自定义 CLI 的 hooks（claude / nested 格式）——此前远程只配置内置 CLI (#192)

## [v1.0.26] - 2026-05-30

### English
- Add pi / Oh My Pi (OMP) coding agent integration — auto-install the bundled extension into `~/.pi/agent/extensions` and `~/.omp/agent/extensions` (#197)
- Isolate the remote SSH socket per user (`/tmp/codeisland-<uid>.sock`) so multiple OS users on a shared host no longer collide or steal each other's events (#193)
- Fix the SSH tunnel being misreported as `ssh exited (0)` when ControlMaster multiplexing makes `ssh -N` hand off the forward and exit immediately — force a dedicated connection (#190)
- Fix iTerm2 click-to-jump landing on the wrong window when the target session is fullscreen or on another Space — select the owning window so macOS switches to its Space (#198)

### 中文
- 新增 pi / Oh My Pi (OMP) 编码 agent 集成——自动把扩展装到 `~/.pi/agent/extensions` 和 `~/.omp/agent/extensions` (#197)
- 远程 SSH socket 改为按用户隔离（`/tmp/codeisland-<uid>.sock`），多用户共享主机不再互相串话或抢占事件 (#193)
- 修复 SSH 隧道在 ControlMaster 多路复用下 `ssh -N` 立即退出、被误报为 `ssh exited (0)` 的问题——强制独占连接 (#190)
- 修复 iTerm2 全屏 / 跨 Space 时点击会话跳到错误窗口——命中后选中目标窗口以触发 Space 切换 (#198)

## [v1.0.23] - 2026-04-25

### English
- Add ESP32 BLE companion device — port mascot animations to a real desk pet (#131)
- Make auto-approve tools configurable in Settings; default no longer auto-approves `ExitPlanMode` so plan-mode exit prompts an approval dialog (#126)
- Fix TraeCli YAML hook injection corruption on mixed indentation; preserve user comments via surgical merge (#122)
- Respect `$CODEX_HOME` in codex auto-config (local + ssh) (#129)
- Add WorkBuddy bundle ID for one-click jump from CodeIsland (#130)
- Fix remote SSH sessions being force-flipped to idle on local timeout (#121)
- Fix Ghostty click-to-jump no-op via System Events Accessibility fallback (#84)
- Fix Terminal.app: minimized window not raising + multi-tab clicks all jumping to same tab (root cause: AppleScript `tty` variable shadowed Terminal.app's tab `tty` property) (#124)
- Add configurable cwd-substring blocklist for hook events — filter out background plugins like claude-mem (#125)
- Add webhook forwarding for hook events to external HTTP endpoints — pipe agent activity into DingTalk / Lark / Slack receivers (#115)
- Add minimum Kiro CLI support — install hooks into `~/.kiro/agents/codeisland.json` (launch with `kiro --agent codeisland`) (#127)

### 中文
- 新增 ESP32 BLE 桌面伴侣设备——把吉祥物动画移植到实体小屏 (#131)
- "自动批准工具"可在设置里逐项配置，默认不再自动批准 `ExitPlanMode`，退出 plan 模式会弹审批 (#126)
- 修复 TraeCli YAML 在混合缩进下 hook 注入损坏的问题，并通过 surgical 合并保留用户注释 (#122)
- codex 自动配置遵循 `$CODEX_HOME`（本地和 ssh 都生效）(#129)
- 新增 WorkBuddy 一键跳转 (#130)
- 修复远程 SSH 任务被本地 timeout 误判完成 (#121)
- 修复 Ghostty 点击灵动岛无反应——加 System Events Accessibility 兜底 (#84)
- 修复 Terminal.app 最小化无法打开 + 多终端点哪个都跳同一 tab（真 root cause：AppleScript 局部变量 `tty` 跟 tab property `tty` 同名导致 Strategy 1 静默失效）(#124)
- 设置里新增"忽略指定路径的 Hook"——按子串过滤 claude-mem 等后台插件触发的事件 (#125)
- 设置里新增"Webhook 转发"——hook 事件以 JSON POST 到外部端点，方便对接钉钉/飞书/Slack (#115)
- 新增 Kiro CLI 最小可用支持——hooks 写到 `~/.kiro/agents/codeisland.json`，启动用 `kiro --agent codeisland` (#127)

## [v1.0.15] - 2026-04-07

### English
- Fix apps built with libghostty (e.g. Supacode) being misidentified as Ghostty (#27)
- Fix DMG release missing app icon by pre-building icns with all sizes
- Fix settings window opaque sidebar in .app bundle (add toolbar for translucent effect)
- Build universal binary (arm64 + x86_64) for DMG releases
- Use root Info.plist for DMG builds to include all required fields

### 中文
- 修复基于 libghostty 构建的应用（如 Supacode）被误识别为 Ghostty 的问题 (#27)
- 修复 DMG 发行版缺少应用图标的问题（预置完整尺寸 icns）
- 修复 .app 版本设置窗口侧边栏不透明的问题（添加 toolbar 实现毛玻璃效果）
- DMG 发行版改为 universal binary（arm64 + x86_64）
- DMG 构建使用完整 Info.plist，包含所有必要字段

## [v1.0.8] - 2026-04-07

### English
- Add GitHub Copilot CLI support as the 9th AI tool
- Allow horizontal drag of panel along the menu bar (Settings → General)
- Horizontal-only drag with no vertical jitter, 5px threshold to prevent accidental drag
- Reset panel to center when drag toggle is turned off
- Update mascot gif backgrounds to white for better README readability

### 中文
- 新增 GitHub Copilot CLI 支持（第 9 个 AI 工具）
- 允许沿菜单栏水平拖动面板（设置 → 通用）
- 仅水平拖动无垂直抖动，5px 阈值防误触
- 关闭拖动开关时面板自动归位居中
- 更新吉祥物 gif 为白色背景，提升 README 可读性

## [v1.0.7] - 2026-04-07

### English
- Add Homebrew Cask distribution support (`brew install --cask codeisland`)
- Add in-app auto-update: download, install and relaunch without leaving the app
- Add "Check for Updates" button in Settings → About
- Detect Homebrew installs and suggest `brew upgrade` instead of auto-update
- Add GitHub Actions CI for automated release builds
- Auto-approve safe internal tools (TaskCreate, TaskUpdate, etc.) to prevent hook blocking
- Fix compact bar showing project name and tool status from different sessions
- Fix restored sessions incorrectly shown as active when CLI process is idle
- Hide project name in tool status area when no tool is running

### 中文
- 新增 Homebrew Cask 分发支持（`brew install --cask codeisland`）
- 新增 App 内自动更新：下载、安装并重启，无需离开应用
- 设置 → 关于页面新增"检查更新"按钮
- 检测 Homebrew 安装并建议使用 `brew upgrade` 更新
- 新增 GitHub Actions CI 自动构建发布
- 自动放行安全内部工具（TaskCreate、TaskUpdate 等），防止 hook 阻塞
- 修复紧凑栏项目名和工具状态来自不同会话的问题
- 修复恢复的会话在 CLI 空闲时仍显示为活跃状态
- 修复无工具运行时仍显示项目名的问题

## [v1.0.6] - 2026-04-07

### English
- Show Claude and Codex session titles in the panel
- New idle state UI with hover interaction on the notch
- Add shimmer animation when AI is thinking
- Extend animation speed slider to 0% to freeze mascot animations
- Add Codex PreToolUse/PostToolUse hook events for tool status display
- Auto-configure codex_hooks=true in ~/.codex/config.toml
- Add IDE terminal detection for smarter notification suppress
- Add cmux terminal support
- Fix user messages rendered as markdown instead of plain text
- Add processing timeout fallback: reset to idle after 60s with no tool
- Fix idle mascot not aligned with the most recently active CLI

### 中文
- Claude 和 Codex 会话现在在面板中显示标题
- 新增空闲状态 UI，支持刘海区域悬停交互
- AI 思考时显示闪烁动画效果
- 动画速度滑块可调至 0% 以冻结吉祥物动画
- 新增 Codex PreToolUse/PostToolUse hook 事件，显示工具状态
- 自动配置 ~/.codex/config.toml 中的 codex_hooks=true
- 新增 IDE 终端检测，更智能的通知抑制
- 新增 cmux 终端支持
- 修复用户消息被渲染为 markdown 而非纯文本
- 增加处理超时回退：60 秒无工具调用后重置为空闲
- 修复空闲吉祥物未对齐最近活跃的 CLI

## [v1.0.5] - 2026-04-06

### English
- Smart suppress: only suppress notifications when looking at the specific session tab
- Support iTerm2, Ghostty, Terminal.app, WezTerm, kitty, and tmux tab detection
- Fix Codex Desktop not discovered due to case-sensitive path matching
- Fix npm/Homebrew Codex not discovered
- Fix OpenCode "Always allow" not persisting
- Fix model badge not showing
- Fix session short ID collision
- Fix bridge binary replacement drop window
- Fix hook script not updating for existing users
- Fix concurrent sessions in same repo incorrectly merged

### 中文
- 智能抑制：只有当你正在看该会话的标签页时才抑制通知
- 支持 iTerm2、Ghostty、Terminal.app、WezTerm、kitty、tmux 标签页检测
- 修复 Codex Desktop 因路径大小写不匹配无法发现
- 修复 npm/Homebrew 安装的 Codex 无法发现
- 修复 OpenCode "始终允许"没有持久化
- 修复 model 标签不显示
- 修复会话短 ID 冲突
- 修复 bridge 二进制替换存在时间窗口
- 修复已安装用户的 hook 脚本不会更新
- 修复同 repo 并发会话被错误合并

## [v1.0.4] - 2026-04-06

### English
- Fix OpenCode socket deadlock
- Fix stuck session states
- Fix AskUserQuestion parsing
- Fix double-click on outside click
- Performance: cache status/primarySource/activeSessionCount, reduce observation polling
- UI: smooth hover animations, panel collapse delay, entrance transitions

### 中文
- 修复 OpenCode socket 死锁
- 修复会话状态卡住
- 修复 AskUserQuestion 解析
- 修复外部点击双击问题
- 性能优化：缓存状态属性，减少轮询频率
- UI：平滑悬停动画，面板折叠延迟，入场过渡动画

## [v1.0.3] - 2026-04-06

### English
- Update checker: auto-check on launch + manual check
- Per-CLI hook toggles
- Boot sound: 8-bit startup jingle
- Behavior animations: animated previews for each setting
- Fix release build crash, OpenCode plugin install, hook fallback socket path

### 中文
- 更新检查器：启动时自动检查 + 手动检查
- 按 CLI 独立开关 hooks
- 启动音效：8-bit 开机音
- 行为动画：每个设置项的动画预览
- 修复发布版本崩溃、OpenCode 插件安装、hook socket 路径回退

## [v1.0.1] - 2026-04-06

### English
- Fix release build crash on Mascots/Hooks pages
- Fix OpenCode plugin installation in release builds
- Fix hook script fallback socket path
- Remove redundant page titles in settings

### 中文
- 修复吉祥物和 Hooks 设置页崩溃
- 修复发布版本中 OpenCode 插件安装
- 修复 hook 脚本 socket 路径回退
- 移除设置中多余的页面标题

## [v1.0.0] - 2026-04-06

### English
- Initial release

### 中文
- 初始发布
