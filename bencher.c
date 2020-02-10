#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <time.h>

#include <sys/types.h>
#include <sys/time.h>
#include <sys/resource.h>
#include <sys/wait.h>

#define STRINGIFY_HELPER(arg) #arg
#define STRINGIFY(arg) STRINGIFY_HELPER(arg)

int usage_error() {
	fprintf(stderr, "Argument format is [-i <input-file>] <output-file> <binary> [<binary arguments>...]i\n");
	return EXIT_FAILURE;
}

char *read_all(const char* filename, size_t *length_out) {
	// Attempt to open the file
	FILE *f = fopen(filename, "r");
	if (!f) {
		perror("Open input");
		return NULL;
	}

	// Get total length
	fseek(f, 0, SEEK_END);
	size_t length = (size_t) ftell(f);
	rewind(f);

	// Write to output param
	if (length_out)
		*length_out = length;

	// Allocate buffer for file contents and terminating '\0'
	char *buffer = malloc(sizeof(char) * (length + 1));
	if (!buffer) {
		fprintf(stderr, "Could not allocate memory to hold %s", filename);
		goto end; // close file & return
	}

	// Attempt to read the file to memory
	size_t read = fread(buffer, sizeof(char), length, f);
	if (read != length) {
		perror("Wrong length");
		free(buffer);
		buffer = NULL;
	}

end:
	// Attempt to close the file
	if (fclose(f))
		perror(filename);

	return buffer;
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
	#define CSV_HEADER "time (seconds)\n"

	// Get decimal places for elapsed
	char elapsed_decimals[10];
	snprintf(elapsed_decimals, 10, "%09ld", elapsed.tv_nsec);

	fprintf(outfile, "%ld.%.3s\n", elapsed.tv_sec, elapsed_decimals);
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
		input = read_all(argv[1], &input_len);
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
	fprintf(outfile, "%s\n" CSV_HEADER, argv[0]);

	#define NUM_ITERS 5

	const char *num_iters_str = STRINGIFY(NUM_ITERS);
	const int num_iters_len = strlen(num_iters_str);

	// Run five timing iterations
	for (int i = 0; i < NUM_ITERS; ++i) {
		printf("Iteration %0*d/%s\n", num_iters_len, i + 1, num_iters_str);
		run_bench(input, input_len, outfile, argv);
	}

	return EXIT_SUCCESS;
}
