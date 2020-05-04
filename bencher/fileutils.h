#ifndef _FILEUTILS_H
#define _FILEUTILS_H

#include <stdio.h>
#include <malloc.h>

char *read_all_ptr(FILE* f, size_t *length_out, int check_length, const char *filename) {
	// Get total length
	fseek(f, 0, SEEK_END);
	size_t length = (size_t) ftell(f);
	rewind(f);

	// Write to output param
	if (length_out)
		*length_out = length;

	// Allocate buffer for file contents and terminating '\0'
	char *buffer = (char *) malloc(sizeof(char) * (length + 1));
	if (!buffer) {
		fprintf(stderr, "Could not allocate memory to hold %s", filename);
		return NULL;
	}

	// Attempt to read the file to memory
	size_t read = fread(buffer, sizeof(char), length, f);
	if (check_length && read != length) {
		perror(filename);
		free(buffer);
		buffer = NULL;
	}

	return buffer;
}

char *read_all(const char* filename, size_t *length_out, int check_length)  {
	// Attempt to open the file
	FILE *f = fopen(filename, "r");
	if (!f) {
		perror(filename);
		return NULL;
	}

	char *result = read_all_ptr(f, length_out, check_length, filename);

	// Attempt to close the file
	if (fclose(f))
		perror(filename);

	return result;
}

#endif // _FILEUTILS_H
