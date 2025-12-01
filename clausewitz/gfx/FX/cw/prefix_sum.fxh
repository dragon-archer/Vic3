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

Includes = {
	"cw/miscmath.fxh"
}

Code
[[
    #define MAX_DISPATCH_DIM                    65535U
    #define NUM_UINT4_ELEMENTS_IN_PARTITION     768U
    #define NUM_THREADS_IN_GROUP                256U
    #define NUM_UINT4_ELEMENTS_PER_THREAD       3U
    #define MIN_WAVE_SIZE                       4U
    #define WAVE_PART_SIZE                      32U

    #define FLAG_NOT_READY  0           //Flag indicating this partition tile's local reduction is not ready
    #define FLAG_REDUCTION  1           //Flag indicating this partition tile's local reduction is ready
    #define FLAG_INCLUSIVE  2           //Flag indicating this partition tile has summed all preceding tiles and added to its sum.
    #define FLAG_MASK       3           //Mask used to retrieve the flag (= 0b11)
]]

ConstantBuffer( PdxConstantBuffer0 )
{
    uint _VectorizedInputSize;
    uint _PartitionCount;
    uint _Pad0;
    uint _Pad1;
};

RWStructuredBufferTexture RWInputBuffer_UINT4
{
    Ref = PdxRWBufferTexture0
    Type = uint4
}

RWStructuredBufferTexture PartitionIndexBuffer
{
    Ref = PdxRWBufferTexture1
    Type = uint
    globallycoherent = yes
}

RWStructuredBufferTexture PartitionReductionsBuffer
{
    Ref = PdxRWBufferTexture2
    Type = uint
    globallycoherent = yes
}

RWStructuredBufferTexture RWIndexOutputBuffer
{
    Ref = PdxRWBufferTexture3
    Type = uint
}

Code
[[

// Compaction uses exclusive prefix sum
#ifdef PREFIX_SUM_COMPACTION
#define PREFIX_SUM_EXCLUSIVE
#endif

    // Wave-local prefix sums for all the elements in a given partition
    groupshared uint4 GS_PartitionWavePrefixSums[ NUM_UINT4_ELEMENTS_IN_PARTITION ];

#ifdef PREFIX_SUM_COMPACTION
    // Input elements to be compacted stored in groupshared memory
    groupshared uint4 GS_PartitionInputElements[ NUM_UINT4_ELEMENTS_IN_PARTITION ];
#endif

    // Total sum of all elements for every wave in a given partition
    groupshared uint GS_WaveReductions[ NUM_THREADS_IN_GROUP / MIN_WAVE_SIZE ];

    groupshared uint GS_PartitionIndex;
    groupshared uint GS_PrevPartitionsReduction;

    inline uint GetWaveIndex( uint GroupThreadID )
    {
        return GroupThreadID / WaveGetLaneCount();
    }

    inline uint GetPartitionStartElementIndex( uint PartitionIndex )
    {
        return PartitionIndex * NUM_UINT4_ELEMENTS_IN_PARTITION;
    }

    inline uint GetWaveStartElementIndexInPartition( uint GroupThreadID )
    {
        const uint WaveWorkingSetSize = NUM_UINT4_ELEMENTS_PER_THREAD * WaveGetLaneCount();
        return GetWaveIndex( GroupThreadID ) * WaveWorkingSetSize;
    }

    // ( x, y, z, w ) -> ( x, x+y, x+y+z, x+y+z+w )
    inline uint4 CalcInclusivePrefixSumUint4( uint4 Value )
    {
        Value.y += Value.x;
        Value.z += Value.y;
        Value.w += Value.z;

        return Value;
    }

    // This function calculates exclusive prefix sums for a partition and fills 2 groupshared arrays:
    // - GS_PartitionWavePrefixSums[ NumElements ]: stores wave-local prefix sum for every element in a partition
    // - GS_WaveReductions[ NumWaves ]: stores total sum of all elements (reduction) for every wave
    inline void PartitionScan( uint GroupThreadID, uint PartitionIndex )
    {
        uint WaveReduction = 0;
        uint ElementIndex = GetWaveStartElementIndexInPartition( GroupThreadID ) + WaveGetLaneIndex();

        [unroll]
        for ( uint i = 0; i < NUM_UINT4_ELEMENTS_PER_THREAD; ++i )
        {
            uint4 LocalPrefixSums = 0;

            const uint GlobalElementIndex = GetPartitionStartElementIndex( PartitionIndex ) + ElementIndex;
            if ( GlobalElementIndex < _VectorizedInputSize )
            {
                uint4 InputValues = RWInputBuffer_UINT4[ GlobalElementIndex ];

#ifdef PREFIX_SUM_COMPACTION
                // Read input values and store them in groupshared memory
                GS_PartitionInputElements[ ElementIndex ] = InputValues;

                // RWInputBuffer_UINT4 stores zeros for elements we want to be removed after compaction.
                // Compaction itself is done with a prefix sum of the array of binary flags
                //   where 1 indicates that the element should be preserved and 0 - that the element should be dropped.
                // Here we clamp non-zero input values to 1 to get this array of binary flags.
                InputValues = clamp( InputValues, 0, 1 );
#endif

                LocalPrefixSums = CalcInclusivePrefixSumUint4( InputValues );
            }

            const uint PrevLanesSum = WavePrefixSum( LocalPrefixSums.w );

#ifdef PREFIX_SUM_EXCLUSIVE
            GS_PartitionWavePrefixSums[ ElementIndex ] = uint4( 0, LocalPrefixSums.xyz ) + PrevLanesSum + WaveReduction;
#else
            GS_PartitionWavePrefixSums[ ElementIndex ] = LocalPrefixSums.xyzw + PrevLanesSum + WaveReduction;
#endif // PREFIX_SUM_EXCLUSIVE

            WaveReduction += WaveReadLaneAt( LocalPrefixSums.w + PrevLanesSum, WaveGetLaneCount() - 1 );

            ElementIndex += WaveGetLaneCount();
        }

        if ( WaveIsFirstLane() )
        {
            GS_WaveReductions[ GetWaveIndex( GroupThreadID ) ] = WaveReduction;
        }
    }

    inline void ReductionScanSingleWave( uint GroupThreadID )
    {
        if ( GroupThreadID < NUM_THREADS_IN_GROUP / WaveGetLaneCount() )
        {
            GS_WaveReductions[ GroupThreadID ] += WavePrefixSum( GS_WaveReductions[ GroupThreadID ] );
        }
    }

    inline void ReductionScanMultipleWaves( uint GroupThreadID, uint partIndex )
    {
        const uint ScanSize = NUM_THREADS_IN_GROUP / WaveGetLaneCount();
        if ( GroupThreadID < ScanSize )
        {
            GS_WaveReductions[ GroupThreadID ] += WavePrefixSum( GS_WaveReductions[ GroupThreadID ] );
        }

        GroupMemoryBarrierWithGroupSync();

        const uint LaneLog = countbits( WaveGetLaneCount() - 1 );
        uint Offset = LaneLog;
        uint j = WaveGetLaneCount();
        for ( ; j < ( ScanSize >> 1 ); j <<= LaneLog )
        {
            if ( GroupThreadID < ( ScanSize >> Offset ) )
            {
                GS_WaveReductions[ ( ( GroupThreadID + 1 ) << Offset ) - 1 ] +=
                    WavePrefixSum( GS_WaveReductions[ ( ( GroupThreadID + 1 ) << Offset ) - 1 ] );
            }

            GroupMemoryBarrierWithGroupSync();

            if ( ( GroupThreadID & ( ( j << LaneLog ) - 1 ) ) >= j && ( GroupThreadID + 1 ) & ( j - 1 ) )
            {
                GS_WaveReductions[ GroupThreadID ] +=
                    WaveReadLaneAt( GS_WaveReductions[ ( ( GroupThreadID >> Offset ) << Offset ) - 1 ], 0 );
            }

            Offset += LaneLog;
        }

        GroupMemoryBarrierWithGroupSync();

        // If ScanSize is not a power of WaveGetLaneCount()
        const uint Index = GroupThreadID + j;
        if ( Index < ScanSize )
        {
            GS_WaveReductions[ Index ] +=
                WaveReadLaneAt( GS_WaveReductions[ ( ( Index >> Offset ) << Offset ) - 1 ], 0 );
        }
    }

    inline void DownSweep( uint GroupThreadID, uint PartitionIndex )
    {
        uint PrevReduction = ( PartitionIndex > 0 ) ? GS_PrevPartitionsReduction : 0;

        // Add wave-local reductions from this partition
        if ( GroupThreadID >= WaveGetLaneCount() )
        {
            PrevReduction += GS_WaveReductions[ GetWaveIndex( GroupThreadID ) - 1 ];
        }

        uint ElementIndex = GetWaveStartElementIndexInPartition( GroupThreadID ) + WaveGetLaneIndex();

        [unroll]
        for ( uint i = 0; i < NUM_UINT4_ELEMENTS_PER_THREAD; ++i )
        {
            const uint GlobalElementIndex = GetPartitionStartElementIndex( PartitionIndex ) + ElementIndex;
            if ( GlobalElementIndex >= _VectorizedInputSize )
            {
                break;
            }

#ifdef PREFIX_SUM_COMPACTION
            // Prefix sums of the binary flags represent the indices of the corresponding elements in the final compacted array.
            // We read this indices and store them in ScatterIndices.
            const uint4 ScatterIndices = GS_PartitionWavePrefixSums[ ElementIndex ] + PrevReduction;

            // GS_PartitionInputElements stores original input elements
            const uint4 InputElements = GS_PartitionInputElements[ ElementIndex ];

            [unroll]
            for ( uint j = 0; j < 4; ++j )
            {
                // We want to preserve only non-zero input elements
                if ( InputElements[ j ] != 0 )
                {
                    // We need to transform ScatterIndices from uint-indexed space to uint4-indexed space
                    //   to be able to index RWInputBuffer_UINT4.
                    const uint IndexBufferOffset = ScatterIndices[ j ] / 4;
                    const uint IndexBufferElement = ScatterIndices[ j ] % 4;

                    // Move input elements to their compacted places
                    RWInputBuffer_UINT4[ IndexBufferOffset ][ IndexBufferElement ] = InputElements[ j ];
#ifdef OUTPUT_COMPACTED_INDICES
                    // Store final indices of the compacted elements in a separate buffer
                    const uint GlobalElementIndexScalar = GlobalElementIndex * 4 + j;
                    RWIndexOutputBuffer[ ScatterIndices[ j ] ] = GlobalElementIndexScalar;
#endif
                }
            }
#else
            RWInputBuffer_UINT4[ GlobalElementIndex ] = GS_PartitionWavePrefixSums[ ElementIndex ] + PrevReduction;
#endif // PREFIX_SUM_COMPACTION

            ElementIndex += WaveGetLaneCount();
        }
    }

    inline void AcquirePartitionIndex( uint GroupThreadID )
    {
        if ( GroupThreadID == 0 )
        {
            InterlockedAdd( PartitionIndexBuffer[ 0 ], 1, GS_PartitionIndex );
        }
    }

    inline void SetPartitionReductionReadyFlag( uint GroupThreadID, uint PartitionIndex )
    {
        const uint LastScanWaveIndex = NUM_THREADS_IN_GROUP / WaveGetLaneCount() - 1;
        if ( GroupThreadID == LastScanWaveIndex )
        {
            // PartitionReductionsBuffer stores per-partition uint values with the following bit layout:
            //   - Two least significant bits of the value are used for the partition status flag
            //   - The rest of the bits contain the sum of all the elements of the partition
            const uint StatusFlag = ( PartitionIndex != 0 ) ? FLAG_REDUCTION : FLAG_INCLUSIVE;
            const uint PartitionReduction = GS_WaveReductions[ LastScanWaveIndex ];
            InterlockedAdd( PartitionReductionsBuffer[ PartitionIndex ], ( PartitionReduction << 2 ) | StatusFlag );
        }
    }

    // For a given partition sum up the reductions of all the preceding partitions.
    // The resulted sum is stored in GS_PrevPartitionsReduction.
    inline void Lookback( uint PartitionIndex )
    {
        uint PrevReductionsSum = 0;

        int PrevPartitionIndex = PartitionIndex - WaveGetLaneIndex() - 1;
        const uint NumWaveParts = CeilingDivide( WaveGetLaneCount(), WAVE_PART_SIZE );

        while ( true )
        {
            const uint FlagPayload = PrevPartitionIndex >= 0 ? PartitionReductionsBuffer[ PrevPartitionIndex ] : FLAG_INCLUSIVE;

            if ( WaveActiveAllTrue( ( FlagPayload & FLAG_MASK ) > FLAG_NOT_READY ) )
            {
                const uint4 InclusiveBallot = WaveActiveBallot( ( FlagPayload & FLAG_MASK ) == FLAG_INCLUSIVE );

                // Check if any of the preceding partitions have FLAG_INCLUSIVE set
                if ( InclusiveBallot.x || InclusiveBallot.y || InclusiveBallot.z || InclusiveBallot.w )
                {
                    // Found a partition with its inclusive prefix sums already calculated - no need to look further back.
                    uint InclusiveIndex = 0;
                    for ( uint WavePartIndex = 0; WavePartIndex < NumWaveParts; ++WavePartIndex )
                    {
                        if ( countbits( InclusiveBallot[ WavePartIndex ] ) > 0 )
                        {
                            InclusiveIndex += firstbitlow( InclusiveBallot[ WavePartIndex ] );
                            break;
                        }
                        else
                        {
                            InclusiveIndex += WAVE_PART_SIZE;
                        }
                    }

                    // Sum up the reductions of the partitions up to and including the found partition
                    PrevReductionsSum += WaveActiveSum( WaveGetLaneIndex() <= InclusiveIndex ? ( FlagPayload >> 2 ) : 0 );

                    // Update the reduction value of the current partition and set the status flag to FLAG_INCLUSIVE
                    if ( WaveIsFirstLane() )
                    {
                        GS_PrevPartitionsReduction = PrevReductionsSum;
                        InterlockedAdd( PartitionReductionsBuffer[ PartitionIndex ], ( PrevReductionsSum << 2 ) | 1 );
                    }

                    break;
                }
                else
                {
                    // Manually sum up the reductions and step one wave back through partitions
                    PrevReductionsSum += WaveActiveSum( FlagPayload >> 2 );
                    PrevPartitionIndex -= WaveGetLaneCount();
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
            uint3 DispatchThreadID : PDX_DispatchThreadID
        };

        Input = "CS_INPUT"
        NumThreads = { 256 1 1 }
        Code
        [[
            PDX_MAIN
            {
                const uint TotalThreadCount = 256 * 256;

                for ( uint ThreadIndex = Input.DispatchThreadID.x; ThreadIndex < _PartitionCount; ThreadIndex += TotalThreadCount )
                {
                    PartitionReductionsBuffer[ ThreadIndex ] = 0;
                }

                if ( Input.DispatchThreadID.x == 0 )
                {
                    PartitionIndexBuffer[ 0 ] = 0;
                }
            }
        ]]
    }
}

ComputeShader =
{
    MainCode CS_ChainedScanDecoupledLookback
    {
        VertexStruct CS_INPUT
        {
            uint3 GroupThreadID : PDX_GroupThreadID
        };

        Input = "CS_INPUT"
        NumThreads = { NUM_THREADS_IN_GROUP 1 1 }
        Code
        [[
            PDX_MAIN
            {
                const uint GroupThreadID = Input.GroupThreadID.x;

                // Atomically acquire unique index for this partition
                AcquirePartitionIndex( GroupThreadID );

                // Wait until acquired GS_PartitionIndex is available for all waves
                GroupMemoryBarrierWithGroupSync();

                const uint PartitionIndex = GS_PartitionIndex;

                // Calculate wave-wide prefix sums and wave reductions for this partition.
                // Results are stored in GS_PartitionWavePrefixSums and GS_WaveReductions.
                // This is done by all waves of the thread group concurrently.
                PartitionScan( GroupThreadID, PartitionIndex );

                // Wait until all waves have calculated their local reductions
                GroupMemoryBarrierWithGroupSync();

                // Now we can calculate prefix sums of wave-local reductions to get partition-wide prefix sums.
                // This can be done with a single wave if there is enough lanes in a wave to cover NUM_THREADS_IN_GROUP.
                // The results are stored in GS_WaveReductions.
                if ( NUM_THREADS_IN_GROUP / WaveGetLaneCount() <= WaveGetLaneCount() )
                {
                    ReductionScanSingleWave( GroupThreadID );
                }
                else
                {
                    ReductionScanMultipleWaves( GroupThreadID, PartitionIndex );
                }

                // Now when the reduction scan for this partition is done we can signal its status to other thread groups.
                // Any thread can do that so we use the thread that scanned last wave reduction to elide an extra barrier.
                SetPartitionReductionReadyFlag( GroupThreadID, PartitionIndex );

                // Once the reduction for the whole partition has been calculated we can start 
                // looking through the reductions of the preceding partitions.
                // This is done using a single wave in a thread group.
                // The resulted sum of all reductions of all previous partitions is stored in GS_PrevPartitionsReduction.
                if ( PartitionIndex > 0 && GroupThreadID < WaveGetLaneCount() )
                {
                    Lookback( PartitionIndex );
                }

                // Wait until GS_PrevPartitionsReduction is available for all waves
                GroupMemoryBarrierWithGroupSync();

                // Calculate final prefix sums using GS_PrevPartitionsReduction and GS_PartitionWavePrefixSums.
                // This is done by all waves of the thread group concurrently.
                DownSweep( GroupThreadID, PartitionIndex );
            }
        ]]
    }
}

Effect PrefixSumInitChainedScan
{
    ComputeShader = "CS_InitChainedScan"
}

Effect PrefixSumChainedScanDecoupledLookback
{
    ComputeShader = "CS_ChainedScanDecoupledLookback"
}