@testset "Recorders" begin
    @testset "NoRecorder" begin
        r = NoRecorder()
        # Should not error and return nothing
        @test record!(r, "state", "record", 1) === nothing
        @test record!(r, nothing, nothing, nothing) === nothing
        @test record!(r, 42, 100, Date(2020)) === nothing
        # Backwards compatibility (2-arg)
        @test record!(r, "state", 1) === nothing
    end

    @testset "TraceRecorderBuilder and SimulationTrace" begin
        builder = TraceRecorderBuilder()
        record!(builder, nothing, nothing, nothing)  # Initial state
        record!(builder, 1.0, (value=10,), 1)
        record!(builder, 2.0, (value=20,), 2)
        record!(builder, 3.0, (value=30,), 3)

        trace = finalize(builder)

        @test trace isa SimulationTrace{Float64,@NamedTuple{value::Int},Int}
        @test length(trace.states) == 3
        @test length(trace.step_records) == 3
        @test length(trace.times) == 3
        @test trace.states == [1.0, 2.0, 3.0]
        @test trace.step_records == [(value=10,), (value=20,), (value=30,)]
        @test trace.times == [1, 2, 3]
    end

    @testset "SimulationTrace Tables.jl interface" begin
        trace = SimulationTrace(
            [1.0, 2.0, 3.0],
            [(v=10,), (v=20,), (v=30,)],
            [100, 200, 300],
        )

        @test Tables.istable(typeof(trace))
        @test Tables.columnaccess(typeof(trace))
        @test Tables.columnnames(trace) == (:state, :step_record, :time)
        @test Tables.getcolumn(trace, :state) == [1.0, 2.0, 3.0]
        @test Tables.getcolumn(trace, :step_record) == [(v=10,), (v=20,), (v=30,)]
        @test Tables.getcolumn(trace, :time) == [100, 200, 300]
        @test Tables.getcolumn(trace, 1) == [1.0, 2.0, 3.0]
        @test Tables.getcolumn(trace, 2) == [(v=10,), (v=20,), (v=30,)]
        @test Tables.getcolumn(trace, 3) == [100, 200, 300]

        # Invalid column access
        @test_throws ArgumentError Tables.getcolumn(trace, :invalid)
        @test_throws BoundsError Tables.getcolumn(trace, 4)

        schema = Tables.schema(trace)
        @test schema.names == (:state, :step_record, :time)
    end

    @testset "TraceRecorder legacy Tables.jl interface" begin
        recorder = TraceRecorder([1.0, 2.0, 3.0], [10, 20, 30])

        @test Tables.istable(typeof(recorder))
        @test Tables.columnaccess(typeof(recorder))
        @test Tables.columnnames(recorder) == (:state, :time)
        @test Tables.getcolumn(recorder, :state) == [1.0, 2.0, 3.0]
        @test Tables.getcolumn(recorder, :time) == [10, 20, 30]
        @test Tables.getcolumn(recorder, 1) == [1.0, 2.0, 3.0]
        @test Tables.getcolumn(recorder, 2) == [10, 20, 30]

        # Invalid column access
        @test_throws ArgumentError Tables.getcolumn(recorder, :invalid)
        @test_throws BoundsError Tables.getcolumn(recorder, 3)

        schema = Tables.schema(recorder)
        @test schema.names == (:state, :time)
        @test schema.types == (Float64, Int)
    end
end
