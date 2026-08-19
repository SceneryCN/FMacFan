#include "CSMC.h"

#include <IOKit/IOKitLib.h>
#include <libkern/OSByteOrder.h>
#include <stdlib.h>
#include <string.h>

enum {
    kSMCUserClientOpen = 0,
    kSMCUserClientClose = 1,
    kSMCHandleYPCEvent = 2,
    kSMCReadKey = 5,
    kSMCWriteKey = 6,
    kSMCGetKeyFromIndex = 8,
    kSMCGetKeyInfo = 9,
    kSMCMaxDataSize = 32
};

typedef struct {
    uint8_t major;
    uint8_t minor;
    uint8_t build;
    uint8_t reserved;
    uint16_t release;
} SMCVersion;

typedef struct {
    uint16_t version;
    uint16_t length;
    uint32_t cpu_limit;
    uint32_t gpu_limit;
    uint32_t memory_limit;
} SMCPLimitData;

typedef struct {
    uint32_t data_size;
    uint32_t data_type;
    uint8_t attributes;
} SMCKeyInfoData;

typedef struct {
    uint32_t key;
    SMCVersion version;
    SMCPLimitData limit_data;
    SMCKeyInfoData key_info;
    uint8_t result;
    uint8_t status;
    uint8_t command;
    uint32_t data32;
    uint8_t bytes[kSMCMaxDataSize];
} SMCParamStruct;

_Static_assert(sizeof(SMCParamStruct) == 80, "Unexpected AppleSMC parameter layout");

struct MFSMCConnection {
    io_connect_t handle;
};

static uint32_t key_code(const char key[4]) {
    uint32_t value = 0;
    memcpy(&value, key, sizeof(value));
    return OSSwapHostToBigInt32(value);
}

static MFSMCStatus call_smc(
    MFSMCConnection *connection,
    const SMCParamStruct *input,
    SMCParamStruct *output
) {
    size_t output_size = sizeof(*output);
    kern_return_t result = IOConnectCallStructMethod(
        connection->handle,
        kSMCHandleYPCEvent,
        input,
        sizeof(*input),
        output,
        &output_size
    );

    if (result != KERN_SUCCESS || output_size != sizeof(*output)) {
        return MFSMC_CALL_FAILED;
    }

    return output->result == 0 ? MFSMC_OK : MFSMC_RESULT_ERROR;
}

static MFSMCStatus read_key_info(
    MFSMCConnection *connection,
    uint32_t key,
    SMCKeyInfoData *key_info
) {
    SMCParamStruct input = {0};
    SMCParamStruct output = {0};
    input.key = key;
    input.command = kSMCGetKeyInfo;

    MFSMCStatus status = call_smc(connection, &input, &output);
    if (status == MFSMC_OK) {
        *key_info = output.key_info;
    }
    return status;
}

MFSMCConnection *mf_smc_open(void) {
    io_service_t service = IOServiceGetMatchingService(
        kIOMainPortDefault,
        IOServiceMatching("AppleSMC")
    );
    if (service == IO_OBJECT_NULL) {
        return NULL;
    }

    MFSMCConnection *connection = calloc(1, sizeof(*connection));
    if (connection == NULL) {
        IOObjectRelease(service);
        return NULL;
    }

    kern_return_t result = IOServiceOpen(
        service,
        mach_task_self(),
        kSMCUserClientOpen,
        &connection->handle
    );
    IOObjectRelease(service);

    if (result != KERN_SUCCESS) {
        free(connection);
        return NULL;
    }

    return connection;
}

void mf_smc_close(MFSMCConnection *connection) {
    if (connection == NULL) {
        return;
    }
    IOServiceClose(connection->handle);
    free(connection);
}

MFSMCStatus mf_smc_read(
    MFSMCConnection *connection,
    const char key[4],
    uint8_t *bytes,
    size_t capacity,
    size_t *size,
    char data_type[5]
) {
    if (connection == NULL || key == NULL || bytes == NULL || size == NULL) {
        return MFSMC_INVALID_ARGUMENT;
    }

    const uint32_t code = key_code(key);
    SMCKeyInfoData key_info = {0};
    MFSMCStatus status = read_key_info(connection, code, &key_info);
    if (status != MFSMC_OK) {
        return status;
    }
    if (key_info.data_size > kSMCMaxDataSize || capacity < key_info.data_size) {
        return MFSMC_BUFFER_TOO_SMALL;
    }

    SMCParamStruct input = {0};
    SMCParamStruct output = {0};
    input.key = code;
    input.key_info.data_size = key_info.data_size;
    input.command = kSMCReadKey;

    status = call_smc(connection, &input, &output);
    if (status != MFSMC_OK) {
        return status;
    }

    memcpy(bytes, output.bytes, key_info.data_size);
    *size = key_info.data_size;

    if (data_type != NULL) {
        const uint32_t type = OSSwapHostToBigInt32(key_info.data_type);
        memcpy(data_type, &type, 4);
        data_type[4] = '\0';
    }
    return MFSMC_OK;
}

MFSMCStatus mf_smc_write(
    MFSMCConnection *connection,
    const char key[4],
    const uint8_t *bytes,
    size_t size
) {
    if (connection == NULL || key == NULL || bytes == NULL || size > kSMCMaxDataSize) {
        return MFSMC_INVALID_ARGUMENT;
    }

    const uint32_t code = key_code(key);
    SMCKeyInfoData key_info = {0};
    MFSMCStatus status = read_key_info(connection, code, &key_info);
    if (status != MFSMC_OK) {
        return status;
    }
    if (key_info.data_size != size) {
        return MFSMC_INVALID_ARGUMENT;
    }

    SMCParamStruct input = {0};
    SMCParamStruct output = {0};
    input.key = code;
    input.key_info = key_info;
    input.command = kSMCWriteKey;
    memcpy(input.bytes, bytes, size);

    return call_smc(connection, &input, &output);
}

MFSMCStatus mf_smc_key_at_index(
    MFSMCConnection *connection,
    uint32_t index,
    char key[5]
) {
    if (connection == NULL || key == NULL) {
        return MFSMC_INVALID_ARGUMENT;
    }

    SMCParamStruct input = {0};
    SMCParamStruct output = {0};
    input.data32 = index;
    input.command = kSMCGetKeyFromIndex;

    MFSMCStatus status = call_smc(connection, &input, &output);
    if (status != MFSMC_OK) {
        return status;
    }

    const uint32_t code = OSSwapHostToBigInt32(output.key);
    memcpy(key, &code, 4);
    key[4] = '\0';
    return MFSMC_OK;
}
