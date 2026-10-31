/* Mbed TLS monotonic milliseconds using the clock present since early iPhoneOS. */
#include <stdint.h>
#include <mach/mach_time.h>

int64_t mbedtls_ms_time(void) {
    mach_timebase_info_data_t scale;
    if (mach_timebase_info(&scale) != 0 || scale.denom == 0) return 0;
    return (int64_t)((double)mach_absolute_time() * scale.numer / scale.denom / 1000000.0);
}
