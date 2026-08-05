#include "cuda_runtime.h"
#include "device_launch_parameters.h"
#include "DS_timer.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

#define BLOCK_SIZE 16

#define CUDA_CHECK(call)                                                      \
    do {                                                                      \
        cudaError_t err = (call);                                             \
        if (err != cudaSuccess) {                                             \
            printf("CUDA error %s:%d : %s\n", __FILE__, __LINE__,             \
                   cudaGetErrorString(err));                                  \
            exit(EXIT_FAILURE);                                               \
        }                                                                     \
    } while (0)

// C(m x n) = A(m x k) * B(k x n)
__global__ void matMul(int *_a, int *_b, int *_c, int m, int n, int k)
{
    int col = blockDim.x * blockIdx.x + threadIdx.x;  // n 방향
    int row = blockDim.y * blockIdx.y + threadIdx.y;  // m 방향

    if (row >= m || col >= n) return;   // 경계 검사 (ceil 때문에 필수)

    int sum = 0;
    for (int i = 0; i < k; i++)
        sum += _a[row * k + i] * _b[i * n + col];

    _c[row * n + col] = sum;
}

void matMulCPU(int *A, int *B, int *C, int m, int n, int k)
{
    for (int row = 0; row < m; row++) {
        for (int col = 0; col < n; col++) {
            int sum = 0;
            for (int i = 0; i < k; i++)
                sum += A[row * k + i] * B[i * n + col];
            C[row * n + col] = sum;
        }
    }
}

void printMatrix(const char *name, int *M, int rows, int cols)
{
    printf("\n[%s] (%d x %d)\n", name, rows, cols);
    if (rows > 8 || cols > 8) {
        printf("  (too large to print, skipped)\n");
        return;
    }
    for (int r = 0; r < rows; r++) {
        printf("  ");
        for (int c = 0; c < cols; c++)
            printf("%6d ", M[r * cols + c]);
        printf("\n");
    }
}

int main(int argc, char *argv[])
{
    if (argc < 4) {
        printf("usage: %s <m> <n> <k>\n", argv[0]);
        return EXIT_FAILURE;
    }

    DS_timer timer(3);
    timer.initTimers();
    timer.setTimerName(0, (char *)"GPU Memcpy");
    timer.setTimerName(1, (char *)"GPU Kernel");
    timer.setTimerName(2, (char *)"CPU");

    int m = atoi(argv[1]);
    int n = atoi(argv[2]);
    int k = atoi(argv[3]);

    int sizeA = m * k;
    int sizeB = k * n;
    int sizeC = m * n;

    int *A    = (int *)malloc(sizeA * sizeof(int));
    int *B    = (int *)malloc(sizeB * sizeof(int));
    int *Ccpu = (int *)malloc(sizeC * sizeof(int));
    int *Cgpu = (int *)malloc(sizeC * sizeof(int));

    srand(0);
    for (int i = 0; i < sizeA; i++) A[i] = rand() % 10;   // sizeA 만큼만
    for (int i = 0; i < sizeB; i++) B[i] = rand() % 10;   // sizeB 만큼만

    int *dA, *dB, *dC;
    cudaMalloc(&dA, sizeA * sizeof(int));
    cudaMalloc(&dB, sizeB * sizeof(int));
    cudaMalloc(&dC, sizeC * sizeof(int));
    cudaMemset(dC, 0, sizeC * sizeof(int));

    // ---------------- CPU ----------------
    timer.onTimer(2);
    matMulCPU(A, B, Ccpu, m, n, k);
    timer.offTimer(2);

    // ---------------- GPU ----------------
    timer.onTimer(0);
    cudaMemcpy(dA, A, sizeA * sizeof(int), cudaMemcpyHostToDevice);
    cudaMemcpy(dB, B, sizeB * sizeof(int), cudaMemcpyHostToDevice);
    timer.offTimer(0);

    dim3 blockDim(BLOCK_SIZE, BLOCK_SIZE);
    dim3 gridDim((n + BLOCK_SIZE - 1) / BLOCK_SIZE,
                 (m + BLOCK_SIZE - 1) / BLOCK_SIZE);

    timer.onTimer(1);
    matMul<<<gridDim, blockDim>>>(dA, dB, dC, m, n, k);
    cudaGetLastError();
    cudaDeviceSynchronize();
    timer.offTimer(1);

    cudaMemcpy(Cgpu, dC, sizeC * sizeof(int), cudaMemcpyDeviceToHost);

    // ---------------- 출력 & 검증 ----------------
    printMatrix("A", A, m, k);
    printMatrix("B", B, k, n);
    printMatrix("C (CPU)", Ccpu, m, n);
    printMatrix("C (GPU)", Cgpu, m, n);

    bool ok = true;
    for (int i = 0; i < sizeC; i++) {
        if (Ccpu[i] != Cgpu[i]) {
            printf("\n[MISMATCH] index %d (row %d, col %d) : CPU %d vs GPU %d\n",
                   i, i / n, i % n, Ccpu[i], Cgpu[i]);
            ok = false;
            break;
        }
    }
    printf("\n결과: %s\n", ok ? "일치 (PASS)" : "불일치 (FAIL)");

    timer.printTimer();

    cudaFree(dA); cudaFree(dB); cudaFree(dC);
    free(A); free(B); free(Ccpu); free(Cgpu);

    return 0;
}