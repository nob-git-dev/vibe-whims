#!/usr/bin/env python3
"""shooter_src.py — NES 縦スクロールシューター ROM ジェネレーター (Salamander 風)

変更点:
  - PPUSCROLL Y によるスクロール背景 (ネームテーブル星フィールド)
  - プレイヤー4方向移動 (PLR_Y 追加)
  - オートファイア (A ホールドで連射)
  - 敵ジグザグ移動 (ENM_OSC で振動)
  - ボスが敵弾を発射 (EBUL0/1)
  - 改良 CHR タイル
"""

import sys
import subprocess
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from tools.asm import Assembler

# ---------------------------------------------------------------------------
# ゼロページ定数
# ---------------------------------------------------------------------------
NMI_FLAG    = 0x00
GAME_STATE  = 0x01
FRAME       = 0x02
SHOOT_COOL  = 0x03
PAD_NOW     = 0x04
PAD_PREV    = 0x05
SPAWN_T     = 0x06
KILLS       = 0x07
BOSS_DIR    = 0x08
BOSS_T      = 0x09
BOSS_HP     = 0x0A
DEAD_TIMER  = 0x0B
SCROLL_Y    = 0x0C   # BG スクロール Y 位置
PLR_Y       = 0x0D   # プレイヤー Y 位置
ENM_SHOOT_T = 0x0E   # 敵弾発射タイマー
TEMP_T      = 0x0F   # 汎用テンポラリ (ネームテーブル初期化で使用)

PLR_X       = 0x14

BUL0_Y      = 0x15
BUL0_X      = 0x16
BUL0_ACT    = 0x17
BUL1_Y      = 0x18
BUL1_X      = 0x19
BUL1_ACT    = 0x1A
BUL2_Y      = 0x1B
BUL2_X      = 0x1C
BUL2_ACT    = 0x1D

ENM0_X      = 0x20
ENM0_Y      = 0x21
ENM0_ACT    = 0x22
ENM1_X      = 0x23
ENM1_Y      = 0x24
ENM1_ACT    = 0x25
ENM2_X      = 0x26
ENM2_Y      = 0x27
ENM2_ACT    = 0x28
ENM3_X      = 0x29
ENM3_Y      = 0x2A
ENM3_ACT    = 0x2B
ENM4_X      = 0x2C
ENM4_Y      = 0x2D
ENM4_ACT    = 0x2E

BOSS_X      = 0x30
BOSS_Y      = 0x31

# 敵振動カウンタ ($40-$44)
ENM0_OSC    = 0x40
ENM1_OSC    = 0x41
ENM2_OSC    = 0x42
ENM3_OSC    = 0x43
ENM4_OSC    = 0x44

# 敵弾 ($48-$4D)
EBUL0_Y     = 0x48
EBUL0_X     = 0x49
EBUL0_ACT   = 0x4A
EBUL1_Y     = 0x4B
EBUL1_X     = 0x4C
EBUL1_ACT   = 0x4D

# ---------------------------------------------------------------------------
# PRG-ROM アセンブル
# ---------------------------------------------------------------------------

a = Assembler(base=0x8000)

# ===========================================================================
# NMI ハンドラ
# ===========================================================================
a.label('NMI')
a.PHA()
a.TXA()
a.PHA()
a.TYA()
a.PHA()

# OAM DMA: $0200 → PPU OAM
a.LDA_IMM(0x00)
a.STA_ABS(0x2003)
a.LDA_IMM(0x02)
a.STA_ABS(0x4014)

# NMI_FLAG = 1
a.LDA_IMM(0x01)
a.STA_ZP(NMI_FLAG)

# SCROLL_Y をインクリメント (2px/frame)
a.LDA_ZP(SCROLL_Y)
a.CLC()
a.ADC_IMM(0x02)
a.CMP_IMM(0xF0)         # 240 に達したら折り返す
a.BCC('SCR_OK')
a.LDA_IMM(0x00)
a.label('SCR_OK')
a.STA_ZP(SCROLL_Y)

# PPUSCROLL 書き込み (アドレスラッチリセット → X → Y)
a.LDA_ABS(0x2002)       # ラッチリセット
a.LDA_IMM(0x00)
a.STA_ABS(0x2005)       # scroll X = 0
a.LDA_ZP(SCROLL_Y)
a.STA_ABS(0x2005)       # scroll Y = SCROLL_Y

a.PLA()
a.TAY()
a.PLA()
a.TAX()
a.PLA()
a.RTI()

# ===========================================================================
# IRQ ハンドラ
# ===========================================================================
a.label('IRQ')
a.RTI()

# ===========================================================================
# NT_INIT_SUB — ネームテーブル 1024 バイトを星フィールドで埋める
# 呼び出し前: PPUADDR を開始アドレスに設定しておくこと
# TEMP_T ($0F) を破壊する
# ===========================================================================
a.label('NT_INIT_SUB')
a.LDA_IMM(0x00)
a.STA_ZP(TEMP_T)        # ページカウンタ = 0
a.LDY_IMM(0x00)         # ページ番号 (0-3)
a.LDX_IMM(0x00)         # バイトインデックス (0-255)
a.label('NIS_PAGE')
a.label('NIS_BYTE')
# 星判定: (X + TEMP_T) AND $07 == $03
a.TXA()
a.CLC()
a.ADC_ZP(TEMP_T)
a.AND_IMM(0x07)
a.CMP_IMM(0x03)
a.BEQ('NIS_STAR')
a.LDA_IMM(0x00)
a.JMP('NIS_WRITE')
a.label('NIS_STAR')
a.LDA_IMM(0x01)
a.label('NIS_WRITE')
a.STA_ABS(0x2007)
a.INX()
a.BNE('NIS_BYTE')
# 256 バイト完了, 次ページへ
a.INC_ZP(TEMP_T)
a.INY()
a.CPY_IMM(0x04)         # 4 ページ = 1024 バイト
a.BNE('NIS_PAGE')
a.RTS()

# ===========================================================================
# RESET — 初期化
# ===========================================================================
a.label('RESET')
a.SEI()
a.CLD()
a.LDX_IMM(0xFF)
a.TXS()

# 最初の VBlank 待機
a.label('VWAIT1')
a.BIT_ABS(0x2002)
a.BPL('VWAIT1')

# PPU を無効化
a.LDA_IMM(0x00)
a.STA_ABS(0x2000)
a.STA_ABS(0x2001)

# 2 番目の VBlank 待機
a.label('VWAIT2')
a.BIT_ABS(0x2002)
a.BPL('VWAIT2')

# パレット設定 ($3F00-$3F1F)
a.LDA_ABS(0x2002)
a.LDA_IMM(0x3F)
a.STA_ABS(0x2006)
a.LDA_IMM(0x00)
a.STA_ABS(0x2006)
# BG パレット0: 黒 / 白 / 灰 / 黒
a.LDA_IMM(0x0F); a.STA_ABS(0x2007)
a.LDA_IMM(0x30); a.STA_ABS(0x2007)
a.LDA_IMM(0x10); a.STA_ABS(0x2007)
a.LDA_IMM(0x0F); a.STA_ABS(0x2007)
# BG パレット1
a.LDA_IMM(0x0F); a.STA_ABS(0x2007)
a.LDA_IMM(0x30); a.STA_ABS(0x2007)
a.LDA_IMM(0x10); a.STA_ABS(0x2007)
a.LDA_IMM(0x0F); a.STA_ABS(0x2007)
# BG パレット2
a.LDA_IMM(0x0F); a.STA_ABS(0x2007)
a.LDA_IMM(0x30); a.STA_ABS(0x2007)
a.LDA_IMM(0x10); a.STA_ABS(0x2007)
a.LDA_IMM(0x0F); a.STA_ABS(0x2007)
# BG パレット3
a.LDA_IMM(0x0F); a.STA_ABS(0x2007)
a.LDA_IMM(0x30); a.STA_ABS(0x2007)
a.LDA_IMM(0x10); a.STA_ABS(0x2007)
a.LDA_IMM(0x0F); a.STA_ABS(0x2007)
# スプライトパレット0: プレイヤー (黒 / 白 / 黄 / 緑)
a.LDA_IMM(0x0F); a.STA_ABS(0x2007)
a.LDA_IMM(0x30); a.STA_ABS(0x2007)
a.LDA_IMM(0x28); a.STA_ABS(0x2007)
a.LDA_IMM(0x19); a.STA_ABS(0x2007)
# スプライトパレット1: 弾 / 敵弾 (黒 / 赤 / オレンジ / 黄)
a.LDA_IMM(0x0F); a.STA_ABS(0x2007)
a.LDA_IMM(0x16); a.STA_ABS(0x2007)
a.LDA_IMM(0x27); a.STA_ABS(0x2007)
a.LDA_IMM(0x28); a.STA_ABS(0x2007)
# スプライトパレット2: ボス (黒 / 青 / 明青 / 紫)
a.LDA_IMM(0x0F); a.STA_ABS(0x2007)
a.LDA_IMM(0x02); a.STA_ABS(0x2007)
a.LDA_IMM(0x12); a.STA_ABS(0x2007)
a.LDA_IMM(0x22); a.STA_ABS(0x2007)
# スプライトパレット3: 敵 (黒 / 赤 / ピンク / 白)
a.LDA_IMM(0x0F); a.STA_ABS(0x2007)
a.LDA_IMM(0x16); a.STA_ABS(0x2007)
a.LDA_IMM(0x25); a.STA_ABS(0x2007)
a.LDA_IMM(0x30); a.STA_ABS(0x2007)

# OAM $0200-$02FF を $FF で初期化
a.LDA_IMM(0xFF)
a.LDX_IMM(0x00)
a.label('OAM_INIT_LOOP')
a.STA_ABX(0x0200)
a.INX()
a.BNE('OAM_INIT_LOOP')

# ネームテーブル NT0 ($2000) を初期化
a.LDA_ABS(0x2002)
a.LDA_IMM(0x20); a.STA_ABS(0x2006)
a.LDA_IMM(0x00); a.STA_ABS(0x2006)
a.JSR('NT_INIT_SUB')

# ネームテーブル NT2 ($2800) を初期化 (シームレスラップ用)
a.LDA_ABS(0x2002)
a.LDA_IMM(0x28); a.STA_ABS(0x2006)
a.LDA_IMM(0x00); a.STA_ABS(0x2006)
a.JSR('NT_INIT_SUB')

# ゼロページ変数の初期化
a.LDA_IMM(0x00)
a.STA_ZP(NMI_FLAG)
a.STA_ZP(GAME_STATE)
a.STA_ZP(FRAME)
a.STA_ZP(SHOOT_COOL)
a.STA_ZP(PAD_NOW)
a.STA_ZP(PAD_PREV)
a.STA_ZP(KILLS)
a.STA_ZP(BOSS_DIR)
a.STA_ZP(DEAD_TIMER)
a.STA_ZP(SCROLL_Y)
a.STA_ZP(BUL0_ACT)
a.STA_ZP(BUL1_ACT)
a.STA_ZP(BUL2_ACT)
a.STA_ZP(ENM0_ACT)
a.STA_ZP(ENM1_ACT)
a.STA_ZP(ENM2_ACT)
a.STA_ZP(ENM3_ACT)
a.STA_ZP(ENM4_ACT)
a.STA_ZP(ENM0_OSC)
a.STA_ZP(ENM1_OSC)
a.STA_ZP(ENM2_OSC)
a.STA_ZP(ENM3_OSC)
a.STA_ZP(ENM4_OSC)
a.STA_ZP(EBUL0_ACT)
a.STA_ZP(EBUL1_ACT)

# スポーンタイマー
a.LDA_IMM(0x28)         # 40 フレーム
a.STA_ZP(SPAWN_T)

# ボス HP / BOSS_T
a.LDA_IMM(0x64)
a.STA_ZP(BOSS_HP)
a.LDA_IMM(0x20)
a.STA_ZP(BOSS_T)

# 敵弾タイマー
a.LDA_IMM(0x5A)         # 90 フレーム
a.STA_ZP(ENM_SHOOT_T)

# プレイヤー初期位置
a.LDA_IMM(0x78)
a.STA_ZP(PLR_X)
a.LDA_IMM(0xC0)         # Y: 画面下部
a.STA_ZP(PLR_Y)

# ボス初期位置
a.LDA_IMM(0x70); a.STA_ZP(BOSS_X)
a.LDA_IMM(0x20); a.STA_ZP(BOSS_Y)

# OAM 固定値設定 ─────────────────────────────
# プレイヤー: tile=0x02, attr=0x00
a.LDA_IMM(0x02); a.STA_ABS(0x0201)
a.LDA_IMM(0x00); a.STA_ABS(0x0202)

# 敵弾0: tile=0x09, attr=0x01 (palette1=赤)
a.LDA_IMM(0x09); a.STA_ABS(0x0205)
a.LDA_IMM(0x01); a.STA_ABS(0x0206)

# 敵弾1: tile=0x09, attr=0x01
a.LDA_IMM(0x09); a.STA_ABS(0x0209)
a.LDA_IMM(0x01); a.STA_ABS(0x020A)

# プレイヤー弾: tile=0x03, attr=0x00
a.LDA_IMM(0x03); a.STA_ABS(0x0215)
a.LDA_IMM(0x00); a.STA_ABS(0x0216)
a.LDA_IMM(0x03); a.STA_ABS(0x0219)
a.LDA_IMM(0x00); a.STA_ABS(0x021A)
a.LDA_IMM(0x03); a.STA_ABS(0x021D)
a.LDA_IMM(0x00); a.STA_ABS(0x021E)

# 敵: tile=0x04, attr=0x03 (palette3=赤系)
a.LDA_IMM(0x04); a.STA_ABS(0x0221)
a.LDA_IMM(0x03); a.STA_ABS(0x0222)
a.LDA_IMM(0x04); a.STA_ABS(0x0225)
a.LDA_IMM(0x03); a.STA_ABS(0x0226)
a.LDA_IMM(0x04); a.STA_ABS(0x0229)
a.LDA_IMM(0x03); a.STA_ABS(0x022A)
a.LDA_IMM(0x04); a.STA_ABS(0x022D)
a.LDA_IMM(0x03); a.STA_ABS(0x022E)
a.LDA_IMM(0x04); a.STA_ABS(0x0231)
a.LDA_IMM(0x03); a.STA_ABS(0x0232)

# ボス: tile=0x05-0x08, attr=0x02 (palette2=青)
a.LDA_IMM(0x05); a.STA_ABS(0x0235)
a.LDA_IMM(0x02); a.STA_ABS(0x0236)
a.LDA_IMM(0x06); a.STA_ABS(0x0239)
a.LDA_IMM(0x02); a.STA_ABS(0x023A)
a.LDA_IMM(0x07); a.STA_ABS(0x023D)
a.LDA_IMM(0x02); a.STA_ABS(0x023E)
a.LDA_IMM(0x08); a.STA_ABS(0x0241)
a.LDA_IMM(0x02); a.STA_ABS(0x0242)

# PPU を有効化
a.LDA_IMM(0x80)         # PPUCTRL: NMI有効, BG PT0
a.STA_ABS(0x2000)
a.LDA_IMM(0x1E)         # PPUMASK: BG+スプライト表示
a.STA_ABS(0x2001)

a.JMP('MAIN_LOOP')

# ===========================================================================
# MAIN_LOOP
# ===========================================================================
a.label('MAIN_LOOP')
a.LDA_ZP(NMI_FLAG)
a.BEQ('MAIN_LOOP')
a.LDA_IMM(0x00)
a.STA_ZP(NMI_FLAG)

a.INC_ZP(FRAME)
a.JSR('READ_CTRL')

a.LDA_ZP(GAME_STATE)
a.CMP_IMM(0x02)
a.BEQ('STATE_WIN')
a.CMP_IMM(0x03)
a.BEQ('STATE_DEAD')
a.CMP_IMM(0x01)
a.BEQ('STATE_BOSS')

# --- STATE_PLAYING ---
a.JSR('UPDATE_PLR')
a.JSR('HANDLE_SHOOT')
a.JSR('UPDATE_BULLETS')
a.JSR('UPDATE_ENEMIES')
a.JSR('UPDATE_EBULLETS')
a.JSR('BUL_HIT_ENM')
a.JSR('PLR_HIT_ENM')
a.JSR('PLR_HIT_EBULLETS')
a.JSR('UPDATE_OAM_PLR')
a.JSR('UPDATE_OAM_ENM')
a.JSR('UPDATE_OAM_BOSS_OFF')
a.JSR('UPDATE_OAM_EBULLETS')
a.JSR('UPDATE_OAM_BULLETS')
a.JSR('SHOOT_COOL_DEC')
a.JMP('MAIN_LOOP')

a.label('STATE_BOSS')
a.JSR('UPDATE_PLR')
a.JSR('HANDLE_SHOOT')
a.JSR('UPDATE_BULLETS')
a.JSR('UPDATE_BOSS')
a.JSR('UPDATE_EBULLETS')
a.JSR('BUL_HIT_BOSS')
a.JSR('PLR_HIT_BOSS')
a.JSR('PLR_HIT_EBULLETS')
a.JSR('UPDATE_OAM_PLR')
a.JSR('UPDATE_OAM_ENM_OFF')
a.JSR('UPDATE_OAM_BOSS_ON')
a.JSR('UPDATE_OAM_EBULLETS')
a.JSR('UPDATE_OAM_BULLETS')
a.JSR('SHOOT_COOL_DEC')
a.JMP('MAIN_LOOP')

a.label('STATE_WIN')
a.JSR('ALL_SPRITES_OFF')
a.JMP('MAIN_LOOP')

a.label('STATE_DEAD')
a.DEC_ZP(DEAD_TIMER)
a.BNE('DEAD_WAITING')
a.JSR('GAME_RESTART')
a.JMP('MAIN_LOOP')
a.label('DEAD_WAITING')
a.JSR('ALL_SPRITES_OFF')
a.JMP('MAIN_LOOP')

# ===========================================================================
# SHOOT_COOL_DEC
# ===========================================================================
a.label('SHOOT_COOL_DEC')
a.LDA_ZP(SHOOT_COOL)
a.BEQ('SCOOL_DONE')
a.DEC_ZP(SHOOT_COOL)
a.label('SCOOL_DONE')
a.RTS()

# ===========================================================================
# ALL_SPRITES_OFF
# ===========================================================================
a.label('ALL_SPRITES_OFF')
a.LDA_IMM(0xFF)
a.STA_ABS(0x0200)
a.STA_ABS(0x0204)
a.STA_ABS(0x0208)
a.STA_ABS(0x020C)
a.STA_ABS(0x0210)
a.STA_ABS(0x0214)
a.STA_ABS(0x0218)
a.STA_ABS(0x021C)
a.STA_ABS(0x0220)
a.STA_ABS(0x0224)
a.STA_ABS(0x0228)
a.STA_ABS(0x022C)
a.STA_ABS(0x0230)
a.STA_ABS(0x0234)
a.STA_ABS(0x0238)
a.STA_ABS(0x023C)
a.STA_ABS(0x0240)
a.RTS()

# ===========================================================================
# READ_CTRL
# ===========================================================================
a.label('READ_CTRL')
a.LDA_ZP(PAD_NOW)
a.STA_ZP(PAD_PREV)
a.LDA_IMM(0x01); a.STA_ABS(0x4016)
a.LDA_IMM(0x00); a.STA_ABS(0x4016)
a.LDA_IMM(0x00); a.STA_ZP(PAD_NOW)
# bit0: A
a.LDA_ABS(0x4016); a.AND_IMM(0x01); a.ORA_ZP(PAD_NOW); a.STA_ZP(PAD_NOW)
# bit1: B
a.LDA_ABS(0x4016); a.AND_IMM(0x01); a.ASL_ACC(); a.ORA_ZP(PAD_NOW); a.STA_ZP(PAD_NOW)
# bit2: Select
a.LDA_ABS(0x4016); a.AND_IMM(0x01)
a.ASL_ACC(); a.ASL_ACC()
a.ORA_ZP(PAD_NOW); a.STA_ZP(PAD_NOW)
# bit3: Start
a.LDA_ABS(0x4016); a.AND_IMM(0x01)
a.ASL_ACC(); a.ASL_ACC(); a.ASL_ACC()
a.ORA_ZP(PAD_NOW); a.STA_ZP(PAD_NOW)
# bit4: Up
a.LDA_ABS(0x4016); a.AND_IMM(0x01)
a.ASL_ACC(); a.ASL_ACC(); a.ASL_ACC(); a.ASL_ACC()
a.ORA_ZP(PAD_NOW); a.STA_ZP(PAD_NOW)
# bit5: Down
a.LDA_ABS(0x4016); a.AND_IMM(0x01)
a.ASL_ACC(); a.ASL_ACC(); a.ASL_ACC(); a.ASL_ACC(); a.ASL_ACC()
a.ORA_ZP(PAD_NOW); a.STA_ZP(PAD_NOW)
# bit6: Left
a.LDA_ABS(0x4016); a.AND_IMM(0x01)
a.ASL_ACC(); a.ASL_ACC(); a.ASL_ACC(); a.ASL_ACC(); a.ASL_ACC(); a.ASL_ACC()
a.ORA_ZP(PAD_NOW); a.STA_ZP(PAD_NOW)
# bit7: Right
a.LDA_ABS(0x4016); a.AND_IMM(0x01)
a.ASL_ACC(); a.ASL_ACC(); a.ASL_ACC(); a.ASL_ACC()
a.ASL_ACC(); a.ASL_ACC(); a.ASL_ACC()
a.ORA_ZP(PAD_NOW); a.STA_ZP(PAD_NOW)
a.RTS()

# ===========================================================================
# UPDATE_PLR — プレイヤー4方向移動
# ===========================================================================
a.label('UPDATE_PLR')
# Up: bit4 = 0x10
a.LDA_ZP(PAD_NOW)
a.AND_IMM(0x10)
a.BEQ('PLR_CHK_DOWN')
a.LDA_ZP(PLR_Y)
a.SEC()
a.SBC_IMM(0x02)
a.CMP_IMM(0x20)         # 上限 Y=0x20
a.BCS('PLR_UP_OK')
a.LDA_IMM(0x20)
a.label('PLR_UP_OK')
a.STA_ZP(PLR_Y)

a.label('PLR_CHK_DOWN')
# Down: bit5 = 0x20
a.LDA_ZP(PAD_NOW)
a.AND_IMM(0x20)
a.BEQ('PLR_CHK_LEFT')
a.LDA_ZP(PLR_Y)
a.CLC()
a.ADC_IMM(0x02)
a.CMP_IMM(0xD0)         # 下限 Y=0xD0
a.BCC('PLR_DOWN_OK')
a.LDA_IMM(0xD0)
a.label('PLR_DOWN_OK')
a.STA_ZP(PLR_Y)

a.label('PLR_CHK_LEFT')
# Left: bit6 = 0x40
a.LDA_ZP(PAD_NOW)
a.AND_IMM(0x40)
a.BEQ('PLR_CHK_RIGHT')
a.LDA_ZP(PLR_X)
a.SEC()
a.SBC_IMM(0x02)
a.CMP_IMM(0x08)
a.BCS('PLR_LEFT_OK')
a.LDA_IMM(0x08)
a.label('PLR_LEFT_OK')
a.STA_ZP(PLR_X)

a.label('PLR_CHK_RIGHT')
# Right: bit7 = 0x80
a.LDA_ZP(PAD_NOW)
a.AND_IMM(0x80)
a.BEQ('PLR_MOVE_DONE')
a.LDA_ZP(PLR_X)
a.CLC()
a.ADC_IMM(0x02)
a.CMP_IMM(0xE8)
a.BCC('PLR_RIGHT_OK')
a.LDA_IMM(0xE8)
a.label('PLR_RIGHT_OK')
a.STA_ZP(PLR_X)

a.label('PLR_MOVE_DONE')
a.RTS()

# ===========================================================================
# HANDLE_SHOOT — A ボタン長押しでオートファイア
# ===========================================================================
a.label('HANDLE_SHOOT')
# A ボタン (bit0) が押されていること
a.LDA_ZP(PAD_NOW)
a.AND_IMM(0x01)
a.BEQ('SHOOT_DONE')
# クールダウンチェック
a.LDA_ZP(SHOOT_COOL)
a.BNE('SHOOT_DONE')
# 空きスロットを探す
a.LDA_ZP(BUL0_ACT)
a.BNE('TRY_BUL1')
a.LDA_IMM(0x01); a.STA_ZP(BUL0_ACT)
a.LDA_ZP(PLR_Y); a.SEC(); a.SBC_IMM(0x08); a.STA_ZP(BUL0_Y)
a.LDA_ZP(PLR_X); a.STA_ZP(BUL0_X)
a.LDA_IMM(0x08); a.STA_ZP(SHOOT_COOL)
a.JMP('SHOOT_DONE')
a.label('TRY_BUL1')
a.LDA_ZP(BUL1_ACT)
a.BNE('TRY_BUL2')
a.LDA_IMM(0x01); a.STA_ZP(BUL1_ACT)
a.LDA_ZP(PLR_Y); a.SEC(); a.SBC_IMM(0x08); a.STA_ZP(BUL1_Y)
a.LDA_ZP(PLR_X); a.STA_ZP(BUL1_X)
a.LDA_IMM(0x08); a.STA_ZP(SHOOT_COOL)
a.JMP('SHOOT_DONE')
a.label('TRY_BUL2')
a.LDA_ZP(BUL2_ACT)
a.BNE('SHOOT_DONE')
a.LDA_IMM(0x01); a.STA_ZP(BUL2_ACT)
a.LDA_ZP(PLR_Y); a.SEC(); a.SBC_IMM(0x08); a.STA_ZP(BUL2_Y)
a.LDA_ZP(PLR_X); a.STA_ZP(BUL2_X)
a.LDA_IMM(0x08); a.STA_ZP(SHOOT_COOL)
a.label('SHOOT_DONE')
a.RTS()

# ===========================================================================
# UPDATE_BULLETS — プレイヤー弾を 4px 上に動かす
# ===========================================================================
a.label('UPDATE_BULLETS')
# Bullet0
a.LDA_ZP(BUL0_ACT)
a.BEQ('UPD_BUL1')
a.LDA_ZP(BUL0_Y)
a.SEC(); a.SBC_IMM(0x04)
a.CMP_IMM(0x08)
a.BCS('BUL0_OK')
a.LDA_IMM(0x00); a.STA_ZP(BUL0_ACT)
a.JMP('UPD_BUL1')
a.label('BUL0_OK')
a.STA_ZP(BUL0_Y)
a.label('UPD_BUL1')
# Bullet1
a.LDA_ZP(BUL1_ACT)
a.BEQ('UPD_BUL2')
a.LDA_ZP(BUL1_Y)
a.SEC(); a.SBC_IMM(0x04)
a.CMP_IMM(0x08)
a.BCS('BUL1_OK')
a.LDA_IMM(0x00); a.STA_ZP(BUL1_ACT)
a.JMP('UPD_BUL2')
a.label('BUL1_OK')
a.STA_ZP(BUL1_Y)
a.label('UPD_BUL2')
# Bullet2
a.LDA_ZP(BUL2_ACT)
a.BEQ('UPD_BUL_DONE')
a.LDA_ZP(BUL2_Y)
a.SEC(); a.SBC_IMM(0x04)
a.CMP_IMM(0x08)
a.BCS('BUL2_OK')
a.LDA_IMM(0x00); a.STA_ZP(BUL2_ACT)
a.JMP('UPD_BUL_DONE')
a.label('BUL2_OK')
a.STA_ZP(BUL2_Y)
a.label('UPD_BUL_DONE')
a.RTS()

# ===========================================================================
# UPDATE_ENEMIES — 敵をジグザグ移動 + スポーン管理
# ===========================================================================
a.label('UPDATE_ENEMIES')

# Enemy0
a.LDA_ZP(ENM0_ACT)
a.BEQ('UPD_ENM1')
# X ジグザグ: OSC の bit4 で方向決定
a.INC_ZP(ENM0_OSC)
a.LDA_ZP(ENM0_OSC)
a.AND_IMM(0x10)
a.BNE('ENM0_ZAG')
a.LDA_ZP(ENM0_X); a.CLC(); a.ADC_IMM(0x01)
a.CMP_IMM(0xE8); a.BCC('ENM0_X_OK')
a.LDA_IMM(0xE8)
a.label('ENM0_X_OK'); a.STA_ZP(ENM0_X)
a.JMP('ENM0_Y')
a.label('ENM0_ZAG')
a.LDA_ZP(ENM0_X); a.SEC(); a.SBC_IMM(0x01)
a.CMP_IMM(0x08); a.BCS('ENM0_XL_OK')
a.LDA_IMM(0x08)
a.label('ENM0_XL_OK'); a.STA_ZP(ENM0_X)
a.label('ENM0_Y')
# Y 移動: 1px 下
a.LDA_ZP(ENM0_Y); a.CLC(); a.ADC_IMM(0x01)
a.CMP_IMM(0xF0)
a.BCC('ENM0_Y_OK')
a.LDA_IMM(0x00); a.STA_ZP(ENM0_ACT)
a.JMP('UPD_ENM1')
a.label('ENM0_Y_OK'); a.STA_ZP(ENM0_Y)

a.label('UPD_ENM1')
# Enemy1
a.LDA_ZP(ENM1_ACT)
a.BEQ('UPD_ENM2')
a.INC_ZP(ENM1_OSC)
a.LDA_ZP(ENM1_OSC)
a.AND_IMM(0x10)
a.BNE('ENM1_ZAG')
a.LDA_ZP(ENM1_X); a.CLC(); a.ADC_IMM(0x01)
a.CMP_IMM(0xE8); a.BCC('ENM1_X_OK')
a.LDA_IMM(0xE8)
a.label('ENM1_X_OK'); a.STA_ZP(ENM1_X)
a.JMP('ENM1_Y')
a.label('ENM1_ZAG')
a.LDA_ZP(ENM1_X); a.SEC(); a.SBC_IMM(0x01)
a.CMP_IMM(0x08); a.BCS('ENM1_XL_OK')
a.LDA_IMM(0x08)
a.label('ENM1_XL_OK'); a.STA_ZP(ENM1_X)
a.label('ENM1_Y')
a.LDA_ZP(ENM1_Y); a.CLC(); a.ADC_IMM(0x01)
a.CMP_IMM(0xF0)
a.BCC('ENM1_Y_OK')
a.LDA_IMM(0x00); a.STA_ZP(ENM1_ACT)
a.JMP('UPD_ENM2')
a.label('ENM1_Y_OK'); a.STA_ZP(ENM1_Y)

a.label('UPD_ENM2')
# Enemy2
a.LDA_ZP(ENM2_ACT)
a.BEQ('UPD_ENM3')
a.INC_ZP(ENM2_OSC)
a.LDA_ZP(ENM2_OSC)
a.AND_IMM(0x10)
a.BNE('ENM2_ZAG')
a.LDA_ZP(ENM2_X); a.CLC(); a.ADC_IMM(0x01)
a.CMP_IMM(0xE8); a.BCC('ENM2_X_OK')
a.LDA_IMM(0xE8)
a.label('ENM2_X_OK'); a.STA_ZP(ENM2_X)
a.JMP('ENM2_Y')
a.label('ENM2_ZAG')
a.LDA_ZP(ENM2_X); a.SEC(); a.SBC_IMM(0x01)
a.CMP_IMM(0x08); a.BCS('ENM2_XL_OK')
a.LDA_IMM(0x08)
a.label('ENM2_XL_OK'); a.STA_ZP(ENM2_X)
a.label('ENM2_Y')
a.LDA_ZP(ENM2_Y); a.CLC(); a.ADC_IMM(0x01)
a.CMP_IMM(0xF0)
a.BCC('ENM2_Y_OK')
a.LDA_IMM(0x00); a.STA_ZP(ENM2_ACT)
a.JMP('UPD_ENM3')
a.label('ENM2_Y_OK'); a.STA_ZP(ENM2_Y)

a.label('UPD_ENM3')
# Enemy3
a.LDA_ZP(ENM3_ACT)
a.BEQ('UPD_ENM4')
a.INC_ZP(ENM3_OSC)
a.LDA_ZP(ENM3_OSC)
a.AND_IMM(0x10)
a.BNE('ENM3_ZAG')
a.LDA_ZP(ENM3_X); a.CLC(); a.ADC_IMM(0x01)
a.CMP_IMM(0xE8); a.BCC('ENM3_X_OK')
a.LDA_IMM(0xE8)
a.label('ENM3_X_OK'); a.STA_ZP(ENM3_X)
a.JMP('ENM3_Y')
a.label('ENM3_ZAG')
a.LDA_ZP(ENM3_X); a.SEC(); a.SBC_IMM(0x01)
a.CMP_IMM(0x08); a.BCS('ENM3_XL_OK')
a.LDA_IMM(0x08)
a.label('ENM3_XL_OK'); a.STA_ZP(ENM3_X)
a.label('ENM3_Y')
a.LDA_ZP(ENM3_Y); a.CLC(); a.ADC_IMM(0x01)
a.CMP_IMM(0xF0)
a.BCC('ENM3_Y_OK')
a.LDA_IMM(0x00); a.STA_ZP(ENM3_ACT)
a.JMP('UPD_ENM4')
a.label('ENM3_Y_OK'); a.STA_ZP(ENM3_Y)

a.label('UPD_ENM4')
# Enemy4
a.LDA_ZP(ENM4_ACT)
a.BEQ('UPD_ENM_SPAWN')
a.INC_ZP(ENM4_OSC)
a.LDA_ZP(ENM4_OSC)
a.AND_IMM(0x10)
a.BNE('ENM4_ZAG')
a.LDA_ZP(ENM4_X); a.CLC(); a.ADC_IMM(0x01)
a.CMP_IMM(0xE8); a.BCC('ENM4_X_OK')
a.LDA_IMM(0xE8)
a.label('ENM4_X_OK'); a.STA_ZP(ENM4_X)
a.JMP('ENM4_Y')
a.label('ENM4_ZAG')
a.LDA_ZP(ENM4_X); a.SEC(); a.SBC_IMM(0x01)
a.CMP_IMM(0x08); a.BCS('ENM4_XL_OK')
a.LDA_IMM(0x08)
a.label('ENM4_XL_OK'); a.STA_ZP(ENM4_X)
a.label('ENM4_Y')
a.LDA_ZP(ENM4_Y); a.CLC(); a.ADC_IMM(0x01)
a.CMP_IMM(0xF0)
a.BCC('ENM4_Y_OK')
a.LDA_IMM(0x00); a.STA_ZP(ENM4_ACT)
a.JMP('UPD_ENM_SPAWN')
a.label('ENM4_Y_OK'); a.STA_ZP(ENM4_Y)

# スポーンタイマー
a.label('UPD_ENM_SPAWN')
a.DEC_ZP(SPAWN_T)
a.BNE('UPD_ENM_DONE')
a.LDA_IMM(0x28)
a.STA_ZP(SPAWN_T)
a.JSR('SPAWN_ENEMY')
a.label('UPD_ENM_DONE')
a.RTS()

# ===========================================================================
# SPAWN_ENEMY
# ===========================================================================
a.label('SPAWN_ENEMY')
a.LDA_ZP(ENM0_ACT)
a.BNE('SP_TRY1')
a.LDA_ZP(FRAME); a.EOR_IMM(0xA5); a.AND_IMM(0xC0); a.CLC(); a.ADC_IMM(0x18)
a.STA_ZP(ENM0_X)
a.LDA_IMM(0x00); a.STA_ZP(ENM0_Y); a.STA_ZP(ENM0_OSC)
a.LDA_IMM(0x01); a.STA_ZP(ENM0_ACT)
a.RTS()
a.label('SP_TRY1')
a.LDA_ZP(ENM1_ACT)
a.BNE('SP_TRY2')
a.LDA_ZP(FRAME); a.EOR_IMM(0xB3); a.AND_IMM(0xC0); a.CLC(); a.ADC_IMM(0x18)
a.STA_ZP(ENM1_X)
a.LDA_IMM(0x00); a.STA_ZP(ENM1_Y); a.STA_ZP(ENM1_OSC)
a.LDA_IMM(0x01); a.STA_ZP(ENM1_ACT)
a.RTS()
a.label('SP_TRY2')
a.LDA_ZP(ENM2_ACT)
a.BNE('SP_TRY3')
a.LDA_ZP(FRAME); a.EOR_IMM(0xC7); a.AND_IMM(0xC0); a.CLC(); a.ADC_IMM(0x18)
a.STA_ZP(ENM2_X)
a.LDA_IMM(0x00); a.STA_ZP(ENM2_Y); a.STA_ZP(ENM2_OSC)
a.LDA_IMM(0x01); a.STA_ZP(ENM2_ACT)
a.RTS()
a.label('SP_TRY3')
a.LDA_ZP(ENM3_ACT)
a.BNE('SP_TRY4')
a.LDA_ZP(FRAME); a.EOR_IMM(0xD9); a.AND_IMM(0xC0); a.CLC(); a.ADC_IMM(0x18)
a.STA_ZP(ENM3_X)
a.LDA_IMM(0x00); a.STA_ZP(ENM3_Y); a.STA_ZP(ENM3_OSC)
a.LDA_IMM(0x01); a.STA_ZP(ENM3_ACT)
a.RTS()
a.label('SP_TRY4')
a.LDA_ZP(ENM4_ACT)
a.BNE('SP_DONE')
a.LDA_ZP(FRAME); a.EOR_IMM(0xE1); a.AND_IMM(0xC0); a.CLC(); a.ADC_IMM(0x18)
a.STA_ZP(ENM4_X)
a.LDA_IMM(0x00); a.STA_ZP(ENM4_Y); a.STA_ZP(ENM4_OSC)
a.LDA_IMM(0x01); a.STA_ZP(ENM4_ACT)
a.label('SP_DONE')
a.RTS()

# ===========================================================================
# UPDATE_EBULLETS — 敵弾を 3px 下に動かす
# ===========================================================================
a.label('UPDATE_EBULLETS')
# EBUL0
a.LDA_ZP(EBUL0_ACT)
a.BEQ('UEBUL1')
a.LDA_ZP(EBUL0_Y); a.CLC(); a.ADC_IMM(0x03)
a.CMP_IMM(0xF0)
a.BCC('EBUL0_OK')
a.LDA_IMM(0x00); a.STA_ZP(EBUL0_ACT)
a.JMP('UEBUL1')
a.label('EBUL0_OK')
a.STA_ZP(EBUL0_Y)
a.label('UEBUL1')
# EBUL1
a.LDA_ZP(EBUL1_ACT)
a.BEQ('UEBUL_DONE')
a.LDA_ZP(EBUL1_Y); a.CLC(); a.ADC_IMM(0x03)
a.CMP_IMM(0xF0)
a.BCC('EBUL1_OK')
a.LDA_IMM(0x00); a.STA_ZP(EBUL1_ACT)
a.JMP('UEBUL_DONE')
a.label('EBUL1_OK')
a.STA_ZP(EBUL1_Y)
a.label('UEBUL_DONE')
a.RTS()

# ===========================================================================
# BUL_HIT_ENM — プレイヤー弾 vs 敵 衝突チェック
# ===========================================================================
a.label('BUL_HIT_ENM')
# Bullet0 vs Enemy0
a.LDA_ZP(BUL0_ACT); a.BEQ('BHE_B0E1')
a.LDA_ZP(ENM0_ACT); a.BEQ('BHE_B0E1')
a.CLC(); a.LDA_ZP(BUL0_X); a.ADC_IMM(0x08); a.CMP_ZP(ENM0_X); a.BCC('BHE_B0E1')
a.CLC(); a.LDA_ZP(ENM0_X); a.ADC_IMM(0x08); a.CMP_ZP(BUL0_X); a.BCC('BHE_B0E1')
a.CLC(); a.LDA_ZP(BUL0_Y); a.ADC_IMM(0x08); a.CMP_ZP(ENM0_Y); a.BCC('BHE_B0E1')
a.CLC(); a.LDA_ZP(ENM0_Y); a.ADC_IMM(0x08); a.CMP_ZP(BUL0_Y); a.BCC('BHE_B0E1')
a.LDA_IMM(0x00); a.STA_ZP(BUL0_ACT); a.STA_ZP(ENM0_ACT)
a.INC_ZP(KILLS); a.JSR('CHECK_BOSS_TRIGGER')

a.label('BHE_B0E1')
a.LDA_ZP(BUL0_ACT); a.BEQ('BHE_B0E2')
a.LDA_ZP(ENM1_ACT); a.BEQ('BHE_B0E2')
a.CLC(); a.LDA_ZP(BUL0_X); a.ADC_IMM(0x08); a.CMP_ZP(ENM1_X); a.BCC('BHE_B0E2')
a.CLC(); a.LDA_ZP(ENM1_X); a.ADC_IMM(0x08); a.CMP_ZP(BUL0_X); a.BCC('BHE_B0E2')
a.CLC(); a.LDA_ZP(BUL0_Y); a.ADC_IMM(0x08); a.CMP_ZP(ENM1_Y); a.BCC('BHE_B0E2')
a.CLC(); a.LDA_ZP(ENM1_Y); a.ADC_IMM(0x08); a.CMP_ZP(BUL0_Y); a.BCC('BHE_B0E2')
a.LDA_IMM(0x00); a.STA_ZP(BUL0_ACT); a.STA_ZP(ENM1_ACT)
a.INC_ZP(KILLS); a.JSR('CHECK_BOSS_TRIGGER')

a.label('BHE_B0E2')
a.LDA_ZP(BUL0_ACT); a.BEQ('BHE_B0E3')
a.LDA_ZP(ENM2_ACT); a.BEQ('BHE_B0E3')
a.CLC(); a.LDA_ZP(BUL0_X); a.ADC_IMM(0x08); a.CMP_ZP(ENM2_X); a.BCC('BHE_B0E3')
a.CLC(); a.LDA_ZP(ENM2_X); a.ADC_IMM(0x08); a.CMP_ZP(BUL0_X); a.BCC('BHE_B0E3')
a.CLC(); a.LDA_ZP(BUL0_Y); a.ADC_IMM(0x08); a.CMP_ZP(ENM2_Y); a.BCC('BHE_B0E3')
a.CLC(); a.LDA_ZP(ENM2_Y); a.ADC_IMM(0x08); a.CMP_ZP(BUL0_Y); a.BCC('BHE_B0E3')
a.LDA_IMM(0x00); a.STA_ZP(BUL0_ACT); a.STA_ZP(ENM2_ACT)
a.INC_ZP(KILLS); a.JSR('CHECK_BOSS_TRIGGER')

a.label('BHE_B0E3')
a.LDA_ZP(BUL0_ACT); a.BEQ('BHE_B0E4')
a.LDA_ZP(ENM3_ACT); a.BEQ('BHE_B0E4')
a.CLC(); a.LDA_ZP(BUL0_X); a.ADC_IMM(0x08); a.CMP_ZP(ENM3_X); a.BCC('BHE_B0E4')
a.CLC(); a.LDA_ZP(ENM3_X); a.ADC_IMM(0x08); a.CMP_ZP(BUL0_X); a.BCC('BHE_B0E4')
a.CLC(); a.LDA_ZP(BUL0_Y); a.ADC_IMM(0x08); a.CMP_ZP(ENM3_Y); a.BCC('BHE_B0E4')
a.CLC(); a.LDA_ZP(ENM3_Y); a.ADC_IMM(0x08); a.CMP_ZP(BUL0_Y); a.BCC('BHE_B0E4')
a.LDA_IMM(0x00); a.STA_ZP(BUL0_ACT); a.STA_ZP(ENM3_ACT)
a.INC_ZP(KILLS); a.JSR('CHECK_BOSS_TRIGGER')

a.label('BHE_B0E4')
a.LDA_ZP(BUL0_ACT); a.BEQ('BHE_B1E0')
a.LDA_ZP(ENM4_ACT); a.BEQ('BHE_B1E0')
a.CLC(); a.LDA_ZP(BUL0_X); a.ADC_IMM(0x08); a.CMP_ZP(ENM4_X); a.BCC('BHE_B1E0')
a.CLC(); a.LDA_ZP(ENM4_X); a.ADC_IMM(0x08); a.CMP_ZP(BUL0_X); a.BCC('BHE_B1E0')
a.CLC(); a.LDA_ZP(BUL0_Y); a.ADC_IMM(0x08); a.CMP_ZP(ENM4_Y); a.BCC('BHE_B1E0')
a.CLC(); a.LDA_ZP(ENM4_Y); a.ADC_IMM(0x08); a.CMP_ZP(BUL0_Y); a.BCC('BHE_B1E0')
a.LDA_IMM(0x00); a.STA_ZP(BUL0_ACT); a.STA_ZP(ENM4_ACT)
a.INC_ZP(KILLS); a.JSR('CHECK_BOSS_TRIGGER')

# Bullet1 vs Enemies
a.label('BHE_B1E0')
a.LDA_ZP(BUL1_ACT); a.BEQ('BHE_B1E1')
a.LDA_ZP(ENM0_ACT); a.BEQ('BHE_B1E1')
a.CLC(); a.LDA_ZP(BUL1_X); a.ADC_IMM(0x08); a.CMP_ZP(ENM0_X); a.BCC('BHE_B1E1')
a.CLC(); a.LDA_ZP(ENM0_X); a.ADC_IMM(0x08); a.CMP_ZP(BUL1_X); a.BCC('BHE_B1E1')
a.CLC(); a.LDA_ZP(BUL1_Y); a.ADC_IMM(0x08); a.CMP_ZP(ENM0_Y); a.BCC('BHE_B1E1')
a.CLC(); a.LDA_ZP(ENM0_Y); a.ADC_IMM(0x08); a.CMP_ZP(BUL1_Y); a.BCC('BHE_B1E1')
a.LDA_IMM(0x00); a.STA_ZP(BUL1_ACT); a.STA_ZP(ENM0_ACT)
a.INC_ZP(KILLS); a.JSR('CHECK_BOSS_TRIGGER')

a.label('BHE_B1E1')
a.LDA_ZP(BUL1_ACT); a.BEQ('BHE_B1E2')
a.LDA_ZP(ENM1_ACT); a.BEQ('BHE_B1E2')
a.CLC(); a.LDA_ZP(BUL1_X); a.ADC_IMM(0x08); a.CMP_ZP(ENM1_X); a.BCC('BHE_B1E2')
a.CLC(); a.LDA_ZP(ENM1_X); a.ADC_IMM(0x08); a.CMP_ZP(BUL1_X); a.BCC('BHE_B1E2')
a.CLC(); a.LDA_ZP(BUL1_Y); a.ADC_IMM(0x08); a.CMP_ZP(ENM1_Y); a.BCC('BHE_B1E2')
a.CLC(); a.LDA_ZP(ENM1_Y); a.ADC_IMM(0x08); a.CMP_ZP(BUL1_Y); a.BCC('BHE_B1E2')
a.LDA_IMM(0x00); a.STA_ZP(BUL1_ACT); a.STA_ZP(ENM1_ACT)
a.INC_ZP(KILLS); a.JSR('CHECK_BOSS_TRIGGER')

a.label('BHE_B1E2')
a.LDA_ZP(BUL1_ACT); a.BEQ('BHE_B1E3')
a.LDA_ZP(ENM2_ACT); a.BEQ('BHE_B1E3')
a.CLC(); a.LDA_ZP(BUL1_X); a.ADC_IMM(0x08); a.CMP_ZP(ENM2_X); a.BCC('BHE_B1E3')
a.CLC(); a.LDA_ZP(ENM2_X); a.ADC_IMM(0x08); a.CMP_ZP(BUL1_X); a.BCC('BHE_B1E3')
a.CLC(); a.LDA_ZP(BUL1_Y); a.ADC_IMM(0x08); a.CMP_ZP(ENM2_Y); a.BCC('BHE_B1E3')
a.CLC(); a.LDA_ZP(ENM2_Y); a.ADC_IMM(0x08); a.CMP_ZP(BUL1_Y); a.BCC('BHE_B1E3')
a.LDA_IMM(0x00); a.STA_ZP(BUL1_ACT); a.STA_ZP(ENM2_ACT)
a.INC_ZP(KILLS); a.JSR('CHECK_BOSS_TRIGGER')

a.label('BHE_B1E3')
a.LDA_ZP(BUL1_ACT); a.BEQ('BHE_B1E4')
a.LDA_ZP(ENM3_ACT); a.BEQ('BHE_B1E4')
a.CLC(); a.LDA_ZP(BUL1_X); a.ADC_IMM(0x08); a.CMP_ZP(ENM3_X); a.BCC('BHE_B1E4')
a.CLC(); a.LDA_ZP(ENM3_X); a.ADC_IMM(0x08); a.CMP_ZP(BUL1_X); a.BCC('BHE_B1E4')
a.CLC(); a.LDA_ZP(BUL1_Y); a.ADC_IMM(0x08); a.CMP_ZP(ENM3_Y); a.BCC('BHE_B1E4')
a.CLC(); a.LDA_ZP(ENM3_Y); a.ADC_IMM(0x08); a.CMP_ZP(BUL1_Y); a.BCC('BHE_B1E4')
a.LDA_IMM(0x00); a.STA_ZP(BUL1_ACT); a.STA_ZP(ENM3_ACT)
a.INC_ZP(KILLS); a.JSR('CHECK_BOSS_TRIGGER')

a.label('BHE_B1E4')
a.LDA_ZP(BUL1_ACT); a.BEQ('BHE_B2E0')
a.LDA_ZP(ENM4_ACT); a.BEQ('BHE_B2E0')
a.CLC(); a.LDA_ZP(BUL1_X); a.ADC_IMM(0x08); a.CMP_ZP(ENM4_X); a.BCC('BHE_B2E0')
a.CLC(); a.LDA_ZP(ENM4_X); a.ADC_IMM(0x08); a.CMP_ZP(BUL1_X); a.BCC('BHE_B2E0')
a.CLC(); a.LDA_ZP(BUL1_Y); a.ADC_IMM(0x08); a.CMP_ZP(ENM4_Y); a.BCC('BHE_B2E0')
a.CLC(); a.LDA_ZP(ENM4_Y); a.ADC_IMM(0x08); a.CMP_ZP(BUL1_Y); a.BCC('BHE_B2E0')
a.LDA_IMM(0x00); a.STA_ZP(BUL1_ACT); a.STA_ZP(ENM4_ACT)
a.INC_ZP(KILLS); a.JSR('CHECK_BOSS_TRIGGER')

# Bullet2 vs Enemies
a.label('BHE_B2E0')
a.LDA_ZP(BUL2_ACT); a.BEQ('BHE_B2E1')
a.LDA_ZP(ENM0_ACT); a.BEQ('BHE_B2E1')
a.CLC(); a.LDA_ZP(BUL2_X); a.ADC_IMM(0x08); a.CMP_ZP(ENM0_X); a.BCC('BHE_B2E1')
a.CLC(); a.LDA_ZP(ENM0_X); a.ADC_IMM(0x08); a.CMP_ZP(BUL2_X); a.BCC('BHE_B2E1')
a.CLC(); a.LDA_ZP(BUL2_Y); a.ADC_IMM(0x08); a.CMP_ZP(ENM0_Y); a.BCC('BHE_B2E1')
a.CLC(); a.LDA_ZP(ENM0_Y); a.ADC_IMM(0x08); a.CMP_ZP(BUL2_Y); a.BCC('BHE_B2E1')
a.LDA_IMM(0x00); a.STA_ZP(BUL2_ACT); a.STA_ZP(ENM0_ACT)
a.INC_ZP(KILLS); a.JSR('CHECK_BOSS_TRIGGER')

a.label('BHE_B2E1')
a.LDA_ZP(BUL2_ACT); a.BEQ('BHE_B2E2')
a.LDA_ZP(ENM1_ACT); a.BEQ('BHE_B2E2')
a.CLC(); a.LDA_ZP(BUL2_X); a.ADC_IMM(0x08); a.CMP_ZP(ENM1_X); a.BCC('BHE_B2E2')
a.CLC(); a.LDA_ZP(ENM1_X); a.ADC_IMM(0x08); a.CMP_ZP(BUL2_X); a.BCC('BHE_B2E2')
a.CLC(); a.LDA_ZP(BUL2_Y); a.ADC_IMM(0x08); a.CMP_ZP(ENM1_Y); a.BCC('BHE_B2E2')
a.CLC(); a.LDA_ZP(ENM1_Y); a.ADC_IMM(0x08); a.CMP_ZP(BUL2_Y); a.BCC('BHE_B2E2')
a.LDA_IMM(0x00); a.STA_ZP(BUL2_ACT); a.STA_ZP(ENM1_ACT)
a.INC_ZP(KILLS); a.JSR('CHECK_BOSS_TRIGGER')

a.label('BHE_B2E2')
a.LDA_ZP(BUL2_ACT); a.BEQ('BHE_B2E3')
a.LDA_ZP(ENM2_ACT); a.BEQ('BHE_B2E3')
a.CLC(); a.LDA_ZP(BUL2_X); a.ADC_IMM(0x08); a.CMP_ZP(ENM2_X); a.BCC('BHE_B2E3')
a.CLC(); a.LDA_ZP(ENM2_X); a.ADC_IMM(0x08); a.CMP_ZP(BUL2_X); a.BCC('BHE_B2E3')
a.CLC(); a.LDA_ZP(BUL2_Y); a.ADC_IMM(0x08); a.CMP_ZP(ENM2_Y); a.BCC('BHE_B2E3')
a.CLC(); a.LDA_ZP(ENM2_Y); a.ADC_IMM(0x08); a.CMP_ZP(BUL2_Y); a.BCC('BHE_B2E3')
a.LDA_IMM(0x00); a.STA_ZP(BUL2_ACT); a.STA_ZP(ENM2_ACT)
a.INC_ZP(KILLS); a.JSR('CHECK_BOSS_TRIGGER')

a.label('BHE_B2E3')
a.LDA_ZP(BUL2_ACT); a.BEQ('BHE_B2E4')
a.LDA_ZP(ENM3_ACT); a.BEQ('BHE_B2E4')
a.CLC(); a.LDA_ZP(BUL2_X); a.ADC_IMM(0x08); a.CMP_ZP(ENM3_X); a.BCC('BHE_B2E4')
a.CLC(); a.LDA_ZP(ENM3_X); a.ADC_IMM(0x08); a.CMP_ZP(BUL2_X); a.BCC('BHE_B2E4')
a.CLC(); a.LDA_ZP(BUL2_Y); a.ADC_IMM(0x08); a.CMP_ZP(ENM3_Y); a.BCC('BHE_B2E4')
a.CLC(); a.LDA_ZP(ENM3_Y); a.ADC_IMM(0x08); a.CMP_ZP(BUL2_Y); a.BCC('BHE_B2E4')
a.LDA_IMM(0x00); a.STA_ZP(BUL2_ACT); a.STA_ZP(ENM3_ACT)
a.INC_ZP(KILLS); a.JSR('CHECK_BOSS_TRIGGER')

a.label('BHE_B2E4')
a.LDA_ZP(BUL2_ACT); a.BEQ('BHE_DONE')
a.LDA_ZP(ENM4_ACT); a.BEQ('BHE_DONE')
a.CLC(); a.LDA_ZP(BUL2_X); a.ADC_IMM(0x08); a.CMP_ZP(ENM4_X); a.BCC('BHE_DONE')
a.CLC(); a.LDA_ZP(ENM4_X); a.ADC_IMM(0x08); a.CMP_ZP(BUL2_X); a.BCC('BHE_DONE')
a.CLC(); a.LDA_ZP(BUL2_Y); a.ADC_IMM(0x08); a.CMP_ZP(ENM4_Y); a.BCC('BHE_DONE')
a.CLC(); a.LDA_ZP(ENM4_Y); a.ADC_IMM(0x08); a.CMP_ZP(BUL2_Y); a.BCC('BHE_DONE')
a.LDA_IMM(0x00); a.STA_ZP(BUL2_ACT); a.STA_ZP(ENM4_ACT)
a.INC_ZP(KILLS); a.JSR('CHECK_BOSS_TRIGGER')

a.label('BHE_DONE')
a.RTS()

# ===========================================================================
# CHECK_BOSS_TRIGGER
# ===========================================================================
a.label('CHECK_BOSS_TRIGGER')
a.LDA_ZP(GAME_STATE)
a.BNE('CBT_DONE')
a.LDA_ZP(KILLS)
a.CMP_IMM(0x0A)
a.BCC('CBT_DONE')
a.LDA_IMM(0x01); a.STA_ZP(GAME_STATE)
a.LDA_IMM(0x64); a.STA_ZP(BOSS_HP)
a.LDA_IMM(0x70); a.STA_ZP(BOSS_X)
a.LDA_IMM(0x20); a.STA_ZP(BOSS_Y)
a.LDA_IMM(0x5A); a.STA_ZP(ENM_SHOOT_T)
a.label('CBT_DONE')
a.RTS()

# ===========================================================================
# PLR_HIT_ENM — プレイヤー (PLR_X/PLR_Y) vs 敵
# ===========================================================================
a.label('PLR_HIT_ENM')
# Enemy0
a.LDA_ZP(ENM0_ACT); a.BEQ('PHE_E1')
a.CLC(); a.LDA_ZP(PLR_X); a.ADC_IMM(0x08); a.CMP_ZP(ENM0_X); a.BCC('PHE_E1')
a.CLC(); a.LDA_ZP(ENM0_X); a.ADC_IMM(0x08); a.CMP_ZP(PLR_X); a.BCC('PHE_E1')
a.CLC(); a.LDA_ZP(PLR_Y); a.ADC_IMM(0x08); a.CMP_ZP(ENM0_Y); a.BCC('PHE_E1')
a.CLC(); a.LDA_ZP(ENM0_Y); a.ADC_IMM(0x08); a.CMP_ZP(PLR_Y); a.BCC('PHE_E1')
a.LDA_IMM(0x78); a.STA_ZP(DEAD_TIMER)
a.LDA_IMM(0x03); a.STA_ZP(GAME_STATE); a.RTS()

a.label('PHE_E1')
a.LDA_ZP(ENM1_ACT); a.BEQ('PHE_E2')
a.CLC(); a.LDA_ZP(PLR_X); a.ADC_IMM(0x08); a.CMP_ZP(ENM1_X); a.BCC('PHE_E2')
a.CLC(); a.LDA_ZP(ENM1_X); a.ADC_IMM(0x08); a.CMP_ZP(PLR_X); a.BCC('PHE_E2')
a.CLC(); a.LDA_ZP(PLR_Y); a.ADC_IMM(0x08); a.CMP_ZP(ENM1_Y); a.BCC('PHE_E2')
a.CLC(); a.LDA_ZP(ENM1_Y); a.ADC_IMM(0x08); a.CMP_ZP(PLR_Y); a.BCC('PHE_E2')
a.LDA_IMM(0x78); a.STA_ZP(DEAD_TIMER)
a.LDA_IMM(0x03); a.STA_ZP(GAME_STATE); a.RTS()

a.label('PHE_E2')
a.LDA_ZP(ENM2_ACT); a.BEQ('PHE_E3')
a.CLC(); a.LDA_ZP(PLR_X); a.ADC_IMM(0x08); a.CMP_ZP(ENM2_X); a.BCC('PHE_E3')
a.CLC(); a.LDA_ZP(ENM2_X); a.ADC_IMM(0x08); a.CMP_ZP(PLR_X); a.BCC('PHE_E3')
a.CLC(); a.LDA_ZP(PLR_Y); a.ADC_IMM(0x08); a.CMP_ZP(ENM2_Y); a.BCC('PHE_E3')
a.CLC(); a.LDA_ZP(ENM2_Y); a.ADC_IMM(0x08); a.CMP_ZP(PLR_Y); a.BCC('PHE_E3')
a.LDA_IMM(0x78); a.STA_ZP(DEAD_TIMER)
a.LDA_IMM(0x03); a.STA_ZP(GAME_STATE); a.RTS()

a.label('PHE_E3')
a.LDA_ZP(ENM3_ACT); a.BEQ('PHE_E4')
a.CLC(); a.LDA_ZP(PLR_X); a.ADC_IMM(0x08); a.CMP_ZP(ENM3_X); a.BCC('PHE_E4')
a.CLC(); a.LDA_ZP(ENM3_X); a.ADC_IMM(0x08); a.CMP_ZP(PLR_X); a.BCC('PHE_E4')
a.CLC(); a.LDA_ZP(PLR_Y); a.ADC_IMM(0x08); a.CMP_ZP(ENM3_Y); a.BCC('PHE_E4')
a.CLC(); a.LDA_ZP(ENM3_Y); a.ADC_IMM(0x08); a.CMP_ZP(PLR_Y); a.BCC('PHE_E4')
a.LDA_IMM(0x78); a.STA_ZP(DEAD_TIMER)
a.LDA_IMM(0x03); a.STA_ZP(GAME_STATE); a.RTS()

a.label('PHE_E4')
a.LDA_ZP(ENM4_ACT); a.BEQ('PHE_DONE')
a.CLC(); a.LDA_ZP(PLR_X); a.ADC_IMM(0x08); a.CMP_ZP(ENM4_X); a.BCC('PHE_DONE')
a.CLC(); a.LDA_ZP(ENM4_X); a.ADC_IMM(0x08); a.CMP_ZP(PLR_X); a.BCC('PHE_DONE')
a.CLC(); a.LDA_ZP(PLR_Y); a.ADC_IMM(0x08); a.CMP_ZP(ENM4_Y); a.BCC('PHE_DONE')
a.CLC(); a.LDA_ZP(ENM4_Y); a.ADC_IMM(0x08); a.CMP_ZP(PLR_Y); a.BCC('PHE_DONE')
a.LDA_IMM(0x78); a.STA_ZP(DEAD_TIMER)
a.LDA_IMM(0x03); a.STA_ZP(GAME_STATE)
a.label('PHE_DONE')
a.RTS()

# ===========================================================================
# PLR_HIT_EBULLETS — プレイヤー vs 敵弾
# ===========================================================================
a.label('PLR_HIT_EBULLETS')
# EBUL0
a.LDA_ZP(EBUL0_ACT); a.BEQ('PHEB_E1')
a.CLC(); a.LDA_ZP(PLR_X); a.ADC_IMM(0x08); a.CMP_ZP(EBUL0_X); a.BCC('PHEB_E1')
a.CLC(); a.LDA_ZP(EBUL0_X); a.ADC_IMM(0x04); a.CMP_ZP(PLR_X); a.BCC('PHEB_E1')
a.CLC(); a.LDA_ZP(PLR_Y); a.ADC_IMM(0x08); a.CMP_ZP(EBUL0_Y); a.BCC('PHEB_E1')
a.CLC(); a.LDA_ZP(EBUL0_Y); a.ADC_IMM(0x06); a.CMP_ZP(PLR_Y); a.BCC('PHEB_E1')
a.LDA_IMM(0x00); a.STA_ZP(EBUL0_ACT)
a.LDA_IMM(0x78); a.STA_ZP(DEAD_TIMER)
a.LDA_IMM(0x03); a.STA_ZP(GAME_STATE)
a.label('PHEB_E1')
# EBUL1
a.LDA_ZP(EBUL1_ACT); a.BEQ('PHEB_DONE')
a.CLC(); a.LDA_ZP(PLR_X); a.ADC_IMM(0x08); a.CMP_ZP(EBUL1_X); a.BCC('PHEB_DONE')
a.CLC(); a.LDA_ZP(EBUL1_X); a.ADC_IMM(0x04); a.CMP_ZP(PLR_X); a.BCC('PHEB_DONE')
a.CLC(); a.LDA_ZP(PLR_Y); a.ADC_IMM(0x08); a.CMP_ZP(EBUL1_Y); a.BCC('PHEB_DONE')
a.CLC(); a.LDA_ZP(EBUL1_Y); a.ADC_IMM(0x06); a.CMP_ZP(PLR_Y); a.BCC('PHEB_DONE')
a.LDA_IMM(0x00); a.STA_ZP(EBUL1_ACT)
a.LDA_IMM(0x78); a.STA_ZP(DEAD_TIMER)
a.LDA_IMM(0x03); a.STA_ZP(GAME_STATE)
a.label('PHEB_DONE')
a.RTS()

# ===========================================================================
# UPDATE_BOSS — 左右移動 + 弾発射
# ===========================================================================
a.label('UPDATE_BOSS')
a.DEC_ZP(BOSS_T)
a.BNE('BOSS_MOVE')
a.LDA_IMM(0x02); a.STA_ZP(BOSS_T)

a.label('BOSS_MOVE')
a.LDA_ZP(BOSS_DIR)
a.BNE('BOSS_MOVE_LEFT')
a.LDA_ZP(BOSS_X); a.CLC(); a.ADC_IMM(0x02)
a.CMP_IMM(0xD0); a.BCC('BOSS_RIGHT_OK')
a.LDA_IMM(0xD0); a.STA_ZP(BOSS_X)
a.LDA_IMM(0x01); a.STA_ZP(BOSS_DIR)
a.JMP('BOSS_SHOOT_CHECK')
a.label('BOSS_RIGHT_OK')
a.STA_ZP(BOSS_X)
a.JMP('BOSS_SHOOT_CHECK')

a.label('BOSS_MOVE_LEFT')
a.LDA_ZP(BOSS_X); a.SEC(); a.SBC_IMM(0x02)
a.CMP_IMM(0x10); a.BCS('BOSS_LEFT_OK')
a.LDA_IMM(0x10); a.STA_ZP(BOSS_X)
a.LDA_IMM(0x00); a.STA_ZP(BOSS_DIR)
a.JMP('BOSS_SHOOT_CHECK')
a.label('BOSS_LEFT_OK')
a.STA_ZP(BOSS_X)

# ボス弾発射チェック
a.label('BOSS_SHOOT_CHECK')
a.DEC_ZP(ENM_SHOOT_T)
a.BNE('BOSS_UPD_DONE')
a.LDA_IMM(0x5A); a.STA_ZP(ENM_SHOOT_T)   # 90 フレーム
# EBUL0 空きチェック
a.LDA_ZP(EBUL0_ACT)
a.BNE('BOSS_TRY_E1')
a.LDA_IMM(0x01); a.STA_ZP(EBUL0_ACT)
a.LDA_ZP(BOSS_Y); a.CLC(); a.ADC_IMM(0x10); a.STA_ZP(EBUL0_Y)
a.LDA_ZP(BOSS_X); a.CLC(); a.ADC_IMM(0x04); a.STA_ZP(EBUL0_X)
a.JMP('BOSS_UPD_DONE')
a.label('BOSS_TRY_E1')
a.LDA_ZP(EBUL1_ACT)
a.BNE('BOSS_UPD_DONE')
a.LDA_IMM(0x01); a.STA_ZP(EBUL1_ACT)
a.LDA_ZP(BOSS_Y); a.CLC(); a.ADC_IMM(0x10); a.STA_ZP(EBUL1_Y)
a.LDA_ZP(BOSS_X); a.CLC(); a.ADC_IMM(0x04); a.STA_ZP(EBUL1_X)

a.label('BOSS_UPD_DONE')
a.RTS()

# ===========================================================================
# BUL_HIT_BOSS — プレイヤー弾 vs ボス (16x16)
# ===========================================================================
a.label('BUL_HIT_BOSS')
# Bullet0
a.LDA_ZP(BUL0_ACT); a.BEQ('BHB_B1')
a.CLC(); a.LDA_ZP(BUL0_X); a.ADC_IMM(0x08); a.CMP_ZP(BOSS_X); a.BCC('BHB_B1')
a.CLC(); a.LDA_ZP(BOSS_X); a.ADC_IMM(0x10); a.CMP_ZP(BUL0_X); a.BCC('BHB_B1')
a.CLC(); a.LDA_ZP(BUL0_Y); a.ADC_IMM(0x08); a.CMP_ZP(BOSS_Y); a.BCC('BHB_B1')
a.CLC(); a.LDA_ZP(BOSS_Y); a.ADC_IMM(0x10); a.CMP_ZP(BUL0_Y); a.BCC('BHB_B1')
a.LDA_IMM(0x00); a.STA_ZP(BUL0_ACT)
a.DEC_ZP(BOSS_HP); a.BNE('BHB_B1')
a.LDA_IMM(0x02); a.STA_ZP(GAME_STATE)

a.label('BHB_B1')
a.LDA_ZP(BUL1_ACT); a.BEQ('BHB_B2')
a.CLC(); a.LDA_ZP(BUL1_X); a.ADC_IMM(0x08); a.CMP_ZP(BOSS_X); a.BCC('BHB_B2')
a.CLC(); a.LDA_ZP(BOSS_X); a.ADC_IMM(0x10); a.CMP_ZP(BUL1_X); a.BCC('BHB_B2')
a.CLC(); a.LDA_ZP(BUL1_Y); a.ADC_IMM(0x08); a.CMP_ZP(BOSS_Y); a.BCC('BHB_B2')
a.CLC(); a.LDA_ZP(BOSS_Y); a.ADC_IMM(0x10); a.CMP_ZP(BUL1_Y); a.BCC('BHB_B2')
a.LDA_IMM(0x00); a.STA_ZP(BUL1_ACT)
a.DEC_ZP(BOSS_HP); a.BNE('BHB_B2')
a.LDA_IMM(0x02); a.STA_ZP(GAME_STATE)

a.label('BHB_B2')
a.LDA_ZP(BUL2_ACT); a.BEQ('BHB_DONE')
a.CLC(); a.LDA_ZP(BUL2_X); a.ADC_IMM(0x08); a.CMP_ZP(BOSS_X); a.BCC('BHB_DONE')
a.CLC(); a.LDA_ZP(BOSS_X); a.ADC_IMM(0x10); a.CMP_ZP(BUL2_X); a.BCC('BHB_DONE')
a.CLC(); a.LDA_ZP(BUL2_Y); a.ADC_IMM(0x08); a.CMP_ZP(BOSS_Y); a.BCC('BHB_DONE')
a.CLC(); a.LDA_ZP(BOSS_Y); a.ADC_IMM(0x10); a.CMP_ZP(BUL2_Y); a.BCC('BHB_DONE')
a.LDA_IMM(0x00); a.STA_ZP(BUL2_ACT)
a.DEC_ZP(BOSS_HP); a.BNE('BHB_DONE')
a.LDA_IMM(0x02); a.STA_ZP(GAME_STATE)

a.label('BHB_DONE')
a.RTS()

# ===========================================================================
# PLR_HIT_BOSS — プレイヤー vs ボス
# ===========================================================================
a.label('PLR_HIT_BOSS')
a.CLC(); a.LDA_ZP(PLR_X); a.ADC_IMM(0x08); a.CMP_ZP(BOSS_X); a.BCC('PHB_DONE')
a.CLC(); a.LDA_ZP(BOSS_X); a.ADC_IMM(0x10); a.CMP_ZP(PLR_X); a.BCC('PHB_DONE')
a.CLC(); a.LDA_ZP(PLR_Y); a.ADC_IMM(0x08); a.CMP_ZP(BOSS_Y); a.BCC('PHB_DONE')
a.CLC(); a.LDA_ZP(BOSS_Y); a.ADC_IMM(0x10); a.CMP_ZP(PLR_Y); a.BCC('PHB_DONE')
a.LDA_IMM(0x78); a.STA_ZP(DEAD_TIMER)
a.LDA_IMM(0x03); a.STA_ZP(GAME_STATE)
a.label('PHB_DONE')
a.RTS()

# ===========================================================================
# OAM 更新
# ===========================================================================

# UPDATE_OAM_PLR — PLR_X / PLR_Y でスプライト更新
a.label('UPDATE_OAM_PLR')
a.LDA_ZP(PLR_Y)
a.STA_ABS(0x0200)
a.LDA_ZP(PLR_X)
a.STA_ABS(0x0203)
a.RTS()

# UPDATE_OAM_EBULLETS — 敵弾 OAM ($0204/$0208)
a.label('UPDATE_OAM_EBULLETS')
# EBUL0
a.LDA_ZP(EBUL0_ACT)
a.BNE('UOEB_E0_ON')
a.LDA_IMM(0xFF); a.STA_ABS(0x0204)
a.JMP('UOEB_E1')
a.label('UOEB_E0_ON')
a.LDA_ZP(EBUL0_Y); a.STA_ABS(0x0204)
a.LDA_ZP(EBUL0_X); a.STA_ABS(0x0207)
a.label('UOEB_E1')
# EBUL1
a.LDA_ZP(EBUL1_ACT)
a.BNE('UOEB_E1_ON')
a.LDA_IMM(0xFF); a.STA_ABS(0x0208)
a.JMP('UOEB_DONE')
a.label('UOEB_E1_ON')
a.LDA_ZP(EBUL1_Y); a.STA_ABS(0x0208)
a.LDA_ZP(EBUL1_X); a.STA_ABS(0x020B)
a.label('UOEB_DONE')
# $020C/$0210 は常に非表示 (OAM_INIT_LOOP で $FF 済み)
a.RTS()

# UPDATE_OAM_BULLETS
a.label('UPDATE_OAM_BULLETS')
a.LDA_ZP(BUL0_ACT)
a.BNE('UOB_B0_ON')
a.LDA_IMM(0xFF); a.STA_ABS(0x0214)
a.JMP('UOB_B1')
a.label('UOB_B0_ON')
a.LDA_ZP(BUL0_Y); a.STA_ABS(0x0214)
a.LDA_ZP(BUL0_X); a.STA_ABS(0x0217)
a.label('UOB_B1')
a.LDA_ZP(BUL1_ACT)
a.BNE('UOB_B1_ON')
a.LDA_IMM(0xFF); a.STA_ABS(0x0218)
a.JMP('UOB_B2')
a.label('UOB_B1_ON')
a.LDA_ZP(BUL1_Y); a.STA_ABS(0x0218)
a.LDA_ZP(BUL1_X); a.STA_ABS(0x021B)
a.label('UOB_B2')
a.LDA_ZP(BUL2_ACT)
a.BNE('UOB_B2_ON')
a.LDA_IMM(0xFF); a.STA_ABS(0x021C)
a.JMP('UOB_DONE')
a.label('UOB_B2_ON')
a.LDA_ZP(BUL2_Y); a.STA_ABS(0x021C)
a.LDA_ZP(BUL2_X); a.STA_ABS(0x021F)
a.label('UOB_DONE')
a.RTS()

# UPDATE_OAM_ENM
a.label('UPDATE_OAM_ENM')
a.LDA_ZP(ENM0_ACT)
a.BNE('UOE_E0_ON')
a.LDA_IMM(0xFF); a.STA_ABS(0x0220)
a.JMP('UOE_E1')
a.label('UOE_E0_ON')
a.LDA_ZP(ENM0_Y); a.STA_ABS(0x0220)
a.LDA_ZP(ENM0_X); a.STA_ABS(0x0223)
a.label('UOE_E1')
a.LDA_ZP(ENM1_ACT)
a.BNE('UOE_E1_ON')
a.LDA_IMM(0xFF); a.STA_ABS(0x0224)
a.JMP('UOE_E2')
a.label('UOE_E1_ON')
a.LDA_ZP(ENM1_Y); a.STA_ABS(0x0224)
a.LDA_ZP(ENM1_X); a.STA_ABS(0x0227)
a.label('UOE_E2')
a.LDA_ZP(ENM2_ACT)
a.BNE('UOE_E2_ON')
a.LDA_IMM(0xFF); a.STA_ABS(0x0228)
a.JMP('UOE_E3')
a.label('UOE_E2_ON')
a.LDA_ZP(ENM2_Y); a.STA_ABS(0x0228)
a.LDA_ZP(ENM2_X); a.STA_ABS(0x022B)
a.label('UOE_E3')
a.LDA_ZP(ENM3_ACT)
a.BNE('UOE_E3_ON')
a.LDA_IMM(0xFF); a.STA_ABS(0x022C)
a.JMP('UOE_E4')
a.label('UOE_E3_ON')
a.LDA_ZP(ENM3_Y); a.STA_ABS(0x022C)
a.LDA_ZP(ENM3_X); a.STA_ABS(0x022F)
a.label('UOE_E4')
a.LDA_ZP(ENM4_ACT)
a.BNE('UOE_E4_ON')
a.LDA_IMM(0xFF); a.STA_ABS(0x0230)
a.JMP('UOE_DONE')
a.label('UOE_E4_ON')
a.LDA_ZP(ENM4_Y); a.STA_ABS(0x0230)
a.LDA_ZP(ENM4_X); a.STA_ABS(0x0233)
a.label('UOE_DONE')
a.RTS()

a.label('UPDATE_OAM_ENM_OFF')
a.LDA_IMM(0xFF)
a.STA_ABS(0x0220); a.STA_ABS(0x0224); a.STA_ABS(0x0228)
a.STA_ABS(0x022C); a.STA_ABS(0x0230)
a.RTS()

a.label('UPDATE_OAM_BOSS_OFF')
a.LDA_IMM(0xFF)
a.STA_ABS(0x0234); a.STA_ABS(0x0238)
a.STA_ABS(0x023C); a.STA_ABS(0x0240)
a.RTS()

a.label('UPDATE_OAM_BOSS_ON')
a.LDA_ZP(BOSS_Y); a.STA_ABS(0x0234)
a.LDA_ZP(BOSS_X); a.STA_ABS(0x0237)
a.LDA_ZP(BOSS_Y); a.STA_ABS(0x0238)
a.LDA_ZP(BOSS_X); a.CLC(); a.ADC_IMM(0x08); a.STA_ABS(0x023B)
a.LDA_ZP(BOSS_Y); a.CLC(); a.ADC_IMM(0x08); a.STA_ABS(0x023C)
a.LDA_ZP(BOSS_X); a.STA_ABS(0x023F)
a.LDA_ZP(BOSS_Y); a.CLC(); a.ADC_IMM(0x08); a.STA_ABS(0x0240)
a.LDA_ZP(BOSS_X); a.CLC(); a.ADC_IMM(0x08); a.STA_ABS(0x0243)
a.RTS()

# ===========================================================================
# GAME_RESTART
# ===========================================================================
a.label('GAME_RESTART')
a.LDA_IMM(0x00)
a.STA_ZP(BUL0_ACT); a.STA_ZP(BUL1_ACT); a.STA_ZP(BUL2_ACT)
a.STA_ZP(ENM0_ACT); a.STA_ZP(ENM1_ACT); a.STA_ZP(ENM2_ACT)
a.STA_ZP(ENM3_ACT); a.STA_ZP(ENM4_ACT)
a.STA_ZP(EBUL0_ACT); a.STA_ZP(EBUL1_ACT)
a.STA_ZP(ENM0_OSC); a.STA_ZP(ENM1_OSC); a.STA_ZP(ENM2_OSC)
a.STA_ZP(ENM3_OSC); a.STA_ZP(ENM4_OSC)
a.STA_ZP(KILLS); a.STA_ZP(BOSS_DIR); a.STA_ZP(GAME_STATE)
a.LDA_IMM(0x78); a.STA_ZP(PLR_X)
a.LDA_IMM(0xC0); a.STA_ZP(PLR_Y)
a.LDA_IMM(0x64); a.STA_ZP(BOSS_HP)
a.LDA_IMM(0x70); a.STA_ZP(BOSS_X)
a.LDA_IMM(0x20); a.STA_ZP(BOSS_Y)
a.LDA_IMM(0x20); a.STA_ZP(BOSS_T)
a.LDA_IMM(0x50); a.STA_ZP(SPAWN_T)
a.LDA_IMM(0x00); a.STA_ZP(SHOOT_COOL)
a.LDA_IMM(0x5A); a.STA_ZP(ENM_SHOOT_T)
a.RTS()

# ===========================================================================
# PRG-ROM ビルド
# ===========================================================================
prg_bytes = a.build()

nmi_addr   = a._labels['NMI']
reset_addr = a._labels['RESET']
irq_addr   = a._labels['IRQ']

print(f"PRG size: {len(prg_bytes)} bytes")
print(f"NMI:   ${nmi_addr:04X}")
print(f"RESET: ${reset_addr:04X}")
print(f"IRQ:   ${irq_addr:04X}")

PRG_SIZE = 16384
prg_padded = bytearray(PRG_SIZE)
prg_padded[:len(prg_bytes)] = prg_bytes

prg_padded[PRG_SIZE - 6] = nmi_addr & 0xFF
prg_padded[PRG_SIZE - 5] = (nmi_addr >> 8) & 0xFF
prg_padded[PRG_SIZE - 4] = reset_addr & 0xFF
prg_padded[PRG_SIZE - 3] = (reset_addr >> 8) & 0xFF
prg_padded[PRG_SIZE - 2] = irq_addr & 0xFF
prg_padded[PRG_SIZE - 1] = (irq_addr >> 8) & 0xFF

# ===========================================================================
# CHR-ROM タイル定義
# ===========================================================================

def tile(p0_rows, p1_rows=None):
    if p1_rows is None:
        p1_rows = [0x00] * 8
    return bytes(p0_rows + p1_rows)

# Tile 0x00: ブランク
t00 = tile([0x00]*8)

# Tile 0x01: 星ドット (BG タイル)
t01 = tile(
    [0x00, 0x00, 0x18, 0x18, 0x00, 0x00, 0x00, 0x00],
    [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
)

# Tile 0x02: プレイヤー戦闘機 (上向き・スリムなデザイン)
# p0=本体シルエット(白), p1=コックピット(黄色部分)
t02 = tile(
    [0x18, 0x18, 0x3C, 0xFF, 0xDB, 0x3C, 0x24, 0x24],
    [0x00, 0x00, 0x00, 0x00, 0x42, 0x00, 0x00, 0x00]
)

# Tile 0x03: プレイヤー弾 (明るい細い縦ビーム)
t03 = tile(
    [0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x00, 0x00],
    [0x18, 0x18, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
)

# Tile 0x04: 敵エイリアン戦闘機 (下向き)
# p0=本体(赤系 palette3 color1), p1=目/コア(明るい)
t04 = tile(
    [0x3C, 0x7E, 0xFF, 0xDB, 0xFF, 0x7E, 0x24, 0x66],
    [0x00, 0x00, 0x00, 0x24, 0x00, 0x00, 0x00, 0x00]
)

# Tile 0x05: ボス左上
t05 = tile(
    [0x0F, 0x3F, 0x7F, 0xFF, 0xFF, 0xEF, 0xFF, 0xFF],
    [0x00, 0x00, 0x00, 0x00, 0x10, 0x30, 0x00, 0x00]
)

# Tile 0x06: ボス右上
t06 = tile(
    [0xF0, 0xFC, 0xFE, 0xFF, 0xFF, 0xF7, 0xFF, 0xFF],
    [0x00, 0x00, 0x00, 0x00, 0x08, 0x0C, 0x00, 0x00]
)

# Tile 0x07: ボス左下
t07 = tile(
    [0xFF, 0xFF, 0xEF, 0xFF, 0xFF, 0x7F, 0x3F, 0x0F],
    [0x00, 0x00, 0x30, 0x10, 0x00, 0x00, 0x00, 0x00]
)

# Tile 0x08: ボス右下
t08 = tile(
    [0xFF, 0xFF, 0xF7, 0xFF, 0xFF, 0xFE, 0xFC, 0xF0],
    [0x00, 0x00, 0x0C, 0x08, 0x00, 0x00, 0x00, 0x00]
)

# Tile 0x09: 敵弾 (赤い短いビーム)
t09 = tile(
    [0x18, 0x3C, 0x3C, 0x18, 0x18, 0x00, 0x00, 0x00],
    [0x00, 0x18, 0x18, 0x00, 0x00, 0x00, 0x00, 0x00]
)

CHR_SIZE = 8192
chr_data = t00 + t01 + t02 + t03 + t04 + t05 + t06 + t07 + t08 + t09
chr_padded = chr_data + bytes(CHR_SIZE - len(chr_data))

# ===========================================================================
# game.rom.txt 出力
# ===========================================================================

def bytes_to_hex_lines(data, cols=16):
    lines = []
    for i in range(0, len(data), cols):
        chunk = data[i:i+cols]
        lines.append(' '.join(f'{b:02X}' for b in chunk))
    return lines

output_lines = []
output_lines.append('[header]')
output_lines.append('4E 45 53 1A  # iNES magic')
output_lines.append('01           # PRG banks')
output_lines.append('01           # CHR banks')
output_lines.append('00           # flags6 (horizontal mirroring, mapper 0)')
output_lines.append('00           # flags7')
output_lines.append('00 00 00 00 00 00 00 00  # padding')
output_lines.append('')

output_lines.append('[prg_rom]')
for line in bytes_to_hex_lines(bytes(prg_padded)):
    output_lines.append(line)
output_lines.append('')

output_lines.append('[chr_rom]')
for line in bytes_to_hex_lines(chr_padded):
    output_lines.append(line)
output_lines.append('')

vec_bytes = bytes(prg_padded[PRG_SIZE-6:PRG_SIZE])
output_lines.append('[vectors]')
output_lines.append(f'{vec_bytes[0]:02X} {vec_bytes[1]:02X}  # NMI vector  (${nmi_addr:04X})')
output_lines.append(f'{vec_bytes[2]:02X} {vec_bytes[3]:02X}  # RESET vector (${reset_addr:04X})')
output_lines.append(f'{vec_bytes[4]:02X} {vec_bytes[5]:02X}  # IRQ vector  (${irq_addr:04X})')
output_lines.append('')

rom_txt = '\n'.join(output_lines)
output_path = Path(__file__).parent / 'game.rom.txt'
output_path.write_text(rom_txt, encoding='utf-8')
print(f"game.rom.txt を書き込みました ({output_path})")

# ===========================================================================
# generate.py を呼び出して game.nes を生成
# ===========================================================================
project_dir = Path(__file__).parent
result = subprocess.run(
    ['python3', 'generate.py'],
    cwd=str(project_dir),
    capture_output=True,
    text=True
)
if result.returncode != 0:
    print("generate.py エラー:")
    print(result.stderr)
    sys.exit(1)
else:
    print(result.stdout.strip())
    print("game.nes を生成しました!")
