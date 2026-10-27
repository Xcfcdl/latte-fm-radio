# 7.2.0 + FM：装机与判定手册（v4，2026-10-27 现场实测后修订）

v3→v4：新增 **§10：插着耳机当天线，声音也能从喇叭出**（板驱动加 `Speaker Amp Switch`，附编译/安装坑与麦克风 A/B 验证）；§7 加一行喇叭无声的分诊；§8/§9 里"fm-radio 7.2 不能用"的结论已作废。

v2→v3：v2 的判定协议全部保留；下面「现场修订」把 v2 里九条**纸上推断**按真机结果改掉，其中三条（`fw_sst_22a8.bin`、`tar -C /`、`arecord -l` 的设备名）照 v2 执行会直接把装机做坏，已同步改在正文对应小节里。
**结论先放这儿：7.2 + FM 组已验收通过** —— baseline 播放干净、FM 组播放同样干净（6.14 那个 `data_polarity` 引入的沙沙声不在 7.2 移植里）；FM 采集 A/B 两序三条判据全 PASS，人耳确认听得出节目内容；`fm-sst` 实时收听在 7.2 上跑通。

## 现场修订（v3，逐条覆盖 v2）

| # | v2 说什么 | 真机是什么 | 影响 |
|---|---|---|---|
| R1 | §2 判据「`fw_sst_22a8.bin` 不存在 = 没声音」 | CHT 的 SST 跑 **ROM 固件**，这个文件本来就不需要（linux-firmware-intel 只发 `.bin.zst`）。判据改成 journal 里 `intel_sst_acpi 808622A8:00: FW Version 01.0b.02.02` | 按 v2 会误判"预检失败"而停机 |
| R2 | §3 `sudo tar -C / -xf` | 包里的成员路径是 `lib/modules/...`，而 Arch 是 merged-usr（`/lib` 是指向 `usr/lib` 的符号链接）。`tar` 会用**真目录替换那个符号链接**，运行中的系统立刻看不见 `/lib/modules`、`/lib/firmware` | 装坏过一次，已用 `fix-lib-and-restore.sh` 回滚。**必须 `tar -C / usr/lib/modules/...` 或解完立刻修链接**（见 §3） |
| R3 | §3 `mv /System.map-... /boot/` | `/boot` 是 FAT 分区，只剩 15 M，放 16 M 的 System.map 会撑爆 | System.map 放 `/root/`，不要进 `/boot` |
| R4 | §3 `tar -C /root/ab-72 -xf ab-7.2.tar.gz` 后得到 `/root/ab-72/{baseline,fm}` | 包里有顶层 `ab-7.2/` 目录，实际落在 `/root/ab-72/ab-7.2/` | 解包后 `mv` 一层 |
| R5 | §4 判据「`grep -c menuentry` 比原来多 1」 | 装了内核 + preset 之后 `grub-mkconfig` 会**自动生成一条 7.2 条目**，40_custom 那条是第二条，多出的是 2 不是 1 | 用 `--id` 判重，别用计数 |
| R6 | §5 `speaker-test -D default` / §6 `aplay -D hw:0,0` | PipeWire 常驻独占 `hw:0,0`，直接 `hw:` 打开必得 `Device or resource busy`。走 PipeWire：`pw-play f.wav`（**不要加 `-q`**，它要一个数值参数会把文件名吃掉）或 `aplay -D default` | 这条同时解释历史现象「FM 启动说输出不可用」 |
| R7 | §5/§6 靠 UCM `HiFi` verb 下发路由 | SST 卡上 `alsaucm -c cht-bsw-rt5659 list _verbs` 有 `HiFi`，但 `list _devices` 失败 ⇒ PipeWire 只暴露 `stereo-fallback` / `pro-audio` | 播放路由只能**按控件名手动开**（§5.6 那个 for 循环是对的，且要一直带着） |
| R8 | §6.1 判据「`arecord -l` 有 `device 6: BTFM`」 | 本机这次开机打印的是 `card 0 ..., device 6: 5 []` —— **PCM 名字不可信**。权威来源：`cat /sys/module/snd_soc_sst_atom_hifi2_platform/parameters/btfm_pcm_dev` | `fm-sst` 的设备号探测已改成先读这个 sysfs（§6.9） |
| R9 | §6.8 判据「`aplay.err` / `arec.err` 都空」 | `fmtest-72.sh` 自己是 `kill` 掉 aplay/arecord 的，被 SIGTERM 的一方必然写一行 `Interrupted system call` | 判据改成「除这一行之外没有别的报错」 |

改动相对 v1：删掉"按 numid 开路由"、删掉"用 rms 判 FM 成功"、补 A/B 协议与预检。
交叉编译在 Mac 上的 colima VM（`ARCH=x86 CROSS_COMPILE=x86_64-linux-gnu-`），全量编译零 error 零 warning，release 字符串 `7.2.0`。

## 0. 先记住三句话

1. **今天的 A/B 是"整包 FM 补丁 vs 作者原样"**，不是"一行极性"。如果作者原样（baseline）就沙沙，那口锅属于作者的 7.2/UCM，不属于 FM。
2. **RMS/有没有声不能证明音质**。位错一格的垃圾音频 RMS 一样爆表（6.14 就是这么骗过我的）。判据只有两条：人耳听不听得懂播报，以及频谱形状（语音能量应集中在 1.5 kHz 以下，15 kHz 以上接近 0）。
3. **一律按控件名操作，不要按 numid**。SST 卡比 SOF 卡多出几十个 `xxx mix/switch/gain` 控件，编号必然整体平移。

## 1. 产物

| 文件 | 内容 |
|---|---|
| `fm-7.2.0.tar.gz` | 内核 + 35 个模块（含 2 个 FM 补丁模块） |
| `baseline-7.2.0.tar.gz` | 同一内核 + 作者原样的那 2 个模块 |
| `ab-7.2.tar.gz` | 只有那 2 个模块的两组副本，换组用（A/B 靠它） |
| `patches/72-0*.diff` `src72/` | 4 文件 594 行补丁与打完补丁的源文件 |
| `fmtest-72.sh` | FM 采集 + 共存 + 频谱形状判定（本版已改） |

两包的 `vmlinuz` / `System.map` / `.config` **逐字节相同**（`cmp` 验过），只有这两个 .ko 不同：

```
baseline: atom  d436ca549e2677bbad3eccf484c6e8dd   board  47106efb7e17a4b99eb008d55d858407
fm:       atom  3a69c7f916eb2b78a71426738cdec253   board  d1e16051cc1aec50fd10e93ead189532
```

（md5 是 .zst 封装后的值。）

## 2. 装之前先预检（都是会导致"全灭但不是 FM 的错"的东西）

```sh
uname -r; df -h /boot                       # /boot 是 FAT，只剩 15 M；System.map 不要放进去（R3）
ls -l /lib/firmware/intel/fw_sst_22a8.bin*  # R1：CHT 用 ROM 固件，没有这个文件是正常的
journalctl -b | grep "intel_sst_acpi"       # R1 的真实判据：有 "FW Version 01.0b.02.02"
ls /sys/class/bluetooth/ ; bluetoothctl show | head -3   # 判据：hci0 存在。FM 靠 HCI 厂商命令，没 hci0 就没法调台
grep -rn "dsp_driver\|snd_sof\|blacklist snd" /etc/modprobe.d/ /etc/modules-load.d/ 2>/dev/null
```

- `dsp_driver` 在 7.2 只存在于 `sound/hda/core/intel-dsp-config.c`（PCI 路径），CHT 没有 HDA PCI ⇒ **这参数在本机惰性**，旧 menuentry 里带着它不会坏事，也别指望它有任何作用。
- 7.2 没编 SOF，ACPI 表第一条就是 `10EC5659 → cht-bsw-rt5659`（SST），所以**不存在"没 SOF 导致声卡不注册"**。
- 但残留的 `modules-load.d` 里若写了 `snd-sof-acpi`，会有个无害报错；有 `blacklist snd-soc-sst*` 就是致命的，先注释掉再装。
- **用户态三个 helper 里写死了 6.14 的设备号 5**，7.2 上是 6：
  ```sh
  grep -rn "hw:0,5\|device 5\|pro-input\|pro-output\|sof_cht" /usr/local/bin/fm-sst /usr/local/bin/hci_fm /usr/local/bin/fm-radio 2>/dev/null
  ```
  命中就先别改文件，本次验收**只用 `arecord -D hw:0,6` + `fm-sst`**（`fm-radio` 是 SOF 版，节点名和 Profile 全对不上，明天必然报"输出不可用"，那不是 FM 坏了）。

## 3. 安装（root，v3 = 今天实际跑通的那套）

```sh
K=7.2.0
# R2：成员路径写死 lib/...，直接 tar -C / 会把 merged-usr 的 /lib 符号链接换成真目录。
# 正确做法：解到暂存目录，再按部件拷到 usr/lib 和 /boot。
sudo rm -rf /tmp/pkg72 && sudo mkdir -p /tmp/pkg72
sudo tar -C /tmp/pkg72 -xf fm-7.2.0.tar.gz
sudo cp -a /tmp/pkg72/lib/modules/$K /usr/lib/modules/
sudo cp -a /tmp/pkg72/vmlinuz* /boot/vmlinuz-linux-latte-72
ls -ld /lib                                     # 判据：还是 symlink -> usr/lib
# 已经手滑解过一次的，跑修复脚本（移动 + 只在空时 rmdir + 重链 + chown + depmod）：
#   sudo bash fix-lib-and-restore.sh
sudo tar -C /root -xf ab-7.2.tar.gz             # R4：包有顶层 ab-7.2/，得到 /root/ab-7.2/{baseline,fm}
sudo mv /tmp/pkg72/System.map* /root/           # R3：不要进 /boot（只剩 15 M）
sudo depmod -a $K
# preset 只留 default，省一半 /boot；heredoc 里的引号在 zsh-over-ssh 会被吃掉，本地生成再 scp
sudo install -m644 linux-latte-72.preset /etc/mkinitcpio.d/linux-latte-72.preset
sudo mkinitcpio -p linux-latte-72
# 判据：不报错，且 /boot 出现 initramfs-linux-latte-72.img
sudo modprobe snd-soc-sst-cht-bsw-rt5659 && echo PROBE-OK
```

- initramfs 里没有 `.ko` 是**正常的**（`modules.builtin` 里 btrfs / i915 / mmc_core / mmc_block / sdhci / sdhci-acpi 全是内置），别拿"No modules were added"当失败。核对方法：`check-initramfs.sh`（zstd magic 偏移 → `zstd -dc` → `bsdtar -tf`；本机没装 `cpio`，`lsinitcpio -a` 也用不了）。
- 换组仍是"唯一 A/B 动作"，之后必须重启，**不要热插拔声卡模块**：

```sh
sudo cp -a /root/ab-72/fm/lib/modules/$K/kernel/sound/. /lib/modules/$K/kernel/sound/
sudo cp -a /root/ab-72/baseline/lib/modules/$K/kernel/sound/. /lib/modules/$K/kernel/sound/
sudo depmod -a $K
md5sum /lib/modules/$K/kernel/sound/soc/intel/atom/*.ko.zst   # 判据：对上 §1 那组 md5
```

## 4. GRUB（默认仍是 6.14，不动它）

**不要照抄任何记忆里的 snippet**，从本机现有配置复制一条完整 `menuentry` 改三处：

```sh
sudo grep -A6 "menuentry .*latte-fm" /boot/grub/grub.cfg
sudo cp /etc/grub.d/40_custom /etc/grub.d/40_custom.bak-$(date +%F)
# 粘进 40_custom，改：标题、--id=gnulinux-linux-latte-72、vmlinuz/initrd 文件名
sudo chmod +x /etc/grub.d/40_custom && sudo grub-mkconfig -o /boot/grub/grub.cfg
grep -c menuentry /boot/grub/grub.cfg        # 判据：比原来多 1
```

`root=/dev/mmcblk0p2`（btrfs 根）照抄原条目，别改分区。用一次性项，下次开机自动回 6.14：

```sh
sudo grub-reboot "gnulinux-linux-latte-72"; sudo reboot
```

R5：装了内核 + preset 之后 `grub-mkconfig` 会**自己生成一条 7.2 条目**（id 是 `gnulinux-linux-latte-72-advanced-<UUID>`），40_custom 那条才是我们的，`grep -c menuentry` 会比原来多 2。判据用 id 而不是计数：
`sudo grep -c "os \$menuentry_id_option 'gnulinux-linux-latte-72' " /boot/grub/grub.cfg` → ≥1（注意别匹配到 auto 那条 `…-advanced-…`）。今天用的完整条目在 `grub72-setup.sh` 里（`search --fs-uuid XXXX-XXXX` + `root=UUID=906fd687-… rootflags=subvol=@`）。
顺带：auto 那条同样能起 7.2，忘了 `grub-reboot` 时手动选它也可以。

## 5. 首轮 = baseline（作者原样）：先确认"播放本身是干净的"

装 baseline 那组 .ko（§3 的换组命令），重启，然后**完全不碰 FM**：

1. `uname -r` → `7.2.0`
2. `aplay -l` → device 0/1 在；`cat /proc/asound/cards` 有 `cht-bsw-rt5659`
3. **声道测试**：GNOME 声音设置里放 Left/Right；命令行等价用 `baseline-listen.sh`（纯 python 生成 1 kHz / 2 s / 20 ms fade 的三个 wav，`lr l r lr l r` 连放）。
   - **R6：不要用 `aplay -D hw:0,0` 或 `speaker-test -D hw:…`** —— PipeWire 常驻独占 `hw:0,0`，必得 `Device or resource busy`（这条也解释了历史上「FM 启动说输出不可用」）。走 PipeWire：`pw-play tone_lr.wav`（**不要加 `-q`**，它要一个数值参数，会把文件名吃掉）或 `aplay -D default`。
   - 判据（干净）：左一声、右一声，音色是**纯净单音**，无沙、无 crackle、音量左右一致
   - 判据（坏）：两个都糊/带沙、或左右音量/内容不对称
   - **今天的实测：baseline 纯净单音、左右对称 → FM 无罪**
4. 人声内容再听一遍（本地音乐/播客任一）
5. 耳机插入时：`sudo dmesg | grep TFA9890` → 判据 `TFA9890 <component名>: output disabled`
   （源码是 `dev_info(card->dev, "TFA9890 %s: output %s\n", component->name, ...)`，
   两颗功放各一行，`component->name` 形如 `i2c-tfa9890:00` / `i2c-tfa9890:01`。）
   7.2 的扬声器靠插孔事件给功放下电，不是我 6.14 那个写 `IF2 ADC Mux` 的假静音。
   **这条只影响喇叭，耳机测试发沙与它无关。**（今天实测：插耳机时两条都报 `output disabled`，作者的门控是活的 ✓）
6. 没声就先开 codec 输出链（按名字，别按号）：
   ```sh
   for c in 'DAC1 Playback Switch' 'DAC1 MIXL DAC1 Switch' 'DAC1 MIXR DAC1 Switch' \
            'Stereo DAC MIXL DAC L1 Switch' 'Stereo DAC MIXR DAC R1 Switch' \
            'HPO L Playback Switch' 'HPO R Playback Switch' 'Headphone Switch' \
            'Headphone Playback Volume'; do
     sudo amixer -c 0 cset name="$c" 100% 2>/dev/null || sudo amixer -c 0 cset name="$c" on
     sudo amixer -c 0 cget name="$c" | sed -n '1p;4p'
   done
   ```
   先 `sudo amixer -c 0 controls | grep -iE "DAC1|HPO|Headphone|Stereo DAC"` 确认名字在本卡上存在。
   这里把 codec 开满只是为了**排除路由**，实际听音音量仍用 PipeWire 的 sink 音量控制（10–20%），不要把 sink 拉满。
   - **R7：别指望 UCM 帮你接路由。** `alsaucm -c cht-bsw-rt5659 list _verbs` 有 `HiFi`，但 `list _devices` 失败 ⇒ PipeWire 只暴露 `stereo-fallback` / `pro-audio`，`pactl list cards` 永远看不到 HiFi。所以**上面这个按名字的 for 循环是常规动作，不是兜底**，声卡每次重注册都要重跑一遍。
   - 控件实测读数（今天装机时，未跑脚本的原始状态；`baseline-listen.sh` / `fm-sst` 会把 `HPO L/R` + `Headphone Switch` 打开再放）：`DAC1 Playback Switch`=on、`DAC1 Playback Volume`=124、`DAC L1/R1 Mux`='**IF2 DAC**'（作者 7.2 的 c2c 喇叭通路）、`DAC1 MIXL/R DAC1 Switch`=on、`Stereo DAC MIXL/R DAC L1/R1 Switch`=on、`HPO L/R Playback Switch`=off、`Headphone Switch`=off、`Headphone Playback Volume` 0..31（-23.25 dB 起，每格 0.75 dB）。插孔：numid 179 `Headphone Jack`、178 `Headset Mic Jack`。

**这一步的结论决定后面怎么读**：baseline 干净 → 继续 §6；baseline 也沙 → FM 无罪，问题在作者内核/UCM，去查 SSP 之外的东西（先记下，别急着改驱动）。

## 6. 二轮 = FM 组：按阶梯验，每步都有判据

换 fm 那组 .ko，重启。

1. **驱动绑定**：`aplay -l` 有 0/1；FM 采集设备号**只认 sysfs**（R8）：
   ```sh
   cat /sys/module/snd_soc_sst_atom_hifi2_platform/parameters/btfm_pcm_dev   # 判据：6
   ```
   **不要按 `arecord -l` 打印的名字找 "BTFM"** —— 本机这次开机它打印的是 `card 0 ..., device 6: 5 []`，名字里根本没有 BTFM，按名字匹配会落空。
   （PCM 设备号 = FE 在 `cht_dailink[]` 里的下标：`0 Audio Port 1 Deep-Buffer 2 SSP2-Codec(BE) 3 Codec AIF2(c2c) 4 TFA-L 5 TFA-R → 6 BTFM`。`hw:0,5` 在 7.2 上不是 FM，会 `No such file or directory`。）
2. **路由自动接通**：`sudo dmesg | grep "FM:"` → 判据 `FM: pcm2_out mix 0 fm_in Switch = on`
   没这行 = DAPM 图没连上，后面全不用做（这是 `0x92` 之外最容易挂的一步）。
3. **增益地板**（每个 gain 格有 Switch/Volume/Ramp 三个控件）：
   ```sh
   sudo amixer -c 0 cget name='fm_in Gain 0 Switch'      # 判据 on
   sudo amixer -c 0 cget name='fm_in Gain 0 Volume'      # 判据 ≈ -18.00dB，不是 -144dB 地板
   sudo amixer -c 0 cget name='pcm2_out Gain 0 Switch'   # 判据 on
   sudo amixer -c 0 cget name='pcm2_out Gain 0 Volume'   # 判据 0dB
   ```
   读到 `off / -144dB` = `sst_gain_open_default()` 没生效，采集必然数字静音。
4. **SSP 几何**：`for p in /sys/module/snd_soc_sst_atom_hifi2_platform/parameters/btfm_*; do echo -n "$p = "; cat $p; done`
   判据 `sel=2 bits=16 slots=2 mode=0 duplex=1 proto=1 fsw=3 map=3 delay=2 fsfreq=3 dpol=0`
   （`fsw=3 delay=2` 是关键：32/1 那组旧值固件会**静默丢数据**，20bit 直接忽略、24bit 只留低字节、32bit 溢出成 0。）
5. **流参数**：`sudo dmesg | grep "stream params"` → 判据 `dev=0xf task=3`（FM 流走 `PIPE_PCM2_OUT`）。
6. **出声 + 形状判定**（`fmtest-72.sh` 本版自带 FFT 频谱形状输出，纯 python，不依赖 numpy/sox）：
   ```sh
   bash fmtest-72.sh A     # FM 先开、播放后加入
   bash fmtest-72.sh B     # 反过来
   ```
   三条判据缺一不可：`rms > 1000`；**`<1.5k 占比 > 50%`**；**`>15k 占比 < 15%`**。
   参考形状：正常电台 ≈ 能量集中在低频（6.14 实测 72% 在 1k 以下、15k 以上为 0）；位错/垃圾是能量平铺到 3k–18k。
   本地自测过：纯低频信号 `PASS`（rms 3888 / <1.5k 97% / >15k 0%）；白噪 `FAIL`（**rms 8945 却形状全散** —— 这就是只看 rms 会漏判的那种）。
   设备号可用环境变量覆盖：`DEV=hw:0,6 FREQ=92.4 bash fmtest-72.sh A`。`fm-sst` 不存在时脚本只采集不调台。
7. **耳朵验收（最终判据）**：`arecord -D hw:0,6 -f S16_LE -c 2 -r 48000 /tmp/x.wav` 录 10 s，
   `mpv /tmp/x.wav` 或拷回来给我 —— **能不能听出人在说话/节目内容**。雪花也算正常（信号弱），但内容必须可辨。
8. **共存**：R9 —— `aplay.err` / `arec.err` **不会全空**：脚本自己是 `kill` 掉 aplay/arecord 的，被 SIGTERM 的一方必写一行 `Interrupted system call`。判据改成「除了这一行之外没有别的报错」，且播放期间 FM 的 rms 不明显塌陷。
9. **实时收听（`fm-sst`，已适配 7.2）**：设备号现在从 sysfs 的 `btfm_pcm_dev` 取（R8），输出走 PipeWire（R6，`PB_DEV=default`），不再碰 `hw:0,0`。
   ```sh
   sudo env XDG_RUNTIME_DIR=/run/user/1000 \
            DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus \
            /usr/local/bin/fm-sst on 92.4            # 判据 tuned … lock=1 rssi=… snr=…
   sudo env ... /usr/local/bin/fm-sst play "" 14 25  # 后台 25 s，判据 cap=hw:0,6 out=default
   sudo env ... /usr/local/bin/fm-sst meter          # 判据同 on
   ```
   - 作为 root 跑 pactl/pw-* 必须带上面两个环境变量，否则 `Connection refused`（历史坑）。
   - 备份在 `/usr/local/bin/fm-sst.bak-20261027`；三次补丁记录在 `patch-fm-sst-72{,b,c}.py`。
   - `play` 起不来自检：`tail -2 /tmp/fm-sst.err`。
   - 已知还没验：`scan` 只跑过短区间；`fm-radio` 图形前端仍是 SOF 版，节点名（`pro-input-0`）和 Profile 全对不上，7.2 上不能用。

## 7. 分诊表（先定位再动手）

| 现象 | 第一嫌疑 | 判据动作 |
|---|---|---|
| baseline 就沙沙 | 作者 7.2 / UCM / codec 路由，**不是 FM** | §5 全部重跑，把 dmesg + `amixer -c0 controls` 发我。**今天实测：不成立，baseline 纯净单音、左右对称** |
| baseline 干净、FM 组沙沙 | FM 组里唯一还没被排除的播放侧改动就是那 2 个模块；`data_polarity` 已确认 7.2 保持作者的 `1`，所以要看 `sst_resend_swm`/`POST_REG` 是否重放了播放 mixer | **今天实测：不成立，FM 组播放与 baseline 听感一致（"跟刚才一样干净"）⇒ 6.14 那个 `sst_ssp_configs.data_polarity 1→0` 的回归没有进 7.2 移植，FM 补丁也没污染共享的 codec-SSP 播放路径。** 若在新组合上复现：dmesg 找 `widget = codec_out0 mix 0` / `pcm1_out mix 0` 的发送时机；把 `fm_in Switch` 手动 `off` 再听一次（`amixer -c0 cset name='pcm2_out mix 0 fm_in Switch' off`） |
| FM 有 rms 但听不懂/全是沙 | SSP 几何或增益 | §6.3/§6.4 逐条核；再 `echo 3 > /sys/module/.../parameters/btfm_delay` 之类做单变量试验 |
| FM 有 rms、内容可辨但只从喇叭不从头戴 | 插孔事件/功放门控 | `dmesg | grep TFA9890` 是否 `output disabled` |
| 插着耳机、选"喇叭"没声 | 功放被插孔门控断电，或 IF2 源选错 | `amixer -c0 cget numid=199` 是否 `on`；dmesg 有没有 `output enabled`；`amixer -c0 cget numid=245` 是否 `DAC_REF`；见 §10 |
| `arecord` 报 `Unable to install hw params` | §6.2 的路由没接通 | 只看 dmesg 那行 `FM: ... = on` |
| 调不了台 | hci0 没起 | `ls /sys/class/bluetooth` |

## 8. 已知没带的东西（别在明天现场找）

- **`rt5659.c` 没有 FM 改动**（全文搜 `bt_fm`/`btfm`/`ssp1`/`FM In` 零命中；仅有的 3 处
  `printk` 是作者本人的 JD3 轮询调试，6.14/7.2 逐字一致）。明天不要怀疑 codec 驱动。
- 6.14 那版 `IF2 ADC Mux` 扬声器门控**没移植，也不该照原样移植**：`IF_ADC2` 不是静音，是 ADC2/MIC 通路，等于往功放灌 MIC 底噪，而且它每 1 s 重申会压住 UCM 的正常路由。7.2 现在只在选"喇叭"时把 IF2 源切到 **`DAC_REF`**（节目音），耳机模式再切回厂商默认的 `IF_ADC2`；功放的通断交给 DAPM `OUT`（§10）。
- `fm-radio` 图形前端**已在 7.2 上跑通**（`patch-fm-radio-72{,b,c}.py` 的九处适配；输出切换走 §10 的 `apply_output_chain()`）。UCM 那句仍然成立：SST 卡上 `list _devices` 失败，没有 HiFi verb/devices，路由只能按控件名开。
- 6.14 归档里的 `patches/01-atom-sst-controls-FM.patch` 与 `src/atom/*` 是 10-21/22 旧版（含已废弃的 `sst_btfm_be_startup` 强制上电实验），**不要照它重编**。最终版源已在 `../sst-fm-patch-20261021/src-final-20261027/`，说明见 `../sst-fm-patch-20261021/MANIFEST.md` 末尾的勘误。

## 9. 实测记录：2026-10-27（7.2.0 + FM 组，一次性条目启动）

环境：`uname -r` = `7.2.0`，卡 `cht-bsw-rt5659`，耳机插着（当天线 + 听音），办公室 LAN。

| 步骤 | 结果 |
|---|---|
| §6.1 采集设备号 | sysfs `btfm_pcm_dev=6`；`arecord -l` 打印 `device 6: 5 []`（**名字不可信**，R8 的来源） |
| §6.2 路由自动接通 | dmesg `FM: pcm2_out mix 0 fm_in Switch = on` ✓ |
| §6.3 增益地板 | `fm_in Gain 0` = on / -18dB，`pcm2_out Gain 0` = on / 0dB ✓ |
| §6.4 SSP 几何 | `sel=2 bits=16 slots=2 mode=0 duplex=1 proto=1 fsw=3 map=3 delay=2 fsfreq=3 dpol=0` 全对 ✓ |
| §6.5 流参数 | `stream params … dev=0xf task=3` ✓ |
| HCI 调台 92.4 | `lock=1 rssi=61…62 snr=14…15`（之后几次读 45–48 / 14–15，信号有起伏） |
| §6.6 形状判定 | A 序与 B 序三条判据全 PASS（rms > 1000、<1.5k > 50%、>15k < 15%） |
| §6.7 耳朵验收 | **用户确认"听得出人在说话/节目内容"** ✓ |
| 录音留档 | `fm924-72.wav`（2304044 B，12 s，md5 `fe4c46af979fe2791ce07276c0a4a933`）；另做音频性检验 `mean|d1|=186.9` vs `mean|d2|=337.7`，无样本重复 ⇒ 不是位错垃圾 |
| §5 A/B（播放侧） | baseline 纯净单音、左右对称；换 FM 组后"跟刚才一样干净" ⇒ **FM 组不污染 codec-SSP 播放路径** |
| §6.9 实时收听 | `fm-sst play "" 14 25` → `cap=hw:0,6 out=default`，25 s 后进程干净退出，`meter` 正常（92.40 lock=1 rssi=48 snr=15） |

当天踩到并已修掉的东西（都写进上面的正文了）：`tar -C /` 破坏 merged-usr（R2）、System.map 进 /boot（R3）、preset heredoc 引号、`aplay -D hw:0,0` 被 PipeWire 占用（R6）、UCM 无 devices（R7）、`arecord -l` 名字探测落空（R8）、`fm-sst` 三次补丁。

未做/未验：`fm-radio` 图形界面的端到端点按（控制层已用 amixer + 麦克风 A/B 验证，见 §10.4）、`fm-sst scan` 全段扫描、7.2 设为默认内核（现在仍是 6.14 默认，7.2 靠 `grub-reboot` 一次性条目）、6.14 日常内核上 `data_polarity` 回归的修复（重编 atom 模块，增量编译即可）。

## 10. v4 追加：插着耳机当天线，声音也能从喇叭出

### 10.1 症状与根因

作者的 7.2 板驱动在插孔通知里做 `cht_spk_power_apply(card, !hp)`：插着耳机就把两颗 TFA9890 的 DAPM `OUT` 断电。耳机插孔同时是 FM 天线、必须常插，于是喇叭永远是哑的。dmesg 每来一次插孔事件就翻一次：当天实测 `2475 / 2478 / 2482 / 2494 / 2841 / 2847 s` 反复 `output enabled/disabled`，`amixer -c0 cget numid=194` 一直是 `on`。

即使用户态强行让功放通电，第二条也拦着：`IF2 ADC Mux`（numid 245）= `IF_ADC2`，功放拿不到节目音。扬声器的数据是 `aif1 → aif2` 回环后从 AIF2TX 出去的，源要选 **`DAC_REF`**。

### 10.2 改法（分层：驱动只描述能力，路由归系统层）

`src72/cht_bsw_rt5659.c` 加卡片级 BOOLEAN 控制 **`Speaker Amp Switch`**（本机 numid 199）：

- put 只记值 + `schedule_work()`，真正改 DAPM 的 `snd_soc_dapm_enable/disable_pin("OUT")` + `snd_soc_dapm_sync()` 在 work 里跑。
  **不能在 put 里同步做**：`snd_soc_dapm_sync()` 持 `dapm_mutex` 会走到 DPCM 的 `dpcm_mutex`，和 `dpcm_fe_dai_open()` 的加锁顺序相反（与 6.14 那次 `kctl->put` 自死锁同一类问题）。
- **插孔只上报，不做策略**：`cht_jack_notify()`、`jack_nb`、`spk_amp_manual` 已删除。
  耳机孔兼作 FM 天线会长期插着，功放开还是关由系统层（UCM）写 `Speaker Amp Switch` 决定。
- `spk_amp_on` 初值置 `true`，与 DAPM 的"OUT 默认连通"对齐；否则系统层第一次写 `off` 会被同值判断吃掉，功放就带着 `IF_ADC2` 底噪一直通着。
- 两条路由由 UCM device 序列区分（`codecs/rt5659/Speaker.conf` / `HeadPhones.conf`）：

  | 输出 | Speaker Amp Switch | IF2 ADC Mux | HPO L/R Playback Switch |
  |---|---|---|---|
  | 喇叭 | on | `DAC_REF` | off |
  | 耳机 | off | `IF_ADC2` | on |

  顺序由 UCM 保证：verb 级先写 `Speaker Amp Switch off`（安全默认），Speaker 设备的 EnableSequence 再上电；
  耳机只跑 DisableSequence（先切 mux 再断电），避免切换时 pop。应用不再写任何 codec 控件。

### 10.3 编译与安装（会卡住的坑）

1. 树已建好时 `make sound/soc/intel/boards/snd-soc-sst-cht-bsw-rt5659.ko` 会去**重建全局 `Module.symvers`**，
   然后死在 `ERROR: modpost: "rt5659_set_jack_detect" ... undefined!`（哪怕它就在 symvers 里）。
2. 加 `KBUILD_MODPOST_WARN=1` 才出 .ko；但它跑完会把 `Module.symvers` 从 15553 行缩到 15348 行。
   ⇒ **编译前 `cp Module.symvers /tmp/Module.symvers.good`，编完拷回去**，否则后续模块全编不了。
3. 7.2 的模块是压缩存放，且路径多一层 `kernel/`：
   `/usr/lib/modules/7.2.0/kernel/sound/soc/intel/boards/snd-soc-sst-cht-bsw-rt5659.ko.zst`
   用 `zstd -q -19 -f new.ko -o 目标.ko.zst` 压回去，`chmod 644` / `chown root:root`，再 `depmod 7.2.0`。
   `MODULES=()` 所以不必重做 initramfs，**重启**即生效（模块不能热插拔平台栈）。
4. 产物与备份：
   - 当前版本（jack 只上报）：`out72/snd-soc-sst-cht-bsw-rt5659.ko.20261027-jackonly`，43736 B，
     md5 `1b73e3d283fa1207d9abfbe3cf71f2d6`，zst md5 `8530073d94107bd2cd6f13bbb96b944e`
   - 上一版（带插孔接管）：`out72/snd-soc-sst-cht-bsw-rt5659.ko`，45176 B，md5 `5103afc449c6f3bce7847865f36b6d81`；
     平板备份 `/root/snd-soc-sst-cht-bsw-rt5659.ko.zst.bak-20261027b`
   - 再前（当天 FM 组那版），md5 `d1e16051cc1aec50fd10e93ead189532`；
     平板 `/root/snd-soc-sst-cht-bsw-rt5659.ko.zst.bak-20261027`，本地 `out72/*.ko.zst.bak-20261027`
   - 源码：`src72/cht_bsw_rt5659.c`（当前 md5 `19d631651fb1c66617cd7fec87691da1`）
5. 开机后自检：
   `amixer -c0 cget numid=199`（应存在；UCM verb 起来后初值 `off`，切到 Speaker 设备后 `on`）；
   插拔耳机时 `Speaker Amp Switch` 不应变化（旧行为的 `jack hp=… ignored` 日志也应消失）。

### 10.4 验证（麦克风 A/B，比等人听更快出结论）

播 1 kHz 测试音的同时，用内置麦克风 `arecord -D hw:0,0 -f S16_LE -c 2 -r 48000 -d 9 /tmp/m.wav` 录，
`analyze_mic.py`（Goertzel，500 ms 一窗）看 1 kHz 带能量 / 邻带（900+1100 Hz）比值：

| 模式 | 比值 | 结论 |
|---|---|---|
| 喇叭（amp on + DAC_REF + HPO off） | **5–28×**，从播放开始那一帧起跳 | 插着耳机，喇叭确实出声 |
| 耳机（amp off + IF_ADC2 + HPO on，同一段音） | **0.5–1.9×** | 无 1 kHz ⇒ 两条路互斥，不是串音假象 |

音量推子对喇叭有效：78% → 1k 幅度 34.2，30% → 18.3（所以不需要再单独写 DAC1 音量）。

### 10.5 限制

- **选"喇叭"时内置麦克风会哑**：`IF2 ADC Mux = DAC_REF` 之后，FM 在播的情况下再 `arecord -D hw:0,0` 得到的是全 0（耳机模式同一时刻录到 ~180 rms 底噪）。FM 应用不用麦，但别在喇叭模式下指望录音。
- 接管是"钉住"的：模块不重载就一直不听插孔。`fm-radio` 每次 `prepare()` / `loopback_on()` 都按当前输出重写一遍；
  想恢复自动行为，重启（或 `rmmod` 板模块再 `modprobe`）即可。
- `fm-radio` 的改动在 `apply_output_chain(target)`：`prepare()` 与 `loopback_on()` 都调它，替换掉原来只开 HPO 的 `open_hp_chain()`。
  备份 `/usr/local/bin/fm-radio.bak-20261027b`；新文件 md5 `dbfca46500d7366c95aa4798bafb45de`。

## 11. 系统层：fm-tuner 服务（FM 变成标准采集源）

分层落到最后一层：**芯片和采集流归系统层**，应用只负责界面与"把源放出来"。

| 层 | 负责 |
|---|---|
| 驱动 | 暴露 `Speaker Amp Switch`、FM 采集 PCM（`btfm_pcm_dev`）；插孔只上报 |
| 系统（UCM） | 输出路由：每个输出设备一个 profile，切 profile 就跑 codec 序列 |
| 系统（fm-tuner） | 芯片所有权：HCI 上电/调谐/扫描；把采集流发布成 `fm_radio` 源 |
| 应用 `fm-radio` | 选 profile、调 RPC、读 `fm_radio`、喂给默认 sink；不再碰 HCI 与 ALSA |
| 用户 | 在系统设置里选喇叭/耳机/蓝牙 |

### 11.1 服务

- `/usr/local/bin/fm-tuner`（Python，root:root 755），unit `/etc/systemd/user/fm-tuner.service`，
  `systemctl --user enable --now fm-tuner`（`WantedBy=default.target`，登录即起）。
- 协议：`$XDG_RUNTIME_DIR/fm-tuner.sock`（0600），逐行 JSON：
  `init` / `off` / `tune{khz,settle}` / `tune_wait{khz,timeout,settle}` / `audio_on` /
  `status` / `read` / `read_raw` / `write` / `raw`。返回 `{"ok":bool,"result":…}`。
- 源节点：`pw-cli create-node adapter '{ factory.name = "api.alsa.pcm.source" … }'`，
  `node.name = fm_radio`、`media.class = Audio/Source`、`api.alsa.path` 取自
  `/sys/module/…/parameters/btfm_pcm_dev`。`init` 建、`off` 销；无消费者时 PipeWire 挂起它，**不长期占用 hw:0,6**。
- 踩过的坑：属性值里带逗号要引号包住（`api.alsa.path = "hw:0,6"`），否则 `syntax error in properties`；
  节点必须 `object.linger = true`，否则创建后立即被回收；重复 create 会出现同名多节点，
  销毁按 `pw-dump` 里 `node.name == "fm_radio"` 找 id。

### 11.2 应用侧改动（`/usr/local/bin/fm-radio`）

- `FMChip` 变成服务客户端（同名方法，内部走 socket）；`init/off/tune/tune_wait/audio_on/read/read_raw` 全部转发。
- 采集：`arecord -D hw:0,6` → `pw-record --target fm_radio --media-category Capture -`（同一份 raw S16_LE 2ch 48k，
  `Stream`/`Recorder`/频谱逻辑不变）。
- 备份：`/usr/local/bin/fm-radio.bak-20261027d`；本地归档 `kernel72/fm-radio.20261027-tuner`（md5 `7be9792a…`）。

### 11.3 验证（2026-10-28 凌晨，插着耳机当天线）

- `tunercli init` → true；`tune 92400` → `[1, 194, 24]`（lock、rssi、snr）。
- 从 `fm_radio` 采 3 s：rms 1161、peak 28260，97% 能量在 1.5 kHz 以下。
- 无头应用链路：`prepare(speaker)` → `init` → `tune` → `STREAM` 采到 rms 947 → `loopback_on` 返回 `fm-pipe` →
  `loopback_alive` true → `off` 之后 `fm_radio` 节点消失、`powered=false`。

### 11.4 已知限制

- **FM 与内置麦并发仍会把 FM pipe 打死**（固件限制）。现在任何程序都能看到 `fm_radio`，这个坑更外露，只能靠文档约束。
- 服务不做心跳回收：应用崩溃且未调 `off` 时芯片会一直通电（源在没人读取时挂起，不占 PCM）。
- 应用侧的图形界面端到端尚未点按验证（控制/采集/播放链路已用无头脚本验过）。

## 12. v5 追加：峰值"电流声"、首开全零、回传（2026-10-27）

### 12.1 峰值处的电流声 = 芯片 16 位输出溢出回绕

- 现象：节目峰值处"叭"一下的电流声，耳机上、音量很低时同样有 ⇒ 与功放/音量无关，在 FM 解码后的数字流里。
- 判据：抓 10 s，统计"单样本极性翻转"（`|中点插值|>1500` 且 `x[i]*interp<0`）。good 例：
  `… 4031, -4096, -4071, -4126, 3958 …` —— 包络在正峰，连续 3 个样本却贴在负满幅；
  步进 ≈ 2×峰值 = 2×(32767×0.1259)。即芯片内部 16 位值超过 +32767 后回绕。
- A/B（只改 `0xF8` 芯片输出电平）：

  | F8 | 92.4 台 signflips | 峰值 | 88.8 台 signflips | 峰值 |
  |---|---|---|---|---|
  | 255 (0xFF) | 115 / 30 s | 4126 | 49 / 10 s | 4124 |
  | 192 | 23 / 30 s | 4126 | 0 | 3927 |
  | 176 | 0 / 20 s | 3999 | — | — |
  | 160 | 0 / 20 s | 3894 | 0 | 3251 |

  修复：`fm-tuner` 的 `init()` 写 `0xF8 = 0x00A0`（160）。部署后两台中复核：92.4 26 s / 88.8 21 s 均 **0 flips**，
  峰值 3579 / 3149（-1.5 dB 左右），rms 基本不变。`0xF8` 在调台时不会被改写，但芯片重新上电必须重写。

### 12.2 新建节点有时全零，重开一次才有声

- 现象：`init`/`tune` 建出的 `fm_radio` 整段 **精确全零**；同时 `/proc/asound/.../pcm6c/sub0` 是 RUNNING、hw_ptr 在前进。
  销节点重建（或第二次 `arecord`）立刻有信号。推测是 SST 的 SSP2 RX 在芯片 I2S 输出就绪前就开了流。
- 修复：`create_node_with_audio()` —— 建好后用 0.4 s `pw-record` 探针，全零就销毁重建，最多 2 次。
  探针用"是否出现任何非零字节"判断，广播节目不存在数字全零，不会误判静音段。

### 12.3 回传 = pw-record 找不到目标时静默改录麦克风

- 现象：喇叭里出现房间声/回声，像"麦克风的声音从喇叭出来"。
- 根因：`pw-record --target fm_radio` **在节点不存在时不退出**（旧注释"exits at once"是错的），
  WirePlumber 把这条流回落到默认源 = 内置麦克风；播放线程照常 `aplay` ⇒ 麦克风→喇叭闭环。
  触发方式：tuner `off`/重开节点时，应用正好在播。
- 修复（应用层）：`fm_source_present()` 用 `pw-dump` 查 `node.name == "fm_radio"`；
  `FmStream._start()` 启动前和 0.3 s 后各查一次，`Player.loopback_alive()` 也查。节点不在就**拒绝启动/停播**。
  实测：有源 → `stream start: True`；`off` 之后 → `source present: False`、`stream start: False`。
- 顺带纠正：FM 的路由开关只有 `pcm2_out mix 0 fm_in`；
  `media_loop1_out mix 0 fm_in` / `pcm0_out mix 0 media_loop1_in` 不是 FM 路由，误开后会让 FM 进 media loop，已恢复 off。

### 12.4 工具

- `fman2.py`：单文件分析器（peak/rms/clip/极性翻转/跳变/峰值处波形），`python3 fman2.py a.wav b.wav`。
- 测试音：`tones.wav`（10 s 柔和旋律提示音，-20 dBFS），替代刺耳的 1 kHz 正弦。

## 13. 装机资产清单（7.2 不是 pacman 包，重装只能照这张单子）

> 仓库里既没有 `docs/` 也没有 `fix_file`，清单就落在本节；同目录已归档
> `fm-tuner`、`fm-radio.20261027-tuner`、`fm-sst`、`fm-tuner.service`、`HeadsetMic.conf`。

### 13.1 内核：手工安装，`pacman -Qo` 查不到

`/usr/lib/modules/7.2.0/` 与 `/boot/vmlinuz-linux-latte-72` 都是裸文件（`make modules_install` +
`cp arch/x86/boot/bzImage` + `mkinitcpio`），没有对应包。重建三件套：

| 件 | 来源 |
|---|---|
| 内核源码 | `linux_latte-7.2-575dbb62.tar.gz` |
| 配置 | `xiaomipad2_defconfig.72`（`CONFIG_SND_SST_ATOM_HIFI2_PLATFORM_ACPI=m`、`CONFIG_SND_SOC_TFA989X=y`） |
| 补丁 | `patches/72-01..04`，源文件留档在 `src72/` |

改动只有 4 个文件，其余全走树内驱动：

- `sound/soc/intel/atom/sst/sst-atom-controls.h` / `.c` —— FM 采集 DAI 与控件
- `sound/soc/intel/atom/sst/sst-mfld-platform-pcm.c` —— FM 输入/输出管道
- `sound/soc/intel/boards/cht_bsw_rt5659.c` —— jack 只上报；TFA9890 供电门控（`cht_spk_power_apply()`）

### 13.2 模块（vermagic `7.2.0 SMP preempt mod_unload modversions`）

| 模块 | sha256 |
|---|---|
| `sound/soc/intel/atom/snd-soc-sst-atom-hifi2-platform.ko.zst` | `15f55092b289298fcd8a2a76e2a50fc65078f937c5d28201ef86f7dd1d90330d` |
| `sound/soc/intel/boards/snd-soc-sst-cht-bsw-rt5659.ko.zst` | `d8ae9029e10e67f5147541d6781c3b2c78f83994e53c9d9f95bb0dfa63807c9d` |
| `sound/soc/codecs/snd-soc-rt5659.ko.zst` | `35ca67a2f606f82b45ba619ca22523388e8f7354f5a3039f0af1557b1613dc55` |

`tfa989x` 是树内 mainline（`CONFIG_SND_SOC_TFA989X=y`，built-in），
`i2c-tfa9890:00/01` 由板级驱动当 DAPM supply 开关，没有独立模块要装。

### 13.3 固件

- **BT/FM 共用** `/lib/firmware/brcm/BCM4356A2.hcd`（64031 B，包 `linux-firmware-broadcom`）。
  判据：`Bluetooth: hci0: BCM4356A2 'brcm/BCM4356A2.hcd' Patch` 之后才有 hci0，FM 的所有 VSC 都走它。
- WiFi：`brcm/brcmfmac4356-pcie.bin.zst` → `../cypress/cyfmac4356-pcie.bin.zst`（同包符号链接），
  板型文件 `brcmfmac4356-pcie.Xiaomi Inc-Mipad2.txt.zst`。
- SST 用 ROM 固件：`/lib/firmware/intel/fw_sst_22a8.bin` 不存在是**正常**的，
  真正判据是 `intel_sst_acpi 808622A8:00: FW Version 01.0b.02.02`。

### 13.4 系统层 / 用户态

| 路径 | 作用 |
|---|---|
| `/usr/local/bin/fm-tuner` + `/etc/systemd/user/fm-tuner.service` | 芯片独占、调谐、发布 `fm_radio` 源 |
| `/usr/local/bin/fm-radio` | GUI，只切 UCM profile / 选输出 |
| `/usr/local/bin/fm-sst` | 诊断与扫频，**tuner 的客户端** |
| `/usr/share/alsa/ucm2/codecs/rt5659/{EnableSeq,Speaker,HeadPhones,IntMic,HeadsetMic}.conf` | UCM 路由（移植源 `/usr/local/share/alsa-ucm2-latte` 需同步） |

`fm-tuner` 是 **user unit**：`systemctl --user status fm-tuner` 才有真状态，
系统作用域查会显示 `inactive`，别误判成服务没起。

## 14. v6 收尾：默认启动 + 尾巴（2026-10-27 晚）

### 14.1 默认启动

`GRUB_DEFAULT` 改为生成的 7.2 条目
`gnulinux-linux-latte-72-advanced-906fd687-…-d0cce9`，`grub-mkconfig` 重生成，
重启后 `uname -r` = 7.2.0、cmdline `loglevel=3 quiet splash plymouth.nolog`，不再需要 `grub-reboot`。
6.14 的 `linux-latte` 仍在菜单里当回退。

### 14.2 fm-sst 改成 tuner 客户端

原来 `fm-sst` 自己调 `hci_fm` 上电、自己 `arecord -D hw:0,6` 采集，和常驻的 `fm_radio` 抢同一个 PCM，
上电序列也复制了一份（`0xF8` 的修复因此要改两处）。现在：

- 所有寄存器操作走 tuner 的 UNIX socket（`$XDG_RUNTIME_DIR/fm-tuner.sock`），`sudo` 下按 `SUDO_UID` 找回用户 runtime dir；
- 扫频用 `tune_wait`（等 lock 稳定再读表），整个频段在一个 python 进程里跑完，不再 200 次进程启动；
- 播放从 `fm_radio` 源取（`pw-record --target fm_radio`），不再直接开 `hw:0,6`；
- `0xF8`、增益、几何参数只在 tuner 里存一份。

### 14.3 头戴麦克风 UCM 缺 `CapturePCM`

`codecs/rt5659/HeadsetMic.conf` 没有 `CapturePCM`（`IntMic.conf` 有），
所以两个带 HeadsetMic 的 profile 一直报 `sources: 0`。补上并补齐 SST 侧中继：

```
cset "name='STO1 ADC Capture Switch' on"
cset "name='Stereo1 ADC Source' 'ADC1'"
cset "name='Stereo1 ADC1 Source' 'ADC'"
cset "name='media_loop2_out mix 0 codec_in0 Switch' on"
cset "name='pcm1_out mix 0 media_loop2_in Switch' on"
CapturePCM "hw:${CardId}"
```

`Stereo1 ADC1 Source` 那句是必需的：上一次 verb 若把它留在 `IF_ADC2`（早期静音门控实验的残留），
头戴麦会采到 ADC2 而不是 ADC1。重启 wireplumber（不是 PipeWire）后，
`HiFi (Headphones, HeadsetMic)` / `HiFi (HeadsetMic, Speaker)` 都变成 `sources: 1`。

### 14.4 扫频结果（2026-10-27 晚，公司环境）

`fm-sst scan`（87.5–108.0，0.1 MHz，0.6 s 驻留）连跑两次，两次的台位一致、强弱排序不一致：

```
88.8 47/11   88.0 42/10   103.6 41/9   90.4 41/8   90.1 41/8   105.2 41/7
91.4 41/7    92.4 40/9    93.3 40/5    90.5 40/2   107.7 39/8  94.0 39/7
```

同一批台在几分钟内 rssi 波动 ±8、snr 波动 ±6，只适合判断"哪些频点有台"，不能横向比强弱；
定强弱要多扫几轮取中位，或直接 `fm-sst fine` 看峰形。

### 14.5 链路复核（改完 UCM 之后）

`fm-sst on 88.8` → `lock=1 rssi=43 snr=12`，抓 8 s：

```
rms=1034  peak=3434  clip=0
energy <1.5k=98.2%   >15k=0.0%   L rms = R rms = 1034
```

三条判据（rms>1000、<1.5k 占比>50%、>15k 占比<15%）同时满足，左右对称、无削顶 ⇒ 人声广播正常。
