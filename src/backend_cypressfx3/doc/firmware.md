@defgroup backend_cypressfx2-fw Cypress FX2 Firmware
@ingroup backend_cypressfx2

The Cypress FX2 chip needs firmware for its configuration. We use the
chip in the "Slave FIFO" mode which only forwards data between USB and
a 16/32 bit wide FIFO interface.

## Cypress Firmware

Currently, the firmware part on the Fx3 is a bit messy:

 * Download http://www.cypress.com/file/139281
 * You will only need the cyusb_linux program
 * Run

     cyusb_linux $GLIP/src/backend_cypressfx3/fw/cyfxslfifosync.img

## KC 705 Notes

The KC705 and adaptor boards are picky on the order of configuration
(due to the PMODE pins to the FPGA):

 * First unconnect both board
 * Connect FX3 board to the PC with the PMODE jumper on
 * Flash the firmware to EEPROM
 * Reconnect the FX3 board without PMODE jumper
 * Connect the FX3 board to the KC705
 * Now you can power up the KC705 and download the bitstream