#include "cuda_runtime.h"
#include "device_launch_parameters.h"
#include "DS_timer.h"
#include <cstdio>
#include <cstdlib>
#include <ctime>
#include <cmath>
#include <cuda_runtime.h>

#define THREADS_PER_BLOCK 256

// ----------------------------------------------------------------------------
//  naive atomic : 각 스레드가 곱한 값을 곧바로 global 에 atomic add
// ----------------------------------------------------------------------------
__global__ void dotNaiveAtomic(int n, const float *A, const float *B, float *result)
{
    int tid = threadIdx.x + blockIdx.x * blockDim.x;   // §2.3.5.1
    if (tid < n) {
        float product = A[tid] * B[tid];
        atomicAdd(result, product);                    // 모든 스레드가 한 곳에 몰림
    }
}

// ----------------------------------------------------------------------------
//  shared + atomic : 블록 안에서 부분합 -> 블록당 1회만 global atomic
// ----------------------------------------------------------------------------
__global__ void dotSharedAtomic(int n, const float *A, const float *B, float *result)
{
    __shared__ float staging[THREADS_PER_BLOCK];       // 블록 하나의 곱 결과를 담을 shared

    int tid  = threadIdx.x + blockIdx.x * blockDim.x;  // 전역 인덱스
    int lane = threadIdx.x;                            // 블록 안 인덱스

    // 1) 각 스레드가 자기 곱을 shared 에 저장 (범위 밖이면 0)
    staging[lane] = (tid < n) ? (A[tid] * B[tid]) : 0.0f;

    __syncthreads();                                   // 모든 로드 완료 보장

    // 2) 블록당 스레드 0번이 shared 를 순회하며 블록 부분합 계산
    if (lane == 0) {
        float blockSum = 0.0f;
        for (int i = 0; i < blockDim.x; i++) {
            blockSum += staging[i];
        }
        // 3) 블록당 딱 한 번만 global 에 atomic add -> atomic 경쟁이 블록 수로 축소
        atomicAdd(result, blockSum);
    }
}

// ----------------------------------------------------------------------------
//  입력 초기화 (A, B 가 서로 다르도록 srand 는 main 에서 1회만 호출)
// ----------------------------------------------------------------------------
void initArray(float *arr, int length)
{
    for (int i = 0; i < length; i++) {
        arr[i] = rand() / (float)RAND_MAX;   // 0~1 사이 난수
    }
}

// ----------------------------------------------------------------------------
int main(int argc, char **argv)
{
    // 입력 초기화용 시드 (initArray 호출 전에 와야 함)
    std::srand((unsigned)std::time(nullptr));

    int vectorLength = 1 << 20; // 2^20 = 1,048,576
    if (argc >= 2) {
        vectorLength = std::atoi(argv[1]);
    }
    int blocks = (vectorLength + THREADS_PER_BLOCK - 1) / THREADS_PER_BLOCK;

    // 디바이스 메모리 포인터
    float *nA, *nB, *sA, *sB, *c_resultNaive, *c_resultShared;

    float *A = (float*)malloc(vectorLength * sizeof(float));
    float *B = (float*)malloc(vectorLength * sizeof(float));

    float *resultNaive  = (float*)malloc(sizeof(float));
    float *resultShared = (float*)malloc(sizeof(float));

    initArray(A, vectorLength);
    initArray(B, vectorLength);

    cudaMalloc(&nA, vectorLength * sizeof(float));
    cudaMalloc(&nB, vectorLength * sizeof(float));

    cudaMalloc(&sA, vectorLength * sizeof(float));
    cudaMalloc(&sB, vectorLength * sizeof(float));

    cudaMalloc(&c_resultNaive,  sizeof(float));
    cudaMalloc(&c_resultShared, sizeof(float));

    // CPU 기준값 (검증용)
    double expected = 0.0;
    for (int i = 0; i < vectorLength; i++) expected += (double)A[i] * (double)B[i];

    DS_timer timer(6);
    timer.initTimers();
    timer.setTimerName(0, (char *)"Native CPU --> GPU");
    timer.setTimerName(1, (char *)"Native Kernel");
    timer.setTimerName(2, (char *)"Native GPU --> CPU");
    timer.setTimerName(3, (char *)"Shared CPU --> GPU");
    timer.setTimerName(4, (char *)"Shared Kernel");
    timer.setTimerName(5, (char *)"Shared GPU --> CPU");

    // naive atomic
    timer.onTimer(0);
    cudaMemcpy(nA, A, vectorLength * sizeof(float), cudaMemcpyHostToDevice);
    cudaMemcpy(nB, B, vectorLength * sizeof(float), cudaMemcpyHostToDevice);
    timer.offTimer(0);

    cudaMemset(c_resultNaive, 0, sizeof(float));

    timer.onTimer(1);
    dotNaiveAtomic<<<blocks, THREADS_PER_BLOCK>>>(vectorLength, nA, nB, c_resultNaive);
    cudaDeviceSynchronize();
    timer.offTimer(1);

    timer.onTimer(2);
    cudaMemcpy(resultNaive, c_resultNaive, sizeof(float), cudaMemcpyDeviceToHost);
    timer.offTimer(2);


    cudaMemset(c_resultShared, 0, sizeof(float));

    timer.onTimer(3);
    cudaMemcpy(sA, A, vectorLength * sizeof(float), cudaMemcpyHostToDevice);
    cudaMemcpy(sB, B, vectorLength * sizeof(float), cudaMemcpyHostToDevice);
    timer.offTimer(3);

    timer.onTimer(4);
    // shared + atomic
    dotSharedAtomic<<<blocks, THREADS_PER_BLOCK>>>(vectorLength, sA, sB, c_resultShared);
    cudaDeviceSynchronize();
    timer.offTimer(4);

    timer.onTimer(5);
    cudaMemcpy(resultShared, c_resultShared, sizeof(float), cudaMemcpyDeviceToHost);
    timer.offTimer(5);


    timer.printTimer();

    // 결과 출력
    printf("vectorLength = %d\n", vectorLength);
    printf("expected (CPU)      : %.4f\n", expected);
    printf("[1] naive atomic    : %.4f\n", *resultNaive);
    printf("[2] shared + atomic : %.4f\n", *resultShared);

    // 정확성 확인
    float tol = 1e-2f * (float)fabs(expected);
    printf("naive  %s / shared %s\n",
           (fabs(*resultNaive  - expected) < tol) ? "OK" : "MISMATCH",
           (fabs(*resultShared - expected) < tol) ? "OK" : "MISMATCH");

    cudaFree(nA);
    cudaFree(nB);
    cudaFree(sA);
    cudaFree(sB);
    cudaFree(c_resultNaive);
    cudaFree(c_resultShared);

    free(A);
    free(B);
    free(resultNaive);
    free(resultShared);

    return 0;
}