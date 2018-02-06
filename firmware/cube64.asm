    ;;
    ;; GameCube to N64 converter: use your GameCube controllers with an N64 console
    ;; Copyright (C) 2004 Micah Dowty <micah@navi.cx>
    ;;               2011 Jacques Gagnon <darthcloud@gmail.com>
    ;;
    ;;   This program is free software; you can redistribute it and/or modify
    ;;   it under the terms of the GNU General Public License as published by
    ;;   the Free Software Foundation; either version 2 of the License, or
    ;;   (at your option) any later version.
    ;;
    ;; This firmware is designed to run on a PIC18F14K22 microcontroller
    ;; clocked at 64 MHz using the internal 16 MHz clock multiplied by
    ;; the 4x PLL.
    ;;
    ;; See n64gc_comm.inc for code and documentation related to the protocol
    ;; used between here, the N64, and the GameCube.
    ;;
    ;; This file doesn't implement all of the N64 controller protocol, but
    ;; it should correctly emulate an official N64 controller with rumble pak.
    ;; It might not respond to unusual circumstances the same as a real N64
    ;; controller would, both due to potential gaps in the reverse engineering,
    ;; and due to corners cut in the algorithm implementation to fit it on
    ;; this microcontroller.
    ;;

    ;; Definitions for the PIC18F14K22 version
    ifdef  __18F14K22
        #include p18f14k22.inc

        CONFIG FOSC = IRC, PLLEN = ON, PCLKEN = OFF, FCMEN = OFF, IESO = OFF
        CONFIG PWRTEN = OFF, BOREN = OFF
        CONFIG WDTEN = ON, WDTPS = 128
        CONFIG HFOFST = ON, MCLRE = OFF
        CONFIG STVREN = OFF, LVP = OFF, BBSIZ = OFF, XINST = OFF, DEBUG = OFF
        CONFIG CP0 = OFF, CP1 = OFF
        CONFIG CPB = OFF, CPD = OFF
        CONFIG WRT0 = OFF, WRT1 = OFF
        CONFIG WRTC = OFF, WRTB = OFF, WRTD = OFF
        CONFIG EBTR0 = OFF, EBTR1 = OFF
        CONFIG EBTRB = OFF

        #define N64_PIN         PORTA, 5
        #define N64_TRIS        TRISA, 5
        #define GAMECUBE_PIN    PORTA, 4
        #define GAMECUBE_TRIS   TRISA, 4
        #define N64C_PIN        PORTA, 2
        #define N64C_TRIS       TRISA, 2
        #define RAM_START       0x00

io_init macro
        clrf    PORTA
        clrf    WPUA        ; Disable pull-ups.
        movlw   0x34        ; The three pins begin as inputs.
        movwf   TRISA
        clrf    PORTC       ; Debug port
        clrf    TRISC       ; Debug port
        clrf    ANSEL       ; Set IOs to digital.
        clrf    ANSELH
        endm

    else
        messg    "Unsupported processor"
    endif

    ;; Delay of about ~2 ms that allow the PLL to shift the frequency to 64 MHz.
pll_startup_delay macro
    bcf     INTCON, TMR0IF      ; Clear overflow bit.
    movlw   0x44                ; Set 8-bit mode and 1:32 prescaler.
    movwf   T0CON
    clrf    TMR0L               ; Clear timer0.
    bsf     T0CON, TMR0ON       ; Enable timer0 and
    btfss   INTCON, TMR0IF      ; wait for timer0 overflow.
    goto    $-2
    bcf     INTCON, TMR0IF      ; Clear overflow bit and
    bcf     T0CON, TMR0ON       ; disable timer0.
    endm

    #include cube64.inc
    #include n64gc_comm.inc

    ;; Reset and interrupt vectors
    org 0x00
    goto    startup
    org 0x08
    retfie
    org 0x18
    retfie

    ;; Variables.
    cblock  RAM_START
        temp
        temp2
        byte_count
        bit_count
        bus_byte_count
        flags
        flags2
        menu_flags
        virtual_map
        calibration_count
        remap_source_button
        remap_dest_button
        ctrl_slot_status
        target_slot_status
        nv_flags
        temp_key_map
        crc_work

        ;; Stored calibration for each GameCube axis.
        joystick_x_calibration
        joystick_y_calibration
        cstick_x_calibration
        cstick_y_calibration
        left_calibration
        right_calibration

        ;; These four items must be contiguous.
        ;; Note that n64_command and n64_bus_address point to the same memory.
        ;; This is explained in the bus write receive code near n64_wait_for_command.
        n64_command:0
        n64_bus_address:2
        n64_bus_packet:.32
        n64_crc

        n64_id_buffer:3
        gamecube_buffer:6           ; Last 2 bytes for gc_buffer are within the first 2
        gamecube_scale:8            ; bytes of gc_scale as it allows using the same macro
        n64_status_buffer:4         ; for both buffers.
    endc

    ;; *******************************************************************************
    ;; ******************************************************  Initialization  *******
    ;; *******************************************************************************

startup
    movlb   0x00                    ; Set bank 0 active.
    bcf     INTCON, GIE             ; Disable interrupts.
    movlw   0x70                    ; Set internal clock to 16 MHz.
    movwf   OSCCON
    pll_startup_delay               ; Wait for PLL to shift frequency to 64 MHz.
    io_init

    movlw   upper crc_large_table   ; Preload table upper & high address bytes.
    movwf   TBLPTRU
    movlw   high crc_large_table
    movwf   TBLPTRH

    n64gc_init
    clrf    flags
    clrf    flags2
    clrf    menu_flags
    clrf    calibration_count
    clrf    FSR1H                   ; We only need to access first bank, so we set it in FSR high byte right away.
    clrf    nv_flags

    ;; Set controller id to occupied slot.
    movlw   0x01
    movwf   ctrl_slot_status

    movlw   .34                     ; Reset bus_byte_count to 34. Keeping this set beforehand,
    movwf   bus_byte_count          ; saves a few precious cycles in receiving bus writes.

    ;; We use the watchdog to implicitly implement controller probing.
    ;; If we have no GameCube controller attached, gamecube_poll_status
    ;; will never return. We therefore never get around to answering the
    ;; N64's requests. This breaks down if we start up with the GameCube
    ;; controller plugged in but it's unplugged while the N64 is idle, but
    ;; the N64 should be polling us pretty constantly.
    ;;
    ;; The watchdog timeout therefore sets how often we retry in our search
    ;; for a responding GameCube controller. The WDTPS configuration is set to
    ;; a postscaler of 1:128, giving us a nominal watchdog timeout of 512 ms.
    clrwdt

    ;; Check our EEPROM for validity, and reset it if it's blank or corrupted.
    call    validate_eeprom

    ;; To detect if the GC controller is a WaveBird, we send a identify command (0x00)
    ;; to the controller. We then follow with N64 task since the controller won't be responding
    ;; to any command for a while.
gc_controller_id_check
    call    gamecube_get_id
    call    n64_wfc_empty_buffer

    ;; If the controller is a WaveBird we need to do some special initialization process first.
    ;; else we have a standard controller and we are ready to poll status.
    btfss   WAVEBIRD
    goto    gc_controller_ready

    ;; If we have an WaveBird associated with the receiver we are ready to init it.
    ;; else we go back reading the controller id.
    btfss   WAVEBIRD_ASSOCIATED
    goto    gc_controller_id_check

    call    gamecube_init_wavebird
    call    n64_wfc_empty_buffer

    ;; Calibrate the controller now since before that the WaveBird would not have repond to poll status.
    ;; Note that we have to continue on with n64_translate_status and n64_wait_for_command
    ;; because the GameCube controller won't be ready for another poll immediately.
gc_controller_ready
    call    gamecube_poll_status
    call    gamecube_reset_calibration

    ;; Check if the user wants to disable Rumble Pak emulation on boot.
    btfsc   gamecube_buffer + GC_D_RIGHT
    clrf    ctrl_slot_status

    ;; Check if the user wants to use the bypass mode on boot.
    btfsc   gamecube_buffer + GC_D_UP
    bsf     FLAG_BYPASS_MODE

    call    n64_translate_status
    call    n64_wait_for_command

main_loop
    call    update_rumble_feedback  ; Give feedback for remapping operations using the rumble motor.
    call    update_slot_empty_timer ; Report slot empty for 1 s following adaptor mode change.
    call    gamecube_poll_status    ; The GameCube poll takes place during the dead period
    call    n64_translate_status    ; between incoming N64 commands, hopefully.
    call    n64_wait_for_command
    goto    main_loop


    ;; *******************************************************************************
    ;; ******************************************************  Axis Calibration  *****
    ;; *******************************************************************************

    ;; Store calibration values for one GameCube axis. This takes its
    ;; actual neutral position from the gamecube_buffer, and is given
    ;; its ideal neutral position as a parameter. The resulting calibration
    ;; is added to the axis later, with clamping to prevent rollover.
store_calibration macro axis_byte, calibration, ideal_neutral
    movf    gamecube_buffer + axis_byte, w
    sublw   ideal_neutral
    movwf   calibration
    endm

    ;; Add the stored neutral values to an axis to calibrate it, clamping
    ;; it in the event of an overflow.
apply_calibration macro axis_byte, calibration
    local   negative
    local   done

    movf    calibration, w  ; Add the calibration
    addwf   gamecube_buffer + axis_byte, f
    btfsc   calibration, 7  ; Test whether the value we just added was negative
    goto    negative

    movlw   0xFF            ; It was positive, clamp to 0xFF if we carried
    btfsc   STATUS, C
    movwf   gamecube_buffer + axis_byte
    goto    done

negative
    btfss   STATUS, C       ; It was negative, clamp to 0 if we borrowed (C=0)
    clrf    gamecube_buffer + axis_byte

done
    endm

    ;; Store calibration values for each axis. The controller's joysticks should
    ;; be centered and the L and R buttons should be released when this is called.
    ;; We assume this is true at startup, and it should be true when the user invokes
    ;; it by holding down X, Y, and Start.
gamecube_reset_calibration
    store_calibration   GC_JOYSTICK_X,  joystick_x_calibration, 0x80
    store_calibration   GC_JOYSTICK_Y,  joystick_y_calibration, 0x80
    store_calibration   GC_CSTICK_X,    cstick_x_calibration,   0x80
    store_calibration   GC_CSTICK_Y,    cstick_y_calibration,   0x80
    store_calibration   GC_L_ANALOG,    left_calibration,       0x00
    store_calibration   GC_R_ANALOG,    right_calibration,      0x00
    return

    ;; This runs at the beginning of each key remap to check for the X+Y+Start
    ;; calibration sequence. Since we don't have a good way to measure out exactly
    ;; 3 seconds to emulate the GameCube's behavior, we just count the number of
    ;; status polls the keys are held down for. We don't know the exact polling rate,
    ;; but on most games 30 polls should be around a second, which is long enough
    ;; to avoid accidentally recalibrating.
check_calibration_combo
    btfss   gamecube_buffer + GC_X
    goto    no_calibration_combo
    btfss   gamecube_buffer + GC_Y
    goto    no_calibration_combo
    btfss   gamecube_buffer + GC_START
    goto    no_calibration_combo

    incf    calibration_count, f
    movf    calibration_count, w
    xorlw   .30
    btfsc   STATUS, Z
    goto    gamecube_reset_calibration
    return

no_calibration_combo
    clrf    calibration_count
    return


    ;; *******************************************************************************
    ;; **********************************************  Static Button/Axis Mappings  **
    ;; *******************************************************************************

    ;; This static mapping layer translates axes directly from N64 to GameCube, and
    ;; it translates buttons via an intermetdiate virtual button ID that's used by
    ;; the dynamic mapping layer. This layer defines our default mappings.

    ;; Compare absolute value between 2 bytes and assign
    ;; the greater value to the destination.
assign_greater_abs_value macro prospect_byte, dest_byte
    local   next
    movff   prospect_byte, temp
    btfsc   prospect_byte, 7                 ; If prospect negative then
    negf    temp                             ; two's complement it.
    movf    temp, w
    movff   dest_byte, temp
    btfsc   dest_byte, 7                     ; Same for dest.
    negf    temp
    cpfslt  temp                             ; If prospect abs value greater
    goto    next                             ; than dest, overwrite it.
    movff   prospect_byte, dest_byte
next
    endm

    ;; Map a GameCube button to a virtual button, and eventually to an N64 button.
map_button_from macro src_byte, src_bit, virtual
    movlw   virtual
    btfsc   gamecube_buffer+src_byte, src_bit
    call    remap_virtual_button
    endm

    ;; Map a virtual button to an N64 button. If the indicated button is the one
    ;; currently in virtual_button, sets the corresponding N64 bit and returns.
map_button_to macro virtual, dest_byte, dest_bit
    local   next
    movf    virtual_map, w
    xorlw   virtual
    btfss   STATUS, Z
    goto    next
    bsf     n64_status_buffer+dest_byte, dest_bit
    return
next
    endm

    ;; Sign an 8-bit 0x80-centered axis if sign=1.
    ;; Also apply a dead zone.
apply_sign_deadzone macro src_byte, sign
    local   negative_axis_value
    local   next

    if sign
        movlw   0x80                         ; Sign GC axis value.
        subwf   gamecube_buffer + src_byte, f
    endif
    movlw   AXIS_DEAD_ZONE
    btfsc   gamecube_buffer + src_byte, 7    ; Check value sign.
    goto    negative_axis_value

    ;; Current value is positive.
    subwf   gamecube_buffer + src_byte, f
    btfsc   gamecube_buffer + src_byte, 7
    clrf    gamecube_buffer + src_byte
    goto    next

    ;; Current value is negative.
negative_axis_value
    addwf   gamecube_buffer + src_byte, f
    btfss   gamecube_buffer + src_byte, 7
    clrf    gamecube_buffer + src_byte

next
    endm

    ;; GameCube joysticks range differs from the N64. N64 has a maximum of ~84 along the axes origin
    ;; and ~71 in the diagonals. GameCube main joystick has a maximum (once dead zone & sign applied)
    ;; of ~90 and ~65 for the same. C joystick maximums are a bit lower at ~82 and ~57. N64 max value
    ;; once plot will give us a square-ish equilateral hexagon while GameCube is an equiangular &
    ;; equilateral hexagon.
    ;; This function uses the opposite axis as a reference to determine dynamically the scaling value
    ;; required. The scaling values are stored in a table using the fixed point format of 1.7. Once
    ;; multiplied by the joystick value (in 8.0 format) this gives us in our hardware multiplier a
    ;; value in the fixed point 9.7 format.
apply_js_scale macro table, axis_byte, ref_byte
    local   set_scale_buffer
    movf    gamecube_buffer + axis_byte, w
    btfsc   NV_FLAG_SCALING_OFF     ; Bypass scaling if flag set.
    bra     set_scale_buffer

    movlw   high table
    movwf   TBLPTRH                 ; Load the right scaling table.
    movff   gamecube_buffer + ref_byte, TBLPTRL
    TBLRD*
    movf    TABLAT, w
    mulwf   gamecube_buffer + axis_byte

    btfsc   gamecube_buffer + axis_byte, 7
    subwf   PRODH, f                ; If negative stick value, fixup high byte.

    rlcf    PRODL, w
    rlcf    PRODH, w                ; We need an 8.0 value, so shift left our 9.7 value and copy the high byte.
set_scale_buffer
    movwf   gamecube_scale + axis_byte
    endm

    ;; Map a GameCube axis to a virtual button, and eventually to an N64 axis or button.
map_axis_from macro src_byte, virtual
    movff   gamecube_scale + src_byte, temp2
    movlw   virtual
    if virtual & 0x01               ; Check direction (sign) of the virtual button.
        btfsc   temp2, 7            ; Virtual button is negative, skip if buffer positive.
    else
        btfss   temp2, 7            ; Virtual button is positive, skip if buffer negative.
    endif
    call    remap_virtual_axis      ; Call if buffer sign match virtual button sign.
    endm

    ;; Map a virtual button to an N64 axis. If the indicated axis is the one
    ;; currently in virtual_button, sets the corresponding N64 byte if its
    ;; absolute value is greater than the current one.
map_axis_to macro virtual, dest_byte
    local   next
    movf    virtual_map, w
    xorlw   virtual
    btfss   STATUS, Z
    goto    next
    if virtual & 0x01               ; Check direction (sign) of the virtual button.
        btfss   temp2, 7            ; Virtual button is negative, skip if buffer negative.
    else
        btfsc   temp2, 7            ; Virtual button is positive, skip if buffer positive.
    endif
    negf    temp2                   ; Two's complement buffer if sign mismatch.
    assign_greater_abs_value temp2, n64_status_buffer + dest_byte
    return
next
    endm

    ;; Map an unsigned axis to a virtual button given a threshold.
map_button_axis macro axis_byte, virtual, thresh
    movlw   thresh + 1
    subwf   gamecube_buffer + axis_byte, w  ; Axis - (upper_thresh+1)
    movlw   virtual
    btfsc   STATUS, C
    call    remap_virtual_button            ; C=1, B=0, (upper_thresh+1) <= axis
    endm

    ;; Map an 8-bit 0x80-centered axis to two virtual buttons,
    ;; given a threshold.
map_button_axis_sign macro axis_byte, lower_virtual, upper_virtual, thresh
    movlw   -thresh
    subwf   gamecube_buffer + axis_byte, w  ; Axis - lower_thresh
    movlw   lower_virtual
    btfsc   STATUS, OV
    goto    $+8
    btfsc   STATUS, N
    call    remap_virtual_button            ; N=1, OV=0, lower_thresh > axis
    movlw   thresh + 1
    subwf   gamecube_buffer + axis_byte, w  ; Axis - (upper_thresh+1)
    movlw   upper_virtual
    btfsc   STATUS, OV
    goto    $+8
    btfss   STATUS, N
    call    remap_virtual_button            ; N=0, OV=0, (upper_thresh+1) <= axis
    endm

    ;; Map a button to one axis direction.
map_axis_button macro virtual, dest_byte
    local   next
    movf    virtual_map, w
    xorlw   virtual
    btfss   STATUS, Z
    goto    next
    if virtual & 0x01                       ; Set value sign base on virtual button sign.
        movlw   -AXIS_BTN_VALUE
    else
        movlw   AXIS_BTN_VALUE
    endif
    movwf   n64_status_buffer + dest_byte   ; Could be overwritten by a real axis.
next
    endm

    ;; Copy status from the GameCube buffer to the N64 buffer. This first
    ;; stage maps all axes, and maps GameCube buttons to virtual buttons.
n64_translate_status
    movlw   upper gamecube_js_scale ; Preload scale table upper address bytes.
    movwf   TBLPTRU

    movf    nv_flags, w
    andlw   LAYOUT_MASK
    movwf   temp_key_map
    call    check_calibration_combo

    apply_calibration   GC_JOYSTICK_X,  joystick_x_calibration
    apply_calibration   GC_JOYSTICK_Y,  joystick_y_calibration
    apply_calibration   GC_CSTICK_X,    cstick_x_calibration
    apply_calibration   GC_CSTICK_Y,    cstick_y_calibration
    apply_calibration   GC_L_ANALOG,    left_calibration
    apply_calibration   GC_R_ANALOG,    right_calibration

    apply_sign_deadzone GC_JOYSTICK_X, 1
    apply_sign_deadzone GC_JOYSTICK_Y, 1
    apply_sign_deadzone GC_CSTICK_X, 1
    apply_sign_deadzone GC_CSTICK_Y, 1
    apply_sign_deadzone GC_L_ANALOG, 0
    apply_sign_deadzone GC_R_ANALOG, 0

    bcf    STATUS, C                ; Divide by 2 to fit N64 positive axis values. Close enough to the proper range.
    rrcf   gamecube_buffer + GC_L_ANALOG, w
    movwf  gamecube_scale + GC_L_ANALOG
    bcf    STATUS, C
    rrcf   gamecube_buffer + GC_R_ANALOG, w
    movwf  gamecube_scale + GC_R_ANALOG

    apply_js_scale      gamecube_js_scale, GC_JOYSTICK_X, GC_JOYSTICK_Y
    apply_js_scale      gamecube_js_scale, GC_JOYSTICK_Y, GC_JOYSTICK_X
    apply_js_scale      gamecube_cs_scale, GC_CSTICK_X, GC_CSTICK_Y
    apply_js_scale      gamecube_cs_scale, GC_CSTICK_Y, GC_CSTICK_X

    call    check_remap_combo       ; Must be after calibration, since it uses analog L and R values

    ;; Restart here if layout modifier button is pressed.
n64_translate_restart
    clrf    n64_status_buffer + 0   ; Start out with everything zeroed...
    clrf    n64_status_buffer + 1
    clrf    n64_status_buffer + 2
    clrf    n64_status_buffer + 3
    bsf     FLAG_NO_VIRTUAL_BTNS

    map_button_from     GC_A,       BTN_A
    map_button_from     GC_B,       BTN_B
    map_button_from     GC_Z,       BTN_RZ
    map_button_from     GC_R,       BTN_R
    map_button_from     GC_L,       BTN_L
    map_button_from     GC_START,   BTN_START

    map_button_from     GC_X,       BTN_X
    map_button_from     GC_Y,       BTN_Y

    map_button_from     GC_D_LEFT,  BTN_D_LEFT
    map_button_from     GC_D_RIGHT, BTN_D_RIGHT
    map_button_from     GC_D_UP,    BTN_D_UP
    map_button_from     GC_D_DOWN,  BTN_D_DOWN

    map_axis_from       GC_JOYSTICK_X,  BTN_LJ_LEFT
    map_axis_from       GC_JOYSTICK_X,  BTN_LJ_RIGHT
    map_axis_from       GC_JOYSTICK_Y,  BTN_LJ_DOWN
    map_axis_from       GC_JOYSTICK_Y,  BTN_LJ_UP
    map_axis_from       GC_CSTICK_X,  BTN_RJ_LEFT
    map_axis_from       GC_CSTICK_X,  BTN_RJ_RIGHT
    map_axis_from       GC_CSTICK_Y,  BTN_RJ_DOWN
    map_axis_from       GC_CSTICK_Y,  BTN_RJ_UP
    map_axis_from       GC_R_ANALOG,  BTN_RA
    map_axis_from       GC_L_ANALOG,  BTN_LA

    bsf     FLAG_AXIS
    map_button_axis_sign     GC_JOYSTICK_X, BTN_LJ_LEFT, BTN_LJ_RIGHT, AXIS_BTN_THRS
    map_button_axis_sign     GC_JOYSTICK_Y, BTN_LJ_DOWN, BTN_LJ_UP, AXIS_BTN_THRS
    map_button_axis_sign     GC_CSTICK_X, BTN_RJ_LEFT, BTN_RJ_RIGHT, AXIS_BTN_THRS
    map_button_axis_sign     GC_CSTICK_Y, BTN_RJ_DOWN, BTN_RJ_UP, AXIS_BTN_THRS
    map_button_axis          GC_R_ANALOG, BTN_RA, TRIGGER_BTN_THRS
    map_button_axis          GC_L_ANALOG, BTN_LA, TRIGGER_BTN_THRS
    bcf     FLAG_AXIS

    btfsc   FLAG_NO_VIRTUAL_BTNS
    bcf     FLAG_WAITING_FOR_RELEASE
    bcf     FLAG_LAYOUT_MODIFIER
    return

    ;; This is called by remap_virtual_button to convert a virtual button code,
    ;; in virtual_button, to a set bit in the N64 status packet.
set_virtual_button
    map_button_to   BTN_D_RIGHT,    N64_D_RIGHT
    map_button_to   BTN_D_LEFT,     N64_D_LEFT
    map_button_to   BTN_D_DOWN,     N64_D_DOWN
    map_button_to   BTN_D_UP,       N64_D_UP

    map_button_to   BTN_START,      N64_START
    map_button_to   BTN_RZ,         N64_Z
    map_button_to   BTN_B,          N64_B
    map_button_to   BTN_A,          N64_A
    map_button_to   BTN_R,          N64_R
    map_button_to   BTN_L,          N64_L
    map_button_to   BTN_RA,         N64_R
    map_button_to   BTN_LA,         N64_L

    map_button_to   BTN_RJ_RIGHT,   N64_C_RIGHT
    map_button_to   BTN_RJ_LEFT,    N64_C_LEFT
    map_button_to   BTN_RJ_DOWN,    N64_C_DOWN
    map_button_to   BTN_RJ_UP,      N64_C_UP

    btfsc   FLAG_AXIS
    return

    map_axis_button BTN_LJ_RIGHT,   N64_JOYSTICK_X
    map_axis_button BTN_LJ_LEFT,    N64_JOYSTICK_X
    map_axis_button BTN_LJ_DOWN,    N64_JOYSTICK_Y
    map_axis_button BTN_LJ_UP,      N64_JOYSTICK_Y
    return

set_virtual_axis
    map_axis_to     BTN_LJ_LEFT,    N64_JOYSTICK_X
    map_axis_to     BTN_LJ_RIGHT,   N64_JOYSTICK_X
    map_axis_to     BTN_LJ_DOWN,    N64_JOYSTICK_Y
    map_axis_to     BTN_LJ_UP,      N64_JOYSTICK_Y
    return

    ;; This is called by remap_virtual_button to convert a virtual button code,
    ;; in virtual button, to a special function of the adapter. This set of virtual
    ;; buttons do not result in any key press on the host system.
set_special_button
    btfsc   FLAG_LAYOUT_MODIFIER    ; Allow only one level of layout modifier.
    bra     skip_layout_modifier

    ;; Check for layout modifier special function.
    andlw   ~LAYOUT_MASK
    xorlw   BTN_MODIFIER
    bz      special_layout_modifier

skip_layout_modifier
    return

    ;; We got a layout modifier button and we need to start over
    ;; the mapping in n64_translate_status.
special_layout_modifier
    bsf     FLAG_LAYOUT_MODIFIER
    movlw   LAYOUT_MASK
    andwf   virtual_map, w
    movwf   temp_key_map
    pop                             ; Pop the stack since we abort this call.
    goto    n64_translate_restart


    ;; *******************************************************************************
    ;; *************************************************  Dynamic Button Remapping  **
    ;; *******************************************************************************

    ;; This is called each time we poll status, for each virtual button that's pressed.
    ;; Here we get a virtual button code in 'w'. Normally we remap this via the EEPROM
    ;; and pass the code on to set_virtual_button.
    ;;
    ;; If we're awaiting a keypress for remapping purposes, this doesn't give any virtual
    ;; button presses to the N64.
    ;;
    ;; Our EEPROM starts with one byte per virtual button, containing the virtual button
    ;; code its mapped to. By default, each byte just contains its address, mapping all
    ;; virtual buttons to themselves.

remap_virtual_button
    ;; Remember that a button is pressed, so we can detect when all have been released
    bcf     FLAG_NO_VIRTUAL_BTNS

    ;; Leave now if we're waiting for buttons to be released
    btfsc   FLAG_WAITING_FOR_RELEASE
    return

    ;; Accept buttons presses if we're waiting for one
    btfsc   FLAG_TOP_CONFIG_MENU
    goto    accept_config_menu_select
    btfsc   FLAG_SOURCE_WAIT
    goto    accept_source
    btfsc   FLAG_REMAP
    goto    accept_remap_dest
    btfsc   FLAG_SPECIAL
    goto    accept_special_dest
    btfsc   FLAG_MODE_SUBMENU
    goto    accept_mode_select
    btfsc   FLAG_LAYOUT_SUBMENU
    goto    accept_layout_select

    ;; Pass anything else on to the N64, mapped through the EEPROM first
    eeprom_btn_addr temp_key_map, 0
    call    eeread
    andlw   BTN_MASK | SPECIAL_MASK
    movwf   virtual_map

    btfss   virtual_map, SPECIAL_BIT
    goto    set_virtual_button
    goto    set_special_button

remap_virtual_axis
    eeprom_btn_addr temp_key_map, 0
    call    eeread
    andlw   BTN_MASK | SPECIAL_MASK
    movwf   virtual_map
    goto    set_virtual_axis

    ;; Looks for the key combinations we use to change button mapping
check_remap_combo
    ;; Leave now if we're waiting for buttons to be released
    btfsc   FLAG_WAITING_FOR_RELEASE
    return

    ;; Key combinations require that the L and R buttons be mostly pressed.
    ;; but that the end stop buttons aren't pressed.
    ;; Ensure the high bit of each axis is set and that the buttons are cleared.
    btfss   gamecube_buffer + GC_L_ANALOG, 7
    return
    btfss   gamecube_buffer + GC_R_ANALOG, 7
    return
    btfsc   gamecube_buffer + GC_L
    return
    btfsc   gamecube_buffer + GC_R
    return

    ;; Enter config menu if third key is Start.
    btfss   gamecube_buffer + GC_START
    return

    ;; The config menu button combo was pressed. Give feedback via the rumble motor,
    ;; and await button presses from the user indicating which menu option they want
    ;; access to. Selection is handled into remap_virtual_button since we need virutal
    ;; button codes.
    bsf     FLAG_WAITING_FOR_RELEASE
    bsf     FLAG_TOP_CONFIG_MENU
    goto    start_rumble_feedback

    ;; Accept the virtual button pressed for menu selection in 'w', and
    ;; set the right flag for next user input.
accept_config_menu_select
    bcf     FLAG_TOP_CONFIG_MENU
    bsf     FLAG_WAITING_FOR_RELEASE

    ;; The remap button combo was pressed. Give feedback via the rumble motor,
    ;; and await button presses from the user indicating what they want to remap.
    ;; We actually read the source and destination keys in remap_virtual_button,
    ;; since we need virtual button codes.
    btfsc   gamecube_buffer + GC_START
    bra     menu_remap_source_wait

    ;; The special function combo was pressed. Same process as remap combo.
    btfsc   gamecube_buffer + GC_Y
    bra     menu_special_source_wait

    bcf     FLAG_TRIGGER            ; Flag not used in following commands.

    ;; The analog trigger mapping combo was pressed.
    ;; This modify both remap and special combo to allow mapping to analog trigger.
    btfsc   gamecube_buffer + GC_X
    bra     menu_trigger_flag_set

    ;; The reset combo was pressed. Reset the EEPROM contents of the current active button
    ;; layout, and use the rumble motor for feedback if possible.
    btfsc   gamecube_buffer + GC_Z
    bra     menu_reset_active_eeprom_layout

    ;; The adapter mode submenu was selected in the config menu.
    btfsc   gamecube_buffer + GC_D_UP
    bra     menu_mode_submenu

    ;; The button layout submenu was selected in the config menu.
    btfsc   gamecube_buffer + GC_D_LEFT
    bra     menu_layout_submenu

    return

menu_remap_source_wait
    bsf     FLAG_REMAP
    bsf     FLAG_SOURCE_WAIT
    goto    start_rumble_feedback

menu_special_source_wait
    bsf     FLAG_SPECIAL
    bsf     FLAG_SOURCE_WAIT
    goto    start_rumble_feedback

menu_trigger_flag_set
    bsf     FLAG_TRIGGER
    bsf     FLAG_TOP_CONFIG_MENU
    goto    start_rumble_feedback

menu_reset_active_eeprom_layout
    call    reset_active_eeprom_layout
    goto    start_rumble_feedback

menu_mode_submenu
    bsf     FLAG_MODE_SUBMENU
    goto    start_rumble_feedback

menu_layout_submenu
    bsf     FLAG_LAYOUT_SUBMENU
    goto    start_rumble_feedback

    ;; Accept the virtual button code for the remap source in 'w', and prepare
    ;; to accept the remap destination.
accept_source
    movwf   remap_source_button
    bsf     FLAG_WAITING_FOR_RELEASE
    bcf     FLAG_SOURCE_WAIT
    return

    ;; Accept the virtual button code for the remap destination in 'w', and write
    ;; the button mapping to EEPROM.
accept_remap_dest
    movwf   EEDATA              ; Destination button is data, source is address.
    bsf     FLAG_WAITING_FOR_RELEASE
    bcf     FLAG_REMAP

    bra     common_accept_dest

    ;; Accept the virtual button code for the special function destination in 'w'.
accept_special_dest
    movwf   EEDATA
    bsf     FLAG_WAITING_FOR_RELEASE
    bcf     FLAG_SPECIAL

    ;; Validate if one of the D-pad direction is pressed for the layout modifier function.
    ;; Save as a special button if so, return otherwise.
    andlw   ~LAYOUT_MASK        ; Check for any D-pad direction.
    bz      common_accept_dest - 2
    bcf     FLAG_TRIGGER
    return

    bsf     EEDATA, SPECIAL_BIT
common_accept_dest
    btfsc   FLAG_TRIGGER        ; If flag set, this means we want to allow analog trigger mapping.
    bra     save_mapping

    movf    remap_source_button, w
    andlw   TRIGGER_TYPE_MASK
    xorlw   BTN_LA
    btfsc   STATUS, Z           ; If analog trigger, overwrite source with digital trigger.
    incf    remap_source_button

save_mapping
    bcf     FLAG_TRIGGER
    movf    remap_source_button, w
    mullw   EEPROM_BTN_BYTE     ; Offset base on how many bytes per button.
    movff   PRODL, EEADR
    movf    nv_flags, w   ; Add offset to EEPROM address to read the right custom buttons layout.
    andlw   LAYOUT_MASK
    mullw   EEPROM_LAYOUT_SIZE
    movf    PRODL, w
    addwf   EEADR, f
    call    eewrite
    goto    start_rumble_feedback

    ;; Accept the adapter mode selection.
accept_mode_select
    movwf   target_slot_status
    bsf     FLAG_WAITING_FOR_RELEASE
    bcf     FLAG_MODE_SUBMENU

    movf    target_slot_status, w
    xorlw   BTN_D_DOWN
    btfsc   STATUS, Z
    return

    bsf     FLAG_FORCE_EMPTIED
    bcf     FLAG_BYPASS_MODE

    movlw   0x02
    movwf   ctrl_slot_status
    goto    start_rumble_feedback

accept_adaptor_mode
    goto    start_rumble_feedback

    ;; Accept the button layout selection.
accept_layout_select
    movwf   remap_source_button
    bsf     FLAG_WAITING_FOR_RELEASE
    bcf     FLAG_LAYOUT_SUBMENU
    andlw   ~LAYOUT_MASK            ; Check for any D-pad direction.
    bnz     check_js_toggle

    movlw   ~LAYOUT_MASK
    andwf   nv_flags, f
    movf    remap_source_button, w
    iorwf   nv_flags, f
    bra     write_nv_flags

check_js_toggle
    movf    remap_source_button, w
    xorlw   BTN_X
    btfss   STATUS, Z
    return
    btg     NV_FLAG_SCALING_OFF

write_nv_flags
    movff   nv_flags, EEDATA
    movlw   EEPROM_NV_FLAGS
    movwf   EEADR
    call    eewrite
    goto    start_rumble_feedback

    ;; Check our EEPROM for the magic word identifying it as button mapping data for
    ;; this version of our firmware. If we don't find the magic word, reset its contents.
validate_eeprom
    movlw   EEPROM_MAGIC_ADDR       ; Check high byte
    call    eeread
    xorlw   EEPROM_MAGIC_WORD >> 8
    btfss   STATUS, Z
    goto    reset_eeprom
    movlw   EEPROM_MAGIC_ADDR + 1   ; Check low byte
    call    eeread
    xorlw   EEPROM_MAGIC_WORD & 0xFF
    btfss   STATUS, Z
    goto    reset_eeprom

    movlw   EEPROM_NV_FLAGS         ; Load last used custom layout.
    call    eeread
    movwf   nv_flags
    return

    ;; Write an identity mapping and a valid magic word to the EEPROM.
reset_eeprom
    movlw   upper eeprom_default    ; Load address for EEPROM layout default.
    movwf   TBLPTRU
    movlw   high eeprom_default
    movwf   TBLPTRH

    movlw   EEPROM_LAYOUT_0         ; Loop over all virtual buttons, writing the identity mapping.
    movwf   EEADR
next_eeprom_bank
    clrf    TBLPTRL
    TBLRD*
    movff   TABLAT, EEDATA
    call    reset_next_byte
    movf    EEADR, w
    xorlw   EEPROM_LAYOUT_0 + EEPROM_LAYOUT_SIZE * 4
    btfss   STATUS, Z
    goto    next_eeprom_bank

    movlw   EEPROM_MAGIC_ADDR       ; Write the magic word
    movwf   EEADR
    movlw   EEPROM_MAGIC_WORD >> 8
    movwf   EEDATA
    call    eewrite
    movlw   EEPROM_MAGIC_ADDR + 1
    movwf   EEADR
    movlw   EEPROM_MAGIC_WORD & 0xFF
    movwf   EEDATA
    call    eewrite

    movlw   EEPROM_NV_FLAGS         ; Init default layout in EEPROM.
    movwf   EEADR
    movlw   0x00
    movwf   EEDATA
    goto    eewrite

    ;; Reset only data relative to the current active button mapping layout.
reset_active_eeprom_layout
    movlw   upper eeprom_default    ; Load address for EEPROM layout default.
    movwf   TBLPTRU
    movlw   high eeprom_default
    movwf   TBLPTRH
    clrf    TBLPTRL

    movf    nv_flags, w
    andlw   LAYOUT_MASK
    mullw   EEPROM_LAYOUT_SIZE
    movff   PRODL, EEADR
    TBLRD*
    movff   TABLAT, EEDATA

    ;; Reset to default all button beginning at the current address set.
reset_next_byte
    call    eewrite
    incf    EEADR, f
    TBLRD+*
    movff   TABLAT, EEDATA
    movf    TBLPTRL, w
    xorlw   EEPROM_LAYOUT_SIZE
    btfss   STATUS, Z
    goto    reset_next_byte
    return

    ;; Read from address 'w' of the EEPROM, return in 'w'.
eeread
    movwf   EEADR
    bcf     EECON1, EEPGD       ; Select EEPROM.
    bcf     EECON1, CFGS
    bsf     EECON1, RD
    movf    EEDATA, w
    return

    ;; Write to the EEPROM using the current EEADR and EEDATA values,
    ;; block until the write is complete.
eewrite
    clrwdt
    bcf     EECON1, EEPGD       ; Select EEPROM.
    bcf     EECON1, CFGS
    bsf     EECON1, WREN        ; Enable write
    movlw   0x55                ; Write the magic sequence to EECON2
    movwf   EECON2
    movlw   0xAA
    movwf   EECON2
    bsf     EECON1, WR          ; Begin write
    btfsc   EECON1, WR          ; Wait for it to finish...
    goto    $-2
    bcf     EECON1, WREN        ; Write protect
    return

    ;; Briefly enable the rumble motor on our own, as feedback during remap combos.
    ;; This use TMR0 in 16-bit mode and will provide feedback for 250 ms.
start_rumble_feedback
    bsf     FLAG_RUMBLE_FEEDBACK
    bcf     INTCON, TMR0IF      ; Clear overflow bit.
    movlw   0x87                ; Enable 16-bit mode with 1:256 prescaler.
    movwf   T0CON
    movlw   0xC2
    movwf   TMR0H
    movlw   0xF6
    movwf   TMR0L               ; TMR0 now loaded with 0xC2F6.
    return

    ;; At each status poll, turn on the rumble motor if we're in the middle of
    ;; giving feedback.
update_rumble_feedback
    btfss   FLAG_RUMBLE_FEEDBACK
    return
    bsf     FLAG_RUMBLE_MOTOR_ON

    btfss   INTCON, TMR0IF
    return
    bcf     FLAG_RUMBLE_FEEDBACK
    bcf     FLAG_RUMBLE_MOTOR_ON ; We need to turn off the motor when we're done.
    bcf     T0CON, TMR0ON
    return

    ;; When switching between adaptor mode, we need to report the controller slot as
    ;; empty for at least 1 s. Otherwise the N64 wouldn't know we might have changed
    ;; accessories. The rumble feedback already provide 250 ms. This set TMR0 for
    ;; another 750 ms.
start_slot_empty_timer
    bcf     INTCON, TMR0IF      ; Clear overflow bit.
    movlw   0x87                ; Enable 16-bit mode with 1:256 prescaler.
    movwf   T0CON
    movlw   0x48
    movwf   TMR0H
    movlw   0xE4
    movwf   TMR0L               ; TMR0 now loaded with 0x48E4.
    return

    ;; Start timer after rumble feedback is done. Then once the timer overflow
    ;; set the proper slot status and bypass mode.
update_slot_empty_timer
    btfss   FLAG_FORCE_EMPTIED
    return
    btfsc   FLAG_RUMBLE_FEEDBACK ; Let rumble feedback finish first.
    return
    btfss   T0CON, TMR0ON        ; Init timer.
    call    start_slot_empty_timer
    btfss   INTCON, TMR0IF
    return

    bcf     FLAG_FORCE_EMPTIED
    bcf     T0CON, TMR0ON
    movf    target_slot_status, w
    btfsc   STATUS, Z           ; If 0x00 we need to set bypass mode.
    bsf     FLAG_BYPASS_MODE
    movff   target_slot_status, ctrl_slot_status
    return


    ;; *******************************************************************************
    ;; ******************************************************  N64 Interface *********
    ;; *******************************************************************************

    ;; While waiting for a WaveBird to associate, we don't have any status poll
    ;; so we need to empty the n64_status_buffer before n64_wait_for_command.
n64_wfc_empty_buffer
    clrf    n64_status_buffer + 0
    clrf    n64_status_buffer + 1
    clrf    n64_status_buffer + 2
    clrf    n64_status_buffer + 3

    ;; Service commands coming in from the N64
n64_wait_for_command
    movlw   upper crc_large_table   ; Preload CRC table upper & high address bytes.
    movwf   TBLPTRU
    movlw   high crc_large_table
    movwf   TBLPTRH

    call    n64_wait_for_idle   ; Ensure the line is idle first, so we don't jump in to the middle of a command

    movlw   n64_command         ; Receive 1 command byte
    movwf   FSR1L
    call    n64_rx_command

ifndef DBG_TRACE
    btfsc   FLAG_BYPASS_MODE
endif
    bra     n64_bypass_mode

    ;; We need to handle controller pak writes very fast because there's no pause
    ;; between the initial command byte and the 34 bytes following. Every
    ;; extra instuction here increases the probability of missing the first bit.
    ;;
    ;; FSR is already pointing at the right buffer- n64_rx will leave FSR pointing
    ;; at the last byte it read, which is n64_command. We've overlaid n64_command
    ;; onto the same memory as our address buffer, and the data buffer is immediately
    ;; after our address buffer.
    ;;
    ;; Since n64_rx must be called as soon as possible, this skips n64_rx if we're not
    ;; doing a write_bus command, and after the fact detects that and looks for other commands.
    ;;
    movlw   N64_COMMAND_WRITE_BUS
    xorwf   n64_command, w
    btfsc   STATUS, Z
    call    n64_rx_bus              ; Do another receive if this was a write_bus command.

    movlw   n64_command             ; n64_command itself might be invalid now. If FSR changed,
    xorwf   FSR1L, w                ; n64_command is invalid and we're doing a bus write
    btfss   STATUS, Z               ; to send the CRC.
    goto    n64_bus_write

    movf    n64_command, w          ; Detect other applicable commands...
    xorlw   N64_COMMAND_READ_BUS
    btfsc   STATUS, Z
    goto    n64_bus_read

    bsf     N64C_TRIS               ; Reset bypass bus state.

    movf    n64_command, w          ; Check for both identity cmd (0x00 & 0xFF) at the same time.
    btfss   STATUS, Z
    comf    n64_command, w
    btfsc   STATUS, Z
    goto    n64_send_id

    movf    n64_command, w
    xorlw   N64_COMMAND_STATUS
    btfsc   STATUS, Z
    goto    n64_send_status

    goto    n64_wait_for_command    ; Ignore unimplemented commands

    ;; Macro for completing the last bit and sending 1 us stop bit.
stop_bit macro cycle
    wait    cycle
    bsf     N64C_TRIS
    wait    .15
    bcf     N64C_TRIS
    wait    .15
    bsf     N64C_TRIS
    endm

    ;; In bypass mode we only handle the status command. Identity, read and write commands
    ;; are left to the real N64 controller to answer.
n64_bypass_mode
    ;; Need to get back receiving for read and write commands.
    movf    n64_command, w
    xorlw   N64_COMMAND_WRITE_BUS
    btfsc   STATUS, Z
    goto    n64_write_copy

    movf    n64_command, w
    xorlw   N64_COMMAND_READ_BUS
    btfsc   STATUS, Z
    goto    n64_read_copy

    stop_bit .15                    ; Send 1 us stop bit to N64 controller.

    ;; Identity is bypassed too since it provides slot information.
    movf    n64_command, w          ; Check for both identity cmd (0x00 & 0xFF) at the same time.
    btfss   STATUS, Z
    comf    n64_command, w
    btfsc   STATUS, Z
    goto    n64_identity_copy

    ;; Adaptor only answer status command.
    movf    n64_command, w
    xorlw   N64_COMMAND_STATUS
    btfsc   STATUS, Z

    ;; In tracing mode the adaptor simply passthough everything and
    ;; copy it on the debug port.
ifdef DBG_TRACE
    goto    n64_status_copy
else
    goto    n64_send_status
endif

    goto    n64_wait_for_command    ; Ignore unimplemented commands.

    ;; Copy 3 bytes from controller to host.
n64_identity_copy
    movlw   3
    bra     n64_bus_copy_device

    ;; Copy 4 bytes from controller to host.
n64_status_copy
    movlw   4
    bra     n64_bus_copy_device

    ;; Copy remaining 2 address bytes then send 1 us stop bit.
    ;; Then, copy 33 bytes from controller to host.
n64_read_copy
    wait    .8
    movlw   2
    call    n64_bus_copy_host
    stop_bit .31                    ; Send 1 us stop bit to N64 controller.
    movlw   .33
    bra     n64_bus_copy_device

    ;; Copy remaining 32 bytes then send 1 us stop bit.
    ;; Then, copy 1 bytes CRC from controller to host.
n64_write_copy
    wait    .8
    movlw   .34
    call    n64_bus_copy_host
    stop_bit .31                    ; Send 1 us stop bit to N64 controller.
    movlw   1
    bra     n64_bus_copy_device

    ;; Receive from the host and copy to dummy controller.
    ;; Send no stop bit.
n64_bus_copy_host
    movwf   byte_count
    bsf     N64C_TRIS
    bcf     N64C_PIN
    n64_bus_copy N64_PIN, N64C_TRIS, byte_count, 0, 0

    ;; Receive from dummy controller and copy to host.
    ;; Send 2 us stop bit.
n64_bus_copy_device
    movwf   byte_count
    bsf     N64_TRIS
    bcf     N64_PIN
    n64_bus_copy N64C_PIN, N64_TRIS, byte_count, 0, 1

    ;; The N64 requested a 32-byte write to our controller pak bus.
    ;; The start address is given in the high 11 bits of n64_bus_address.
    ;; The low 5 bits are to verify the address- the algorithm for this is
    ;; known, but to save time they are currently ignored.
    ;; Addresses from 0x0000 to 0x7FFF are only used by the memory pak's RAM.
    ;; To emulate a rumble pak, we should only need to respond to configuration
    ;; writes at 0x8000 and rumble pak motor writes at 0xC000.
    ;;
    ;; Since all the packets we'll get while emulating a rumble pak are copies
    ;; of the same byte, we assume this is always true and use a table storing
    ;; the checksums of all such packets. We always negate the checksum to indicate
    ;; that a controller pak has been detected and initialized properly.
n64_bus_write
    movlw   .25                 ; We have about 3us to kill here, we don't
    movwf   bus_byte_count      ; want to begin transmitting before the stop bit is over.
time_killing
    decfsz  bus_byte_count, f
    goto    time_killing

    movlw   .34                 ; Reset bus_byte_count to 34. Keeping this set beforehand
    movwf   bus_byte_count      ; saves a few precious cycles in receiving bus writes.

    movf    crc_work, w         ; Computed CRC already in crc_work.
    xorlw   0xFF                ; Negate the CRC, we emulate a rumble pak.
    movwf   n64_crc             ; Send back the CRC in a 1-byte transmission.
    movlw   n64_crc
    movwf   FSR1L
    movlw   1
    call    n64_tx              ; We need a 2us stop bit after all CRCs.

    movf    n64_bus_address, w  ; Is this a write to the rumble pak?
    xorlw   0xC0                ; (only check the top 8 bits. This excludes a few address bits and all check bits).
    btfss   STATUS, Z
    return                      ; Nope, return. We ignore the initialization writes to 0x8000.

    btfss   ctrl_slot_status, 0 ; Do not rumble if we are supose to be an empty controller.
    return

    bcf     FLAG_RUMBLE_MOTOR_ON    ; Set the rumble flag from the low bit of the first data byte.
    btfsc   n64_bus_packet + 0, 0
    bsf     FLAG_RUMBLE_MOTOR_ON
    return

    ;; The N64 requested a 32-byte read from our controller pak bus.
    ;; If all is well, this should only happen at address 0x8000, where it
    ;; tries to identify what type of controller pak we have. Always
    ;; indicate we have a rumble pak by sending all 0x80s.
n64_bus_read
    movlw   .2                  ; Read 2 address bytes.
    movwf   byte_count          ; FSR already point at n64_bus_address.
    call    n64_rx_address

    movlw   .32
    movwf   byte_count

    movlw   0x01                ; Check if address is 0x8001, answer 0x80s if so.
    xorwf   n64_bus_address + 1, w
    btfss   STATUS, Z
    goto    zero_packet
    movlw   0x80
    xorwf   n64_bus_address + 0, f
    btfss   STATUS, Z
    goto    zero_packet
    goto    setup_buffer        ; We conveniently already got 0x80 in w.
zero_packet
    movlw   0x00                ; Otherwise reply 0x00s.

setup_buffer
    incf    FSR1L, f

bus_read_fill_loop
    movwf   INDF1
    incf    FSR1L, f
    decfsz  byte_count, f
    goto    bus_read_fill_loop

    movlw   0xFF                ; Preload n64_crc for final CRC XOR.
    movwf   n64_crc

    movlw   n64_bus_packet      ; Send back the data and CRC.
    movwf   FSR1L
    movlw   .33                 ; Send 32 bytes data and 1 byte CRC right after.
    goto    n64_tx              ; We need a 2us stop bit after all CRCs.

    ;; The N64 asked for our button and joystick status.
n64_send_status
    movlw   n64_status_buffer   ; Transmit the status buffer
    movwf   FSR1L
    movlw   4
    goto    n64_tx

    ;; The N64 asked for our identity. Report that we're an
    ;; N64 controller with the controller pak slot occupied or empty.
n64_send_id
    movlw   0x05
    movwf   n64_id_buffer + 0
    movlw   0x00
    movwf   n64_id_buffer + 1
    movf    ctrl_slot_status, w
    movwf   n64_id_buffer + 2

    movlw   n64_id_buffer       ; Transmit the ID buffer
    movwf   FSR1L
    movlw   3
    goto    n64_tx

    ;; Don't return until the N64 data line has been idle long enough to ensure
    ;; we aren't in the middle of a packet already.
n64_wait_for_idle
    movlw   0x33
    movwf   temp
keep_waiting_for_idle
    btfss   N64_PIN
    goto    n64_wait_for_idle
    decfsz  temp, f
    goto    keep_waiting_for_idle
    return

    ;; Before transmitting, we explicitly force the output latch low- it may have
    ;; been left high by a read-modify-write operation elsewhere.
    ;; For controller response we allways need an 2us stop bit.
n64_tx
    wait    .55
    bsf     N64_TRIS
    bcf     N64_PIN
    n64gc_tx_buffer N64_TRIS, 1

n64_rx_bus
    n64gc_rx_buffer N64_PIN, bus_byte_count, 0

n64_rx_address
    n64gc_rx_buffer N64_PIN, byte_count, 0

n64_rx_command
    movlw   .1
    movwf   byte_count
    bsf     N64C_TRIS
    bcf     N64C_PIN
    n64_bus_copy N64_PIN, N64C_TRIS, byte_count, 1, 0 ; Clear the watchdog while waiting for commands.


    ;; *******************************************************************************
    ;; ******************************************************  GameCube Interface  ***
    ;; *******************************************************************************

    ;; To support the WaveBird we must poll the controller identity first.
gamecube_get_id
    movlw   0x00                    ; Put 0x00 in the gamecube_buffer.
    movwf   gamecube_buffer + 0

    movlw   gamecube_buffer         ; Transmit the gamecube_buffer.
    movwf   FSR1L
    movlw   1
    call    gamecube_tx

    movlw   gamecube_buffer         ; Receive 3 status bytes.
    movwf   FSR1L
    movlw   3
    call    gamecube_rx

    btfss   gamecube_buffer + 0, 7  ; Check only the MSB of the first byte since it's enough
    return                          ; to tell between normal controller and WaveBird.

    movlw   0x02                    ; WaveBird don't have rumble motor so we show to the N64
    movwf   ctrl_slot_status        ; that we are a controller with empty slot.

    bsf     WAVEBIRD                ; We have a WaveBird receiver connected and we check if
    movf    gamecube_buffer, w      ; a WaveBird is associated with it.
    xorlw   0xA8
    btfsc   STATUS, Z
    return

    bsf     WAVEBIRD_ASSOCIATED     ; WaveBird is associated and we save his unique id.
    return

    ;; If we receive something other than 0xA8xxxx as ID we must repond with the WaveBird unique ID
    ;; at the end of command 0x4Exxxx to enable the WaveBird. It will not answer the poll status otherwise.
gamecube_init_wavebird
    movlw   0x4E                    ; Put 0x4Exxxx in the gamecube_buffer to enable WaveBird.
    movwf   gamecube_buffer + 0

    ;; Two other bytes containing the WB unique ID already in the buffer.
    bcf     gamecube_buffer + 1, 5  ; Bits 5 and 4 are always 0 & 1 respectively in a 0x4E init command.
    bsf     gamecube_buffer + 1, 4

    movlw   gamecube_buffer         ; Transmit the gamecube_buffer.
    movwf   FSR1L
    movlw   3
    call    gamecube_tx

    movlw   gamecube_buffer         ; Receive 3 status bytes
    movwf   FSR1L
    movlw   3
    call    gamecube_rx
    return

    ;; Poll the GameCube controller's state by transmitting a magical
    ;; poll command (0x400300) then receiving 8 bytes of status.
gamecube_poll_status
    movlw   0x40                    ; Put 0x400300 in the gamecube_buffer
    movwf   gamecube_buffer + 0
    movlw   0x03
    movwf   gamecube_buffer + 1
    movlw   0x00
    movwf   gamecube_buffer + 2

    btfsc   FLAG_RUMBLE_MOTOR_ON    ; Set the low bit of our GameCube command to turn on rumble.
    bsf     gamecube_buffer + 2, 0

    movlw   gamecube_buffer         ; Transmit the gamecube_buffer
    movwf   FSR1L
    movlw   3
    call    gamecube_tx

    movlw   gamecube_buffer         ; Receive 8 status bytes
    movwf   FSR1L
    movlw   8
    call    gamecube_rx
    return

gamecube_tx
    bcf     GAMECUBE_PIN
    n64gc_tx_buffer GAMECUBE_TRIS, 0

gamecube_rx
    movwf   byte_count
    n64gc_rx_buffer GAMECUBE_PIN, byte_count, 0


    ;; *******************************************************************************
    ;; ******************************************************  Lookup Tables  ********
    ;; *******************************************************************************

    ;; This contain the default configuration used if the EEPROM is empty, corrupt or
    ;; user perform reset.
    org     0x3C00
eeprom_default
    #include eeprom_default.inc

    ;; This contains the scaling tables used to scale our GC joysticks values.
    org     0x3D00
    #include js_scale.inc

    ;; 256-byte table extracted from the test vectors, that can be used to
    ;; compute any CRC. This table is the inverted CRC generated for every
    ;; possible message with exactly one bit set.
    ;;
    ;; It was generated using the reversed large-table
    ;; implementation of the CRC, in notes/gen_asm_large_table_crc.py
    org     0x3F00
crc_large_table
    #include large_table_crc.inc

    end
