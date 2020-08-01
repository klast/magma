/*
    -- MAGMA (version 2.5.3) --
       Univ. of Tennessee, Knoxville
       Univ. of California, Berkeley
       Univ. of Colorado, Denver
       @date March 2020

       @author Azzam Haidar
       @author Tingxing Dong

       @generated from magmablas/zgeqr2_batched.cu, normal z -> c, Sun Mar 29 20:48:31 2020
*/

#include "magma_internal.h"
#include "magma_templates.h"
#include "batched_kernel_param.h"

#define BLOCK_SIZE 256


#define dA(a_1,a_2) (dA  + (a_1) + (a_2)*(local_lda))


#include "clarfg_devicesfunc.cuh"

/******************************************************************************/
static __device__
void clarfx_device(
    int m, int n,  magmaFloatComplex *v, magmaFloatComplex *tau,
    magmaFloatComplex *dc, magma_int_t ldc, magmaFloatComplex* sum)
{
    if (n <= 0) return;
    if (MAGMA_C_EQUAL(*tau, MAGMA_C_ZERO) )  return; // check singularity

    const int tx = threadIdx.x;

    magmaFloatComplex lsum;
    
    for (int k=0; k < n; k++)
    {
        /* perform  w := v' * C  */
        if (tx < BLOCK_SIZE)
        {
            if (tx == 0)
                lsum = dc[0+ldc*k]; //since V[0] should be one
            else
                lsum = MAGMA_C_ZERO;
            for (int j = tx+1; j < m; j += BLOCK_SIZE) {
                lsum += MAGMA_C_MUL( MAGMA_C_CONJ( v[j] ), dc[j+ldc*k] );
            }

            sum[tx] = lsum;
        }

        magma_sum_reduce< BLOCK_SIZE >( tx, sum );
        __syncthreads();

        magmaFloatComplex z__1 = - MAGMA_C_CONJ(*tau) * sum[0];
        /*  C := C - v * w  */
        if (tx < BLOCK_SIZE)
        {
            for (int j = tx+1; j < m; j += BLOCK_SIZE)
                dc[j+ldc*k] += z__1 * v[j];
        }
        if (tx == 0) dc[0+ldc*k] += z__1;

        __syncthreads();
    }
}


/******************************************************************************/
static __device__
void cgeqr2_device( magma_int_t m, magma_int_t n,
                               magmaFloatComplex* dA, magma_int_t lda,
                               magmaFloatComplex *dtau,
                               magmaFloatComplex *dv,
                               magmaFloatComplex *sum,
                               float *swork,
                               magmaFloatComplex *scale,
                               float *sscale)
{
    //lapack clarfg, compute the norm, scale and generate the householder vector
    clarfg_device(m, dv, &(dv[1]), 1, dtau, swork, sscale, scale);
    
    __syncthreads();
    
    //update the trailing matix with the householder
    clarfx_device(m, n, dv, dtau, dA, lda, sum);
    
    __syncthreads();
}


/******************************************************************************/
extern __shared__ magmaFloatComplex shared_data[];


/******************************************************************************/
__global__
void cgeqr2_sm_kernel_batched( int m, int n, magmaFloatComplex** dA_array, magma_int_t lda,
                               magmaFloatComplex **dtau_array)
{
    magmaFloatComplex* dA = dA_array[blockIdx.z];
    magmaFloatComplex* dtau = dtau_array[blockIdx.z];

    magmaFloatComplex *sdata = (magmaFloatComplex*)shared_data;

    const int tx = threadIdx.x;

    __shared__ magmaFloatComplex scale;
    __shared__ magmaFloatComplex sum[ BLOCK_SIZE ];

    __shared__ float swork[ BLOCK_SIZE ];
    __shared__ float sscale;
    
    //load data from global to shared memory
    for (int s=0; s < n; s++)
    {
        for (int j = tx; j < m; j += BLOCK_SIZE)
        {
            sdata[j + s * m] = dA[j + s * lda];
        }
    }


    __syncthreads();
 
    for (int s=0; s < min(m,n); s++)
    {
        cgeqr2_device( m-s, n-(s+1),
                       &(sdata[s+(s+1)*m]), m,
                       dtau+s,
                       &(sdata[s+s*m]),
                       sum,
                       swork,
                       &scale,
                       &sscale);
    } // end of s

    //copy back to global memory
    for (int s=0; s < n; s++)
    {
        for (int j = tx; j < m; j += BLOCK_SIZE)
        {
            dA[j + s * lda] = sdata[j + s * m];
        }
    }
}


/******************************************************************************/
__global__
void cgeqr2_column_sm_kernel_batched( int m, int n, magmaFloatComplex** dA_array, magma_int_t lda,
                               magmaFloatComplex **dtau_array)
{
    magmaFloatComplex* dA = dA_array[blockIdx.z];
    magmaFloatComplex* dtau = dtau_array[blockIdx.z];

    magmaFloatComplex *sdata = (magmaFloatComplex*)shared_data;


    __shared__ magmaFloatComplex scale;
    __shared__ magmaFloatComplex sum[ BLOCK_SIZE ];

    __shared__ float swork[ BLOCK_SIZE ];
    __shared__ float sscale;

    const int tx = threadIdx.x;

    for (int s=0; s < min(m,n); s++)
    {
        //load one vector in shared memory: sdata
        for (int j = tx; j < m-s; j += BLOCK_SIZE)
        {
            sdata[j] = dA[s + j + s * lda];
        }
        
        __syncthreads();
        
        //sdata is written
        cgeqr2_device(m-s, n-(s+1),
                                &(dA[s+(s+1)*lda]), lda,
                                dtau+s,
                                sdata,
                                sum,
                                swork,
                                &scale,
                                &sscale);
        
        for (int j = tx; j < m-s; j += BLOCK_SIZE)
        {
            dA[s + j + s * lda] = sdata[j];
        }
        
        __syncthreads();
    }  
}


/******************************************************************************/
__global__
void cgeqr2_kernel_batched( int m, int n, magmaFloatComplex** dA_array, magma_int_t lda,
                               magmaFloatComplex **dtau_array)
{
    magmaFloatComplex* dA = dA_array[blockIdx.z];
    magmaFloatComplex* dtau = dtau_array[blockIdx.z];

    __shared__ magmaFloatComplex scale;
    __shared__ magmaFloatComplex sum[ BLOCK_SIZE ];

    __shared__ float swork[ BLOCK_SIZE ];
    __shared__ float sscale;



    for (int s=0; s < min(m,n); s++)
    {
        cgeqr2_device( m-s, n-(s+1),
                       &(dA[s+(s+1)*lda]), lda,
                       dtau+s,
                       &(dA[s+s*lda]),
                       sum,
                       swork,
                       &scale,
                       &sscale );
    }
}


/***************************************************************************//**
    Purpose
    -------
    CGEQR2 computes a QR factorization of a complex m by n matrix A:
    A = Q * R.

    This version implements the right-looking QR with non-blocking.

    Arguments
    ---------
    @param[in]
    m       INTEGER
            The number of rows of the matrix A.  M >= 0.

    @param[in]
    n       INTEGER
            The number of columns of the matrix A.  N >= 0.

    @param[in,out]
    dA_array Array of pointers, dimension (batchCount).
             Each is a COMPLEX array on the GPU, dimension (LDDA,N)
             On entry, the M-by-N matrix A.
             On exit, the elements on and above the diagonal of the array
             contain the min(M,N)-by-N upper trapezoidal matrix R (R is
             upper triangular if m >= n); the elements below the diagonal,
             with the array TAU, represent the orthogonal matrix Q as a
             product of min(m,n) elementary reflectors (see Further
             Details).

    @param[in]
    ldda     INTEGER
             The leading dimension of the array dA.  LDDA >= max(1,M).
             To benefit from coalescent memory accesses LDDA must be
             divisible by 16.

    @param[out]
    dtau_array Array of pointers, dimension (batchCount).
             Each is a COMPLEX array, dimension (min(M,N))
             The scalar factors of the elementary reflectors (see Further
             Details).

    @param[out]
    info_array  Array of INTEGERs, dimension (batchCount), for corresponding matrices.
      -     = 0:  successful exit
      -     < 0:  if INFO = -i, the i-th argument had an illegal value
                  or another error occured, such as memory allocation failed.

    @param[in]
    batchCount  INTEGER
                The number of matrices to operate on.

    @param[in]
    queue   magma_queue_t
            Queue to execute in.

    Further Details
    ---------------
    The matrix Q is represented as a product of elementary reflectors

       Q = H(1) H(2) . . . H(k), where k = min(m,n).

    Each H(i) has the form

       H(i) = I - tau * v * v'

    where tau is a complex scalar, and v is a complex vector with
    v(1:i-1) = 0 and v(i) = 1; v(i+1:m) is stored on exit in A(i+1:m,i),
    and tau in TAU(i).

    @ingroup magma_geqr2_batched
*******************************************************************************/
extern "C" magma_int_t
magma_cgeqr2_batched(magma_int_t m, magma_int_t n, 
                     magmaFloatComplex **dA_array, magma_int_t ldda, 
                     magmaFloatComplex **dtau_array,
                     magma_int_t *info_array, magma_int_t batchCount, magma_queue_t queue)
{
    magma_int_t k;

    /* Check arguments */
    magma_int_t arginfo = 0;
    if (m < 0)
        arginfo = -1;
    else if (n < 0)
        arginfo = -2;
    else if (ldda < max(1,m))
        arginfo = -4;

    if (arginfo != 0) {
        magma_xerbla( __func__, -(arginfo) );
        return arginfo;
    }

    k = min(m,n);

    dim3 blocks(1, 1, batchCount);
    dim3 threads(BLOCK_SIZE);

    if (sizeof(magmaFloatComplex)*(m*k) <= 42000 /*sizeof(magmaFloatComplex) * 128 * k*/) // there are some static shared memory besides of dynamic ones
    {
        //load panel in shared memory and factorize it and copy back to gloabl memory
        //intend for small panel to avoid overfill of shared memory.
        //this kernel is composed of device routine and thus clean
        cgeqr2_sm_kernel_batched<<< blocks, threads, sizeof(magmaFloatComplex)*(m*k), queue->cuda_stream() >>>
                                      (m, k, dA_array, ldda, dtau_array);
    }
    else
    {
        //load one column vector in shared memory and householder it and used it to update trailing matrix which is global memory
        // one vector is normally smaller than  48K shared memory
        if (sizeof(magmaFloatComplex)*(m) < 42000)
            cgeqr2_column_sm_kernel_batched<<< blocks, threads, sizeof(magmaFloatComplex)*(m), queue->cuda_stream() >>>
                                      (m, k, dA_array, ldda, dtau_array);
        else
            //not use dynamic shared memory at all
            cgeqr2_kernel_batched<<< blocks, threads, 0, queue->cuda_stream() >>>
                                      (m, k, dA_array, ldda, dtau_array);
    }

    return arginfo;
}
