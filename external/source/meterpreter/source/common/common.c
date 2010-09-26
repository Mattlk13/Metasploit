#include "common.h"

#ifndef _WIN32

int debugging_enabled;

/*
 * If we supply real_dprintf in the common.h, each .o file will have a private copy of that symbol.
 * This leads to bloat. Defining it here means that there will only be a single implementation of it.
 */ 

void real_dprintf(char *filename, int line, const char *function, char *format, ...)
{
	va_list args;
	char buffer[2048];
	int size;
	static int fd;

	size = snprintf(buffer, sizeof(buffer), "[%s:%d (%s)] ", filename, line, function);

	va_start(args, format);
	vsnprintf(buffer + size, sizeof(buffer) - size, format, args);
	strcat(buffer, "\n");
	va_end(args);

	if(fd <= 0) {
		char filename[128];
		sprintf(filename, "/tmp/meterpreter.log.%d", getpid());
		
		fd = open(filename, O_RDWR|O_TRUNC|O_CREAT|O_SYNC, 0644);
		
		if(fd <= 0) return;
	}

	write(fd, buffer, strlen(buffer));
}

void enable_debugging()
{
	debugging_enabled = 1;
}

#endif
