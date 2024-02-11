void  *memset(void *ptr, int val, int len) {
  int i;
  unsigned char *p = ptr;
  i = 0;
  while(len > 0) {
    *p = val;
    p++;
    len--;
  }
  return(ptr);
}
