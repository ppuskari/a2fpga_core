#ifndef M3_FATFS_DISKIO_H
#define M3_FATFS_DISKIO_H
#include "ff.h"
typedef BYTE DSTATUS;
typedef BYTE DRESULT;
#define STA_NOINIT 0x01
#define STA_NODISK 0x02
#define STA_PROTECT 0x04
#define RES_OK 0
#define RES_ERROR 1
#define RES_WRPRT 2
#define RES_NOTRDY 3
#define RES_PARERR 4
#define CTRL_SYNC 0
#define GET_SECTOR_COUNT 1
#define GET_BLOCK_SIZE 2
#endif
