CFLAGS= -nostdinc -nostdlib -fPIC -DPIC 
CFLAGS+= -I../libc/include -I../libc/private -I../libc/bionic -I../libc/kernel/arch-x86
CFLAGS+= -I../libc/kernel/common/linux/ -I../libc/arch-x86/include/ -I../libc/kernel/common/


all:
	gcc -m32 -shared -o libdl.so $(CFLAGS) libdl.c

clean:
	rm libdl.so
