using SimOptDecisions
using Test
using Random
using Tables
using Dates

# Import specific functions to avoid conflicts with Base
import SimOptDecisions: finalize, step

@testset "SimOptDecisions.jl" begin
    include("test_types.jl")
    include("test_recorders.jl")
    include("test_simulation.jl")
    include("test_validation.jl")
    include("test_optimization.jl")
    include("test_persistence.jl")
end
