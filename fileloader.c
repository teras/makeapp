#include "fileconst.h"

#include <stdio.h>
#include <stdlib.h>
#include "fileloader.h"

// if we want the real thing, maybe get inspired by https://github.com/AlexDenisov/segment_dumper/blob/master/main.c

int needsSigningMem(const void* memblock) {
    struct mach_header_64 * header;
    header = (struct mach_header_64 *)memblock;
    return (*header).filetype == MH_EXECUTE || (*header).filetype == MH_DYLIB ;
}

__attribute__((used)) int needsSigning(const char* path) {
    struct mach_header_64 header;
    FILE * file = fopen (path, "r");
    if (!file)
        return FALSE;
    size_t found = fread(&header, sizeof(header), 1, file);
    fclose(file);
    return found == 1 && needsSigningMem(&header);
}
