#!/usr/bin/env python3
#
# This script generate the default buttons mapping layout file.
#
# --Jacques Gagnon <darthcloud@gmail.com>
#

import sys, os
from enum import IntEnum, auto

class ProperEnum(IntEnum):
    def _generate_next_value_(name, start, count, last_values):
        return count

class buttons(ProperEnum):
    BTN_D_UP = auto()
    BTN_D_LEFT = auto()
    BTN_D_RIGHT = auto()
    BTN_D_DOWN = auto()
    BTN_LJ_UP = auto()
    BTN_LJ_LEFT = auto()
    BTN_LJ_RIGHT = auto()
    BTN_LJ_DOWN = auto()
    BTN_RJ_UP = auto()
    BTN_RJ_LEFT = auto()
    BTN_RJ_RIGHT = auto()
    BTN_RJ_DOWN = auto()

    BTN_LA = auto()
    BTN_L = auto()
    BTN_RA = auto()
    BTN_R = auto()
    BTN_LZ = auto()
    BTN_LG = auto()
    BTN_LJ = auto()
    BTN_RZ = auto()
    BTN_RG = auto()
    BTN_RJ = auto()

    BTN_A = auto()
    BTN_B = auto()
    BTN_X = auto()
    BTN_Y = auto()

    BTN_SELECT = auto()
    BTN_HOME = auto()
    BTN_START = auto()
    BTN_C = auto()
    BTN_NONE = auto()
    BTN_A_C_DOWN = 0x36
    BTN_B_C_LEFT = 0x37

        #Default Value       #Button Address
buttons_presets = [
    [   #0: Default (Z on L)
        buttons.BTN_D_UP,    #BTN_D_UP
        buttons.BTN_D_LEFT,  #BTN_D_LEFT
        buttons.BTN_D_RIGHT, #BTN_D_RIGHT
        buttons.BTN_D_DOWN,  #BTN_D_DOWN
        buttons.BTN_LJ_UP,   #BTN_LJ_UP
        buttons.BTN_LJ_LEFT, #BTN_LJ_LEFT
        buttons.BTN_LJ_RIGHT,#BTN_LJ_RIGHT
        buttons.BTN_LJ_DOWN, #BTN_LJ_DOWN
        buttons.BTN_RJ_UP,   #BTN_RJ_UP
        buttons.BTN_RJ_LEFT, #BTN_RJ_LEFT
        buttons.BTN_RJ_RIGHT,#BTN_RJ_RIGHT
        buttons.BTN_RJ_DOWN, #BTN_RJ_DOWN

        buttons.BTN_NONE,    #BTN_LA
        buttons.BTN_RZ,      #BTN_L
        buttons.BTN_NONE,    #BTN_RA
        buttons.BTN_R,       #BTN_R
        buttons.BTN_NONE,    #BTN_LZ
        buttons.BTN_NONE,    #BTN_LG
        buttons.BTN_NONE,    #BTN_LJ
        buttons.BTN_RJ_RIGHT,#BTN_RZ
        buttons.BTN_NONE,    #BTN_RG
        buttons.BTN_NONE,    #BTN_RJ

        buttons.BTN_A,       #BTN_A
        buttons.BTN_B,       #BTN_B
        buttons.BTN_RJ_DOWN, #BTN_X
        buttons.BTN_RJ_LEFT, #BTN_Y

        buttons.BTN_NONE,    #BTN_SELECT
        buttons.BTN_NONE,    #BTN_HOME
        buttons.BTN_START,   #BTN_START
        buttons.BTN_NONE,    #BTN_C
        0x00,                #JS_CURVE
        0x00,                #CS_CURVE
    ],
    [   #1: Modern FPS (Z on R, Joystick/C-buttons swap)
        buttons.BTN_D_UP,    #BTN_D_UP
        buttons.BTN_D_LEFT,  #BTN_D_LEFT
        buttons.BTN_D_RIGHT, #BTN_D_RIGHT
        buttons.BTN_D_DOWN,  #BTN_D_DOWN
        buttons.BTN_RJ_UP,   #BTN_LJ_UP
        buttons.BTN_RJ_LEFT, #BTN_LJ_LEFT
        buttons.BTN_RJ_RIGHT,#BTN_LJ_RIGHT
        buttons.BTN_RJ_DOWN, #BTN_LJ_DOWN
        buttons.BTN_LJ_UP,   #BTN_RJ_UP
        buttons.BTN_LJ_LEFT, #BTN_RJ_LEFT
        buttons.BTN_LJ_RIGHT,#BTN_RJ_RIGHT
        buttons.BTN_LJ_DOWN, #BTN_RJ_DOWN

        buttons.BTN_NONE,    #BTN_LA
        buttons.BTN_R,       #BTN_L
        buttons.BTN_NONE,    #BTN_RA
        buttons.BTN_RZ,      #BTN_R
        buttons.BTN_NONE,    #BTN_LZ
        buttons.BTN_NONE,    #BTN_LG
        buttons.BTN_NONE,    #BTN_LJ
        buttons.BTN_L,       #BTN_RZ
        buttons.BTN_NONE,    #BTN_RG
        buttons.BTN_NONE,    #BTN_RJ

        buttons.BTN_A,       #BTN_A
        buttons.BTN_B,       #BTN_B
        buttons.BTN_D_DOWN,  #BTN_X
        buttons.BTN_D_UP,    #BTN_Y

        buttons.BTN_NONE,    #BTN_SELECT
        buttons.BTN_NONE,    #BTN_HOME
        buttons.BTN_START,   #BTN_START
        buttons.BTN_NONE,    #BTN_C
        0x00,                #JS_CURVE
        0x00,                #CS_CURVE
    ],
    [   #2: 3rd Person shooter / Legacy FPS (Z on R)
        buttons.BTN_D_UP,    #BTN_D_UP
        buttons.BTN_D_LEFT,  #BTN_D_LEFT
        buttons.BTN_D_RIGHT, #BTN_D_RIGHT
        buttons.BTN_D_DOWN,  #BTN_D_DOWN
        buttons.BTN_LJ_UP,   #BTN_LJ_UP
        buttons.BTN_LJ_LEFT, #BTN_LJ_LEFT
        buttons.BTN_LJ_RIGHT,#BTN_LJ_RIGHT
        buttons.BTN_LJ_DOWN, #BTN_LJ_DOWN
        buttons.BTN_RJ_UP,   #BTN_RJ_UP
        buttons.BTN_RJ_LEFT, #BTN_RJ_LEFT
        buttons.BTN_RJ_RIGHT,#BTN_RJ_RIGHT
        buttons.BTN_RJ_DOWN, #BTN_RJ_DOWN

        buttons.BTN_NONE,    #BTN_LA
        buttons.BTN_R,       #BTN_L
        buttons.BTN_NONE,    #BTN_RA
        buttons.BTN_RZ,      #BTN_R
        buttons.BTN_NONE,    #BTN_LZ
        buttons.BTN_NONE,    #BTN_LG
        buttons.BTN_NONE,    #BTN_LJ
        buttons.BTN_L,       #BTN_RZ
        buttons.BTN_NONE,    #BTN_RG
        buttons.BTN_NONE,    #BTN_RJ

        buttons.BTN_A,       #BTN_A
        buttons.BTN_B,       #BTN_B
        buttons.BTN_RJ_DOWN, #BTN_X
        buttons.BTN_RJ_LEFT, #BTN_Y

        buttons.BTN_NONE,    #BTN_SELECT
        buttons.BTN_NONE,    #BTN_HOME
        buttons.BTN_START,   #BTN_START
        buttons.BTN_NONE,    #BTN_C
        0x00,                #JS_CURVE
        0x00,                #CS_CURVE
    ],
    [   #3: Racing (JS Up/Down on Analog R/L)
        buttons.BTN_D_UP,    #BTN_D_UP
        buttons.BTN_D_LEFT,  #BTN_D_LEFT
        buttons.BTN_D_RIGHT, #BTN_D_RIGHT
        buttons.BTN_D_DOWN,  #BTN_D_DOWN
        buttons.BTN_NONE,    #BTN_LJ_UP
        buttons.BTN_LJ_LEFT, #BTN_LJ_LEFT
        buttons.BTN_LJ_RIGHT,#BTN_LJ_RIGHT
        buttons.BTN_NONE,    #BTN_LJ_DOWN
        buttons.BTN_RJ_UP,   #BTN_RJ_UP
        buttons.BTN_RJ_LEFT, #BTN_RJ_LEFT
        buttons.BTN_RJ_RIGHT,#BTN_RJ_RIGHT
        buttons.BTN_RJ_DOWN, #BTN_RJ_DOWN

        buttons.BTN_LJ_DOWN, #BTN_LA
        buttons.BTN_NONE,    #BTN_L
        buttons.BTN_LJ_UP,   #BTN_RA
        buttons.BTN_NONE,    #BTN_R
        buttons.BTN_NONE,    #BTN_LZ
        buttons.BTN_NONE,    #BTN_LG
        buttons.BTN_NONE,    #BTN_LJ
        buttons.BTN_RJ_RIGHT,#BTN_RZ
        buttons.BTN_NONE,    #BTN_RG
        buttons.BTN_NONE,    #BTN_RJ

        buttons.BTN_A,       #BTN_A
        buttons.BTN_B,       #BTN_B
        buttons.BTN_D_DOWN,  #BTN_X
        buttons.BTN_D_UP,    #BTN_Y

        buttons.BTN_NONE,    #BTN_SELECT
        buttons.BTN_NONE,    #BTN_HOME
        buttons.BTN_START,   #BTN_START
        buttons.BTN_NONE,    #BTN_C
        0x00,                #JS_CURVE
        0x00,                #CS_CURVE
    ],
    [   #4: Fighting (C-UP/C-DOWN on Z/L/R)
        buttons.BTN_D_UP,    #BTN_D_UP
        buttons.BTN_D_LEFT,  #BTN_D_LEFT
        buttons.BTN_D_RIGHT, #BTN_D_RIGHT
        buttons.BTN_D_DOWN,  #BTN_D_DOWN
        buttons.BTN_LJ_UP,   #BTN_LJ_UP
        buttons.BTN_LJ_LEFT, #BTN_LJ_LEFT
        buttons.BTN_LJ_RIGHT,#BTN_LJ_RIGHT
        buttons.BTN_LJ_DOWN, #BTN_LJ_DOWN
        buttons.BTN_RJ_UP,   #BTN_RJ_UP
        buttons.BTN_RJ_LEFT, #BTN_RJ_LEFT
        buttons.BTN_RJ_RIGHT,#BTN_RJ_RIGHT
        buttons.BTN_RJ_DOWN, #BTN_RJ_DOWN

        buttons.BTN_NONE,    #BTN_LA
        buttons.BTN_RJ_UP,   #BTN_L
        buttons.BTN_NONE,    #BTN_RA
        buttons.BTN_RJ_RIGHT,#BTN_R
        buttons.BTN_NONE,    #BTN_LZ
        buttons.BTN_NONE,    #BTN_LG
        buttons.BTN_NONE,    #BTN_LJ
        buttons.BTN_RZ,      #BTN_RZ
        buttons.BTN_NONE,    #BTN_RG
        buttons.BTN_NONE,    #BTN_RJ

        buttons.BTN_A,       #BTN_A
        buttons.BTN_B,       #BTN_B
        buttons.BTN_RJ_DOWN, #BTN_X
        buttons.BTN_RJ_LEFT, #BTN_Y

        buttons.BTN_NONE,    #BTN_SELECT
        buttons.BTN_NONE,    #BTN_HOME
        buttons.BTN_START,   #BTN_START
        buttons.BTN_NONE,    #BTN_C
        0x00,                #JS_CURVE
        0x00,                #CS_CURVE
    ],
    [   #5: Star Wars: Rogue Squadron (Rogue Leader style)
        buttons.BTN_D_UP,    #BTN_D_UP
        buttons.BTN_D_LEFT,  #BTN_D_LEFT
        buttons.BTN_D_RIGHT, #BTN_D_RIGHT
        buttons.BTN_D_DOWN,  #BTN_D_DOWN
        buttons.BTN_LJ_UP,   #BTN_LJ_UP
        buttons.BTN_LJ_LEFT, #BTN_LJ_LEFT
        buttons.BTN_LJ_RIGHT,#BTN_LJ_RIGHT
        buttons.BTN_LJ_DOWN, #BTN_LJ_DOWN
        buttons.BTN_L,       #BTN_RJ_UP
        buttons.BTN_L,       #BTN_RJ_LEFT
        buttons.BTN_L,       #BTN_RJ_RIGHT
        buttons.BTN_L,       #BTN_RJ_DOWN

        buttons.BTN_RZ,      #BTN_LA
        buttons.BTN_RZ,      #BTN_L
        buttons.BTN_A,       #BTN_RA
        buttons.BTN_RJ_RIGHT,#BTN_R
        buttons.BTN_NONE,    #BTN_LZ
        buttons.BTN_NONE,    #BTN_LG
        buttons.BTN_NONE,    #BTN_LJ
        buttons.BTN_R,       #BTN_RZ
        buttons.BTN_NONE,    #BTN_RG
        buttons.BTN_NONE,    #BTN_RJ

        buttons.BTN_B,       #BTN_A
        buttons.BTN_RJ_LEFT, #BTN_B
        buttons.BTN_RJ_DOWN, #BTN_X
        buttons.BTN_RJ_UP,   #BTN_Y

        buttons.BTN_NONE,    #BTN_SELECT
        buttons.BTN_NONE,    #BTN_HOME
        buttons.BTN_START,   #BTN_START
        buttons.BTN_NONE,    #BTN_C
        0x00,                #JS_CURVE
        0x00,                #CS_CURVE
    ],
    [   #6: Shadows of the Empire (FPS)
        buttons.BTN_D_UP,    #BTN_D_UP
        buttons.BTN_D_LEFT,  #BTN_D_LEFT
        buttons.BTN_D_RIGHT, #BTN_D_RIGHT
        buttons.BTN_D_DOWN,  #BTN_D_DOWN
        buttons.BTN_LJ_UP,   #BTN_LJ_UP
        buttons.BTN_RZ,      #BTN_LJ_LEFT
        buttons.BTN_R,       #BTN_LJ_RIGHT
        buttons.BTN_LJ_DOWN, #BTN_LJ_DOWN
        buttons.BTN_LJ_UP,   #BTN_RJ_UP
        buttons.BTN_LJ_LEFT, #BTN_RJ_LEFT
        buttons.BTN_LJ_RIGHT,#BTN_RJ_RIGHT
        buttons.BTN_LJ_DOWN, #BTN_RJ_DOWN

        buttons.BTN_NONE,    #BTN_LA
        buttons.BTN_RJ_RIGHT,#BTN_L
        buttons.BTN_NONE,    #BTN_RA
        buttons.BTN_A,       #BTN_R
        buttons.BTN_NONE,    #BTN_LZ
        buttons.BTN_NONE,    #BTN_LG
        buttons.BTN_NONE,    #BTN_LJ
        buttons.BTN_RJ_DOWN, #BTN_RZ
        buttons.BTN_NONE,    #BTN_RG
        buttons.BTN_NONE,    #BTN_RJ

        buttons.BTN_B,       #BTN_A
        buttons.BTN_RJ_UP,   #BTN_B
        buttons.BTN_RJ_LEFT, #BTN_X
        buttons.BTN_L,       #BTN_Y

        buttons.BTN_NONE,    #BTN_SELECT
        buttons.BTN_NONE,    #BTN_HOME
        buttons.BTN_START,   #BTN_START
        buttons.BTN_NONE,    #BTN_C
        0x00,                #JS_CURVE
        0x00,                #CS_CURVE
    ],
    [   #7: Tony Hawk (Merged A+C-DOWN & B+C-LEFT)
        buttons.BTN_D_UP,    #BTN_D_UP
        buttons.BTN_D_LEFT,  #BTN_D_LEFT
        buttons.BTN_D_RIGHT, #BTN_D_RIGHT
        buttons.BTN_D_DOWN,  #BTN_D_DOWN
        buttons.BTN_LJ_UP,   #BTN_LJ_UP
        buttons.BTN_LJ_LEFT, #BTN_LJ_LEFT
        buttons.BTN_LJ_RIGHT,#BTN_LJ_RIGHT
        buttons.BTN_LJ_DOWN, #BTN_LJ_DOWN
        buttons.BTN_RJ_UP,   #BTN_RJ_UP
        buttons.BTN_RJ_LEFT, #BTN_RJ_LEFT
        buttons.BTN_RJ_RIGHT,#BTN_RJ_RIGHT
        buttons.BTN_RJ_DOWN, #BTN_RJ_DOWN

        buttons.BTN_NONE,    #BTN_LA
        buttons.BTN_RZ,      #BTN_L
        buttons.BTN_NONE,    #BTN_RA
        buttons.BTN_R,       #BTN_R
        buttons.BTN_NONE,    #BTN_LZ
        buttons.BTN_NONE,    #BTN_LG
        buttons.BTN_NONE,    #BTN_LJ
        buttons.BTN_L,       #BTN_RZ
        buttons.BTN_NONE,    #BTN_RG
        buttons.BTN_NONE,    #BTN_RJ

        buttons.BTN_A_C_DOWN,#BTN_A
        buttons.BTN_B_C_LEFT,#BTN_B
        buttons.BTN_RJ_RIGHT,#BTN_X
        buttons.BTN_RJ_UP,   #BTN_Y

        buttons.BTN_NONE,    #BTN_SELECT
        buttons.BTN_NONE,    #BTN_HOME
        buttons.BTN_START,   #BTN_START
        buttons.BTN_NONE,    #BTN_C
        0x00,                #JS_CURVE
        0x00,                #CS_CURVE
    ],
]

if __name__ == "__main__":
    eeprom_default = "../firmware/eeprom_default.inc"

    if os.path.exists(eeprom_default):
        os.unlink(eeprom_default)

    FILE = open(eeprom_default,"wb")

    FILE.write(b"    ;; EEPROM default data.\n")
    FILE.write(b"    ;; Generated by Jacques Gagnon <darthcloud@gmail.com>.\n")
    FILE.write(b"    ;; See notes/gen_asm_eeprom_default.py\n")
    FILE.write(b"\n")

    for layout in buttons_presets:
        FILE.write(b"    db ")
        for address, default in enumerate(layout):
            FILE.write(b"0x%02X" % default)
            if address < buttons.BTN_NONE+1:
                FILE.write(b", ")
        FILE.write(b"\n")
    FILE.write(b"\n")
    FILE.close()

    print("{} generated.".format(eeprom_default))

### The End ###
