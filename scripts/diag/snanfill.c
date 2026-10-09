// Interpone malloc/realloc: rellena cada bloque nuevo con NaN SENALIZANTE
// (0x7FF4000000000001 por palabra de 8 bytes). Cualquier aritmetica sobre un
// real(8) sin inicializar dispara SIGFPE con -ffpe-trap=invalid.
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <malloc/malloc.h>
#define DYLD_INTERPOSE(_r,_o) __attribute__((used)) static struct{const void*r;const void*o;} _i_##_o __attribute__((section("__DATA,__interpose"))) = {(const void*)(unsigned long)&_r,(const void*)(unsigned long)&_o};
static void fill(void *p, size_t n){ if(!p) return; uint64_t *w=(uint64_t*)p; size_t k=n/8; for(size_t i=0;i<k;i++) w[i]=0x7FF4000000000001ULL; }
void *my_malloc(size_t n){ void *p=malloc(n); fill(p,n); return p; }
void *my_realloc(void *q,size_t n){ size_t old=q?malloc_size(q):0; void *p=realloc(q,n); if(p&&n>old) fill((char*)p+old,n-old); return p; }
DYLD_INTERPOSE(my_malloc,malloc)
DYLD_INTERPOSE(my_realloc,realloc)
