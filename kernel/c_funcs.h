#ifndef CFUNCS_H_INCLUDED
#define CFUNCS_H_INCLUDED

// TEMP PLACE HOLDER FILE FOR C FUNCTION PROTOTYPES
#include "types.h";

void timerinit();
void kmain();
void panic(char *s);
void consputc(int c);
void uartintr(void);

struct spinlock;
extern struct spinlock uart_tx_lock;

// uart.c
void            uartinit(void);
void            uartintr(void);
void            uartputc(int);
void            uartputc_sync(int);

//void initlock(struct spinlock*, char*);
extern volatile int panicked; // from printf.c

// forward declartion for spinlock
struct cpu;

void procinit(void);

void            consoleintr(int);
void            sleep(void*, struct spinlock*);
void            wakeup(void*);


void consputc(int c);
int consolewrite(int user_src, uint64 src, int n);
int consoleread(int user_dst, uint64 dst, int n);
void consoleintr(int c);
void consoleinit(void);

void            printf(char*, ...);


struct buf;
void            c_binit(void);
struct buf*     c_bread(uint, uint);
void            c_brelse(struct buf*);
void            c_bwrite(struct buf*);
void            c_bpin(struct buf*);
void            c_bunpin(struct buf*);


typedef uint64 pte_t;
typedef uint64 *pagetable_t; // 512 PTEs
pte_t *walk_c(pagetable_t pagetable, uint64 va, int alloc);
uint64 walkaddr_c(pagetable_t pagetable, uint64 va);


#endif