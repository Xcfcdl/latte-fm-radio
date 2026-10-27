# SOF 音频 + BCM4356 FM（小米平板 2 / latte）

这套文件让 Cherry Trail 版小米平板 2 在主线内核上具备：

- 扬声器与有线耳机自动切换（RT5659 JD3 插孔检测）
- 两路 TFA9890 功放正常出声
- 以有线耳机线当天线收听 FM，声音可走扬声器、有线耳机、蓝牙音箱或蓝牙耳机
- 图形收音机（调频 / 搜台 / 历史 / 实时频谱）和命令行脚本

内核侧的机器驱动、codec 插孔 quirk 和 ACPI 匹配放在独立的内核 PR 里（三条 ASoC 补丁）；本仓库是配套的拓扑、内核配置片段和用户态 FM 工具。

相关链接：

- 内核补丁（ASoC: SOF: add audio and FM support for the Xiaomi Mi Pad 2）
  <https://github.com/xiaomi-latte-dev/linux_latte/pull/7>
- SOF 固件 `sof-cht.ri`（sof-bin v2.2，随发行版提供，不在本仓库）
  <https://github.com/thesofproject/sof-bin>

## 状态与边界（封档）

这是一个**机型级**项目：给 Cherry Trail 版小米平板 2 补上主线内核上的 SOF 音频与 BCM4356 FM。
它不是 SOF 平台的新支持，也不打算复活 Bay Trail / Cherry Trail。

平台状态（有来源）：

- SOF 已把 BYT/CHT 转入维护模式，**v2.2 是最后一个带固件支持的版本**，之后不再做固件修复
  （Intel 在 [issue #3868](https://github.com/thesofproject/sof/issues/3868) 的收尾说明）
- 2023-01-27 提交 `89f7aa0ab` *platform: remove support for Baytrail and Cherrytrail*
  把平台从 `main` 移除；历史支持在 `stable-v2.2` 分支
- 固件只从 sof-bin `v2.2.x` 取：`sof-cht.ri`，md5 `95573d5a1ccf71c19fd7181b5653bc57`；本仓库不分发固件
- 内核侧 `sound/soc/sof/intel/{byt,atom}.c` 仍在，但 2024–2025 只有 tree-wide 清理，没有新功能

已知风险：

- SOF 在 BYT/CHT 上有过"播放几分钟后持续蜂鸣"的历史报告（[#3868](https://github.com/thesofproject/sof/issues/3868)，
  5.11–5.18 + SOF 2.1.x + rt5640）。本机（6.14 + v2.2 + 自写拓扑）连续听音未复现；
  遇到长鸣先停 App 判断是否 loopback 叠加（本项目的长鸣就是它，已修复），再重启音频服务
- 冻结平台的固件问题不会再有官方修复，接受这一点再使用

为什么曾经不用 SST（**2026-10-26 已作废，改走 SST**）：

- 当时的理由：SST 的 `cht_bsw_rt5659` 机器驱动只有 FE、SSP2-Codec 和 `dummy → TFA`
  两条链路，没有 SSP1 采集，BCM4356 的 FM 音频进不来
- 这个前提是可以修的：我们往 `sst-atom-controls` / `sst-mfld-platform-pcm` /
  `cht_bsw_rt5659` 上加了 SSP1 采集链路和两路 `rt5659-aif2 → TFA9890` c2c，
  FM 在 SST 上已经跑通，见 [docs/INSTALL-7.2-FM.md](docs/INSTALL-7.2-FM.md)
- 现在的架构（2026-10-27）走 SST：驱动只描述能力，UCM 负责路由，
  `fm-tuner` 服务独占芯片并发布 `fm_radio` 源，图形前端只切 profile / 选输出

SST 路线（当前）：

```text
BCM4356 FM ──SSP1(I2S, 16 bit slot)──> SST (ROM 固件) ──> PCM2 capture (hw:0,6)
                                                            │
                              fm-tuner 服务 ── pw-cli create-node ──> fm_radio 源
                                                            │
UI ── pw-record --target fm_radio ── aplay ──> RT5659 ─┬─ HPO L/R ── 3.5 mm（兼 FM 天线）
                                                      └─ AIF2 ── 2 × TFA9890 ── 扬声器
```

- 芯片上电、调谐、RSSI/SNR 由 `fm-tuner` 通过 HCI VSC 完成；`hci_fm` 仍是底层命令工具
- 插孔只上报，不做策略：耳机长期插着当天线，扬声器/耳机由 UCM profile 决定
- 下面的 SOF 章节是 2026-10-26 之前的方案，保留作历史对照

关于"驱动是不是 SST 复制品"：

- ASoC machine driver 本身就是板级接线（DAI link、DAPM、jack、功放），与 SST 板驱动共享硬件描述是必然的
- 本驱动新增的是 SSP1 采集 BE、两路 `rt5659-aif2 → TFA9890` c2c、每次 `hw_params` 重写 PLL、`idle_bias_off`
- 运行时 DSP 是 SOF：`snd_sof*` 已加载、拓扑 ABI 3:22:1、`ssp0..5-port` DAI 来自
  `sound/soc/sof/intel/atom.c`、`amixer` 有拓扑的 PGA 控件；SST 的 `sst-mfld-platform` 组件并未注册

开发状态：**封档**。只接受能复现的 bug 修复，不新增功能。

## 链路

```text
BCM4356 FM ──SSP1(I2S 1.92 MHz, 2×20 bit, 16 bit)──┐
                                                    ├─ SOF DSP (sof-cht.ri v2.2)
RT5659 codec ──SSP2(I2S 1.92 MHz, 2×20 bit, 16 bit)─┘
   ├─ HPO L/R ── 3.5 mm 耳机（同时是 FM 天线）
   └─ AIF2 ───── 2 × TFA9890 ── 扬声器
```

- 播放：PCM0 → SSP2 → RT5659 → 耳机 / 扬声器
- 采集：SSP1 ← BCM4356 → PCM0 capture
- FM 的上电、调谐、RSSI/SNR 读取由用户态 `hci_fm` 通过 HCI VSC（opcode `0xFC15`）完成，不使用 V4L2
- 声卡固定使用 `pro-audio` profile，扬声器/耳机切换只改 RT5659 mixer

## 目录

```text
latte-fm-radio/
├── README.md                 本文件
├── LICENSE                   GPL-2.0-only
├── kernel-config.fragment    内核配置片段
├── sof/
│   ├── sof-cht-rt5659.m4     拓扑源码
│   └── sof-cht-rt5659.tplg   已构建拓扑（md5 d8d68f860fda619bb63ae68c01804d1e）
├── tools/
│   ├── hci_fm.c              BCM FM HCI VSC 工具（GPL-2.0，作者 arttttt）
│   ├── fm-radio              GTK3 收音机前端（只切 profile / 选输出）
│   ├── fm-tuner              系统层调谐器：独占芯片 + 发布 fm_radio 源
│   ├── fm-tuner.service      上面那个服务的 user unit
│   ├── fm-sst               诊断 / 扫频，tuner 的客户端
│   ├── fm-listen.sh          命令行收听 / 扫描 / 停止（SOF 时期）
│   ├── latte-jack-switch     插孔自动切换守护脚本（SOF 时期）
│   ├── latte-jack-switch.service
│   ├── fm-radio.desktop
│   └── install.sh
├── docs/
│   └── INSTALL-7.2-FM.md     7.2 + FM-on-SST 的 bring-up 与实测记录
├── Intel/ codecs/ conf.d/    UCM 覆盖（SST 路线的当前路由，见下）
```

`Intel/`、`codecs/`、`conf.d/` 是 UCM 覆盖文件：SST 路线靠它们做扬声器/耳机/麦克风路由
（`Speaker Amp Switch` 决定功放供电，插孔只上报不决定策略）。装到
`/usr/share/alsa/ucm2/` 对应位置后按 `HiFi (...)` profile 生效。

## 前置条件

### 内核

需要包含本仓库的三条 ASoC 补丁：

1. `ASoC: SOF: add machine driver for Xiaomi Mi Pad 2 (CHT + RT5659)`
2. `ASoC: rt5659: add jack detection quirk for Xiaomi Mi Pad 2`
3. `ASoC: Intel: cht: use the Mi Pad 2 SOF machine driver via DMI`

配置片段：

```bash
scripts/kconfig/merge_config.sh .config fix_file/audio/kernel-config.fragment
make olddefconfig
```

构建并安装模块后，`aplay -l` 应出现 `sof-cht-rt5659` 声卡，`dmesg | grep -i sof` 应看到 `sof_cht_rt5659` 和固件 ABI 日志。

### 固件

- `sof-cht.ri` **必须用 sof-bin v2.2**（v2.3 起已移除 Cherry Trail）：
  `/lib/firmware/intel/sof/sof-cht.ri`
- 已实测文件 md5：`95573d5a1ccf71c19fd7181b5653bc57`
- 拓扑安装到 `/lib/firmware/intel/sof-tplg/sof-cht-rt5659.tplg`

重新生成拓扑（可选）：

```bash
T=<sof 源码>/tools/topology/topology1
m4 -I "$T/m4" -I "$T/sof" -I "$T/common" \
   -I "$T/platform/common" -I "$T/platform/intel" -I "$T" \
   -DPLATFORM=cht fix_file/audio/sof/sof-cht-rt5659.m4 > sof-cht-rt5659.conf
alsatplg -c sof-cht-rt5659.conf -o sof-cht-rt5659.tplg
```

随包的 `.tplg` 由 alsatplg 1.2.14 构建；较老的 alsatplg 会生成字节不同但等价的文件。

### 用户态依赖

Arch：`alsa-utils pipewire pipewire-pulse wireplumber python-gobject gtk3 bluez bluez-utils`
Debian/Ubuntu：`alsa-utils pipewire pipewire-pulse wireplumber python3-gi gir1.2-gtk-3.0 bluez`

## 安装

```bash
sudo fix_file/audio/tools/install.sh
systemctl --user enable --now latte-jack-switch.service
```

`install.sh` 会安装工具、桌面项、用户服务和拓扑，并编译 `hci_fm`。固件和内核需要按上面的步骤单独准备。

### sudo 权限

工具以普通用户运行，通过 `sudo -n` 调用 `hci_fm` 和 `amixer`：

```sudoers
Cmnd_Alias LATTE_FM = /usr/local/bin/hci_fm, /usr/bin/amixer
<用户名> ALL=(root) NOPASSWD: LATTE_FM
```

`fm-listen.sh --rebind` 还会写 sysfs；若需要无密码使用，额外授权 `/usr/bin/tee`，或直接以 root 执行该选项。

## 使用

### 图形界面

启动「FM 收音机」（`/usr/local/bin/fm-radio`）：

- 拖动滑杆或 `± 0.1` 调频
- 「◀ 向下搜台 / 向上搜台 ▶」按 0.1 MHz 步进，命中即停并记录
- 「搜台」做全频段扫描，结果按频率升序排列，收藏的台固定在顶部
- 扫描和搜频段时会自动把解调音频送到当前输出；未在收听时会临时打开回环，扫描过程中可连续听到当前频点，随时可以按「停止」取消
- 标题栏右侧显示天线状态：已插入时显示“天线：耳机已插入”，未插入时显示“⚠ 请插入耳机当天线”
- 每行左侧的 `★` / `☆` 用于收藏并置顶；收藏跨扫描保留，未搜到的收藏会标记“本次未搜到”
- 扫描结果写入 `~/.config/fm-radio/stations.json`（含 `favorite` 标记）
- 右侧输出选择器列出扬声器、有线耳机和 A2DP 音乐节点（`bluez_output.<MAC>.1`）。判断某个节点是不是免提，看的是 `pactl list sinks` 里的 `api.bluez5.profile`：本板子上 SCO 节点复用了 A2DP 的节点名（只改成 1ch/16000Hz），靠名字里的 `head-unit` 是认不出来的。同一只双 Profile 耳机在切换 Profile 的瞬间会同时出现 A2DP 和免提（HFP/SCO，单声道）两个 sink，收音机只需要音乐 Profile，所以免提节点默认不列出；若某设备只剩免提节点，才会带“（免提·单声道）”后缀显示出来
- 切换输出时同时把系统默认 sink 切到同一个设备（`pactl set-default-sink`）。GNOME 音量条和音量键作用在默认 sink 上；两者不一致时会出现“系统音量拉到 100 也没变响”——声音还走原来那个 sink，滑杆调的是另一台设备
- 音量是全局的：默认 20%，切换输出时沿用当前音量，不按设备分别记忆。App 调的就是输出 sink 的音量，与系统音量同一个值；每 1 s 读一次 sink 音量（播放中或暂停时都读，否则暂停期间在混音器里调好的值会在下一次播放时被存下来的旧值覆盖），用系统音量键或 GNOME 音量条改了就跟着变（需连续两次读到同一新值，避免把切换过程中 WirePlumber 的瞬时回填当成用户操作；拖动滑杆和切输出时不跟随）
- 历史记录持久化在 `~/.config/fm-radio/history.json`
- 右下的「录音」卡片可以录下当前频点：填好时长（1–240 分钟）按「● 立即录音」，或者填 `HH:MM` 按「定时录音」（过了当天时间点会自动顺延到第二天），排好之后按「取消定时」撤掉。录音直接读采集节点，和输出路由无关——静音、走蓝牙、甚至没在收听时都能录；定时录音不会自己出声。录完的文件列在卡片里，`▶` 回放、`✕` 删除（会二次确认）。录音中不能调台/搜台，停止收听时芯片会保持供电让录音继续

录音文件：`~/Music/fm-radio/FM_<日期>_<时间>_<频率>MHz_<分钟>min.wav`（48 kHz / 单声道 / 16 bit，约 5.5 MB/分钟）。实际时长会比设定少约 2 秒（采集流建立耗时）。按 WAV 存是为了不依赖额外编码器；需要压缩可以录完自己转 opus/flac。

### 命令行

```bash
fm-listen.sh 88.8              # 开始收听（默认扬声器，音量 20%）
VOL=20 OUT=headphones fm-listen.sh 88.8
fm-listen.sh --scan            # 扫描频段并打印 RSSI
fm-listen.sh --off             # 停止并关闭 FM
fm-listen.sh --rebind          # codec 时钟过期时的兜底
```

### 输出切换

FM 采集节点是 `alsa_input.platform-sof_cht_rt5659.pro-input-0`，本地播放节点是 `alsa_output.platform-sof_cht_rt5659.pro-output-0`。蓝牙输出使用 `bluez_output.*`，切换时把 loopback 迁到目标 sink。**无论输出选哪个，都必须插着有线耳机当天线**，否则收不到台。

- 切换输出时先静音再改路由，避免切换瞬间的爆音
- 选蓝牙时会把本地喇叭/耳机输出（numid 6/162/163/164/165）关掉，防止本地功放继续出声；切回本地时再打开
- App 每 3 秒检查 loopback 是否还在、是否挂在当前 sink 上；被外部打断会自动重建，不需要手动切一轮
- 输出切换和扫描互斥；扫描/搜频段过程中随时可以按「停止」取消并关闭音频

### 控制口

设置 `FM_RADIO_CTL=/tmp/fm-radio.sock` 启动后会开一个 unix socket，一行一条命令：

```text
status                       # 含 recording / rec_path / rec_minutes / rec_elapsed / rec_at / playing_back
record start [分钟]          # 立即录音（不给分钟就用界面上的时长）
record stop
record at HH:MM [分钟]       # 定时开始（跨天自动顺延）
record cancel                # 取消定时
recordings                   # 录音列表（name / seconds / bytes / mtime / playing）
play <序号|文件名>            # 回放
play stop
```

### 插孔自动切换

`latte-jack-switch` 每秒检查插孔，只改 RT5659 mixer（不改 UCM profile）。检测到 FM 正在使用（`/run/user/<uid>/fm-radio-active` 或 loopback 模块）时完全不干预；FM 停止后按插孔状态恢复扬声器/耳机路由。

## 必须遵守的约束

1. **放音时不要切换声卡的 UCM profile**（旧 HiFi profile 的 Speaker/Headphones）。播放中切 profile 会让 SOF 固件进入 `fw_state: termin.`，随后 `IPC timeout`、`hw_params -110`，整机 GUI 卡死。声卡保持 `pro-audio`，用 mixer 或 App 的输出选择器换路由。
2. **音量默认 20%**，不要拉满。滑杆改的是 PipeWire 的软件增益（实测 0→100% 扫一遍，codec 的 `DAC1/HP/OUT/SPO/PGA` 寄存器一个都不动）；模拟增益不由滑杆管，别指望用滑杆去补偿。
3. FM 听音必须 `0x00=0x01`（`init(rds=False)`）。`0x00=0x03`（FM+RDS）在本固件上会静音。
4. 首次调台前必须写 `0xFB` 边界（76–108 MHz），否则频率写不进去，所有读数停在旧频点。
5. 搜台判定：等 `0x12` 锁定后**再等 0.25 s** 读 RSSI/SNR。锁定瞬间 SNR 只有约 8，稳定后可达 17；立刻读值会把强台误判掉。首扫阈值 32 dBuV / SNR 9，二次确认 30 / 8。
6. 只通过 HCI VSC 控制 FM；不要 `ioremap`/直接读 LPE、SSP MMIO，会挂死整机。
7. 有音频流打开时不要卸载/重载 SOF 模块。
8. 双 Profile 蓝牙耳机在切 Profile 的瞬间会同时出现 A2DP 与免提两个 sink。收音机只路由到 A2DP：免提是 8/16 kHz 单声道的 SCO 通道，切过去会没声或严重劣化，前端已默认隐藏免提节点。判断依据是 `api.bluez5.profile`——本板子上 SCO 节点复用 A2DP 的节点名，名字里没有 `head-unit`。

## 重启与开机自启

重启后会自动恢复的东西：

- `/usr/local/bin/{fm-radio,hci_fm,fm-listen.sh,latte-jack-switch}`、拓扑、UCM、内核模块（都在磁盘上）
- `~/.config/fm-radio/config.json`：频率、音量、输出、录音时长，以及未到期的定时录音（错过的超过 1 分钟则作废）
- `~/Music/fm-radio/` 里的录音
- 插孔守护 `latte-jack-switch.service`（systemd user，已 enable）
- App 本身：`install.sh` 会装 `/etc/xdg/autostart/fm-radio.desktop`，登录即启动
- App 启动时会先清掉上一轮残留的 loopback 和 FM 电源状态，不会带着脏状态起来

会丢的：

- 正在进行的录音会中断。正常关机时 `parecord` 收到 SIGTERM 会收尾，文件仍可播放；直接断电可能留下长度写不回头的 WAV（未实测）

## 故障恢复

### 所有输出都没有声音

```bash
pactl list short modules | grep loopback     # 应有一条 module-loopback
pactl list short sink-inputs                 # 回环应出现在 sink 端
fm-listen.sh --rebind                        # 重绑 codec，刷新时钟状态
```

声卡重新注册后旧 loopback 可能只剩一端，卸载后重新加载即可。

### FM 在播但静音

```bash
sudo hci_fm raw 0x00 0x00 0x01   # 退出 RDS 静音
pactl get-sink-volume alsa_output.platform-sof_cht_rt5659.pro-output-0
```

同时检查 loopback 的 source-outputs 和 sink-inputs 两端。

### 输出设备列表里多出一条「免提」

同一只双 Profile 耳机（如 thinkplus-LP19，同时支持 A2DP 和 Handsfree）在蓝卡 Profile 切换的瞬间，`pactl list sinks` 会同时出现 A2DP 和免提（HFP/SCO 单声道）两个 sink。若把会话切到免提 Profile，SCO 节点在本板子上复用了 A2DP 的节点名（`bluez_output.<MAC>.1`，只是格式变成 1ch/16000Hz），只有 `api.bluez5.profile = "headset-head-unit"` 能把它分开，所以前端按 profile 属性判断而不是按节点名。如果把所有 `bluez_output.*` 都列进下拉，就会出现「只有一只耳机却看到两条」；选到免提那条会没声或严重劣化。本前端只列 A2DP 节点，只有当某设备仅暴露免提节点时才带「（免提·单声道）」后缀显示。

验证方式（不需要真耳机）：切换 `pactl set-card-profile bluez_card.<MAC> a2dp-sink|headset-head-unit`，两种状态下 `fm-radio` 的下拉都应只有一条「蓝牙 · …」；只有免提那种状态会多出后缀，且 `outputs` 里的 id 不变。

### 系统音量拉满但没变响

先看默认 sink 对不对：

```bash
pactl get-default-sink
pactl list short sinks
```

GNOME 音量条、音量键、`pactl set-sink-volume @DEFAULT_SINK@` 都作用在**默认 sink** 上。蓝牙音箱一连上，WirePlumber 常把默认 sink 切到蓝牙，而收音机的 loopback 还挂在本地 `pro-output-0` 上——此时拉系统音量调的是蓝牙那一路，本地那一路没动，听起来就是「拉满也只有一半」。App 在切换输出时会同时 `pactl set-default-sink`，所以正常操作下两者一致；如果手动用外部脚本切过 sink，把默认 sink 指回来即可。

### 切蓝牙或扫描时出现长鸣

- 先按 App 的「停止」：它会立即静音、卸载 loopback、关闭 FM，并把本地输出关掉；扫描/切换过程中停止键都可用
- 选蓝牙时本地喇叭/耳机输出应保持 off（numid 6/162/163/164/165），不要用外部脚本把它们重新打开
- App 每 3 秒检查 loopback 是否还在、是否挂在当前 sink 上；被外部打断会自动重建，不需要手动切一轮输出

### 插充电线后 FM 变杂

这是充电器/PMIC 的开关噪声经充电线耦合进 FM 天线，属于 EMI，不是软件增益或解调参数问题。可尝试：

- 换低纹波充电器或移动电源（电池供电通常更干净）
- 充电线加铁氧体磁环，并远离耳机线
- 保持有线耳机作为天线，不要把耳机线缠在充电线上

BCM4356 这条路径没有可用的软件陷波/降噪开关；App 不做会损伤音质的音频滤波。

### DSP 固件终止（`fw_state: termin.`）

1. `pactl set-card-profile alsa_card.platform-sof_cht_rt5659 off` 释放 PCM
2. 只停 WirePlumber，**保留 PipeWire**：`systemctl --user stop wireplumber`
3. 按 `lsmod` 依赖顺序卸载 SOF 模块（`snd_sof_acpi`、`snd_sof_intel_atom`、`snd_sof` 等）
4. 重新 `modprobe`，启动 WirePlumber，确认 `pactl list cards` 恢复 `pro-audio`
5. UCM 若只剩 `off`/`pro-audio`，检查 `/usr/share/alsa/ucm2/Intel/cht-bsw-rt5659/` 的 include

卸载模块可能让内核 taint（`G D C OE`），条件允许时尽快重启。

## 已知限制

- 硬件 seek（`0x09=0x02`）在本固件上不可用，搜台只能软件步进
- 当前固件/信号不投递 RDS 组，PS/RT/PI 解析已实现但通常为空
- 蓝牙耳机输出未实测（测试时设备离线，`br-connection-page-timeout`，20 秒扫描也不可见）；蓝牙音箱（联想 thinkplus LP19，A2DP）已实测。免提节点的识别用蓝卡切 Profile 的方式离线验证过，不需要真耳机
- 插孔检测是 500 ms 轮询，插拔后最多约半秒才切换
- 没有 `/dev/radio0`；BCM4356 FM 由 `hci_fm` 通过 HCI 控制

## 验证记录（2026-10-22）

- 内核 `6.14.0-sof`；PipeWire 1.4.9、WirePlumber 0.5.12、GTK 3.24.51、python-gobject 3.54.5、bluez 5.84
- 88.8 MHz：RSSI 42 dBuV、SNR 17；从 88.7 和 87.5 向上搜均命中 88.8
- 全量扫描得到 15 个台（92.4 / 88.8 / 89.3 / 96.7 / 94.6 / 90.1 / 103.8 / 105.5 / 101.5 / 99.8 / 91.4 / 93.6 / 99.2 / 102.1 / 103.2）
- 扬声器、有线耳机、蓝牙音箱三种输出实测出声；蓝牙耳机因设备离线未测
- 音量 20% 在喇叭→耳机→蓝牙之间切换保持不变（全局音量，不按设备记忆）
- 录音（2026-10-22 实测）：
  - 立即录 1 分钟：到点自动停，文件 `FM_20261022_1919_88.8MHz_1min.wav` 5,570,604 B、58.0 s（比设定少约 2 s，是采集流建立耗时），WAV 头有效（1ch / 48 kHz / 16 bit），29/29 个 100 ms 窗口有声（中位 RMS 3362、峰值 15982）
  - 全程 `loopback=0`、`playing=false`：定时/静默录音确实不出声，只给芯片上电（`0x00` 读回 `01`）
  - 录音中按「停止收听」：`playing` 变 false、`recording` 仍为 true、`loopback=0`，文件在 8 s 内从 589,868 B 长到 1,376,300 B
  - 定时 `19:23` 起录：到点自动开始（10 s 轮询内命中），`loopback=0`、未出声；手动停止后 schedule 清空、芯片断电（`0x00` 读回 `00`）
  - 回放最新录音：sink monitor 13/13 个窗口有声、峰值 12558
- 切蓝牙后本地输出 numid 6/162/163/164/165 全部 off；手动卸载 loopback 后 App 在 7 秒内自动重建并恢复出声
- 扫描连续试听：15 秒内 FM 源与输出端各有 220+ 个 100 ms 窗口有音频（RMS 3–4k）
- 扫描中按「停止」可立即取消：loopback 卸载、FM 关闭、本地输出关闭
- 播放中用 `pactl set-sink-volume` 外部改到 35%，滑杆 3 秒内跟上并写入配置；0.5 秒的瞬时抬到 55% 不被采纳
- 停止状态下在混音器改到 35%，滑杆同样 3 秒内跟上，再按播放不会回退成旧值
- 切换输出后 `pactl get-default-sink` 与 App 的目标 sink 一致：切蓝牙 → 默认 sink 变 `bluez_output…1`，切回喇叭 → 变回 `pro-output-0`
- 蓝牙列表：LP19 在 A2DP 下只有一条「蓝牙 · 联想thinkplus-LP19」；把蓝卡切到 `headset-head-unit`（节点名不变、变成 1ch/16000Hz）后 id 仍相同，四种快照（仅 A2DP / 仅 SCO 同名 / 同卡两节点 / 无 profile 属性的老命名）离线单测全部符合预期
- 蓝牙 A2DP 出声：40/40 个 100 ms 窗口有声，中位 RMS 3811、峰值 17616（音量 20%）；BT↔喇叭切换各 2 次，loopback 恒为 1 条；停止后 BT monitor 采样峰值为 0
- 冷重启复测：SOF 探测、插孔守护、`pro-audio` 配置、定向搜台/全量扫描、蓝牙音箱出声全部正常
- 拓扑 md5 `d8d68f860fda619bb63ae68c01804d1e`；固件 md5 `95573d5a1ccf71c19fd7181b5653bc57`

## 许可

- 内核补丁：GPL-2.0-only
- `fm-radio`、`fm-listen.sh`、`latte-jack-switch`：GPL-2.0-only，© 2026 Xcfcdl
- `hci_fm.c`：GPL-2.0，© 2026 arttttt
- `sof-cht.ri`：Intel SOF 固件，随 sof-bin v2.2 分发，未包含在本目录
