#include "cuda_runtime.h"
#include "device_launch_parameters.h"

#include "DS_timer.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

#define DO_CPU
#define DATA_TYPE int

#define SIZE_M (512*2)
#define SIZE_N (512*4)
#define SIZE_K (512*2)

#define INDEX2ROW(_index,_width)	(int)((_index)/(_width))
#define INDEX2COL(_index,_width)	((_index)%(_width))
#define ID2INDEX(_row,_col, _width) (((_row)*(_width))+(_col))

#define BLOCK_SIZE 16

// Macro function
//#define KERNEL_MUL(_a,_b) __fmul_rn(_a,_b)
#define KERNEL_MUL(_a,_b) (_a*_b)

#define CHECK_CUDA(call) do { \
	cudaError_t _e = (call); \
	if (_e != cudaSuccess) { \
		printf("CUDA error %s:%d : %s\n", __FILE__, __LINE__, cudaGetErrorString(_e)); \
		exit(1); \
	} \
} while(0)

// kernel declarations
__global__ void MatMul(DATA_TYPE* matA, DATA_TYPE* matB, DATA_TYPE* matC, int m, int n, int k);
__global__ void MatMul_Coalesced(DATA_TYPE* matA, DATA_TYPE* matB, DATA_TYPE* matC, int m, int n, int k);
__global__ void MatMul_Shared(DATA_TYPE* matA, DATA_TYPE* matB, DATA_TYPE* matC, int m, int n, int k);

template<class T> void allocNinitMem(T** p, long long size, double* memUsage = NULL);
bool compareMatrix(DATA_TYPE* _A, DATA_TYPE* _B, int _size);

int main(int argc, char* argv[])
{
	DS_timer timer(10);
	timer.setTimerName(0, (char*)"CPU algorithm");
	timer.setTimerName(1, (char*)"GPU/CUDA algorithm");
	timer.setTimerName(2, (char*)" - Kernel (basic)");
	timer.setTimerName(3, (char*)" - Kernel (coalesced)");
	timer.setTimerName(4, (char*)" - Kernel (shared)");
	timer.setTimerName(5, (char*)" - [Data transfer] host->device");
	timer.setTimerName(6, (char*)" - [Data transfer] device->host");

	// set matrix size
	int m, n, k;

	if (argc < 3) { m = SIZE_M;	n = SIZE_N;	k = SIZE_K; }
	else { m = atoi(argv[1]);	n = atoi(argv[2]);	k = atoi(argv[3]); }

	printf("Size : A = (%d by %d), B = (%d by %d), C = (%d by %d)\n", m, k, k, n, m, n);

	int sizeA = m * k;
	int sizeB = k * n;
	int sizeC = m * n;

	// Make matrix
	DATA_TYPE* A = NULL, * B = NULL;
	allocNinitMem<DATA_TYPE>(&A, sizeA);
	allocNinitMem<DATA_TYPE>(&B, sizeB);

	DATA_TYPE* Ccpu = NULL, * Cbasic = NULL, * Ccoal = NULL, * Cshared = NULL;
	allocNinitMem<DATA_TYPE>(&Ccpu, sizeC);
	allocNinitMem<DATA_TYPE>(&Cbasic, sizeC);
	allocNinitMem<DATA_TYPE>(&Ccoal, sizeC);
	allocNinitMem<DATA_TYPE>(&Cshared, sizeC);

	// generate input matrices
	for (int i = 0; i < sizeA; i++) A[i] = ((rand() % 10) + ((rand() % 100) / 100.0));
	for (int i = 0; i < sizeB; i++) B[i] = ((rand() % 10) + ((rand() % 100) / 100.0));

#ifdef DO_CPU // CPU version (OpenMP)
	timer.onTimer(0);
//#pragma omp parallel for num_threads(4)
	for (int row = 0; row < m; row++) {
		for (int col = 0; col < n; col++) {
			int cIndex = ID2INDEX(row, col, n);
			Ccpu[cIndex] = 0;
			for (int i = 0; i < k; i++)
				Ccpu[cIndex] += (A[ID2INDEX(row, i, k)] * B[ID2INDEX(i, col, n)]);
		}
	}
	printf("CPU finished!\n");
	timer.offTimer(0);
#endif

	// GPU setup
	DATA_TYPE* dA, * dB, * dCbasic, * dCcoal, * dCshared;

	CHECK_CUDA(cudaMalloc(&dA, sizeA * sizeof(DATA_TYPE)));
	CHECK_CUDA(cudaMemset(dA, 0, sizeA * sizeof(DATA_TYPE)));

	CHECK_CUDA(cudaMalloc(&dB, sizeB * sizeof(DATA_TYPE)));
	CHECK_CUDA(cudaMemset(dB, 0, sizeB * sizeof(DATA_TYPE)));

	CHECK_CUDA(cudaMalloc(&dCbasic, sizeC * sizeof(DATA_TYPE)));
	CHECK_CUDA(cudaMemset(dCbasic, 0, sizeC * sizeof(DATA_TYPE)));

	CHECK_CUDA(cudaMalloc(&dCcoal, sizeC * sizeof(DATA_TYPE)));
	CHECK_CUDA(cudaMemset(dCcoal, 0, sizeC * sizeof(DATA_TYPE)));

	CHECK_CUDA(cudaMalloc(&dCshared, sizeC * sizeof(DATA_TYPE)));
	CHECK_CUDA(cudaMemset(dCshared, 0, sizeC * sizeof(DATA_TYPE)));

	timer.onTimer(1);

	timer.onTimer(5);
	CHECK_CUDA(cudaMemcpy(dA, A, sizeA * sizeof(DATA_TYPE), cudaMemcpyHostToDevice));
	CHECK_CUDA(cudaMemcpy(dB, B, sizeB * sizeof(DATA_TYPE), cudaMemcpyHostToDevice));
	timer.offTimer(5);

	dim3 blockDim(BLOCK_SIZE, BLOCK_SIZE);

	// basic : x축 -> 행(row), y축 -> 열(col)
	dim3 gridDimBasic(ceil((float)m / BLOCK_SIZE), ceil((float)n / BLOCK_SIZE));

	// coalesced / shared : x축 -> 열(col), y축 -> 행(row)
	dim3 gridDimCoal(ceil((float)n / BLOCK_SIZE), ceil((float)m / BLOCK_SIZE));

	printf("Basic     Grid(%d, %d), Block(%d, %d)\n", gridDimBasic.x, gridDimBasic.y, blockDim.x, blockDim.y);
	printf("Coal/Shrd Grid(%d, %d), Block(%d, %d)\n", gridDimCoal.x, gridDimCoal.y, blockDim.x, blockDim.y);

	// [1] basic
	timer.onTimer(2);
	MatMul <<< gridDimBasic, blockDim >>> (dA, dB, dCbasic, m, n, k);
	CHECK_CUDA(cudaDeviceSynchronize());
	timer.offTimer(2);

	// [2] coalesced
	timer.onTimer(3);
	MatMul_Coalesced <<< gridDimCoal, blockDim >>> (dA, dB, dCcoal, m, n, k);
	CHECK_CUDA(cudaDeviceSynchronize());
	timer.offTimer(3);

	// [3] shared memory (tiled)
	timer.onTimer(4);
	MatMul_Shared <<< gridDimCoal, blockDim >>> (dA, dB, dCshared, m, n, k);
	CHECK_CUDA(cudaDeviceSynchronize());
	timer.offTimer(4);

	timer.onTimer(6);
	CHECK_CUDA(cudaMemcpy(Cbasic, dCbasic, sizeC * sizeof(DATA_TYPE), cudaMemcpyDeviceToHost));
	CHECK_CUDA(cudaMemcpy(Ccoal, dCcoal, sizeC * sizeof(DATA_TYPE), cudaMemcpyDeviceToHost));
	CHECK_CUDA(cudaMemcpy(Cshared, dCshared, sizeC * sizeof(DATA_TYPE), cudaMemcpyDeviceToHost));
	timer.offTimer(6);

	timer.offTimer(1);

	cudaFree(dA);
	cudaFree(dB);
	cudaFree(dCbasic);
	cudaFree(dCcoal);
	cudaFree(dCshared);

#ifdef DO_CPU
	printf("[Kernel basic]     "); compareMatrix(Ccpu, Cbasic, sizeC);
	printf("[Kernel coalesced] "); compareMatrix(Ccpu, Ccoal, sizeC);
	printf("[Kernel shared]    "); compareMatrix(Ccpu, Cshared, sizeC);
#endif

	timer.printTimer(1);

	delete[] A;
	delete[] B;
	delete[] Ccpu;
	delete[] Cbasic;
	delete[] Ccoal;
	delete[] Cshared;

	return 0;
}

bool compareMatrix(DATA_TYPE* _A, DATA_TYPE* _B, int _size)
{
	bool isMatched = true;
	int errCount = 0;
	for (int i = 0; i < _size; i++) {
		if (fabs((double)_A[i] - (double)_B[i]) > 1e-3) {
			if (errCount < 5)
				printf("\n  [%d] not matched! (%f, %f)", i, (double)_A[i], (double)_B[i]);
			errCount++;
			isMatched = false;
		}
	}
	if (isMatched)
		printf("Results are matched!\n");
	else
		printf("\n  Results are not matched!!! (%d errors)\n", errCount);

	return isMatched;
}

// [1] 기본 버전 : threadIdx.x가 '행'에 매핑됨 -> 병합 접근 실패
__global__ void MatMul(DATA_TYPE* matA, DATA_TYPE* matB, DATA_TYPE* matC, int m, int n, int k)
{
	int row = blockDim.x * blockIdx.x + threadIdx.x;
	int col = blockDim.y * blockIdx.y + threadIdx.y;

	if (row >= m || col >= n)
		return;

	DATA_TYPE val = 0; // hope to use register
	for (int i = 0; i < k; i++)
		val += KERNEL_MUL(matA[ID2INDEX(row, i, k)], matB[ID2INDEX(i, col, n)]);

	matC[ID2INDEX(row, col, n)] = val;
}

// [2] 병합 접근 버전 : threadIdx.x가 '열'에 매핑됨 -> 워프가 연속 주소 접근
__global__ void MatMul_Coalesced(DATA_TYPE* matA, DATA_TYPE* matB, DATA_TYPE* matC, int m, int n, int k)
{
	int col = blockDim.x * blockIdx.x + threadIdx.x;
	int row = blockDim.y * blockIdx.y + threadIdx.y;

	if (row >= m || col >= n)
		return;

	DATA_TYPE val = 0;
	for (int i = 0; i < k; i++)
		val += KERNEL_MUL(matA[ID2INDEX(row, i, k)], matB[ID2INDEX(i, col, n)]);

	matC[ID2INDEX(row, col, n)] = val;
}

// [3] 공유 메모리 타일링 버전
__global__ void MatMul_Shared(DATA_TYPE* matA, DATA_TYPE* matB, DATA_TYPE* matC, int m, int n, int k)
{
	int tx = threadIdx.x;
	int ty = threadIdx.y;

	int col = blockDim.x * blockIdx.x + tx;
	int row = blockDim.y * blockIdx.y + ty;

	__shared__ DATA_TYPE sA[BLOCK_SIZE][BLOCK_SIZE];
	__shared__ DATA_TYPE sB[BLOCK_SIZE][BLOCK_SIZE];

	DATA_TYPE val = 0;

	int numTiles = (k + BLOCK_SIZE - 1) / BLOCK_SIZE;

	for (int t = 0; t < numTiles; t++) {

		int aCol = t * BLOCK_SIZE + tx;
		int bRow = t * BLOCK_SIZE + ty;

		// 타일을 공유 메모리로 적재 (범위 밖은 0으로 패딩)
		sA[ty][tx] = (row < m && aCol < k) ? matA[ID2INDEX(row, aCol, k)] : 0;
		sB[ty][tx] = (bRow < k && col < n) ? matB[ID2INDEX(bRow, col, n)] : 0;

		// 블록 내 모든 스레드가 적재를 끝낼 때까지 대기
		__syncthreads();

		// 공유 메모리에서만 연산 (Global 접근 없음)
		for (int i = 0; i < BLOCK_SIZE; i++)
			val += KERNEL_MUL(sA[ty][i], sB[i][tx]);

		// 다음 타일이 덮어쓰기 전에 연산이 끝나기를 대기
		__syncthreads();
	}

	if (row < m && col < n)
		matC[ID2INDEX(row, col, n)] = val;
}

template<class T>
void allocNinitMem(T** p, long long size, double* memUsage) {
	*p = new T[size];
	memset(*p, 0, sizeof(T) * size);

	if (memUsage != NULL) {
		*memUsage += sizeof(T) * size;
	}
}