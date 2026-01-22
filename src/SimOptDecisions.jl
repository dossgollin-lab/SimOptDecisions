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
include("metrics.jl")
include("optimization.jl")
include("persistence.jl")
include("plotting.jl")
include("executors.jl")
include("exploration.jl")
include("macros.jl")

# ============================================================================
# Exports
# ============================================================================

# Abstract types (users subtype these)
export AbstractState,
    AbstractPolicy, AbstractConfig, AbstractScenario, AbstractRecorder, AbstractAction,
    AbstractOutcome

# TimeStep struct and accessors
export TimeStep, index

# Core simulation
export simulate, simulate_traced, get_action

# Callbacks (users implement these)
export initialize, run_timestep, time_axis, compute_outcome

# Utility functions
export discount_factor, is_first, is_last, timeindex

# TimeSeriesParameter
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
export merge_into_pareto!, dominates, get_bounds

# Validation hooks
export validate

# Constraints
export AbstractConstraint, FeasibilityConstraint, PenaltyConstraint

# Declarative Metrics
export AbstractMetric,
    ExpectedValue, Probability, Variance, MeanAndVariance, Quantile, CustomMetric
export compute_metric, compute_metrics

# Persistence
export SharedParameters, ExperimentConfig
export save_checkpoint, load_checkpoint
export save_experiment, load_experiment

# ---------- Phase 3 Exports ----------

# Plotting (requires Makie extension)
export to_scalars, plot_trace, plot_pareto, plot_parallel

# ---------- Phase 4 Exports: Exploratory Modeling ----------

# Parameter types
export AbstractParameter, ContinuousParameter, DiscreteParameter, CategoricalParameter
export GenericParameter
export value

# Definition macros
export @scenariodef, @policydef, @configdef, @statedef, @outcomedef

# Executors
export AbstractExecutor, SequentialExecutor, ThreadedExecutor, DistributedExecutor
export CRNConfig, create_scenario_rng

# Storage backends
export AbstractStorageBackend, InMemoryBackend, ZarrBackend

# Exploration (YAXArray-based)
export explore, explore_traced
export outcomes_for_policy, outcomes_for_scenario
export load_zarr_results
export save_netcdf, load_netcdf
export ExploratoryInterfaceError

# Exploration plotting (requires Makie extension)
export plot_exploration, plot_exploration_parallel, plot_exploration_scatter

end # module SimOptDecisions
