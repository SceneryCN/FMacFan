#ifndef CSMC_H
#define CSMC_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct MFSMCConnection MFSMCConnection;

typedef enum {
    MFSMC_OK = 0,
    MFSMC_INVALID_ARGUMENT = -1,
    MFSMC_SERVICE_NOT_FOUND = -2,
    MFSMC_OPEN_FAILED = -3,
    MFSMC_CALL_FAILED = -4,
    MFSMC_RESULT_ERROR = -5,
    MFSMC_BUFFER_TOO_SMALL = -6
} MFSMCStatus;

MFSMCConnection *mf_smc_open(void);
void mf_smc_close(MFSMCConnection *connection);

MFSMCStatus mf_smc_read(
    MFSMCConnection *connection,
    const char key[4],
    uint8_t *bytes,
    size_t capacity,
    size_t *size,
    char data_type[5]
);

MFSMCStatus mf_smc_write(
    MFSMCConnection *connection,
    const char key[4],
    const uint8_t *bytes,
    size_t size
);

MFSMCStatus mf_smc_key_at_index(
    MFSMCConnection *connection,
    uint32_t index,
    char key[5]
);

#ifdef __cplusplus
}
#endif

#endif
