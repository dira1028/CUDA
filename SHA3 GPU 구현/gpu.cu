#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include <time.h>

#define SHAKE128_RATE 168
#define SHAKE256_RATE 136

#define ROTL64(x, y) (((x) << (y)) | ((x) >> (64 - (y))))

typedef struct {
    uint64_t ctx[26];
} shake128incctx;

typedef struct {
    uint64_t ctx[26];
} shake256incctx;

// Round constants
__constant__ uint64_t RC[24] = {
    0x0000000000000001, 0x0000000000008082, 0x800000000000808a,
    0x8000000080008000, 0x000000000000808b, 0x0000000080000001,
    0x8000000080008081, 0x8000000000008009, 0x000000000000008a,
    0x0000000000000088, 0x0000000080008009, 0x000000008000000a,
    0x000000008000808b, 0x800000000000008b, 0x8000000000008089,
    0x8000000000008003, 0x8000000000008002, 0x8000000000000080, 
    0x000000000000800a, 0x800000008000000a, 0x8000000080008081,
    0x8000000000008080, 0x0000000080000001, 0x8000000080008008
};

// Rotation offsets
__constant__ const int r_offset[24] = {
    1,  3,  6,  10, 15, 21, 28, 36, 45, 55, 2,  14, 
    27, 41, 56, 8,  25, 43, 62, 18, 39, 61, 20, 44
};

__constant__ const int piln[24] = {
    10, 7,  11, 17, 18, 3, 5,  16, 8,  21, 24, 4, 
    15, 23, 19, 13, 12, 2, 20, 14, 22, 9,  6,  1 
};

// Updates the state with 24 rounds
__device__ void keccakf(uint64_t *state) {
    int i, j;
    uint64_t temp, C[5];

    for (int round = 0; round < 24; round++) {
        //theta
        for (i = 0; i < 5; i++) {
            C[i] = state[i] ^ state[i + 5] ^ state[i + 10] ^ state[i + 15] ^ state[i + 20];
        }
        for (i = 0; i < 5; i++) {
            temp = C[(i + 4) % 5] ^ ROTL64(C[(i + 1) % 5], 1);
            for (j = 0; j < 25; j += 5) {
                state[j + i] ^= temp;
            }
        }
        //rho pi
        temp = state[1];
        for (i = 0; i < 24; i++) {
            j = piln[i];
            C[0] = state[j];
            state[j] = ROTL64(temp, r_offset[i]);
            temp = C[0];
        }
        
        //chi
        for (j = 0; j < 25; j += 5) {
            for (i = 0; i < 5; i++) {
                C[i] = state[j + i];
            }
            for (i = 0; i < 5; i++) {
                state[j + i] ^= (~C[(i + 1) % 5]) & C[(i + 2) % 5];
            }
        }
        //iota
        state[0] ^= RC[round];
    }
}

// 1. Init
__device__ void keccak_inc_init(uint64_t *s_inc) {
    size_t i;
    for (i = 0; i < 25; ++i) {
        s_inc[i] = 0;
    }
    s_inc[25] = 0;
}

__device__ void keccak_inc_absorb(uint64_t *s_inc, uint32_t r, const uint8_t *m, size_t mlen) {
    size_t i;
    while (mlen > 0) {
        size_t len = r - s_inc[25];
        if (mlen < len) len = mlen;
        
        for (i = 0; i < len; i++) {
            s_inc[(s_inc[25] + i) >> 3] ^= (uint64_t)m[i] << (8 * ((s_inc[25] + i) & 0x07));
        }
        
        s_inc[25] += len;
        m += len;
        mlen -= len;
        
        if (s_inc[25] == r) {
            keccakf(s_inc);
            s_inc[25] = 0;
        }
    }
}

__device__ void keccak_inc_finalize(uint64_t *s_inc, uint32_t r, uint8_t p) {
    s_inc[s_inc[25] >> 3] ^= (uint64_t)p << (8 * (s_inc[25] & 0x07));
    s_inc[(r - 1) >> 3] ^= (uint64_t)128 << (8 * ((r - 1) & 0x07));
    s_inc[25] = 0;
}

__device__ void keccak_inc_squeeze(uint8_t *h, size_t outlen, uint64_t *s_inc, uint32_t r) {
    size_t i;
    for (i = 0; i < outlen && i < s_inc[25]; i++) {
        h[i] = (uint8_t)(s_inc[(r - s_inc[25] + i) >> 3] >> (8 * ((r - s_inc[25] + i) & 0x07)));
    }
    h += i;
    outlen -= i;
    s_inc[25] -= i;

    while (outlen > 0) {
        keccakf(s_inc);
        for (i = 0; i < outlen && i < r; i++) {
            h[i] = (uint8_t)(s_inc[i >> 3] >> (8 * (i & 0x07)));
        }
        h += i;
        outlen -= i;
        s_inc[25] = r - i;
    }
}

/* ================== SHAKE128 Wrapper ================== */
__device__ void shake128_inc_init(shake128incctx *state) {
    keccak_inc_init(state->ctx);
}

__device__ void shake128_inc_absorb(shake128incctx *state, const uint8_t *input, size_t inlen) {
    keccak_inc_absorb(state->ctx, SHAKE128_RATE, input, inlen);
}

__device__ void shake128_inc_finalize(shake128incctx *state) {
    keccak_inc_finalize(state->ctx, SHAKE128_RATE, 0x1F);
}

__device__ void shake128_inc_squeeze(uint8_t *output, size_t outlen, shake128incctx *state) {
    keccak_inc_squeeze(output, outlen, state->ctx, SHAKE128_RATE);
}


/* ================== SHAKE256 Wrapper ================== */
__device__ void shake256_inc_init(shake256incctx *state) {
    keccak_inc_init(state->ctx);
}

__device__ void shake256_inc_absorb(shake256incctx *state, const uint8_t *input, size_t inlen) {
    keccak_inc_absorb(state->ctx, SHAKE256_RATE, input, inlen);
}

__device__ void shake256_inc_finalize(shake256incctx *state) {
    keccak_inc_finalize(state->ctx, SHAKE256_RATE, 0x1F);
}

__device__ void shake256_inc_squeeze(uint8_t *output, size_t outlen, shake256incctx *state) {
    keccak_inc_squeeze(output, outlen, state->ctx, SHAKE256_RATE);
}

__device__ void shake256_inc_ctx_clone(shake256incctx *dest, const shake256incctx *src) {
    memcpy(dest->ctx, src->ctx, sizeof(src->ctx));
}

__constant__ uint8_t seed[32] = {0xff, 0xee, 0xdd, 0xcc, 0xbb, 0xaa, 0x99, 0x88,
                        0x77, 0x66, 0x55, 0x44, 0x33, 0x22, 0x11, 0x00,
                        0xff, 0xee, 0xdd, 0xcc, 0xbb, 0xaa, 0x99, 0x88,
                        0x77, 0x66, 0x55, 0x44, 0x33, 0x22, 0x11, 0x00};

/* ================== Benchmark ================== */
__global__ void benchmark_shake128(int iterations) {
    __shared__ uint64_t state[26];
    uint32_t rate = SHAKE128_RATE;
    uint8_t p = 0x1F;    

    uint8_t squeeze_out[168]; 
    


    clock_t start = clock();
    
    for (int i = 0; i < iterations; i++) {
        keccak_inc_init(state);
        
        keccak_inc_absorb(state, rate, seed, sizeof(seed));
        keccak_inc_finalize(state, rate, p);
        
        for (int j = 0; j < 5; j++) {
            keccak_inc_squeeze(squeeze_out, rate, state, rate);
        }
    }
    
    clock_t end = clock();
    double time_used = (double)(end - start) / CLOCKS_PER_SEC;
    
    printf("Iterations: %d\n", iterations);
    printf("Time used: %f seconds\n", time_used);
}

int main(int argc, char *argv[]) {
    int iterations = 100000;
    if (argc > 1) {
        iterations = atoi(argv[1]);
    }

    // 현재 커널은 디바이스 포인터 인자가 없으므로 cudaMalloc은 생략합니다.

    // 1개의 블록, 1개의 스레드로 벤치마크 커널 실행 (단일 스레드 측정)
    benchmark_shake128<<<1, 1>>>(iterations);

    // 커널 실행이 완료될 때까지 호스트 대기
    // GPU 내부의 printf 출력 버퍼를 호스트 콘솔로 밀어내기 위해 반드시 필요합니다.
    cudaDeviceSynchronize();

    return EXIT_SUCCESS;
}