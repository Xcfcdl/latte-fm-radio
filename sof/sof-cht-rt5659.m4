`# Topology for Xiaomi Mi Pad 2: playback on SSP2 (RT5659), capture on SSP1 (BCM4356 FM)'

include(`utils.m4')
include(`dai.m4')
include(`pipeline.m4')
include(`ssp.m4')

include(`common/tlv.m4')
include(`sof/tokens.m4')
include(`platform/intel/'PLATFORM`.m4')

#
# PCM0 playback -> SSP2 (RT5659) -> headphones
# PCM0 capture  <- SSP1 RX (BCM4356 FM)
# PCM1 playback -> SSP2 (deep buffer)
#

# Low Latency capture pipeline 2 on PCM 0
PIPELINE_PCM_ADD(sof/pipe-low-latency-capture.m4,
	2, 0, 2, s16le,
	1000, 0, 0,
	48000, 48000, 48000)

# playback DAI is SSP2 (codec)
DAI_ADD(sof/pipe-mixer-volume-dai-playback.m4,
	1, SSP, 2, SSP2-Codec,
	NOT_USED_IGNORED, 2, s16le,
	1000, 1, 0, SCHEDULE_TIME_DOMAIN_DMA,
	2, 48000)

# PCM Playback pipeline 3 on PCM 0
PIPELINE_PCM_ADD(sof/pipe-host-volume-playback.m4,
	3, 0, 2, s16le,
	1000, 0, 0,
	48000, 48000, 48000,
	SCHEDULE_TIME_DOMAIN_DMA,
	PIPELINE_PLAYBACK_SCHED_COMP_1)

# PCM Playback pipeline 4 on PCM 1 (deep buffer)
PIPELINE_PCM_ADD(sof/pipe-host-volume-playback.m4,
	4, 1, 2, s16le,
	10000, 0, 0,
	48000, 48000, 48000,
	SCHEDULE_TIME_DOMAIN_DMA,
	PIPELINE_PLAYBACK_SCHED_COMP_1)

SectionGraph."PIPE_NAME" {
	index "0"

	lines [
		dapm(PIPELINE_MIXER_1, PIPELINE_SOURCE_3)
		dapm(PIPELINE_MIXER_1, PIPELINE_SOURCE_4)
	]
}

# capture DAI is SSP1 (BCM4356 BT/FM PCM bus)
DAI_ADD(sof/pipe-dai-capture.m4,
	2, SSP, 1, SSP1-BTFM,
	PIPELINE_SINK_2, 2, s16le,
	1000, 0, 0, SCHEDULE_TIME_DOMAIN_DMA)

# PCM definitions
PCM_DUPLEX_ADD(PCM, 0, PIPELINE_PCM_3, PIPELINE_PCM_2)
PCM_PLAYBACK_ADD(PCM Deep Buffer, 1, PIPELINE_PCM_4)

#
# BE configurations
#
DAI_CONFIG(SSP, 2, 0, SSP2-Codec,
	   SSP_CONFIG(I2S, SSP_CLOCK(mclk, 19200000, codec_mclk_in),
		      SSP_CLOCK(bclk, 1920000, codec_slave),
		      SSP_CLOCK(fsync, 48000, codec_slave),
		      SSP_TDM(2, 20, 3, 3),
		      SSP_CONFIG_DATA(SSP, 2, 16)))

# FM: 2 x 20 bit @ 1.92 MHz (BCM4356 BT+FM frame), no internal loopback
DAI_CONFIG(SSP, 1, 1, SSP1-BTFM,
	   SSP_CONFIG(I2S, SSP_CLOCK(mclk, 19200000, codec_mclk_in),
		      SSP_CLOCK(bclk, 1920000, codec_slave),
		      SSP_CLOCK(fsync, 48000, codec_slave),
		      SSP_TDM(2, 20, 3, 3),
		      SSP_CONFIG_DATA(SSP, 1, 16, 0, 0)))

VIRTUAL_WIDGET(ssp1 Rx, out_drv, 3)
VIRTUAL_WIDGET(ssp1 Tx, out_drv, 4)
