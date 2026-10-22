#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2026 Xcfcdl <746953609@qq.com>
# fm-listen.sh - BCM4356 FM -> SSP1 -> SOF -> SSP2 -> RT5659 -> speaker
#
# Usage:
#   fm-listen.sh [freq_mhz]      start (default 97.4)
#   fm-listen.sh --off           stop loopback and power FM down
#   fm-listen.sh --scan          scan 87.5-108.0 and print RSSI
#   fm-listen.sh --rebind        rebind codec first (stale-clock rescue)
#
# Env: VOL=<0-100> PipeWire sink volume, default 20.
#      OUT=speaker|headphones, default speaker.

set -u

CARD=0
CARD_NAME=alsa_card.platform-sof_cht_rt5659
PROFILE=pro-audio
HCI=/usr/local/bin/hci_fm
SRC=alsa_input.platform-sof_cht_rt5659.pro-input-0
SINK=alsa_output.platform-sof_cht_rt5659.pro-output-0
VOL=${VOL:-20}
OUT=${OUT:-speaker}

SUDO="sudo -n"
[ "$(id -u)" -eq 0 ] && SUDO=""

export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}

fmw()  { $SUDO "$HCI" write "$1" "$2" >/dev/null; }
fmr()  { $SUDO "$HCI" read "$1" "${2:-2}" | awk '{print $NF}'; }

fm_on() {
	$SUDO "$HCI" raw 0x00 0x00 0x01 >/dev/null
	# search boundaries: 108 MHz / 76 MHz, without this every tune fails
	$SUDO "$HCI" raw 0xFB 0x00 0xE0 0xAB 0xE0 0x2E >/dev/null
	fmw 0x01 0x0003		# region + stereo
	fmw 0xF8 0x00FF		# FM chip output level
}

fm_tune() {			# $1 = kHz (e.g. 97400)
	fmw 0x0A $(( $1 - 64000 ))
	$SUDO "$HCI" raw 0x09 0x00 0x01 >/dev/null
	sleep 1
	# I2S out on PCM pins, 75 us de-emphasis
	fmw 0x05 0x006C
	$SUDO "$HCI" vsc 0x61 0x07 0x19 0x18 0x19 0x19 >/dev/null
}

fm_khz() {
	local h
	h=$($SUDO "$HCI" read 0x0A 2 | awk '{ if (NF >= 3) printf "%s%s", $3, $2 }')
	[ -n "$h" ] && echo $((16#$h + 64000))
}

fm_status() {
	printf 'freq=%s kHz  tune=0x%s  rssi=0x%s  snr=0x%s\n' \
		"$(fm_khz)" "$(fmr 0x12 1)" "$(fmr 0x0F 1)" "$(fmr 0xDF 1)"
}

amix() { $SUDO amixer -c $CARD cset numid="$1" "$2" >/dev/null 2>&1; }
mic_on() { $SUDO amixer -c $CARD cset name="$1" "$2" >/dev/null 2>&1; }

codec_path_on() {
	for n in 6 91 93 102 107 162 163 27; do
		amix "$n" on
	done
}

codec_route() {
	case "$OUT" in
	headphones)
		amix 29 on; amix 164 on; amix 165 on; amix 82 IF_ADC2
		amix 6 on; amix 93 on; amix 95 on; amix 104 on; amix 109 on
		;;
	*)
		amix 6 on; amix 82 DAC_REF; amix 162 on; amix 163 on
		amix 29 off; amix 164 off; amix 165 off
		;;
	esac
	mic_on "Int Mic Switch" on
	mic_on "RECMIX1L BST3 Switch" on
	mic_on "RECMIX1R BST4 Switch" on
	mic_on "STO1 ADC Capture Switch" on
	mic_on "Stereo1 ADC Source" ADC1
	mic_on "Stereo1 ADC1 Source" ADC
	mic_on "Stereo1 ADC MIXL ADC1 Switch" on
	mic_on "Stereo1 ADC MIXR ADC1 Switch" on
}

sink_ctl() {
	if ! pactl list short sinks | grep -qF "$SINK"; then
		pactl set-card-profile "$CARD_NAME" "$PROFILE"
		for _ in $(seq 40); do
			pactl list short sinks | grep -qF "$SINK" && break
			sleep 0.1
		done
	fi
	pactl set-sink-volume "$SINK" "${VOL}%"
	pactl set-sink-mute "$SINK" 0
}

loopback_on() {
	if ! pactl list short modules | grep -q 'module-loopback.*platform-sof_cht_rt5659'; then
		pactl load-module module-loopback source=$SRC sink=$SINK latency_msec=80 >/dev/null
	fi
}

loopback_off() {
	for id in $(pactl list short modules | awk '/module-loopback/ && /platform-sof_cht_rt5659/ {print $1}'); do
		pactl unload-module "$id"
	done
}

case ${1:-} in
--off)
	loopback_off
	$SUDO "$HCI" raw 0x00 0x00 0x00 >/dev/null
	echo "FM stopped"
	exit 0
	;;
--rebind)
	echo i2c-10EC5659:01 | $SUDO tee /sys/bus/i2c/drivers/rt5659/unbind >/dev/null
	echo i2c-10EC5659:01 | $SUDO tee /sys/bus/i2c/drivers/rt5659/bind >/dev/null
	sleep 1
	codec_path_on
	;;
--scan)
	fm_on
	printf '%-6s %-5s %-5s\n' MHz RSSI TUNE
	for k in $(seq 8750 100 10800); do
		fmw 0x0A $(( k - 64000 ))
		$SUDO "$HCI" raw 0x09 0x00 0x01 >/dev/null
		# wait for lock, then let RSSI/SNR settle before judging
		for _ in $(seq 1 12); do
			sleep 0.06
			t=$(fmr 0x12 1)
			[ -n "$t" ] && [ $(( 0x$t & 3 )) -eq 1 ] && break
		done
		sleep 0.25
		t=$(fmr 0x12 1); r=$(fmr 0x0F 1)
		[ -n "$t" ] && [ $(( 0x$t & 3 )) -eq 1 ] || continue
		[ -n "$r" ] && [ $(( 0x$r & 0x80 )) -ne 0 ] || continue
		dbu=$(( 0x$r & 0x7f ))
		[ "$dbu" -ge 30 ] && printf '%-6s %-5s %-5s\n' \
			"$((k/1000)).$(((k%1000)/100))" "$dbu" "$t"
	done
	exit 0
	;;
esac

FMKHZ=$(awk -v f="${1:-97.4}" 'BEGIN { printf "%d", f * 1000 + 0.5 }')
fm_on
fm_tune "$FMKHZ"
codec_path_on
codec_route
sink_ctl
loopback_on
fm_status
