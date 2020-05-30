#include "fileconst.h"

#include <stdio.h>
#include <stdlib.h>

int needsSigningMem(const void* memblock) {
    struct mach_header_64 * header;
    header = (struct mach_header_64 *)memblock;
    return (*header).filetype == MH_EXECUTE || (*header).filetype == MH_DYLIB ;
}

int needsSigning(const char* path) {
    struct mach_header_64 header;
    FILE * file = fopen (path, "r");
    if (!file)
        return FALSE;
    size_t found = fread(&header, sizeof(header), 1, file);
    fclose(file);
    return found == 1 && needsSigningMem(&header);
}
