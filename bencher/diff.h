#ifndef _DIFF_H
#define _DIFF_H

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

#include "fileutils.h"

struct Diff {
	size_t length;
	char *text;
	long double abserr;
	char binary;
};

int binary_diff(FILE *file, const struct Diff *diff) {
    int ok = 1;
    size_t length;
    char *comp = read_all_ptr(file, &length, 1, "Buffer");

    if (length != diff->length) {
        fprintf(stderr, "Error: Binary data lengths differ. (Expected %ld, got %ld)\n", diff->length, length);
        ok = 0;
    } else if (memcmp(diff->text, comp, length) != 0) {
        fprintf(stderr, "Error: Binary data mismatch.\n");
        ok = 0;
    }

    free(comp);
    return ok;
}

#define DIFF_COUNT 3
void more_errors(int count, const char *text) {
    if (count > DIFF_COUNT) {
        int remaining = count - DIFF_COUNT;

        if (remaining == 1)
            fprintf(stderr, "... 1 additional %s.\n", text);
        else
            fprintf(stderr, "... %d additional %ss.\n", remaining, text);
    }
}

void early_end_error(char **line, size_t *len, FILE *file, int *ok) {
    *ok = 0;

    fprintf(stderr, "Error: Expected result ended before end of actual result.\n");
    fprintf(stderr, "Remaining:\n  %s", *line);

    int linecnt = 1;
	ssize_t read;
    while ((read = getline(line, len, file)) != -1) {
        if (linecnt < DIFF_COUNT)
            fprintf(stderr, "  %s", *line);
        ++linecnt;
    }

    more_errors(linecnt, "line");
}

void internal_error(size_t diff_line, char *diff_text, char *line, long double err, int *ok, int *error_count) {
    if (*ok) {
        fprintf(stderr, "Error: Diff failed.\n");
        *ok = 0;
    }

    if (*error_count < DIFF_COUNT) {
        fprintf(stderr, "  Baseline: %.*s", (int) diff_line, diff_text);
        fprintf(stderr, "  Current:  %s", line);
        if (err != 0.0)
            fprintf(stderr, "  Error:     %Lg\n", err);
    }
    ++ *error_count;
}

void ending_errors(char *diff_text, const struct Diff *diff, int error_count, int *ok) {
    more_errors(error_count, "error");

	// Print error, when output ended before diff
	if (diff_text != diff->text + diff->length) {
        *ok = 0;

        fprintf(stderr, "Error: Actual result ended before end of expected result.\n");
        fprintf(stderr, "Remaining:\n");

        int linecnt = 0;
        char *line_end;
        while ((line_end = strchr(diff_text, '\n'))) {
            if (linecnt < DIFF_COUNT)
                fprintf(stderr, "  %.*s\n", (int) (line_end - diff_text), diff_text);
            ++linecnt;

            diff_text = line_end + 1;
        }

        more_errors(linecnt, "line");
    }
}

long double numdiff(char *diff_text, char *line) {
    long double expected, actual;

    int pos;
    sscanf(diff_text, "%Lf%n", &expected, &pos);
    sscanf(line, "%Lf", &actual);

    return fabsl(actual - expected);
}

int textual_diff(FILE *file, const struct Diff *diff) {
	// Variables for getline
	char *line = NULL;
	size_t len = 0;
	ssize_t read;

	// Current position
	char *diff_text = diff->text;

	// Current Status
	int ok = 1;
	int error_count = 0;
	while ((read = getline(&line, &len, file)) != -1) {
		// Find diff line-end
		char *diff_next = strchr(diff_text, '\n');

		// Print error when diff ended before output
		if (!diff_next) {
            early_end_error(&line, &len, file, &ok);
			break;
		}
		++diff_next; // include newline

		// Calculate length of diff line
		size_t diff_line = diff_next - diff_text;

		// Textual diff first
		// Unsing min is fine here because both strings include a terminating '\n'
		#define MIN(a, b) (b) ^ (((a) ^ (b)) & -((a) < (b)))
		int result = strncmp(line, diff_text, MIN(read, diff_line));


		// Numerical diff as fallback
		long double err = 0.0;
		if (result != 0 && diff->abserr != 0) {
            err = numdiff(diff_text, line);
		}

		// Print failure
		if (result != 0 || err > diff->abserr)
            internal_error(diff_line, diff_text, line, err, &ok, &error_count);

		// Advance position of diff
		diff_text = diff_next;
	}

    ending_errors(diff_text, diff, error_count, &ok);

	free(line);
	return ok;
}

int check_output(FILE *file, const struct Diff *diff) {
	// Don't do anything when no diff is provided
	if (!diff->text)
		return 1;

	// Special case for binary data (potentially containing \0)
	if (diff->binary)
        return binary_diff(file, diff);

    // Textual diff otherwise
    return textual_diff(file, diff);
}

#endif // _DIFF_H
