  .inesprg 1    ; 1x 16KB PRG code
  .ineschr 1    ; 1x  8KB CHR data
  .inesmap 0    ; mapper 0 = NROM, no bank swapping
  .inesmir 1    ; background mirroring

  .bank 0
  .org $C000

;;;;;;;;;;;;;;;
  .rsset $0000  ;; start variables at ram location 0

curr_input .rs 1    ; reserve 1 byte for input (from bit 7 - 0: A, B, Select, Start, Up, Down, Left, Right)
last_input .rs 1    ; extra byte to store last frame's input
player_x  .rs 1
player_y  .rs 1
game_state .rs 1    ; information about game state (bit 0 means game is paused. other bits reserved for potential later use)
player_state .rs 1   ; info about player state (bit 0 for horizontal mvmt, bit 1 if jumping)
mvt_timer .rs 1   ; movement timer. caps out at #$03 and resets. used to do walk cycles

;;;;;;;;;;;;;;;

RESET:
  SEI         ; disable IRQs
  CLD         ; disable decimal mode
  LDX #$40
  STX $4017   ; disable APU frame IRQ
  LDX #$FF
  TXS         ; Set up stack
  INX         ; now X = 0
  STX $2000   ; disable NMI
  STX $2001   ; disable rendering
  STX $4010   ; disable DMC IRQs

vblankwait1:       ; First wait for vblank to make sure PPU is ready
  BIT $2002
	BPL vblankwait1

clrmem:
	LDA #$00
  STA $0000, x
  STA $0100, x
  STA $0200, x
  STA $0400, x
  STA $0500, x
  STA $0600, x
  STA $0700, x
  LDA #$FE
  STA $0300, x
  INX
  BNE clrmem
   
vblankwait2:      ; Second wait for vblank, PPU is ready after this
  BIT $2002
  BPL vblankwait2

LoadPalettes:
  LDA $2002           ; read PPU status to reset the high/low latch
  LDA #$3F
  STA $2006           ; write the high byte of $3F00 address
  LDA #$00
  STA $2006           ; write the low byte of $3F00 address
  LDX #$00            ; start out at 0

LoadBackgroundPaletteLoop:
  LDA background_palette, X         ; load data from address (palette + value in x)
  STA $2007           ; write to PPU
  INX
  CPX #$10            ; compare X to $10 - copying 16 bytes = 4 sprites
  BNE LoadBackgroundPaletteLoop

  LDX #$00    ;reset x register to zero to load sprite palette colors

LoadSpritePaletteLoop:
  LDA sprite_palette, X     ;load palette byte
  STA $2007         ;write to PPU
  INX
  CPX #$10
  BNE LoadSpritePaletteLoop

  LDX #$00

LoadSpritesLoop:
  LDA sprites, x    ; load data from address (sprites + x)
  STA $0200, x      ; store into RAM address ($0200 + x)
  INX
  CPX #$10
  BNE LoadSpritesLoop

  LDA #%10000000    ; enable NMI, sprites from Pattern table 0
  STA $2000

  LDA #%00010000    ;enable sprites
  STA $2001

  LDA $0200         ;set y pos of sprite 0
  STA player_y

  LDA $0203         ;set x pos of sprite 0
  STA player_x

Foreverloop:
  JMP Foreverloop

NMI:

  LDA #$00
  STA $2003       ; set the low byte (00) of the RAM address
  LDA #$02
  STA $4014       ; set the high byte (02) of the RAM address, start the transfer

LatchController:
  LDA #$01
  STA $4016
  LDA #$00
  STA $4016         ; tell both controllers to latch buttons

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; Read button presses

ReadA: 
  LDA $4016       ; player 1 - A
  AND #%00000001  ; only look at bit 0
  BEQ ReadADone   ; branch to ReadADone if button is NOT pressed (0)

  CLC
  LDA curr_input
  ADC #%10000000
  STA curr_input
  
ReadADone:        ; handling this button is done
  
ReadB: 
  LDA $4016       ; player 1 - B
  AND #%00000001  ; only look at bit 0
  BEQ ReadBDone   ; branch to ReadBDone if button is NOT pressed (0)

  CLC
  LDA curr_input
  ADC #%01000000
  STA curr_input

ReadBDone:        ; handling this button is done

ReadSelect: 
  LDA $4016       ; player 1 - Select
  AND #%00000001  ; only look at bit 0
  BEQ ReadSelectDone   ; branch to ReadSelectDone if button is NOT pressed (0)

  CLC
  LDA curr_input
  ADC #%00100000
  STA curr_input

ReadSelectDone:

ReadStart: 
  LDA $4016       ; player 1 - Start
  AND #%00000001  ; only look at bit 0
  BEQ ReadStartDone   ; branch to ReadStartDone if button is NOT pressed (0)

  CLC
  LDA curr_input
  ADC #%00010000
  STA curr_input

ReadStartDone:

ReadUp: 
  LDA $4016       ; player 1 - Up
  AND #%00000001  ; only look at bit 0
  BEQ ReadUpDone   ; branch to ReadUpDone if button is NOT pressed (0)

  CLC
  LDA curr_input
  ADC #%00001000
  STA curr_input

ReadUpDone:

ReadDown: 
  LDA $4016       ; player 1 - Down
  AND #%00000001  ; only look at bit 0
  BEQ ReadDownDone   ; branch to ReadDownDone if button is NOT pressed (0)

  CLC
  LDA curr_input
  ADC #%00000100
  STA curr_input

ReadDownDone:

ReadLeft: 
  LDA $4016       ; player 1 - Left
  AND #%00000001  ; only look at bit 0
  BEQ ReadLeftDone   ; branch to ReadLeftDone if button is NOT pressed (0)

  CLC
  LDA curr_input
  ADC #%00000010
  STA curr_input

ReadLeftDone:

ReadRight: 
  LDA $4016       ; player 1 - Right
  AND #%00000001  ; only look at bit 0
  BEQ ReadRightDone ; branch to ReadRightDone if button is NOT pressed (0)

  CLC
  LDA curr_input
  ADC #%00000001
  STA curr_input

ReadRightDone:

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

GameLoop:
  JSR CheckPauseButton
  JSR CheckJumpButton
  JSR CheckDPad

  JSR AnimateShibe

  JMP SetLastInput

;-------------------- Pause Handling

CheckPauseButton:
  LDA curr_input  
  AND #%00010000  ; start pressed?
  BEQ PauseGame   ; no? check if paused

CheckHoldStart:
  LDA last_input
  AND #%00010000  ; start held?
  BNE PauseGame   ; yes? check if paused

  LDA game_state
  EOR #%00000001  ; no? flip bit in game state
  STA game_state

PauseGame:
  LDA game_state
  AND #%00000001  ; game paused?
  BNE JumpPastGameLoop  ; skip game logic
  
  RTS  ; continue if not paused

JumpPastGameLoop:
  JMP SetLastInput

;-------------------- Jump handling

CheckJumpButton:
  LDA curr_input
  AND #%10000000  ; A pressed?
  BNE Jump  ; yes? continue

  LDA player_state  ; no? set jump bit back to zero
  AND #%11111101
  STA player_state

  RTS

Jump:
  LDX player_y
  DEX
  STX player_y  ; decrement (y=0 is top of screen) y value and store position
  ; i'll make gravity work later

  STA $0200   ; store relative y values in sprite tiles
  STA $0204
  ADC #$08
  STA $0208
  STA $020C

  LDA player_state
  ORA #%00000010  ; set jump bit to 1 if not already
  STA player_state

  RTS

;-------------------- D-Pad Handling

CheckDPad:
  LDA curr_input
  AND #%00000011  ; left/right pressed?
  BNE Walking   ; yes? continue

  LDA player_state  ; no? set walking bit back to zero
  AND #%11111110  
  STA player_state

  RTS

Walking:
  LDA player_state  
  ORA #%00000001  ; set walking bit to 1
  STA player_state

  LDA curr_input
  AND #%00000010  ; left pressed?
  BNE WalkLeft  ; yes? walk left

  JMP WalkRight ; no? dpad press already checked. must be walk right

WalkLeft:
  DEC player_x    ; move 1 pixel left per frame

  LDA player_x
  STA $0207   ; store relative x values in sprite tiles
  STA $020F   ; also repositions tiles if sprite is flipped
  CLC
  ADC #$08
  STA $0203
  STA $020B

  LDA #%01000000  ; could flip the bit for each individual tile
  STA $0202       ; don't know if that's necessary yet though
  STA $0206
  STA $020A
  STA $020E

  RTS

WalkRight:
  INC player_x    ; move 1 pixel right per frame

  LDA player_x
  STA $0203   ; store relative x values in sprite tiles
  STA $020B   ; also repositions tiles if sprite is flipped
  CLC
  ADC #$08
  STA $0207
  STA $020F

  LDA #%00000000  ; could flip the bit for each individual tile
  STA $0202       ; don't know if that's necessary yet though
  STA $0206
  STA $020A
  STA $020E

  RTS

;-------------------- Animation Stuff

AnimateShibe:
  LDA player_state
  AND #%00000010
  BNE AnimateJump

  LDA player_state
  AND #%00000001
  BEQ StandStill

  INC mvt_timer
  LDA mvt_timer
  AND #%00001000
  BEQ WalkFrame1  ; likely a better way to do this
  BNE WalkFrame2

  RTS

AnimateJump:
  LDA #$08  ; set jumping sprites
  STA $0209
  LDA #$09
  STA $020D

  RTS

StandStill:
  LDA #$00
  STA mvt_timer   ; reset mvt_timer

  LDA #$02  ; set standing sprites
  STA $0209
  LDA #$03
  STA $020D

  RTS

WalkFrame1:
  LDA #$04  ; set walking sprites
  STA $0209
  LDA #$05
  STA $020D

  RTS

WalkFrame2:
  LDA #$06  ; set walking sprites
  STA $0209
  LDA #$07
  STA $020D

  RTS

;-------------------- Wrapping up current frame

SetLastInput:
  LDA curr_input
  STA last_input  ; Set next frame's last input to this frame's current input
  LDA #$00
  STA curr_input  ; Reset next frame's current input

End:
  RTI

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; color palettes and sprite setup

  .bank 1
  .org $E000

background_palette: 
  .db $22,$29,$1A,$0F   ;background palette 1

sprite_palette:
  .db $22,$16,$27,$20   ;sprite palette 1 (shibe)
  .db $22,$1A,$15,$16   ;ground tile palette (i think ground tiles need to be in the background?? but i dont know how to do that yet. sooooo theyre going in the sprite layer)

sprites:
    ; vert, tile, attr, horiz
  .db $C0, $00, %00000000, $08    ;sprite 0 (top left)
  .db $C0, $01, %00000000, $10    ;sprite 1 (top right)
  .db $C8, $02, %00000000, $08    ;sprite 2 (bottom left)
  .db $C8, $03, %00000000, $10    ;sprite 3 (bottom right)

;;;;;;;;;;;;;;;

  .org $FFFA  ;first of the three vectors starts here
  .dw NMI     ;when an NMI happens (once per frame if enabled) the processor will jump to the label NMI:
  .dw RESET   ;when the processor first turns on or is reset it will jump to the label RESET:
  .dw 0       ;external interrupt IRQ is not used

;;;;;;;;;;;;;;;

  .bank 2
  .org $0000
  .incbin "shibe.chr"   ;includes 8KB graphics file

;;;;;;;;;;;;;;;
