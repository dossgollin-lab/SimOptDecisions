using SimOptDecisions
using Test
using Random
using Tables
using Dates

# Load extensions at the start so they're available for all tests
using Metaheuristics
using CairoMakie

# Import specific functions to avoid conflicts with Base
import SimOptDecisions: finalize, step

@testset "SimOptDecisions.jl" begin
    include("test_types.jl")
    include("test_recorders.jl")
    include("test_simulation.jl")
    include("test_timestepping.jl")
    include("test_validation.jl")
    include("test_optimization.jl")
    include("test_persistence.jl")
    include("test_aqua.jl")

    # Extension tests (Metaheuristics and CairoMakie are loaded at the top)
    @testset "Extensions" begin
        @info "Running Metaheuristics extension tests..."
        include("ext/test_metaheuristics_ext.jl")

        @info "Running Makie extension tests..."
        include("ext/test_makie_ext.jl")
    end
end
