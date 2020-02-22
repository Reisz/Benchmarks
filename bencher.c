#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <time.h>
#include <assert.h>

#include <sys/types.h>
#include <sys/time.h>
#include <sys/resource.h>
#include <sys/wait.h>

#include "fileutils.h"
#include "cpufreq.h"

#define STRINGIFY_HELPER(arg) #arg
#define STRINGIFY(arg) STRINGIFY_HELPER(arg)

int usage_error() {
	fprintf(stderr, "Argument format is [-i <input-file>] <output-file> <binary> [<binary arguments>...]i\n");
	return EXIT_FAILURE;
}

#define CLOCK CLOCK_MONOTONIC
void run_bench(const char* input, size_t input_len, FILE* outfile, char** argv) {
	// Store start time
	struct timespec start;
	clock_gettime(CLOCK, &start);

	// Create pipes for communication
	#define CHILD_IN 0
	#define PARENT_OUT 1
	#define PARENT_IN 2
	#define CHILD_OUT 3
	int pipes[4];

	// Create first set of pipes
	if (pipe(&pipes[0])) {
		perror("pipe child -> parent");
		exit(EXIT_FAILURE);
	}

	// Create second set of pipes
	if (pipe(&pipes[2])) {
		perror("pipe parent -> child");
		exit(EXIT_FAILURE);
	}

	// Attempt to fork/execv to run child process
	pid_t pid = fork();
	if (pid < 0) {
		perror("fork");
		exit(EXIT_FAILURE);
	} else if (pid == 0) {
		// Close wrong sides of pipes
		close(pipes[PARENT_IN]);
		close(pipes[PARENT_OUT]);

		// Map pipes to stdin/stdout
		dup2(pipes[CHILD_IN], 0);
		dup2(pipes[CHILD_OUT], 1);

		execv(argv[0], argv);
		perror(argv[0]);
		exit(EXIT_FAILURE);
	}

	// Close wrong sides of pipes
	close(pipes[CHILD_IN]);
	close(pipes[CHILD_OUT]);

	// Write to the pipe if applicable
	if (input)
		write(pipes[PARENT_OUT], input, input_len);

	// Close after writing
	close(pipes[PARENT_OUT]);

	// Wait for process to end
	int status;
	struct rusage rusage;
	wait4(pid, &status, 0, &rusage);

	// Store end time
	struct timespec elapsed;
	clock_gettime(CLOCK, &elapsed);

	// TODO check output?

	// Close pipe after reading
	close(pipes[PARENT_IN]);

	// Subtract times, manually carry
	elapsed.tv_sec -= start.tv_sec;
	if (elapsed.tv_nsec < start.tv_nsec) {
		elapsed.tv_nsec += 1e9;
		--elapsed.tv_sec;
	}
	elapsed.tv_nsec -= start.tv_nsec;

	// Write information to file
	#define CSV_SEP "  "
	#define CSV_HEADER \
		"total  " CSV_SEP \
		"user   " CSV_SEP \
		"system " CSV_SEP \
		"minflt " CSV_SEP \
		"majflt " CSV_SEP \
		"swap   " CSV_SEP \
		"vcsw   " CSV_SEP \
		"ivcsw\n"

	char decimals[10];

	// Total time
	snprintf(decimals, 10, "%09ld", elapsed.tv_nsec);
	assert(elapsed.tv_sec < 1e4);
	fprintf(outfile, "%3ld.%.3s" CSV_SEP, elapsed.tv_sec, decimals);

	// User time
	snprintf(decimals, 7, "%06ld", rusage.ru_utime.tv_usec);
	assert(rusage.ru_utime.tv_sec < 1e4);
	fprintf(outfile, "%3ld.%.3s" CSV_SEP, rusage.ru_utime.tv_sec, decimals);

	// System time
	snprintf(decimals, 7, "%06ld", rusage.ru_stime.tv_usec);
	assert(rusage.ru_stime.tv_sec < 1e4);
	fprintf(outfile, "%3ld.%.3s" CSV_SEP, rusage.ru_stime.tv_sec, decimals);

	// Pagefaults
	assert(rusage.ru_minflt < 1e8 && rusage.ru_majflt < 1e8);
	fprintf(outfile, "%7ld" CSV_SEP "%7ld" CSV_SEP, rusage.ru_minflt, rusage.ru_majflt);

	// Swaps
	assert(rusage.ru_nswap < 1e8);
	fprintf(outfile, "%7ld" CSV_SEP, rusage.ru_nswap);

	// Context switches
	assert(rusage.ru_nvcsw < 1e8 && rusage.ru_nivcsw < 1e8);
	fprintf(outfile, "%7ld" CSV_SEP "%7ld\n", rusage.ru_nvcsw, rusage.ru_nivcsw);
}

int main(int argc, char** argv) {
	// Strip first argument containing program name
	--argc;
	++argv;

	// Need at least two args to check for "-i" "<input-file>"
	if (argc < 2)
		return usage_error();

	// Optional argument "<input-file>" after "-i"
	size_t input_len;
	char* input = 0;
	if (strncmp("-i", argv[0], 2) == 0) {
		// Take "-i" and "<input-file>" from argv, open as read
		input = read_all(argv[1], &input_len, 1);
		argc -= 2;
		argv += 2;
	}

	// Need at least two args for "<output-file>" and "<binary>"
	if (argc < 2)
		return usage_error();

	// Take "<output-file>" from argv, redirect to stdout or open as append
	FILE* outfile;
	if (strncmp(argv[0], "-", 1) == 0) {
		outfile = stdout;
	} else {
		outfile = fopen(argv[0], "a");
		if (!outfile) {
			perror(argv[0]);
			return EXIT_FAILURE;
		}
	}
	++argv;

	// Write header for current run
	struct cpuinfo info;
	get_cpuinfo(&info);

	// Convert frequency
	char decimals[8];
	char *unit;
	if (info.overall_freq >= 1e6) {
		snprintf(decimals, 8, ".%06d", info.overall_freq % 1000000);
		info.overall_freq /= 1000000;
		unit = "GHz";
	} else if (info.overall_freq >= 1e3) {
		snprintf(decimals, 8, ".%03d", info.overall_freq % 1000);
		info.overall_freq /= 1000;
		unit = "MHz";
	} else {
		unit = "kHz";
	}

	// Truncate trailing zeroes
	for (int i = strnlen(decimals, 8) - 1; i >= 0; --i) {
		if (i == 0) {
			decimals[0] = 0;
		} else if (decimals[i] != '0') {
			decimals[i + 1] = 0;
			break;
		}
	}

	#ifndef ISA_NAME
		#define ISA_NAME "unknown" // ISA_NAME should be set in Makefile
	#endif
	fprintf(outfile, "%s (%d x %d%s %s, " ISA_NAME ")\n" CSV_HEADER, argv[0], info.count, info.overall_freq, decimals, unit);

	#define NUM_ITERS 5

	const char *num_iters_str = STRINGIFY(NUM_ITERS);
	const int num_iters_len = strlen(num_iters_str);

	// Run five timing iterations
	for (int i = 0; i < NUM_ITERS; ++i) {
		if (outfile != stdout)
			printf("Iteration %0*d/%s\n", num_iters_len, i + 1, num_iters_str);
		run_bench(input, input_len, outfile, argv);
	}

	return EXIT_SUCCESS;
}
