#include <stdio.h>
#include <stdlib.h>
#include <math.h>

// fp_lookup.c: Generates an 11-bit-addressed lookup table for the function atan/PI (ignoring sign bit and last 4 bits of mantissa)

typedef union 
{
    _Float16 f;
    uint16_t i;
} FloatBits;

// Calculate atan(x)/PI for the float {1'b0, x, 4'b1000}
uint16_t approx_atan(uint16_t x) {
    FloatBits f;
    f.i = (x << 4) + 0b1000;
    FloatBits r;
    r.f = atanf(f.f) / M_PI;
    printf("%d: %f => %f\n", f.i, (double) f.f, (double) r.f);
    return r.i;
}

int main() {
    FILE *fp = fopen("atan_lut.mem", "w");
    for (int i = 0; i < 2048; i++) {
        fprintf(fp, "%.4x\n", approx_atan(i));
    }
    fclose(fp);
    return 0;
}