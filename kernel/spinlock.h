// Mutual exclusion lock.
#include "types.h"

struct spinlock {
  uint32 locked;       // Is the lock held?

  // For debugging:
  char *name;        // Name of lock.
  struct cpu *cpu;   // The cpu holding the lock.
};


// spinlock.c
void acquire(struct spinlock*);
int  holding(struct spinlock*);
void initlock(struct spinlock*, char*);
void release(struct spinlock*);
void push_off(void);
void pop_off(void);
