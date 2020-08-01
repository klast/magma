/*
    -- MAGMA (version 2.5.3) --
       Univ. of Tennessee, Knoxville
       Univ. of California, Berkeley
       Univ. of Colorado, Denver
       @date March 2020

       @generated from include/magma_zgehrd_m.h, normal z -> d, Sun Mar 29 20:48:36 2020
       @author Mark Gates
*/

#ifndef MAGMA_DGEHRD_H
#define MAGMA_DGEHRD_H

#include "magma_types.h"

#ifdef __cplusplus
extern "C" {
#endif

/***************************************************************************//**
    Structure containing matrices for multi-GPU dgehrd.

    - dA  is distributed column block-cyclic across GPUs.
    - dV  is duplicated on all GPUs.
    - dVd is distributed row block-cyclic across GPUs (TODO: verify).
    - dY  is partial results on each GPU in dlahr2,
          then complete results are duplicated on all GPUs for dlahru.
    - dW  is local to each GPU (workspace).
    - dTi is duplicated on all GPUs.

    @ingroup magma_gehrd
*******************************************************************************/
struct dgehrd_data
{
    magma_int_t ngpu;
    
    magma_int_t ldda;
    magma_int_t ldv;
    magma_int_t ldvd;
    
    magmaDouble_ptr dA [ MagmaMaxGPUs ];  // ldda*nlocal
    magmaDouble_ptr dV [ MagmaMaxGPUs ];  // ldv *nb, whole panel
    magmaDouble_ptr dVd[ MagmaMaxGPUs ];  // ldvd*nb, block-cyclic
    magmaDouble_ptr dY [ MagmaMaxGPUs ];  // ldda*nb
    magmaDouble_ptr dW [ MagmaMaxGPUs ];  // ldda*nb
    magmaDouble_ptr dTi[ MagmaMaxGPUs ];  // nb*nb
    
    magma_queue_t queues[ MagmaMaxGPUs ];
};

#ifdef __cplusplus
}
#endif

#endif        //  #ifndef MAGMA_DGEHRD_H
