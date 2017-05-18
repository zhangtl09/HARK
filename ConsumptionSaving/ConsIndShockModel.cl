#pragma OPENCL EXTENSION cl_khr_fp64 : enable
#pragma OPENCL EXTENSION cl_amd_fp64 : enable

/* Random number generator */
inline uint RNG(uint s) {
    uint seed = (s * 0x5DEECE66DL + 0xBL) & ((1L << 48) - 1);
    return (seed >> 16);
}



/* Kernel for killing off agents and replacing them in ConsIndShockModel */
__kernel void getMortality(
     __global int *IntegerInputs
    ,__global int *TypeNow
    ,__global int *tCycleNow
    ,__global int *tAgeNow
    ,__global int *TypeAddress
    ,__global double *NormDraws
    ,__global double *LivPrb
    ,__global double *aNrmInitMean
    ,__global double *aNrmInitStd
    ,__global double *pLvlInitMean
    ,__global double *pLvlInitStd
    ,__global double *aNrmNow
    ,__global double *pLvlNow
) {

    /* Initialize this thread's id */
    int Gid = get_global_id(0);             /* global thread id */
    if (Gid >= IntegerInputs[0]){
        return;
    }

    /* Unpack the integer inputs */
    int AgentCount = IntegerInputs[0];
    int tSim = IntegerInputs[4];

    /* Get basic information about this agent */
    int Type = TypeNow[Gid];
    int LocA = TypeAddress[Type];
    int temp = LocA + tCycleNow[Gid];
    
    /* Randomly draw whether this agent should be replaced */
    uint Seed = (uint)(tSim*AgentCount + Gid) + 15;
    uint LivRand = RNG(Seed);
    double LivShk = ((double)LivRand)/pown(2.0,16);
    if (LivShk > LivPrb[temp]) {
	uint pRand = RNG(Seed+1);
	uint aRand = RNG(Seed+2);
        pRand = pRand - 65536*(pRand/65536);
        aRand = aRand - 65536*(aRand/65536);
        pLvlNow[Gid] = exp(NormDraws[pRand]*pLvlInitStd[temp] + pLvlInitMean[temp]);
        aNrmNow[Gid] = exp(NormDraws[aRand]*aNrmInitStd[temp] + aNrmInitMean[temp]);
        tCycleNow[Gid] = 0;
        tAgeNow[Gid] = 0;
    }
}




/* Kernel for obtaining shock variables in ConsIndShockModel */
__kernel void getShocks(
     __global int *IntegerInputs
    ,__global int *TypeNow
    ,__global int *tCycleNow
    ,__global int *TypeAddress
    ,__global double *NormDraws
    ,__global double *PermStd
    ,__global double *TranStd
    ,__global double *UnempPrb
    ,__global double *IncUnemp
    ,__global double *PermShkNow
    ,__global double *TranShkNow
) {

    /* Initialize this thread's id */
    int Gid = get_global_id(0);             /* global thread id */
    if (Gid >= IntegerInputs[0]){
        return;
    }

    /* Unpack the integer inputs */
    int AgentCount = IntegerInputs[0];
    int tSim = IntegerInputs[4];

    /* Get basic information about this agent */
    int Type = TypeNow[Gid];
    int LocA = TypeAddress[Type];
    int temp = LocA + tCycleNow[Gid];
    
    /* Generate three random integers to be used */
    uint Seed = (uint)((tSim*AgentCount + Gid)*3);
    uint PermRand = RNG(Seed);
    uint TranRand = RNG(Seed+1);
    PermRand = PermRand - 65536*(PermRand/65536);
    TranRand = TranRand - 65536*(TranRand/65536);
    uint UnempRand = RNG(Seed+2);

    /* Transform random integers into shocks for this agent */
    double psiStd = PermStd[temp];
    double thetaStd = TranStd[temp];
    double PermShk = exp(NormDraws[PermRand]*psiStd - 0.5*powr(psiStd,2.0));
    double TranShk = exp(NormDraws[TranRand]*thetaStd - 0.5*powr(thetaStd,2.0));
    double UnempShk = ((double)UnempRand)/pown(2.0,16);
    if (UnempShk < UnempPrb[temp]) {
        TranShk = IncUnemp[temp];
    }

    /* Store the shocks in global memory */
    PermShkNow[Gid] = PermShk;
    TranShkNow[Gid] = TranShk;
}





/* Kernel for calculating state variables at decision time in ConsIndShockModel */
__kernel void getStates(
     __global int *IntegerInputs
    ,__global int *TypeNow
    ,__global int *tCycleNow
    ,__global int *TypeAddress
    ,__global double *PermGroFac
    ,__global double *Rfree
    ,__global double *aNrmNow
    ,__global double *PermShkNow
    ,__global double *TranShkNow
    ,__global double *mNrmNow
    ,__global double *pLvlNow
) {

    /* Initialize this thread's id */
    int Gid = get_global_id(0);             /* global thread id */
    if (Gid >= IntegerInputs[0]){
        return;
    }

    /* Get consumer's type, permanent income growth factor, interest factor, and post-state */
    int Type = TypeNow[Gid];
    int Loc = TypeAddress[Type] + tCycleNow[Gid];
    double R = Rfree[Type];
    double Gamma = PermGroFac[Loc];
    double pLvl = pLvlNow[Gid];
    double aNrm = aNrmNow[Gid];

    /* Calculate consumer's market resources and new permanent income level */
    double psi = PermShkNow[Gid];
    pLvlNow[Gid] = pLvl*psi*Gamma;
    mNrmNow[Gid] = aNrm*R/(psi*Gamma) + TranShkNow[Gid];
}





/* Kernel for calculating the control variable in ConsIndShockModel */
__kernel void getControls(
     __global int *IntegerInputs
    ,__global int *TypeNow
    ,__global int *tCycleNow
    ,__global int *TypeAddress
    ,__global int *CoeffsAddress
    ,__global double *mGrid
    ,__global double *mLowerBound
    ,__global double *Coeffs0
    ,__global double *Coeffs1
    ,__global double *Coeffs2
    ,__global double *Coeffs3
    ,__global double *mNrmNow
    ,__global double *cNrmNow
    ,__global double *MPCnow
) {

    /* Initialize this thread's id */
    int Gid = get_global_id(0);             /* global thread id */
    if (Gid >= IntegerInputs[0]){
        return;
    }

    /* Initialize some variables to be used shortly */
    int j;
    int Botj;
    int Topj;
    int Diffj;
    int Newj;
    double Botm;
    double Topm;
    double Newm;
    double b0;
    double b1;
    double b2;
    double b3;
    double Span;
    double mX;
    double cNrm;
    double MPC;

    /* Unpack the integer inputs */
    int TypeAgeSize = IntegerInputs[2];
    int CoeffsSize = IntegerInputs[3];

    /* Get basic information about this agent */
    int Type = TypeNow[Gid];
    int LocA = TypeAddress[Type];
    double mNrm = mNrmNow[Gid];
    int temp = LocA + tCycleNow[Gid];
    int LocB = CoeffsAddress[temp];
    int GridSize;
    if ((temp+1) == TypeAgeSize) {
        GridSize = CoeffsSize - LocB;
    }
    else {
        GridSize = CoeffsAddress[temp+1] - LocB;
    }
    double mBound = mLowerBound[LocB];

    /* Find correct grid sector for this agent */
    Botj = 0;
    Topj = GridSize - 1;
    Botm = mGrid[LocB + Botj];
    Topm = mGrid[LocB + Topj];
    Diffj = Topj - Botj;
    Newj = Botj + Diffj/2;
    Newm = mGrid[LocB + Newj];
    if (mNrm < Botm) { /* If m is outside the grid bounds, this is easy (shouldn't happen) */
        j = 0;
        Topm = Botm;
        Botm = Topm - 1.0;
    }
    else if (mNrm > Topm) {
        j = GridSize-1;
        Botm = Topm;
    }
    else { /* Otherwise, perform a binary/golden search for the right segment */
        while (Diffj > 1) {
            if (mNrm < Newm) {
                Topj = Newj;
                Topm = Newm;
            }
            else {
                Botj = Newj;
                Botm = Newm;
            }
            Diffj = Topj - Botj;
            Newj = Botj + Diffj/2;
            Newm = mGrid[LocB + Newj];
        }
        j = Botj;
    }
    
    /* Get the interpolation coefficients for this segment */
    temp = LocB + j;
    b0 = Coeffs0[temp];
    b1 = Coeffs1[temp];
    b2 = Coeffs2[temp];
    b3 = Coeffs3[temp];
    if (Topm > Botm) {
        Span = (Topm - Botm);
    } else {
        Span = 1.0;
    }
    mX = (mNrm - Botm)/Span;

    /* Evaluate consumption on main portion of cFunc */
    if (j < (GridSize-1)) {
        cNrm = b0 + mX*(b1 + mX*(b2 + mX*(b3)));
        MPC = (b1 + mX*(2*b2 + mX*(3*b3)))/Span;
    }
    else { /* Evaluate consumption on extrapolated cFunc */
        cNrm = b0 + mNrm*b1 - b2*exp(mX*b3);
        MPC = b1 - b3*b2*exp(mX*b3);
    }

    /* Make sure consumption does not violate the borrowing constraint */
    double cNrmCons = mNrm - mBound;
    if (cNrmCons < cNrm) {
        cNrm = cNrmCons;
        MPC = 1.0;
    }

    /* Store this agent's consumption and MPC in global buffers */
    cNrmNow[Gid] = cNrm;
    MPCnow[Gid] = MPC;
}





/* Kernel for calculating the post-decision state variables in ConsIndShockModel */
__kernel void getPostStates(
     __global int *IntegerInputs
    ,__global int *TypeNow
    ,__global int *tCycleNow
    ,__global int *tAgeNow
    ,__global int *Ttotal
    ,__global double *mNrmNow
    ,__global double *cNrmNow
    ,__global double *pLvlNow
    ,__global double *aNrmNow
    ,__global double *aLvlNow
) {

    /* Initialize this thread's id */
    int Gid = get_global_id(0);             /* global thread id */
    if (Gid >= IntegerInputs[0]){
        return;
    }

    /* Calculate end of period assets, normalized and in level */
    double aNrm = mNrmNow[Gid] - cNrmNow[Gid];
    aNrmNow[Gid] = aNrm;
    aLvlNow[Gid] = aNrm*pLvlNow[Gid];

    /* Advance time for this agent */
    int Type = TypeNow[Gid];
    tAgeNow[Gid] = tAgeNow[Gid] + 1;
    int temp = tCycleNow[Gid] + 1;
    if (temp == Ttotal[Type]) {
        temp = 0;
    }
    tCycleNow[Gid] = temp;
}



