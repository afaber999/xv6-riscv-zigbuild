#ifndef START_H_INCLUDED
#define START_H_INCLUDED

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
int             uartgetc(void);

//void initlock(struct spinlock*, char*);

// forward declartion for spinlock
struct cpu;

void procinit(void);

#endif