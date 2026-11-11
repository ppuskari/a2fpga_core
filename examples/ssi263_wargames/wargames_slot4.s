; WOPR-inspired SSI-263 speech demonstration: "Shall we play a game?"
; Target: Apple IIe Mockingboard C / a2n20v2-Enhanced in SLOT 4.
; CPU: 6502/65C02. ca65/ld65; load at $6000; CALL 24576.
; Allophone codes are from the pinned SSI-263 physical ROM table,
; reference/ssi263/pico-v1.0.1/rom_bits.csv.
; Phrase and flat intonation intentionally approximate the scene.
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
    lda #$68
    sta SSI_R2             ; slower syllable rate than Disk 1 ($A8)
    lda #$63
    sta SSI_R1             ; nearly fixed inflection (WOPR-like flatness)
    lda #$69
    sta SSI_R3             ; power on, articulation 6, volume 9

    ldy #$00
next_phoneme:
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
phrase:
    .byte $B2,$4C,$60      ; SH / AE / L      "shall"
    .byte $00              ; pause ~160ms
    .byte $A3,$41          ; W / E            "we"
    .byte $80              ; short pause
    .byte $A7,$A0,$45      ; P / L / AY       "play"
    .byte $80              ; short pause
    .byte $8E              ; AH               "a" (unstressed schwa approx)
    .byte $80              ; short pause
    .byte $A6,$45,$77      ; voiced KV / AY / M  "game"
    .byte $00              ; final pause/release
phrase_end:

old_pcr:    .byte $00
timeout_hi: .byte $00
.endproc
