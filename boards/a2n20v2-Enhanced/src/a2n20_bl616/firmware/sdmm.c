/*------------------------------------------------------------------------/
/  Foolproof MMCv3/SDv1/SDv2 (in SPI mode) control module
/-------------------------------------------------------------------------/
/
/  Copyright (C) 2019, ChaN, all right reserved.
/
/ * This software is a free software and there is NO WARRANTY.
/ * No restriction on use. You can use, modify and redistribute it for
/   personal, non-profit or commercial products UNDER YOUR RESPONSIBILITY.
/ * Redistributions of source code must retain the above copyright notice.
/
/-------------------------------------------------------------------------/
  Platform layer rewritten for A2N20 FPGA SPI tunnel.
  SD card is physically connected to FPGA pins; the BL616 MCU accesses it
  by writing/reading FPGA registers 0x6C-0x6E via the existing SPI link.
/------------------------------------------------------------------------*/

#include "ff.h"		/* Obtains integer types for FatFs */
#include "diskio.h"	/* Common include file for FatFs and disk I/O layer */
#include "fpga_spi.h"
#include "bflb_mtimer.h"

/*-------------------------------------------------------------------------*/
/* Card type flags (used in CardType)                                      */
/*-------------------------------------------------------------------------*/

#define CT_MMC3		0x01	/* MMCv3 */
#define CT_SDC1		0x02	/* SDv1 */
#define CT_SDC2		0x04	/* SDv2 */
#define CT_SDC		(CT_SDC1|CT_SDC2)	/* SD */
#define CT_BLOCK	0x08	/* Block addressing */

/*-------------------------------------------------------------------------*/
/* FPGA SD card register addresses                                         */
/*-------------------------------------------------------------------------*/

#define SD_REG_CTRL   0x6C  /* [1]=slow_clk, [0]=CS# */
#define SD_REG_XFER   0x6D  /* W=start xfer with TX byte, R=last RX byte */
#define SD_REG_STATUS 0x6E  /* [0]=byte busy, M3 [7:4]=cap/done/active/error */

/* M3 is opt-in at firmware build time, and ALSO runtime capability gated.
 * Upgrading Stage 2 without upgrading FPGA remains entirely functional. */
#ifndef FPGA_SD_BURST_READ
#define FPGA_SD_BURST_READ 0
#endif
#define SD_BURST_CAP         0x80u
#define SD_BURST_DONE        0x40u
#define SD_BURST_ACTIVE      0x20u
#define SD_BURST_ERROR       0x10u
#define SD_BURST_CMD_START   0xA1u
#define SD_BURST_CMD_ABORT   0xAFu
#define SD_BURST_LIMIT_US    200000u
#ifndef FPGA_SD_BURST_VALIDATE_CRC
#define FPGA_SD_BURST_VALIDATE_CRC 1
#endif

#if FPGA_SD_BURST_READ && defined(FATFS_EXTERNAL_DISKIO)
#include "FreeRTOS.h"
#include "task.h"
#include "osd_console.h"
#define SD_BURST_WAIT() vTaskDelay(pdMS_TO_TICKS(1))
#define SD_BURST_LOG(...) osd_log(__VA_ARGS__)
#else
#define SD_BURST_WAIT() bflb_mtimer_delay_us(100)
#define SD_BURST_LOG(...) do {} while(0)
#endif
static int s_sd_burst_cap=-1; /* -1=unknown,0=legacy,1=M3 FPGA */ 
static uint32_t s_sd_burst_reads,s_sd_burst_timeouts,s_sd_burst_errors;
static uint32_t s_sd_burst_crc_errors;

/* SD SPI read-data CRC is CRC16-CCITT, poly 0x1021, initial value 0,
 * big-endian on the two wire bytes after the data payload. Validate
 * accelerated sectors end-to-end: a self-test of the XFER buffer alone
 * cannot catch MISO bit slips at the SD FPGA PHY. */
#if FPGA_SD_BURST_READ && FPGA_SD_BURST_VALIDATE_CRC
static uint16_t sd_m3_crc16(const BYTE *data,UINT n)
{
    uint16_t crc=0;
    for(UINT i=0;i<n;i++) {
        crc^=(uint16_t)data[i]<<8;
        for(unsigned bit=0;bit<8u;bit++)
            crc=(uint16_t)((crc<<1) ^
                 ((crc&0x8000u)?0x1021u:0u));
    }
    return crc;
}
#endif
static bool s_sd_host_portal_reported;

uint32_t mmc_sd_burst_read_count(void){return s_sd_burst_reads;}
uint32_t mmc_sd_burst_error_count(void){
    return s_sd_burst_timeouts+s_sd_burst_errors+s_sd_burst_crc_errors;
}
/* Only call for the payload AFTER the card's 0xFE data token has been
 * received. The SD card stays selected and no other thread accesses this
 * card: the disk thread is the sole FatFS owner. The shared BL616-to-FPGA
 * SPI mutex is free between tiny status probes and 128B portal frames. */
static int sd_m3_receive_sector(BYTE *buff)
{
#if FPGA_SD_BURST_READ
    if(s_sd_burst_cap<0) {
        s_sd_burst_cap=(fpga_spi_reg_read(SD_REG_STATUS)&SD_BURST_CAP)?1:0;
        SD_BURST_LOG("M3 SD BURST FPGA=%s",
                     s_sd_burst_cap ? "YES":"NO (M2 FALLBACK)");
    }
    if(!s_sd_burst_cap)return -1; /* use historical bytewise SD */
    fpga_spi_reg_write(SD_REG_STATUS,SD_BURST_CMD_START);
    const uint32_t begin=(uint32_t)bflb_mtimer_get_time_us();
    for(;;) {
        const BYTE status=fpga_spi_reg_read(SD_REG_STATUS);
        if((status&SD_BURST_DONE) && !(status&SD_BURST_ACTIVE)) {
            if(status&SD_BURST_ERROR) {
                ++s_sd_burst_errors;
                SD_BURST_LOG("M3 SD BURST FPGA ERROR STATUS=%02X",status);
                fpga_spi_reg_write(SD_REG_STATUS,SD_BURST_CMD_ABORT);
                return 0; /* card stream consumed: fail this block */
            }
            fpga_spi_sd_burst_buffer_read(buff);
            ++s_sd_burst_reads;
            if(!s_sd_host_portal_reported) {
                s_sd_host_portal_reported=true;
                SD_BURST_LOG("M3 SD 512B BURST READY HOST SPI=%s",
                     fpga_spi_sd_burst_bulk_ok()?"BULK":"BYTEWISE FALLBACK");
            }
            return 1;
        }
        if((uint32_t)((uint32_t)bflb_mtimer_get_time_us()-begin)>=
           SD_BURST_LIMIT_US) {
            ++s_sd_burst_timeouts;
            SD_BURST_LOG("M3 SD BURST TIMEOUT STATUS=%02X",status);
            fpga_spi_reg_write(SD_REG_STATUS,SD_BURST_CMD_ABORT);
            return 0; /* never retry within an already-clocked SD block */
        }
        SD_BURST_WAIT();
    }
#else
    (void)buff;
    return -1;
#endif
}

/*-------------------------------------------------------------------------*/
/* Platform-dependent functions for FPGA SPI tunnel                        */
/*-------------------------------------------------------------------------*/

#define CS_H()  fpga_spi_reg_write(SD_REG_CTRL, (sd_ctrl_r | 0x01))
#define CS_L()  fpga_spi_reg_write(SD_REG_CTRL, (sd_ctrl_r & ~0x01))

static BYTE sd_ctrl_r = 0x03;  /* Current SD_CTRL value: CS# high + slow clock */

static
void dly_us(UINT n)
{
	bflb_mtimer_delay_us(n);
}

/* Transfer one byte via FPGA SPI tunnel and return received byte */
static
BYTE xchg_spi(BYTE dat)
{
	fpga_spi_reg_write(SD_REG_XFER, dat);
	/* Poll until transfer complete (timeout ~1ms at worst) */
	for (int i = 0; i < 10000; i++) {
		if (!(fpga_spi_reg_read(SD_REG_STATUS) & 0x01))
			return fpga_spi_reg_read(SD_REG_XFER);
	}
	return 0xFF;  /* Timeout — return bus-idle value */
}

/*-----------------------------------------------------------------------*/
/* Transmit bytes to the card                                            */
/*-----------------------------------------------------------------------*/

static
void xmit_mmc (
	const BYTE* buff,	/* Data to be sent */
	UINT bc				/* Number of bytes to send */
)
{
	do {
		xchg_spi(*buff++);
	} while (--bc);
}

/*-----------------------------------------------------------------------*/
/* Receive bytes from the card                                           */
/*-----------------------------------------------------------------------*/

static
void rcvr_mmc (
	BYTE *buff,	/* Pointer to read buffer */
	UINT bc		/* Number of bytes to receive */
)
{
	do {
		*buff++ = xchg_spi(0xFF);
	} while (--bc);
}


/*--------------------------------------------------------------------------

   Module Private Functions

---------------------------------------------------------------------------*/

/* MMC/SD command (SPI mode) */
#define CMD0	(0)			/* GO_IDLE_STATE */
#define CMD1	(1)			/* SEND_OP_COND */
#define	ACMD41	(0x80+41)	/* SEND_OP_COND (SDC) */
#define CMD8	(8)			/* SEND_IF_COND */
#define CMD9	(9)			/* SEND_CSD */
#define CMD10	(10)		/* SEND_CID */
#define CMD12	(12)		/* STOP_TRANSMISSION */
#define CMD13	(13)		/* SEND_STATUS */
#define ACMD13	(0x80+13)	/* SD_STATUS (SDC) */
#define CMD16	(16)		/* SET_BLOCKLEN */
#define CMD17	(17)		/* READ_SINGLE_BLOCK */
#define CMD18	(18)		/* READ_MULTIPLE_BLOCK */
#define CMD23	(23)		/* SET_BLOCK_COUNT */
#define	ACMD23	(0x80+23)	/* SET_WR_BLK_ERASE_COUNT (SDC) */
#define CMD24	(24)		/* WRITE_BLOCK */
#define CMD25	(25)		/* WRITE_MULTIPLE_BLOCK */
#define CMD32	(32)		/* ERASE_ER_BLK_START */
#define CMD33	(33)		/* ERASE_ER_BLK_END */
#define CMD38	(38)		/* ERASE */
#define CMD55	(55)		/* APP_CMD */
#define CMD58	(58)		/* READ_OCR */


static
DSTATUS Stat = STA_NOINIT;	/* Disk status */

static
BYTE CardType;			/* b0:MMC, b1:SDv1, b2:SDv2, b3:Block addressing */



/*-----------------------------------------------------------------------*/
/* Wait for card ready                                                   */
/*-----------------------------------------------------------------------*/

static
int wait_ready (void)	/* 1:OK, 0:Timeout */
{
	BYTE d;
	UINT tmr;


	for (tmr = 5000; tmr; tmr--) {	/* Wait for ready in timeout of 500ms */
		rcvr_mmc(&d, 1);
		if (d == 0xFF) break;
		dly_us(100);
	}

	return tmr ? 1 : 0;
}



/*-----------------------------------------------------------------------*/
/* Deselect the card and release SPI bus                                 */
/*-----------------------------------------------------------------------*/

static
void deselect (void)
{
	BYTE d;

	CS_H();				/* Set CS# high */
	rcvr_mmc(&d, 1);	/* Dummy clock (force DO hi-z for multiple slave SPI) */
}



/*-----------------------------------------------------------------------*/
/* Select the card and wait for ready                                    */
/*-----------------------------------------------------------------------*/

static
int sd_select (void)	/* 1:OK, 0:Timeout */
{
	BYTE d;

	CS_L();				/* Set CS# low */
	rcvr_mmc(&d, 1);	/* Dummy clock (force DO enabled) */
	if (wait_ready()) return 1;	/* Wait for card ready */

	deselect();
	return 0;			/* Failed */
}



/*-----------------------------------------------------------------------*/
/* Receive a data packet from the card                                   */
/*-----------------------------------------------------------------------*/

static
int rcvr_datablock (	/* 1:OK, 0:Failed */
	BYTE *buff,			/* Data buffer to store received data */
	UINT btr			/* Byte count */
)
{
	BYTE d[2];
	UINT tmr;


	for (tmr = 1000; tmr; tmr--) {	/* Wait for data packet in timeout of 100ms */
		rcvr_mmc(d, 1);
		if (d[0] != 0xFF) break;
		dly_us(100);
	}
	if (d[0] != 0xFE) return 0;		/* If not valid data token, return with error */

	/* M3: FPGA receives the whole 512-byte payload autonomously;
	 * BL616 fetches it via 4 short XFER0 frames. All non-512-byte
	 * reads (CSD, status), commands, response tokens, and CRC bytes
	 * retain the known-good register-byte path. */
	int staged=(btr==512u)?sd_m3_receive_sector(buff):-1;
	if(staged==0)return 0;  /* failed mid-packet: caller deselects */
	if(staged<0)rcvr_mmc(buff,btr);
	rcvr_mmc(d, 2);					/* SD CRC16 (legacy ignores) */
#if FPGA_SD_BURST_READ && FPGA_SD_BURST_VALIDATE_CRC
	if(staged==1) {
		const uint16_t wire=(uint16_t)(((uint16_t)d[0]<<8)|d[1]);
		const uint16_t got=sd_m3_crc16(buff,btr);
		if(got!=wire) {
			++s_sd_burst_crc_errors;
			SD_BURST_LOG("M3 SD CRC16 FAIL CALC=%04X WIRE=%04X; FALLBACK M2",
			             got,wire);
			s_sd_burst_cap=0; /* sticky until next card initialization */
			return 0; /* never deliver a possibly corrupted FatFS sector */
		}
	}
#endif
	return 1;						/* Return with success */
}



/*-----------------------------------------------------------------------*/
/* Send a data packet to the card                                        */
/*-----------------------------------------------------------------------*/

static
int xmit_datablock (	/* 1:OK, 0:Failed */
	const BYTE *buff,	/* 512 byte data block to be transmitted */
	BYTE token			/* Data/Stop token */
)
{
	BYTE d[2];


	if (!wait_ready()) return 0;

	d[0] = token;
	xmit_mmc(d, 1);				/* Xmit a token */
	if (token != 0xFD) {		/* Is it data token? */
		xmit_mmc(buff, 512);	/* Xmit the 512 byte data block to MMC */
		rcvr_mmc(d, 2);			/* Xmit dummy CRC (0xFF,0xFF) */
		rcvr_mmc(d, 1);			/* Receive data response */
		if ((d[0] & 0x1F) != 0x05)	/* If not accepted, return with error */
			return 0;
	}

	return 1;
}



/*-----------------------------------------------------------------------*/
/* Send a command packet to the card                                     */
/*-----------------------------------------------------------------------*/

static
BYTE send_cmd (		/* Returns command response (bit7==1:Send failed)*/
	BYTE cmd,		/* Command byte */
	DWORD arg		/* Argument */
)
{
	BYTE n, d, buf[6];


	if (cmd & 0x80) {	/* ACMD<n> is the command sequense of CMD55-CMD<n> */
		cmd &= 0x7F;
		n = send_cmd(CMD55, 0);
		if (n > 1) return n;
	}

	/* Select the card and wait for ready except to stop multiple block read */
	if (cmd != CMD12) {
		deselect();
		if (!sd_select()) return 0xFF;
	}

	/* Send a command packet */
	buf[0] = 0x40 | cmd;			/* Start + Command index */
	buf[1] = (BYTE)(arg >> 24);		/* Argument[31..24] */
	buf[2] = (BYTE)(arg >> 16);		/* Argument[23..16] */
	buf[3] = (BYTE)(arg >> 8);		/* Argument[15..8] */
	buf[4] = (BYTE)arg;				/* Argument[7..0] */
	n = 0x01;						/* Dummy CRC + Stop */
	if (cmd == CMD0) n = 0x95;		/* (valid CRC for CMD0(0)) */
	if (cmd == CMD8) n = 0x87;		/* (valid CRC for CMD8(0x1AA)) */
	buf[5] = n;
	xmit_mmc(buf, 6);

	/* Receive command response */
	if (cmd == CMD12) rcvr_mmc(&d, 1);	/* Skip a stuff byte when stop reading */
	n = 10;								/* Wait for a valid response in timeout of 10 attempts */
	do
		rcvr_mmc(&d, 1);
	while ((d & 0x80) && --n);

	return d;			/* Return with the response value */
}



/*--------------------------------------------------------------------------

   Public Functions

---------------------------------------------------------------------------*/


/*-----------------------------------------------------------------------*/
/* Get Disk Status                                                       */
/*-----------------------------------------------------------------------*/

DSTATUS mmc_disk_status (
	BYTE drv			/* Drive number (always 0) */
)
{
	if (drv) return STA_NOINIT;

	return Stat;
}



/*-----------------------------------------------------------------------*/
/* Initialize Disk Drive                                                 */
/*-----------------------------------------------------------------------*/

DSTATUS mmc_disk_initialize (
	BYTE drv		/* Physical drive nmuber (0) */
)
{
	BYTE n, ty, cmd, buf[4];
	UINT tmr;
	DSTATUS s;


	if (drv) return RES_NOTRDY;

	dly_us(10000);			/* 10ms */

	/* Set CS# high + slow clock for init sequence */
	s_sd_burst_cap=-1;
	s_sd_host_portal_reported=false;
	sd_ctrl_r = 0x03;		/* [1]=slow_clk, [0]=CS# high */
	fpga_spi_reg_write(SD_REG_CTRL, sd_ctrl_r);

	for (n = 10; n; n--) rcvr_mmc(buf, 1);	/* Apply 80 dummy clocks and the card gets ready to receive command */

	ty = 0;
	if (send_cmd(CMD0, 0) == 1) {			/* Enter Idle state */
		if (send_cmd(CMD8, 0x1AA) == 1) {	/* SDv2? */
			rcvr_mmc(buf, 4);							/* Get trailing return value of R7 resp */
			if (buf[2] == 0x01 && buf[3] == 0xAA) {		/* The card can work at vdd range of 2.7-3.6V */
				for (tmr = 1000; tmr; tmr--) {			/* Wait for leaving idle state (ACMD41 with HCS bit) */
					if (send_cmd(ACMD41, 1UL << 30) == 0) break;
					dly_us(1000);
				}
				if (tmr && send_cmd(CMD58, 0) == 0) {	/* Check CCS bit in the OCR */
					rcvr_mmc(buf, 4);
					ty = (buf[0] & 0x40) ? CT_SDC2 | CT_BLOCK : CT_SDC2;	/* SDv2+ */
				}
			}
		} else {							/* SDv1 or MMCv3 */
			if (send_cmd(ACMD41, 0) <= 1) 	{
				ty = CT_SDC2; cmd = ACMD41;	/* SDv1 */
			} else {
				ty = CT_MMC3; cmd = CMD1;	/* MMCv3 */
			}
			for (tmr = 1000; tmr; tmr--) {			/* Wait for leaving idle state */
				if (send_cmd(cmd, 0) == 0) break;
				dly_us(1000);
			}
			if (!tmr || send_cmd(CMD16, 512) != 0)	/* Set R/W block length to 512 */
				ty = 0;
		}
	}
	CardType = ty;
	s = ty ? 0 : STA_NOINIT;
	Stat = s;

	deselect();

	/* Switch to fast clock after init */
	if (s == 0) {
		sd_ctrl_r = 0x01;	/* CS# high, fast clock */
		fpga_spi_reg_write(SD_REG_CTRL, sd_ctrl_r);
	}

	return s;
}



/*-----------------------------------------------------------------------*/
/* Read Sector(s)                                                        */
/*-----------------------------------------------------------------------*/

DRESULT mmc_disk_read (
	BYTE drv,			/* Physical drive nmuber (0) */
	BYTE *buff,			/* Pointer to the data buffer to store read data */
	LBA_t sector,		/* Start sector number (LBA) */
	UINT count			/* Sector count (1..128) */
)
{
	BYTE cmd;
	DWORD sect = (DWORD)sector;


	if (mmc_disk_status(drv) & STA_NOINIT) return RES_NOTRDY;
	if (!(CardType & CT_BLOCK)) sect *= 512;	/* Convert LBA to byte address if needed */

	cmd = count > 1 ? CMD18 : CMD17;			/*  READ_MULTIPLE_BLOCK : READ_SINGLE_BLOCK */
	if (send_cmd(cmd, sect) == 0) {
		do {
			if (!rcvr_datablock(buff, 512)) break;
			buff += 512;
		} while (--count);
		if (cmd == CMD18) send_cmd(CMD12, 0);	/* STOP_TRANSMISSION */
	}
	deselect();

	return count ? RES_ERROR : RES_OK;
}



/*-----------------------------------------------------------------------*/
/* Write Sector(s)                                                       */
/*-----------------------------------------------------------------------*/

DRESULT mmc_disk_write (
	BYTE drv,			/* Physical drive nmuber (0) */
	const BYTE *buff,	/* Pointer to the data to be written */
	LBA_t sector,		/* Start sector number (LBA) */
	UINT count			/* Sector count (1..128) */
)
{
	DWORD sect = (DWORD)sector;


	if (mmc_disk_status(drv) & STA_NOINIT) return RES_NOTRDY;
	if (!(CardType & CT_BLOCK)) sect *= 512;	/* Convert LBA to byte address if needed */

	if (count == 1) {	/* Single block write */
		if ((send_cmd(CMD24, sect) == 0)	/* WRITE_BLOCK */
			&& xmit_datablock(buff, 0xFE))
			count = 0;
	}
	else {				/* Multiple block write */
		if (CardType & CT_SDC) send_cmd(ACMD23, count);
		if (send_cmd(CMD25, sect) == 0) {	/* WRITE_MULTIPLE_BLOCK */
			do {
				if (!xmit_datablock(buff, 0xFC)) break;
				buff += 512;
			} while (--count);
			if (!xmit_datablock(0, 0xFD))	/* STOP_TRAN token */
				count = 1;
		}
	}
	deselect();

	return count ? RES_ERROR : RES_OK;
}


/*-----------------------------------------------------------------------*/
/* Miscellaneous Functions                                               */
/*-----------------------------------------------------------------------*/

DRESULT mmc_disk_ioctl (
	BYTE drv,		/* Physical drive nmuber (0) */
	BYTE ctrl,		/* Control code */
	void *buff		/* Buffer to send/receive control data */
)
{
	DRESULT res;
	BYTE n, csd[16];
	DWORD cs;


	if (mmc_disk_status(drv) & STA_NOINIT) return RES_NOTRDY;	/* Check if card is in the socket */

	res = RES_ERROR;
	switch (ctrl) {
		case CTRL_SYNC :		/* Make sure that no pending write process */
			if (sd_select()) res = RES_OK;
			break;

		case GET_SECTOR_COUNT :	/* Get number of sectors on the disk (DWORD) */
			if ((send_cmd(CMD9, 0) == 0) && rcvr_datablock(csd, 16)) {
				if ((csd[0] >> 6) == 1) {	/* SDC ver 2.00 */
					cs = csd[9] + ((WORD)csd[8] << 8) + ((DWORD)(csd[7] & 63) << 16) + 1;
					*(LBA_t*)buff = cs << 10;
				} else {					/* SDC ver 1.XX or MMC */
					n = (csd[5] & 15) + ((csd[10] & 128) >> 7) + ((csd[9] & 3) << 1) + 2;
					cs = (csd[8] >> 6) + ((WORD)csd[7] << 2) + ((WORD)(csd[6] & 3) << 10) + 1;
					*(LBA_t*)buff = cs << (n - 9);
				}
				res = RES_OK;
			}
			break;

		case GET_BLOCK_SIZE :	/* Get erase block size in unit of sector (DWORD) */
			*(DWORD*)buff = 128;
			res = RES_OK;
			break;

		default:
			res = RES_PARERR;
	}

	deselect();

	return res;
}


/*-----------------------------------------------------------------------*/
/* FatFs disk_* entry points                                             */
/*-----------------------------------------------------------------------*/
/* The SD logic above is exported as mmc_disk_* so a multi-backend build  */
/* (firmware_host) can route between SD and USB. The single-drive (device */
/* / FT2232) build defines the standard FatFs disk_* names here. The host */
/* build compiles with -DFATFS_EXTERNAL_DISKIO and supplies disk_* in its */
/* own router (diskio_host.c), so these wrappers are omitted there.       */
#ifndef FATFS_EXTERNAL_DISKIO
DSTATUS disk_status(BYTE drv) { return mmc_disk_status(drv); }
DSTATUS disk_initialize(BYTE drv) { return mmc_disk_initialize(drv); }
DRESULT disk_read(BYTE drv, BYTE *buff, LBA_t sector, UINT count) {
	return mmc_disk_read(drv, buff, sector, count);
}
DRESULT disk_write(BYTE drv, const BYTE *buff, LBA_t sector, UINT count) {
	return mmc_disk_write(drv, buff, sector, count);
}
DRESULT disk_ioctl(BYTE drv, BYTE ctrl, void *buff) {
	return mmc_disk_ioctl(drv, ctrl, buff);
}
#endif
