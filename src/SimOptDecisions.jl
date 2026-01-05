module SimOptDecisions

# Dependencies
using Random
using Tables
using Dates
using JLD2

# Include source files in dependency order
include("types.jl")
include("recorders.jl")
include("validation.jl")
include("simulation.jl")
include("optimization.jl")
include("persistence.jl")

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

# ---------- Phase 2 Exports ----------

# Optimization direction and objectives
export OptimizationDirection, Minimize, Maximize
export Objective, minimize, maximize

# Batch sizing
export AbstractBatchSize, FullBatch, FixedBatch, FractionBatch

# Optimization backends
export AbstractOptimizationBackend, MetaheuristicsBackend

# Policy interface
export params, param_bounds

# Optimization problem and execution
export OptimizationProblem, OptimizationResult
export evaluate_policy, optimize, optimize_backend, pareto_front

# Validation hooks
export validate

# Constraints
export AbstractConstraint, FeasibilityConstraint, PenaltyConstraint

# Persistence
export SharedParameters, ExperimentConfig
export save_checkpoint, load_checkpoint
export save_experiment, load_experiment

end # module SimOptDecisions
