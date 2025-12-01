#/******************************************************************************
# * GPUPrefixSums
# * Chained Scan with Decoupled Lookback Implementation
# *
# * SPDX-License-Identifier: MIT
# * Copyright Thomas Smith 3/5/2024
# * https://github.com/b0nes164/GPUPrefixSums
# *
# * Based off of Research by:
# *          Duane Merrill, Nvidia Corporation
# *          Michael Garland, Nvidia Corporation
# *          https://research.nvidia.com/publication/2016-03_single-pass-parallel-prefix-scan-decoupled-look-back
# * 
# ******************************************************************************/
Code
[[
    #define MAX_DISPATCH_DIM    65535U
    #define UINT4_PART_SIZE     768U
    #define BLOCK_DIM           256U
    #define UINT4_PER_THREAD    3U
    #define MIN_WAVE_SIZE       4U
]]

ConstantBuffer( PdxConstantBuffer0 )
{
    uint e_vectorizedSize;
    uint e_threadBlocks;
    uint e_isPartial;
    uint e_fullDispatches;
};

RWStructuredBufferTexture b_scan
{
	Ref = PdxRWBufferTexture0
    Type = uint4
}

Code 
[[
    groupshared uint4 g_shared[UINT4_PART_SIZE];
    groupshared uint g_reduction[BLOCK_DIM / MIN_WAVE_SIZE];

    inline uint getWaveIndex(uint _gtid)
    {
        return _gtid / WaveGetLaneCount();
    }

    inline bool isPartialDispatch()
    {
        return e_isPartial;
    }

    inline uint flattenGid(uint3 gid)
    {
        return isPartialDispatch() ?
            gid.x + e_fullDispatches * MAX_DISPATCH_DIM :
            gid.x + gid.y * MAX_DISPATCH_DIM;
    }

    inline uint PartStart(uint _partIndex)
    {
        return _partIndex * UINT4_PART_SIZE;
    }

    inline uint WavePartSize()
    {
        return UINT4_PER_THREAD * WaveGetLaneCount();
    }

    inline uint WavePartStart(uint _gtid)
    {
        return getWaveIndex(_gtid) * WavePartSize();
    }

    inline uint4 SetXAddYZW(uint t, uint4 val)
    {
        return uint4(t, val.yzw + t);
    }

    //read in and scan
    inline void ScanExclusiveFull(uint gtid, uint partIndex)
    {
        const uint laneMask = WaveGetLaneCount() - 1;
        const uint circularShift = WaveGetLaneIndex() + laneMask & laneMask;
        uint waveReduction = 0;
        
        [unroll]
        for (uint i = WaveGetLaneIndex() + WavePartStart(gtid), k = 0;
            k < UINT4_PER_THREAD;
            i += WaveGetLaneCount(), ++k)
        {
            uint4 t = b_scan[i + PartStart(partIndex)];

            uint t2 = t.x;
            t.x += t.y;
            t.y = t2;

            t2 = t.x;
            t.x += t.z;
            t.z = t2;

            t2 = t.x;
            t.x += t.w;
            t.w = t2;
            
            const uint t3 = WaveReadLaneAt(t.x + WavePrefixSum(t.x), circularShift);
            g_shared[i] = SetXAddYZW((WaveGetLaneIndex() ? t3 : 0) + waveReduction, t);
            waveReduction += WaveReadLaneAt(t3, 0);
        }
        
        if (!WaveGetLaneIndex())
            g_reduction[getWaveIndex(gtid)] = waveReduction;
    }

    inline void ScanExclusivePartial(uint gtid, uint partIndex)
    {
        const uint laneMask = WaveGetLaneCount() - 1;
        const uint circularShift = WaveGetLaneIndex() + laneMask & laneMask;
        const uint finalPartSize = e_vectorizedSize - PartStart(partIndex);
        uint waveReduction = 0;
        
        [unroll]
        for (uint i = WaveGetLaneIndex() + WavePartStart(gtid), k = 0;
            k < UINT4_PER_THREAD;
            i += WaveGetLaneCount(), ++k)
        {
            uint4 t = i < finalPartSize ? b_scan[i + PartStart(partIndex)] : 0;

            uint t2 = t.x;
            t.x += t.y;
            t.y = t2;

            t2 = t.x;
            t.x += t.z;
            t.z = t2;

            t2 = t.x;
            t.x += t.w;
            t.w = t2;
            
            const uint t3 = WaveReadLaneAt(t.x + WavePrefixSum(t.x), circularShift);
            g_shared[i] = SetXAddYZW((WaveGetLaneIndex() ? t3 : 0) + waveReduction, t);
            waveReduction += WaveReadLaneAt(t3, 0);
        }
        
        if (!WaveGetLaneIndex())
            g_reduction[getWaveIndex(gtid)] = waveReduction;
    }

    inline void ScanInclusiveFull(uint gtid, uint partIndex)
    {
        const uint laneMask = WaveGetLaneCount() - 1;
        const uint circularShift = WaveGetLaneIndex() + laneMask & laneMask;
        uint waveReduction = 0;
        
        [unroll]
        for (uint i = WaveGetLaneIndex() + WavePartStart(gtid), k = 0;
            k < UINT4_PER_THREAD;
            i += WaveGetLaneCount(), ++k)
        {
            uint4 t = b_scan[i + PartStart(partIndex)];
            t.y += t.x;
            t.z += t.y;
            t.w += t.z;
            
            const uint t2 = WaveReadLaneAt(t.w + WavePrefixSum(t.w), circularShift);
            g_shared[i] = t + (WaveGetLaneIndex() ? t2 : 0) + waveReduction;
            waveReduction += WaveReadLaneAt(t2, 0);
        }
        
        if (!WaveGetLaneIndex())
            g_reduction[getWaveIndex(gtid)] = waveReduction;
    }

    inline void ScanInclusivePartial(uint gtid, uint partIndex)
    {
        const uint laneMask = WaveGetLaneCount() - 1;
        const uint circularShift = WaveGetLaneIndex() + laneMask & laneMask;
        const uint finalPartSize = e_vectorizedSize - PartStart(partIndex);
        uint waveReduction = 0;
        
        [unroll]
        for (uint i = WaveGetLaneIndex() + WavePartStart(gtid), k = 0;
            k < UINT4_PER_THREAD;
            i += WaveGetLaneCount(), ++k)
        {
            uint4 t = i < finalPartSize ? b_scan[i + PartStart(partIndex)] : 0;
            t.y += t.x;
            t.z += t.y;
            t.w += t.z;
            
            const uint t2 = WaveReadLaneAt(t.w + WavePrefixSum(t.w), circularShift);
            g_shared[i] = t + (WaveGetLaneIndex() ? t2 : 0) + waveReduction;
            waveReduction += WaveReadLaneAt(t2, 0);
        }
        
        if (!WaveGetLaneIndex())
            g_reduction[getWaveIndex(gtid)] = waveReduction;
    }

    //Reduce the wave reductions
    inline void LocalScanInclusiveWGE16(uint gtid, uint partIndex)
    {
        if (gtid < BLOCK_DIM / WaveGetLaneCount())
            g_reduction[gtid] += WavePrefixSum(g_reduction[gtid]);
    }

    inline void LocalScanInclusiveWLT16(uint gtid, uint partIndex)
    {
        const uint scanSize = BLOCK_DIM / WaveGetLaneCount();
        if (gtid < scanSize)
            g_reduction[gtid] += WavePrefixSum(g_reduction[gtid]);
        GroupMemoryBarrierWithGroupSync();
            
        const uint laneLog = countbits(WaveGetLaneCount() - 1);
        uint offset = laneLog;
        uint j = WaveGetLaneCount();
        for (; j < (scanSize >> 1); j <<= laneLog)
        {
            if (gtid < (scanSize >> offset))
            {
                g_reduction[((gtid + 1) << offset) - 1] +=
                    WavePrefixSum(g_reduction[((gtid + 1) << offset) - 1]);
            }
            GroupMemoryBarrierWithGroupSync();
                
            if ((gtid & ((j << laneLog) - 1)) >= j && (gtid + 1) & (j - 1))
            {
                g_reduction[gtid] +=
                    WaveReadLaneAt(g_reduction[((gtid >> offset) << offset) - 1], 0);
            }
            offset += laneLog;
        }
        GroupMemoryBarrierWithGroupSync();
            
        //If scanSize is not a power of lanecount
        const uint index = gtid + j;
        if (index < scanSize)
        {
            g_reduction[index] +=
                WaveReadLaneAt(g_reduction[((index >> offset) << offset) - 1], 0);
        }
    }

    //Pass in previous reductions, and write out
    inline void DownSweepFull(uint gtid, uint partIndex, uint prevReduction)
    {
        [unroll]
        for (uint i = WaveGetLaneIndex() + WavePartStart(gtid), k = 0;
            k < UINT4_PER_THREAD;
            i += WaveGetLaneCount(), ++k)
        {
            b_scan[i + PartStart(partIndex)] = g_shared[i] + prevReduction;
        }
    }

    inline void DownSweepPartial(uint gtid, uint partIndex, uint prevReduction)
    {
        const uint finalPartSize = e_vectorizedSize - PartStart(partIndex);
        for (uint i = WaveGetLaneIndex() + WavePartStart(gtid), k = 0;
            k < UINT4_PER_THREAD && i < finalPartSize;
            i += WaveGetLaneCount(), ++k)
        {
            b_scan[i + PartStart(partIndex)] = g_shared[i] + prevReduction;
        }
    }
]]

# Start of Chained Scan with Decoupled Lookback Implementation
Code
[[
    #define FLAG_NOT_READY  0           //Flag indicating this partition tile's local reduction is not ready
    #define FLAG_REDUCTION  1           //Flag indicating this partition tile's local reduction is ready
    #define FLAG_INCLUSIVE  2           //Flag indicating this partition tile has summed all preceding tiles and added to its sum.
    #define FLAG_MASK       3           //Mask used to retrieve the flag
]]

RWStructuredBufferTexture b_index
{
	Ref = PdxRWBufferTexture1
    Type = uint
	globallycoherent = yes
}

RWStructuredBufferTexture b_threadBlockReduction
{
	Ref = PdxRWBufferTexture2
    Type = uint
	globallycoherent = yes
}

Code
[[
    groupshared uint g_broadcast;

    inline void AcquirePartitionIndex(uint gtid)
    {
        if(!gtid)
            InterlockedAdd(b_index[0], 1, g_broadcast);
    }

    //use the exact thread that performed the scan on the last element
    //to elide an extra barrier
    inline void DeviceBroadcast(uint gtid, uint partIndex)
    {
        if (gtid == BLOCK_DIM / WaveGetLaneCount() - 1)
        {
            InterlockedAdd(b_threadBlockReduction[partIndex],
                (partIndex ? FLAG_REDUCTION : FLAG_INCLUSIVE) | g_reduction[gtid] << 2);
        }
    }

    inline void Lookback(uint partIndex)
    {
        uint prevReduction = 0;
        uint k = partIndex + WaveGetLaneCount() - WaveGetLaneIndex();
        const uint waveParts = (WaveGetLaneCount() + 31) / 32;
        
        while (true)
        {
            const uint flagPayload = k > WaveGetLaneCount() ? 
                b_threadBlockReduction[k - WaveGetLaneCount() - 1] : FLAG_INCLUSIVE;

            if (WaveActiveAllTrue((flagPayload & FLAG_MASK) > FLAG_NOT_READY))
            {
                const uint4 inclusiveBallot = WaveActiveBallot((flagPayload & FLAG_MASK) == FLAG_INCLUSIVE);
                
                //dot(inclusiveBallot, uint4(1,1,1,1)) != 0 does not work
                //consider 0xffffffff + 1 + 0xffffffff + 1
                if (inclusiveBallot.x || inclusiveBallot.y || inclusiveBallot.z || inclusiveBallot.w)
                {
                    uint inclusiveIndex = 0;
                    for (uint wavePart = 0; wavePart < waveParts; ++wavePart)
                    {
                        if (countbits(inclusiveBallot[wavePart]))
                        {
                            inclusiveIndex += firstbitlow(inclusiveBallot[wavePart]);
                            break;
                        }
                        else
                        {
                            inclusiveIndex += 32;
                        }
                    }
                                        
                    prevReduction += WaveActiveSum(WaveGetLaneIndex() <= inclusiveIndex ? (flagPayload >> 2) : 0);
                                    
                    if (WaveGetLaneIndex() == 0)
                    {
                        g_broadcast = prevReduction;
                        InterlockedAdd(b_threadBlockReduction[partIndex], 1 | (prevReduction << 2));
                    }
                    break;
                }
                else
                {
                    prevReduction += WaveActiveSum(flagPayload >> 2);
                    k -= WaveGetLaneCount();
                }
            }
        }
    }
]]


ComputeShader =
{
	MainCode CS_InitChainedScan
	{
		VertexStruct CS_INPUT
		{
			uint3 id : PDX_DispatchThreadID
		};

		Input = "CS_INPUT"
		NumThreads = { 256 1 1 }
		Code
		[[
			PDX_MAIN
			{
                const uint increment = 256 * 256;
    
                for (uint i = Input.id.x; i < e_threadBlocks; i += increment)
                    b_threadBlockReduction[i] = 0;
                
                if (!Input.id.x)
                    b_index[Input.id.x] = 0;
            }
        ]]
    }
}

ComputeShader =
{
	MainCode CS_ChainedScanDecoupledLookbackExclusive
	{
		VertexStruct CS_INPUT
		{
			uint3 gtid : PDX_GroupThreadID
		};

		Input = "CS_INPUT"
		# NumThreads = { BLOCK_DIM 1 1 }
		NumThreads = { 256 1 1 }
		Code
		[[
			PDX_MAIN
			{
                AcquirePartitionIndex(Input.gtid.x);
                GroupMemoryBarrierWithGroupSync();
                const uint partitionIndex = g_broadcast;

                if (partitionIndex < e_threadBlocks - 1)
                    ScanExclusiveFull(Input.gtid.x, partitionIndex);
                
                if(partitionIndex == e_threadBlocks - 1)
                    ScanExclusivePartial(Input.gtid.x, partitionIndex);
                GroupMemoryBarrierWithGroupSync();
                
                if (WaveGetLaneCount() >= 16)
                    LocalScanInclusiveWGE16(Input.gtid.x, partitionIndex);
                
                if (WaveGetLaneCount() < 16)
                    LocalScanInclusiveWLT16(Input.gtid.x, partitionIndex);
                
                DeviceBroadcast(Input.gtid.x, partitionIndex);
                
                if (partitionIndex && Input.gtid.x < WaveGetLaneCount())
                    Lookback(partitionIndex);
                GroupMemoryBarrierWithGroupSync();
                
                const uint prevReduction = g_broadcast + 
                    (Input.gtid.x >= WaveGetLaneCount() ? g_reduction[getWaveIndex(Input.gtid.x) - 1] : 0);
                
                if (partitionIndex < e_threadBlocks - 1)
                    DownSweepFull(Input.gtid.x, partitionIndex, prevReduction);
                
                if (partitionIndex == e_threadBlocks - 1)
                    DownSweepPartial(Input.gtid.x, partitionIndex, prevReduction);
            }
        ]]
    }
}

ComputeShader =
{
	MainCode CS_ChainedScanDecoupledLookbackInclusive
	{
		VertexStruct CS_INPUT
		{
			uint3 gtid : PDX_GroupThreadID
		};

		Input = "CS_INPUT"
		# NumThreads = { BLOCK_DIM 1 1 }
		NumThreads = { 256 1 1 }
		Code
		[[
			PDX_MAIN
			{
                AcquirePartitionIndex(Input.gtid.x);
                GroupMemoryBarrierWithGroupSync();
                const uint partitionIndex = g_broadcast;

                if (partitionIndex < e_threadBlocks - 1)
                    ScanInclusiveFull(Input.gtid.x, partitionIndex);
                
                if (partitionIndex == e_threadBlocks - 1)
                    ScanInclusivePartial(Input.gtid.x, partitionIndex);
                GroupMemoryBarrierWithGroupSync();
                
                if (WaveGetLaneCount() >= 16)
                    LocalScanInclusiveWGE16(Input.gtid.x, partitionIndex);
                
                if (WaveGetLaneCount() < 16)
                    LocalScanInclusiveWLT16(Input.gtid.x, partitionIndex);
                
                DeviceBroadcast(Input.gtid.x, partitionIndex);
                
                if (partitionIndex && Input.gtid.x < WaveGetLaneCount())
                    Lookback(partitionIndex);
                GroupMemoryBarrierWithGroupSync();
                
                const uint prevReduction = g_broadcast +
                    (Input.gtid.x >= WaveGetLaneCount() ? g_reduction[getWaveIndex(Input.gtid.x) - 1] : 0);
                
                if (partitionIndex < e_threadBlocks - 1)
                    DownSweepFull(Input.gtid.x, partitionIndex, prevReduction);
                
                if (partitionIndex == e_threadBlocks - 1)
                    DownSweepPartial(Input.gtid.x, partitionIndex, prevReduction);
            }
        ]]
    }
}

Effect PrefixSumInitChainedScan
{
	ComputeShader = "CS_InitChainedScan"
}

Effect PrefixSumChainedScanDecoupledLookbackExclusive
{
	ComputeShader = "CS_ChainedScanDecoupledLookbackExclusive"
}

Effect PrefixSumChainedScanDecoupledLookbackInclusive
{
	ComputeShader = "CS_ChainedScanDecoupledLookbackInclusive"
}
