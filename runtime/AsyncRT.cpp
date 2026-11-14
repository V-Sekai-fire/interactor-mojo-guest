// Replaces Mojo/lib/CompilerRT/AsyncRT.cpp (modular/modular e6e596ce). The original
// is a thread-pool runtime built on AsyncRT/Runtime, which is not in the public
// tree and needs threads a guest does not have. This gives main() the one CPU
// device its startup code asks for. Chains, tasks and coroutines are not here, so
// anything that uses the async runtime (parallelize, async fn) fails to link.
#include "Support/SymbolExport.h"
#include <cstdint>

namespace { char cpuDevice; }

COMPILERRT_EXPORT COMPILERRT_VISIBILITY_EXPORT void *KGEN_CompilerRT_AsyncRT_GetCurrentCPUDevice() { return nullptr; }
COMPILERRT_EXPORT COMPILERRT_VISIBILITY_EXPORT void *KGEN_CompilerRT_AsyncRT_GetOrCreateCPUDevice() { return &cpuDevice; }
COMPILERRT_EXPORT COMPILERRT_VISIBILITY_EXPORT void KGEN_CompilerRT_AsyncRT_ReleaseCPUDevice(void *) {}
COMPILERRT_EXPORT COMPILERRT_VISIBILITY_EXPORT uint32_t KGEN_CompilerRT_AsyncRT_ParallelismLevel() { return 1; }
