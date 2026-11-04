#import <Foundation/Foundation.h>
#import <IOKit/IOKitLib.h>
#import <math.h>
// Read-only AppleSMC interface; no write command is implemented.
// TL0P display association follows Stats; Apple does not document its location.
typedef struct { uint8_t major, minor, build, reserved; uint16_t release; } XDRSMCVers;
typedef struct { uint16_t version, length; uint32_t cpu, gpu, mem; } XDRSMCLimits;
typedef struct { uint32_t size, type; uint8_t attributes; } XDRSMCInfo;
typedef struct {
    uint32_t key; XDRSMCVers vers; XDRSMCLimits limits; XDRSMCInfo info;
    uint8_t result, status, command; uint32_t index; uint8_t bytes[32];
} XDRSMCData;
_Static_assert(sizeof(XDRSMCData) == 80, "SMC ABI must be 80 bytes");
static uint32_t XDRFourCC(const char *k) {
    return (uint32_t)(uint8_t)k[0]<<24 | (uint32_t)(uint8_t)k[1]<<16 | (uint32_t)(uint8_t)k[2]<<8 | (uint8_t)k[3];
}
@interface TemperatureReader : NSObject
@property io_connect_t connection;
- (double)readCelsius:(const char *)key;
@end
@implementation TemperatureReader
- (instancetype)init {
    self = [super init];
    if (self) {
        io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
        if (service) {
            io_connect_t connection = 0;
            if (IOServiceOpen(service, mach_task_self(), 0, &connection) == KERN_SUCCESS) self.connection = connection;
            IOObjectRelease(service);
        }
    }
    return self;
}
- (double)readCelsius:(const char *)key {
    if (!self.connection) return NAN;
    XDRSMCData input = {0}, output = {0}; size_t size = sizeof output;
    input.key = XDRFourCC(key); input.command = 9;
    kern_return_t result = IOConnectCallStructMethod(self.connection, 2, &input, sizeof input, &output, &size);
    if (result != KERN_SUCCESS || size != sizeof output || output.result || output.info.size == 0 || output.info.size > 32) return NAN;
    uint32_t type = output.info.type, bytes = output.info.size;
    input.info.size = bytes; input.command = 5; size = sizeof output;
    result = IOConnectCallStructMethod(self.connection, 2, &input, sizeof input, &output, &size);
    if (result != KERN_SUCCESS || size != sizeof output || output.result) return NAN;
    double value = NAN;
    if (type == XDRFourCC("flt ") && bytes == 4) { float temp; memcpy(&temp, output.bytes, 4); value = temp; }
    else if (type == XDRFourCC("sp78") && bytes == 2) value = (int16_t)((output.bytes[0]<<8)|output.bytes[1])/256.0;
    return isfinite(value) && value > 0 && value < 120 ? value : NAN;
}
- (void)dealloc { if (_connection) IOServiceClose(_connection); }
@end
static NSString *ThermalLabel(NSProcessInfoThermalState state) {
    switch (state) {
        case NSProcessInfoThermalStateNominal: return @"正常";
        case NSProcessInfoThermalStateFair: return @"升温";
        case NSProcessInfoThermalStateSerious: return @"较高";
        case NSProcessInfoThermalStateCritical: return @"严重";
    }
    return @"未知";
}
