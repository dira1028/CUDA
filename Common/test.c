#include <stdio.h>
#include <time.h>

#define iter 10000

#define uint64_t unsigned long long
#define ROTL(S, a) (((S) << (a)) | ((S) >> (64 - (a))))
int rho_offset[25] = {0, 1, 62, 28, 27, 36, 44, 6, 55, 20, 3, 10, 43, 25, 39, 41, 45, 15, 21, 8, 18, 2, 61, 56, 14};

void split_ver(uint64_t *state){
    // 1. Rho 단계: 각 요소를 offset 만큼 회전
    for(int i=0;i<iter;i++){
        for(int i = 1; i < 25; i++){
                state[i] = ROTL(state[i], rho_offset[i]);
            }

            // 2. Pi 단계: 정해진 주기(24 주기)에 맞추어 인덱스 치환
            uint64_t temp = state[1];
            state[1]  = state[6];
            state[6]  = state[9];
            state[9]  = state[22];
            state[22] = state[14];
            state[14] = state[20];
            state[20] = state[2];
            state[2]  = state[12];
            state[12] = state[13];
            state[13] = state[19];
            state[19] = state[23];
            state[23] = state[15];
            state[15] = state[4];
            state[4]  = state[24];
            state[24] = state[21];
            state[21] = state[8];
            state[8]  = state[16];
            state[16] = state[5];
            state[5]  = state[3];
            state[3]  = state[18];
            state[18] = state[17];
            state[17] = state[11];
            state[11] = state[7];
            state[7]  = state[10];
            state[10] = temp;
    }
}

void merge_ver(uint64_t *state){
    uint64_t temp = state[1];
    state[1]  = ROTL(state[6], rho_offset[6]); 
    //..
    state[10] = ROTL(temp, rho_offset[1]);
}

void init_state(uint64_t *state) {
    for (int i = 0; i < 25; i++) {
        state[i] = (uint64_t)(i * 13 * 37);
    }
}

int main(){
    uint64_t splitS[25];
    uint64_t mergeS[25];

    init_state(splitS);
    init_state(mergeS);

    clock_t start, end;
    double time_split, time_merge;
    



    start = clock();  
    for(int i = 0; i < iter; i++){
        split_ver(splitS);
    }
    end = clock();    
    

    time_split = (double)(end - start) / CLOCKS_PER_SEC;
    printf("split_ver 실행 시간 (%d회 반복): %f 초\n", iter, time_split);


    start = clock();
    for(int i = 0; i < iter; i++){
        merge_ver(mergeS);
    }
    end = clock();
    

    time_merge = (double)(end - start) / CLOCKS_PER_SEC;
    printf("merge_ver 실행 시간 (%d회 반복): %f 초\n", iter, time_merge);

    return 0;
}