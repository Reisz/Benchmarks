#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <time.h>
#include <assert.h>
#include <sched.h>

#include <sys/types.h>
#include <sys/time.h>
#include <sys/resource.h>
#include <sys/wait.h>

#include "diff.h"
#include "fileutils.h"
#include "cpufreq.h"

#define STRINGIFY_HELPER(arg) #arg
#define STRINGIFY(arg) STRINGIFY_HELPER(arg)

int usage_error() {
	fprintf(stderr, "Argument format is [-i <input-file>] [-diff <diff-file> [-abserr <absolute-error> | -bin]] [-t <timeout-secs>] <output-file> <binary> [<binary arguments>...]\n");
	return EXIT_FAILURE;
}

struct Input {
	size_t length;
	char *text;
};

#define CLOCK CLOCK_MONOTONIC
#ifndef BUFFER
	#define BUFFER "tmp/buffer"
#endif
int run_bench(const struct Input *input, FILE* outfile, char** argv, rlim_t timeout_secs, const struct Diff *diff) {

	// Create pipes for communication
	#define CHILD_IN 0
	#define PARENT_OUT 1
	int pipes[2];

	// Create first set of pipes
	if (pipe(pipes)) {
		perror("pipe child -> parent");
		exit(EXIT_FAILURE);
	}

	// Create cpu set for cpu 0
	cpu_set_t cpu_set;
	CPU_ZERO(&cpu_set);
	CPU_SET(1, &cpu_set);

	// Store start time
	struct timespec start;
	clock_gettime(CLOCK, &start);

	// Attempt to fork/execv to run child process
	pid_t pid = fork();
	if (pid < 0) {
		perror("fork");
		exit(EXIT_FAILURE);
	} else if (pid == 0) {
		// Close wrong side of pipe
		close(pipes[PARENT_OUT]);

		// Map pipes to stdin
		dup2(pipes[CHILD_IN], 0);

		// Map stdout to tmpfs
		freopen(BUFFER, "w", stdout);

		// Pin to cpu 0
		sched_setaffinity(0, sizeof(cpu_set), &cpu_set);

		// Set timeout
		if (timeout_secs > 0) {
			struct rlimit limit;
			getrlimit(RLIMIT_CPU, &limit);
			limit.rlim_cur = timeout_secs;
			setrlimit(RLIMIT_CPU, &limit);
		}

		// Run benchmark
		execv(argv[0], argv);
		perror(argv[0]);
		exit(EXIT_FAILURE);
	}

	// Close wrong side of pipe
	close(pipes[CHILD_IN]);

	// Write to the pipe if applicable
	if (input)
		write(pipes[PARENT_OUT], input->text, input->length);

	// Close after writing
	close(pipes[PARENT_OUT]);

	// Wait for process to end
	int status;
	struct rusage rusage;
	wait4(pid, &status, 0, &rusage);

	// Stop if the process did not exit successfully
	if (status != EXIT_SUCCESS)
		return 0;

	// Store end time
	struct timespec elapsed;
	clock_gettime(CLOCK, &elapsed);

	// Check output and close pipe
	FILE *output = fopen(BUFFER, "r");
	int result = check_output(output, diff);
	fclose(output);

	// Don't log results on diff failure
	if (!result)
		return result;

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
		"maxrss " CSV_SEP \
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

	// Maximum resident set size
	assert(rusage.ru_maxrss < 1e8 && rusage.ru_maxrss < 1e8);
	fprintf(outfile, "%7ld" CSV_SEP , rusage.ru_maxrss);

	// Pagefaults
	assert(rusage.ru_minflt < 1e8 && rusage.ru_majflt < 1e8);
	fprintf(outfile, "%7ld" CSV_SEP "%7ld" CSV_SEP, rusage.ru_minflt, rusage.ru_majflt);

	// Swaps
	assert(rusage.ru_nswap < 1e8);
	fprintf(outfile, "%7ld" CSV_SEP, rusage.ru_nswap);

	// Context switches
	assert(rusage.ru_nvcsw < 1e8 && rusage.ru_nivcsw < 1e8);
	fprintf(outfile, "%7ld" CSV_SEP "%7ld\n", rusage.ru_nvcsw, rusage.ru_nivcsw);

	return 1;
}

int main(int argc, char** argv) {
	// Strip first argument containing program name
	--argc;
	++argv;

	// Need at least two args to check for "-i" "<input-file>"
	if (argc < 2)
		return usage_error();

	// Optional argument "<input-file>" after "-i"
	struct Input input = { 0, NULL };
	if (strncmp("-i", argv[0], 2) == 0) {
		// Take "-i" and "<input-file>" from argv, read file to memory
		input.text = read_all(argv[1], &input.length, 1);
		argc -= 2;
		argv += 2;
	}

	// Need at least two args to check for "<diff-file>" after "-d"
	if (argc < 2)
		return usage_error();

	// Optional file to diff output against and optional absolute error for numeric diff.
	struct Diff diff = { 0, NULL, 0.0, 0 };
	if (strncmp("-diff", argv[0], 5) == 0) {
		// Take "-diff" and "<diff-file>" from argv, read file to memory
		diff.text = read_all(argv[1], &diff.length, 1);
		argc -= 2;
		argv += 2;


		// Need at least two args to check for "<absolute-error>" after "-abserr"
		if (argc < 2)
			return usage_error();

		if (strncmp("-abserr", argv[0], 7) == 0) {
			// Take "-abserr" and "<absolute-error>" from argv, parse long double
			sscanf(argv[1], "%Lf", &diff.abserr);
			argc -= 2;
			argv += 2;
		} else if (strncmp("-bin", argv[0], 4) == 0) {
			diff.binary = 1;
			argc -= 1;
			argv += 1;
		}
	}

	// Need at least two args to check for "<timeout-secs>" after "-t"
	if (argc < 2)
		return usage_error();

	rlim_t timeout_secs = 0;
	if (strncmp("-t", argv[0], 7) == 0) {
		// Take "-t" and "<timout-secs>" from argv, parse long
		sscanf(argv[1], "%lu", &timeout_secs);
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
		if (!run_bench(&input, outfile, argv, timeout_secs, &diff))
			break;
	}

	free(input.text);
	free(diff.text);

	return EXIT_SUCCESS;
}
