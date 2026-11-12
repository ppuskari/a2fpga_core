; WOPR-inspired SSI-263 speech demonstration TAKE 3: measured movie pacing
; Target: Apple IIe Mockingboard C / a2n20v2-Enhanced in SLOT 4.
; CPU: 6502/65C02. ca65/ld65; load at $6000; CALL 24576.
; Allophone codes are from the pinned SSI-263 physical ROM table,
; reference/ssi263/pico-v1.0.1/rom_bits.csv.
; Word transition times and stepped F0 estimated from HQ movie WAV.
; Only derived timing/pitch notes used. No film audio embedded.
; Film duration 2.194s. A/R-driven 48.19ms phoneme-frame approximation.
; Not an extract of John Wood's recorded/sound-edited 1983 film voice.
;
; Register layout from verified Demo Disk 1 ($Cn40..$Cn44):
;   R0 $C440 phoneme+duration; R1 $C441 pitch;
;   R2 $C442 rate; R3 $C443 control/volume; R4 $C444 filter clock.
; Right VIA CA1 A/R interrupt flag = IFR bit 1, at $C48D.
; Poll IFR (no interrupts required) with timeouts; power off on exit.
;
; To adapt for a different Mockingboard slot change all $C4xx to $Cnxx.
.export _start
.segment "CODE"

SSI_R0  = $C440
SSI_R1  = $C441
SSI_R2  = $C442
SSI_R3  = $C443
SSI_R4  = $C444
VIA_PCR = $C48C
VIA_IFR = $C48D
IFR_CA1 = $02

.proc _start
    php
    sei
    lda VIA_PCR
    sta old_pcr
    and #$FE               ; CA1 triggered by falling A/R edge
    sta VIA_PCR
    lda #IFR_CA1
    sta VIA_IFR             ; clear stale CA1 interrupt flag

    lda #$80
    sta SSI_R3             ; power down before reconfiguration
    lda #$C0
    sta SSI_R0             ; PA (code 0), mode 3 for A/R handshake
    lda #$E8
    sta SSI_R4             ; Demo Disk-compatible filter clock divider
    lda #$48
    sta SSI_R2             ; slower ~2.1s WOPR cadence (Disk 1=$A8)
    lda #$33
    sta SSI_R1             ; target ~77Hz for SHALL
    lda #$69
    sta SSI_R3             ; power on, articulation 6, volume 9

    ldy #$00
next_phoneme:
    ; Switch pitch by word rather than globally flattening the phrase.
    ; Formula in mode 3 at R2=$48: f0 ~ 127500/(2048-64*(R1>>3)).
    ;  $33 -> ~77Hz; $43 -> ~83Hz; $53 -> ~91Hz; $83 -> ~124Hz.
    ; Timed R1 writes do not alter the already-qualified PCM protocol.
    cpy #4
    bne not_we
    lda #$43             ; WE: ~83Hz
    sta SSI_R1
not_we:
    cpy #7
    bne not_play
    lda #$53             ; PLAY: ~91Hz
    sta SSI_R1
not_play:
    cpy #12
    bne not_game
    lda #$83             ; pre-glide during A->GAME pause; ~124Hz target
    sta SSI_R1
not_game:
    lda #IFR_CA1
    sta VIA_IFR
    lda phrase,y
    sta SSI_R0
    lda #$80
    sta timeout_hi         ; bounded ~0.4s at Apple IIe 1MHz
    ldx #$00
wait_ready:
    lda VIA_IFR
    and #IFR_CA1
    bne ready
    dex
    bne wait_ready
    dec timeout_hi
    bne wait_ready
    ; Defensive timeout: avoid permanently wedging Apple BASIC.
    jmp done

ready:
    lda #IFR_CA1
    sta VIA_IFR
    iny
    cpy #phrase_end - phrase
    bne next_phoneme

done:
    lda #$80
    sta SSI_R3             ; explicit power-off (also tests CTL behavior)
    lda old_pcr
    sta VIA_PCR
    plp
    rts

; R0[5:0] = phoneme; R0[7:6] = duration code:
; 0 -> 4 frames, 1 -> 3 frames, 2 -> 2 frames, 3 -> 1 frame.
; Plain PA (pause phoneme, code 0) creates controlled word spacing.
; SH is called SCH in the reconciled ROM; "G" uses voiced KV.
; Calculated at R2=$48: 1 frame ~= 48.19ms; total 45 frames
; = 2.1685s before Pico model timer/rounding; film reference 2.1943s.
; Target word start phases 0.00 / 0.58 / 0.96 / 1.35 / 1.64s.
phrase:
    .byte $B2,$0C,$60      ; SHALL: SCH 2f + AE 4f + L 3f = 9 frames
    .byte $40              ; PA 3f: pronounced ~145ms boundary
    .byte $A3,$01          ; WE: W 2f + E 4f = 6 frames
    .byte $80              ; PA 2f: ~96ms gap
    .byte $E7,$A0,$05      ; PLAY: P 1f + L 2f + AY 4f = 7 frames
    .byte $C0              ; PA 1f: ~48ms clipped transition
    .byte $0E              ; A: AH 4f: ~193ms
    .byte $80              ; PA 2f: ~96ms, low-energy movie transition
    .byte $A6,$05,$B7      ; GAME: KV 2f + AY 4f + M 2f = 8 frames
    .byte $40              ; PA 3f: ~145ms post-word release/tail
phrase_end:

old_pcr:    .byte $00
timeout_hi: .byte $00
.endproc
