module SimOptDecisions

# Dependencies
using Random
using Tables

# Include source files in dependency order
include("types.jl")
include("recorders.jl")
include("simulation.jl")

# ============================================================================
# Exports
# ============================================================================

# Abstract types (users subtype these)
export AbstractState, AbstractPolicy, AbstractSystemModel, AbstractSOW, AbstractRecorder

# TimeStep struct
export TimeStep

# Interface functions (users implement these)
export initialize, step, time_axis, aggregate_outcome, is_terminal

# Core simulation
export simulate

# Recorders
export NoRecorder, TraceRecorderBuilder, TraceRecorder, record!, finalize

end # module SimOptDecisions
