#include "DS_timer.h"

#define ITERATION_COUNT 10000

int REJ_FLAG = 0;
extern "C"
{
#include <stdio.h>
#include <stdint.h>
#include "fips202.h"
#include "packing.h"
#include "params.h"
#include "poly.h"
#include "polyvec.h"
#include "randombytes.h"
#include "sign.h"
#include "symmetric.h"
}

int PQCLEAN_MLDSA44_CLEAN_crypto_sign_keypair(uint8_t *pk, uint8_t *sk)
{
    uint8_t seedbuf[2 * SEEDBYTES + CRHBYTES];
    uint8_t tr[TRBYTES];
    const uint8_t *rho, *rhoprime, *key;
    polyvecl mat[K];
    polyvecl s1, s1hat;
    polyveck s2, t1, t0;

    DS_timer timer(10);
    timer.initTimers();

    /* Get randomness for rho, rhoprime and key */
    randombytes(seedbuf, SEEDBYTES);
    seedbuf[SEEDBYTES + 0] = K;
    seedbuf[SEEDBYTES + 1] = L;
    shake256(seedbuf, 2 * SEEDBYTES + CRHBYTES, seedbuf, SEEDBYTES + 2);
    rho = seedbuf;
    rhoprime = rho + SEEDBYTES;
    key = rhoprime + CRHBYTES;

    //===========================
    //=======Expand A
    timer.onTimer(0);
    for (int i = 0; i < ITERATION_COUNT; i++)
    {
        PQCLEAN_MLDSA44_CLEAN_polyvec_matrix_expand(mat, rho);
    }
    timer.offTimer(0);
    timer.setTimerName(0, "Expand A");

    //===========================
    //=======Expand S
    timer.onTimer(1);
    for (int i = 0; i < ITERATION_COUNT; i++)
    {
        PQCLEAN_MLDSA44_CLEAN_polyvecl_uniform_eta(&s1, rhoprime, 0);
        PQCLEAN_MLDSA44_CLEAN_polyveck_uniform_eta(&s2, rhoprime, L);
    }
    timer.offTimer(1);
    timer.setTimerName(1, "Expand S");

    /* Matrix-vector multiplication */
    s1hat = s1;

    timer.onTimer(2);
    for (int i = 0; i < ITERATION_COUNT; i++)
    {
        PQCLEAN_MLDSA44_CLEAN_polyvecl_ntt(&s1hat);
    }
    timer.offTimer(2);
    timer.setTimerName(2, "NTT S");

    timer.onTimer(3);
    for (int i = 0; i < ITERATION_COUNT; i++)
    {
        PQCLEAN_MLDSA44_CLEAN_polyvec_matrix_pointwise_montgomery(&t1, mat, &s1hat);
    }
    timer.offTimer(3);
    for (int i = 0; i < ITERATION_COUNT; i++)
    {
        PQCLEAN_MLDSA44_CLEAN_polyveck_reduce(&t1);
    }
    timer.setTimerName(3, "A * s1");

    timer.onTimer(4);
    for (int i = 0; i < ITERATION_COUNT; i++)
    {
        PQCLEAN_MLDSA44_CLEAN_polyveck_invntt_tomont(&t1);
    }
    timer.offTimer(4);
    timer.setTimerName(4, "INTT t1");

    /* Add error vector s2 */
    PQCLEAN_MLDSA44_CLEAN_polyveck_add(&t1, &t1, &s2);

    /* Extract t1 and write public key */
    PQCLEAN_MLDSA44_CLEAN_polyveck_caddq(&t1);

    timer.onTimer(5);
    for (int i = 0; i < ITERATION_COUNT; i++)
    {
        PQCLEAN_MLDSA44_CLEAN_polyveck_decompose(&t1, &t0, &t1);
    }
    timer.offTimer(5);
    timer.setTimerName(5, "Power2Round");

    PQCLEAN_MLDSA44_CLEAN_pack_pk(pk, rho, &t1);

    /* Compute H(rho, t1) and write secret key */
    shake256(tr, TRBYTES, pk, PQCLEAN_MLDSA44_CLEAN_CRYPTO_PUBLICKEYBYTES);
    PQCLEAN_MLDSA44_CLEAN_pack_sk(sk, rho, tr, key, &t0, &s1, &s2);

    timer.printTimer();

    return 0;
}

int PQCLEAN_MLDSA44_CLEAN_crypto_sign_signature_ctx(uint8_t *sig,
                                                    size_t *siglen,
                                                    const uint8_t *m,
                                                    size_t mlen,
                                                    const uint8_t *ctx,
                                                    size_t ctxlen,
                                                    const uint8_t *sk)
{
    unsigned int n;
    uint8_t seedbuf[2 * SEEDBYTES + TRBYTES + RNDBYTES + 2 * CRHBYTES];
    uint8_t *rho, *tr, *key, *mu, *rhoprime, *rnd;
    uint16_t nonce = 0;
    polyvecl mat[K], s1, y, z;
    polyveck t0, s2, w1, w0, h;
    poly cp;
    shake256incctx state;

    if (ctxlen > 255)
    {
        return -1;
    }

    DS_timer timer(20);
    timer.initTimers();

    rho = seedbuf;
    tr = rho + SEEDBYTES;
    key = tr + TRBYTES;
    rnd = key + SEEDBYTES;
    mu = rnd + RNDBYTES;
    rhoprime = mu + CRHBYTES;
    PQCLEAN_MLDSA44_CLEAN_unpack_sk(rho, tr, key, &t0, &s1, &s2, sk);

    /* Compute mu = CRH(tr, 0, ctxlen, ctx, msg) */
    mu[0] = 0;
    mu[1] = (uint8_t)ctxlen;

    timer.onTimer(1);
    shake256_inc_init(&state);
    shake256_inc_absorb(&state, tr, TRBYTES);
    shake256_inc_absorb(&state, mu, 2);
    shake256_inc_absorb(&state, ctx, ctxlen);
    shake256_inc_absorb(&state, m, mlen);
    shake256_inc_finalize(&state);
    shake256_inc_squeeze(mu, CRHBYTES, &state);
    shake256_inc_ctx_release(&state);

    randombytes(rnd, RNDBYTES);
    shake256(rhoprime, CRHBYTES, key, SEEDBYTES + RNDBYTES + CRHBYTES);
    timer.offTimer(1);
    timer.setTimerName(1, "Compute tr, mu (include Hash MSG)");

    /* Expand matrix and transform vectors */
    timer.onTimer(0);
    for (int i = 0; i < ITERATION_COUNT; i++)
    {
        PQCLEAN_MLDSA44_CLEAN_polyvec_matrix_expand(mat, rho);
    }
    timer.offTimer(0);
    timer.setTimerName(0, "Expand A");

    timer.onTimer(10);
    for (int i = 0; i < ITERATION_COUNT; i++)
    {
        PQCLEAN_MLDSA44_CLEAN_polyvecl_ntt(&s1);
        PQCLEAN_MLDSA44_CLEAN_polyveck_ntt(&s2);
        PQCLEAN_MLDSA44_CLEAN_polyveck_ntt(&t0);
    }
    timer.offTimer(10);
    timer.setTimerName(10, "NTT s1, s2, t0");
    int count_signtimes = 0;
rej:
    count_signtimes++;
    /* Sample intermediate vector y */
    timer.onTimer(1);
    for (int i = 0; i < ITERATION_COUNT; i++)
    {
        PQCLEAN_MLDSA44_CLEAN_polyvecl_uniform_gamma1(&y, rhoprime, nonce++);
    }
    timer.offTimer(1);
    timer.setTimerName(1, "ExpandMask");



    /* Matrix-vector multiplication */
    z = y;
    timer.onTimer(11);
    for (int i = 0; i < ITERATION_COUNT; i++)
    {
        PQCLEAN_MLDSA44_CLEAN_polyvecl_ntt(&z);
    }
    timer.offTimer(11);
    timer.setTimerName(11, "NTT y");



    timer.onTimer(2);
    for (int i = 0; i < ITERATION_COUNT; i++)
    {
        PQCLEAN_MLDSA44_CLEAN_polyvec_matrix_pointwise_montgomery(&w1, mat, &z);
        PQCLEAN_MLDSA44_CLEAN_polyveck_reduce(&w1);
    }
    timer.offTimer(2);
    timer.setTimerName(2, "A * y");



    timer.onTimer(12);
    for (int i = 0; i < ITERATION_COUNT; i++)
    {
        PQCLEAN_MLDSA44_CLEAN_polyveck_invntt_tomont(&w1);
    }
    timer.offTimer(12);
    timer.setTimerName(12, "INVNTT A * y");



    /* Decompose w and call the random oracle */
    PQCLEAN_MLDSA44_CLEAN_polyveck_caddq(&w1);
    timer.onTimer(4);
    for (int i = 0; i < ITERATION_COUNT; i++)
    {
        PQCLEAN_MLDSA44_CLEAN_polyveck_decompose(&w1, &w0, &w1);
    }
    timer.offTimer(4);
    timer.setTimerName(4, "Highbits w1");



    PQCLEAN_MLDSA44_CLEAN_polyveck_pack_w1(sig, &w1);



    timer.onTimer(5);
    for (int i = 0; i < ITERATION_COUNT; i++)
    {
        shake256_inc_init(&state);
        shake256_inc_absorb(&state, mu, CRHBYTES);
        shake256_inc_absorb(&state, sig, K * POLYW1_PACKEDBYTES);
        shake256_inc_finalize(&state);
        shake256_inc_squeeze(sig, CTILDEBYTES, &state);
        shake256_inc_ctx_release(&state);
    }
    timer.offTimer(5);
    timer.setTimerName(5, "c tilde");


    timer.onTimer(6);
    for (int i = 0; i < ITERATION_COUNT; i++)
    {
        PQCLEAN_MLDSA44_CLEAN_poly_challenge(&cp, sig);
    }
    timer.offTimer(6);
    timer.setTimerName(6, "c");

    timer.onTimer(13);
    for (int i = 0; i < ITERATION_COUNT; i++)
    {
        PQCLEAN_MLDSA44_CLEAN_poly_ntt(&cp);
    }
    timer.offTimer(13);
    timer.setTimerName(13, "NTT c ");

    /* Compute z, reject if it reveals secret */


    //cs1
    timer.onTimer(7);
    for (int i = 0; i < ITERATION_COUNT; i++){
        PQCLEAN_MLDSA44_CLEAN_polyvecl_pointwise_poly_montgomery(&z, &cp, &s1);
    }
    timer.offTimer(7);
    timer.setTimerName(7, "c * s1, c*s2");


    timer.onTimer(14);
    for(int i = 0; i < ITERATION_COUNT; i++){
        PQCLEAN_MLDSA44_CLEAN_polyvecl_invntt_tomont(&z);
    }
    timer.offTimer(14);
    timer.setTimerName(14, "INTT c * s1, c*s2");

    PQCLEAN_MLDSA44_CLEAN_polyvecl_add(&z, &z, &y);
    PQCLEAN_MLDSA44_CLEAN_polyvecl_reduce(&z);


    if (PQCLEAN_MLDSA44_CLEAN_polyvecl_chknorm(&z, GAMMA1 - BETA))
    {
        REJ_FLAG = 1;
    }

    /* Check that subtracting cs2 does not change high bits of w and low bits
     * do not reveal secret information */


    //cs2
    timer.onTimer(7);
    for (int i = 0; i < ITERATION_COUNT; i++)
    {
        PQCLEAN_MLDSA44_CLEAN_polyveck_pointwise_poly_montgomery(&h, &cp, &s2);
    }
    timer.offTimer(7);


    timer.onTimer(14);
    for(int i = 0; i < ITERATION_COUNT; i++){
        PQCLEAN_MLDSA44_CLEAN_polyveck_invntt_tomont(&h);
    }
    timer.offTimer(14);



    PQCLEAN_MLDSA44_CLEAN_polyveck_sub(&w0, &w0, &h);
    PQCLEAN_MLDSA44_CLEAN_polyveck_reduce(&w0);
    if (PQCLEAN_MLDSA44_CLEAN_polyveck_chknorm(&w0, GAMMA2 - BETA))
    {
        REJ_FLAG = 1;
    }


    /* Compute hints for w1 */
    //ct0
    timer.onTimer(8);
    for (int i = 0; i < ITERATION_COUNT; i++)
    {
        PQCLEAN_MLDSA44_CLEAN_polyveck_pointwise_poly_montgomery(&h, &cp, &t0);
    }
    timer.offTimer(8);
    timer.setTimerName(8, "ct0");

    timer.onTimer(15);
    for(int i = 0; i < ITERATION_COUNT; i++){
        PQCLEAN_MLDSA44_CLEAN_polyveck_invntt_tomont(&h);
    }
    timer.offTimer(15);
    timer.setTimerName(15, "INTT ct0");


    PQCLEAN_MLDSA44_CLEAN_polyveck_reduce(&h);
    if (PQCLEAN_MLDSA44_CLEAN_polyveck_chknorm(&h, GAMMA2))
    {
        REJ_FLAG = 1;
    }

    PQCLEAN_MLDSA44_CLEAN_polyveck_add(&w0, &w0, &h);

    timer.onTimer(9);
    for (int i = 0; i < ITERATION_COUNT; i++)
    {
        n = PQCLEAN_MLDSA44_CLEAN_polyveck_make_hint(&h, &w0, &w1);
    }
    timer.offTimer(9);
    timer.setTimerName(9, "Make Hint");

    if (n > OMEGA)
    {
        REJ_FLAG = 1;
    }

    /* Write signature */
    PQCLEAN_MLDSA44_CLEAN_pack_sig(sig, sig, &z, &h);
    *siglen = PQCLEAN_MLDSA44_CLEAN_CRYPTO_BYTES;
    printf("===========================\n=========================\n");
    timer.printTimer();

    return 0;
}   

/*************************************************
 * Name:        crypto_sign
 *
 * Description: Compute signed message.
 *
 * Arguments:   - uint8_t *sm: pointer to output signed message (allocated
 *                             array with PQCLEAN_MLDSA44_CLEAN_CRYPTO_BYTES + mlen bytes),
 *                             can be equal to m
 *              - size_t *smlen: pointer to output length of signed
 *                               message
 *              - const uint8_t *m: pointer to message to be signed
 *              - size_t mlen: length of message
 *              - const uint8_t *ctx: pointer to context string
 *              - size_t ctxlen: length of context string
 *              - const uint8_t *sk: pointer to bit-packed secret key
 *
 * Returns 0 (success) or -1 (context string too long)
 **************************************************/
int PQCLEAN_MLDSA44_CLEAN_crypto_sign_ctx(uint8_t *sm,
                                          size_t *smlen,
                                          const uint8_t *m,
                                          size_t mlen,
                                          const uint8_t *ctx,
                                          size_t ctxlen,
                                          const uint8_t *sk)
{
    int ret;
    size_t i;

    for (i = 0; i < mlen; ++i)
    {
        sm[PQCLEAN_MLDSA44_CLEAN_CRYPTO_BYTES + mlen - 1 - i] = m[mlen - 1 - i];
    }
    ret = PQCLEAN_MLDSA44_CLEAN_crypto_sign_signature_ctx(sm, smlen, sm + PQCLEAN_MLDSA44_CLEAN_CRYPTO_BYTES, mlen, ctx, ctxlen, sk);
    *smlen += mlen;
    return ret;
}



int PQCLEAN_MLDSA44_CLEAN_crypto_sign_verify_ctx(const uint8_t *sig,
        size_t siglen,
        const uint8_t *m,
        size_t mlen,
        const uint8_t *ctx,
        size_t ctxlen,
        const uint8_t *pk) {
    unsigned int i;
    uint8_t buf[K * POLYW1_PACKEDBYTES];
    uint8_t rho[SEEDBYTES];
    uint8_t mu[CRHBYTES];
    uint8_t c[CTILDEBYTES];
    uint8_t c2[CTILDEBYTES];
    poly cp;
    polyvecl mat[K], z;
    polyveck t1, w1, h;
    shake256incctx state;

    DS_timer timer(20);
    timer.initTimers();

    if (ctxlen > 255 || siglen != PQCLEAN_MLDSA44_CLEAN_CRYPTO_BYTES) {
        // return -1;
    }

    PQCLEAN_MLDSA44_CLEAN_unpack_pk(rho, &t1, pk);
    if (PQCLEAN_MLDSA44_CLEAN_unpack_sig(c, &z, &h, sig)) {
        // return -1;
    }
    if (PQCLEAN_MLDSA44_CLEAN_polyvecl_chknorm(&z, GAMMA1 - BETA)) {
        // return -1;
    }

    /* Compute CRH(H(rho, t1), msg) */


    timer.onTimer(0);
    for (int i = 0; i < ITERATION_COUNT; i++)
    {
        shake256(mu, TRBYTES, pk, PQCLEAN_MLDSA44_CLEAN_CRYPTO_PUBLICKEYBYTES);
        shake256_inc_init(&state);
        shake256_inc_absorb(&state, mu, TRBYTES);
        mu[0] = 0;
        mu[1] = (uint8_t)ctxlen;
        shake256_inc_absorb(&state, mu, 2);
        shake256_inc_absorb(&state, ctx, ctxlen);
        shake256_inc_absorb(&state, m, mlen);
        shake256_inc_finalize(&state);
        shake256_inc_squeeze(mu, CRHBYTES, &state);
        shake256_inc_ctx_release(&state);
    }    
    timer.offTimer(0);
    timer.setTimerName(0,"tr, mu");







    /* Matrix-vector multiplication; compute Az - c2^dt1 */
    PQCLEAN_MLDSA44_CLEAN_poly_challenge(&cp, c);


    timer.onTimer(1);
    for (int i = 0; i < ITERATION_COUNT; i++)
    {
        PQCLEAN_MLDSA44_CLEAN_polyvec_matrix_expand(mat, rho);
    }
    timer.offTimer(1);
    timer.setTimerName(1, "Expand A");


    timer.onTimer(10);
    for (int i = 0; i < ITERATION_COUNT; i++){
        PQCLEAN_MLDSA44_CLEAN_polyvecl_ntt(&z);
    }
    timer.offTimer(10);
    timer.setTimerName(10, "NTT z");




    timer.onTimer(2);
    for (int i = 0; i < ITERATION_COUNT; i++)
    {
        PQCLEAN_MLDSA44_CLEAN_polyvec_matrix_pointwise_montgomery(&w1, mat, &z);
    }
    timer.offTimer(2);
    timer.setTimerName(2, "A * z");


    timer.onTimer(11);
    for (int i = 0; i < ITERATION_COUNT; i++){
        PQCLEAN_MLDSA44_CLEAN_poly_ntt(&cp);
    }
    timer.offTimer(11);
    timer.setTimerName(11, "NTT c");



    PQCLEAN_MLDSA44_CLEAN_polyveck_shiftl(&t1);

    timer.onTimer(12);
    for (int i = 0; i < ITERATION_COUNT; i++){
        PQCLEAN_MLDSA44_CLEAN_polyveck_ntt(&t1);
    }
    timer.offTimer(12);
    timer.setTimerName(12, "NTT t1");


    timer.onTimer(3);
    for (int i = 0; i < ITERATION_COUNT; i++)
    {
        PQCLEAN_MLDSA44_CLEAN_polyveck_pointwise_poly_montgomery(&t1, &cp, &t1);
    }
    timer.offTimer(3);
    timer.setTimerName(3, "c * t1");





    PQCLEAN_MLDSA44_CLEAN_polyveck_sub(&w1, &w1, &t1);
    PQCLEAN_MLDSA44_CLEAN_polyveck_reduce(&w1);


    timer.onTimer(13);
    for (int i = 0; i < ITERATION_COUNT; i++){
        PQCLEAN_MLDSA44_CLEAN_polyveck_invntt_tomont(&w1);
    }
    timer.offTimer(13);
    timer.setTimerName(13, "INTT w1");

    /* Reconstruct w1 */
    PQCLEAN_MLDSA44_CLEAN_polyveck_caddq(&w1);


    timer.onTimer(4);
    for (int i = 0; i < ITERATION_COUNT; i++){
        PQCLEAN_MLDSA44_CLEAN_polyveck_use_hint(&w1, &w1, &h);
    }
    timer.offTimer(4);
    timer.setTimerName(4, "Use Hint");



    PQCLEAN_MLDSA44_CLEAN_polyveck_pack_w1(buf, &w1);



    /* Call random oracle and verify challenge */

    timer.onTimer(5);
    shake256_inc_init(&state);
    shake256_inc_absorb(&state, mu, CRHBYTES);
    shake256_inc_absorb(&state, buf, K * POLYW1_PACKEDBYTES);
    shake256_inc_finalize(&state);
    shake256_inc_squeeze(c2, CTILDEBYTES, &state);
    shake256_inc_ctx_release(&state);
    timer.offTimer(5);
    timer.setTimerName(5, "c tilde");

    printf("===========================\n=========================\n");
    printf("Verify");
    timer.printTimer();

    for (i = 0; i < CTILDEBYTES; ++i) {
        if (c[i] != c2[i]) {
            return -1;
        }
    }

    return 0;
}

/*************************************************
* Name:        crypto_sign_open
*
* Description: Verify signed message.
*
* Arguments:   - uint8_t *m: pointer to output message (allocated
*                            array with smlen bytes), can be equal to sm
*              - size_t *mlen: pointer to output length of message
*              - const uint8_t *sm: pointer to signed message
*              - size_t smlen: length of signed message
*              - const uint8_t *ctx: pointer to context tring
*              - size_t ctxlen: length of context string
*              - const uint8_t *pk: pointer to bit-packed public key
*
* Returns 0 if signed message could be verified correctly and -1 otherwise
**************************************************/
int PQCLEAN_MLDSA44_CLEAN_crypto_sign_open_ctx(uint8_t *m,
        size_t *mlen,
        const uint8_t *sm,
        size_t smlen,
        const uint8_t *ctx,
        size_t ctxlen,
        const uint8_t *pk) {
    size_t i;

    if (smlen < PQCLEAN_MLDSA44_CLEAN_CRYPTO_BYTES) {
        goto badsig;
    }

    *mlen = smlen - PQCLEAN_MLDSA44_CLEAN_CRYPTO_BYTES;
    if (PQCLEAN_MLDSA44_CLEAN_crypto_sign_verify_ctx(sm, PQCLEAN_MLDSA44_CLEAN_CRYPTO_BYTES, sm + PQCLEAN_MLDSA44_CLEAN_CRYPTO_BYTES, *mlen, ctx, ctxlen, pk)) {
        goto badsig;
    } else {
        /* All good, copy msg, return 0 */
        for (i = 0; i < *mlen; ++i) {
            m[i] = sm[PQCLEAN_MLDSA44_CLEAN_CRYPTO_BYTES + i];
        }
        return 0;
    }

badsig:
    /* Signature verification failed */
    *mlen = 0;
    for (i = 0; i < smlen; ++i) {
        m[i] = 0;
    }

    return -1;
}



// 기존 operation_time.cpp 파일의 맨 아래에 있던 main 함수를 아래 코드로 교체하세요.

int main() {
    uint8_t pk[PQCLEAN_MLDSA44_CLEAN_CRYPTO_PUBLICKEYBYTES];
    uint8_t sk[PQCLEAN_MLDSA44_CLEAN_CRYPTO_SECRETKEYBYTES];

    // 1. 원본 메시지($m$) 및 컨텍스트($ctx$) 설정
    const char* msg_str = "ML-DSA-44 Signature Verification Test Message";
    size_t mlen = strlen(msg_str);
    uint8_t m[100];
    memcpy(m, msg_str, mlen);

    uint8_t ctx_str[] = "test_context_string";
    size_t ctxlen = strlen((char*)ctx_str);

    // 서명, 서명된 메시지($sm$), 검증 후 복원된 메시지를 담을 버퍼
    uint8_t sig[PQCLEAN_MLDSA44_CLEAN_CRYPTO_BYTES];
    size_t siglen;
    
    uint8_t sm[PQCLEAN_MLDSA44_CLEAN_CRYPTO_BYTES + 100];
    size_t smlen;

    uint8_t m_out[100];
    size_t mlen_out;

    printf("\n=== ML-DSA-44 Sign & Verify Test ===\n");

    // 2. 키쌍 생성
    int ret_keypair = PQCLEAN_MLDSA44_CLEAN_crypto_sign_keypair(pk, sk);

    // 3. 서명 생성 ($sig$ 배열에 서명 값만 추출)
    PQCLEAN_MLDSA44_CLEAN_crypto_sign_signature_ctx(sig, &siglen, m, mlen, ctx_str, ctxlen, sk);

    // 4. 서명된 메시지 배열($sm$) 구성: $sm = sig \parallel m$
    // 개방형 검증 함수(open)는 서명과 메시지가 결합된 $sm$ 배열을 입력으로 받습니다.
    memcpy(sm, sig, siglen);
    memcpy(sm + siglen, m, mlen);
    smlen = siglen + mlen;

    // 5. 서명 검증 및 메시지 복원 (요청하신 함수 호출)
    int ret_verify = PQCLEAN_MLDSA44_CLEAN_crypto_sign_open_ctx(m_out, &mlen_out, sm, smlen, ctx_str, ctxlen, pk);

    // 6. 검증 결과 확인


    return 0;
}