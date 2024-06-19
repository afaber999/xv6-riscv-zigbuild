#ifndef START_H_INCLUDED
#define START_H_INCLUDED

// TEMP PLACE HOLDER FILE FOR C FUNCTION PROTOTYPES
#include "types.h";

void timerinit();
void kmain();
void panic(char *s);
void consputc(int c);

// forward declartion for spinlock
struct cpu;

#endif