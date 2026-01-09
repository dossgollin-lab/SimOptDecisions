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
include("utils.jl")
include("timestepping.jl")
include("simulation.jl")
include("optimization.jl")
include("persistence.jl")
include("plotting.jl")

# ============================================================================
# Exports
# ============================================================================

# Abstract types (users subtype these)
export AbstractState, AbstractPolicy, AbstractConfig, AbstractSOW, AbstractRecorder, AbstractAction

# TimeStep struct
export TimeStep

# Core simulation
export simulate, get_action

# Utils helper submodule
export Utils

# TimeStepping submodule
export TimeStepping

# TimeSeriesParameter (from TimeStepping module)
using .TimeStepping: TimeSeriesParameter, TimeSeriesParameterBoundsError
export TimeSeriesParameter, TimeSeriesParameterBoundsError

# Recorders and traces
export NoRecorder, TraceRecorderBuilder, SimulationTrace, record!, build_trace

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

# ---------- Phase 3 Exports ----------

# Plotting (requires Makie extension)
export to_scalars, plot_trace, plot_pareto, plot_parallel

end # module SimOptDecisions
