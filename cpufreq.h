#ifndef _CPUFREQ_H
#define _CPUFREQ_H

#include <stdio.h>
#include <stdlib.h>

#include <sys/sysinfo.h>

#include "fileutils.h"

#define GOVERNOR_FILE "/sys/devices/system/cpu/cpu%d/cpufreq/scaling_governor"
#define CURRENT_FREQUENCY "/sys/devices/system/cpu/cpu%d/cpufreq/scaling_cur_freq"
#define MAX_FREQUENCY "/sys/devices/system/cpu/cpu%d/cpufreq/scaling_max_freq"

char *governor(int cpu) {
    // Enough room to print any int (warns for lower numbers)
    char filename[sizeof GOVERNOR_FILE + 8];
    snprintf(filename, sizeof filename, GOVERNOR_FILE, cpu);

    return read_all(filename, NULL, 0);
}

int current_frequency(int cpu) {
    // Enough room to print any int (warns for lower numbers)
    char filename[sizeof CURRENT_FREQUENCY + 8];
    snprintf(filename, sizeof filename, CURRENT_FREQUENCY, cpu);

    char *freq = read_all(filename, NULL, 0);
    int result = atoi(freq);
    free(freq);

    return result;
}

int max_frequency(int cpu) {
    // Enough room to print any int (warns for lower numbers)
    char filename[sizeof MAX_FREQUENCY + 8];
    snprintf(filename, sizeof filename, MAX_FREQUENCY, cpu);

    char *freq = read_all(filename, NULL, 0);
    int result = atoi(freq);
    free(freq);

    return result;
}

struct cpuinfo {
    int count;
    int overall_freq;
};

void get_cpuinfo(struct cpuinfo *result) {
    int cpus = get_nprocs();
    result->count = cpus;

    int all_same = 1;
    int prev, current;

    for (int i = 0; i < cpus; ++i) {
        char *gov = governor(i);

        // Find frequency for governor
        if (strncmp(gov, "userspace", 9) == 0) {
            current = current_frequency(i);
        } else if (strncmp(gov, "performance", 11) == 0) {
            current = max_frequency(i);
        } else {
            fprintf(stderr, "Error: Cpu %d is not configured to an appropriate governor.", i);
            exit(1);
        }

        free(gov);

        // Compare to previous frequency
        if (all_same && i > 0 && prev != current)
            all_same = 0;
        prev = current;
    }

    if (!all_same) {
        fprintf(stderr, "Error: Not all cpus are configured the same.");
        exit(1);
    }

    result->overall_freq = current;
}

#endif // _CPUFREQ_H
