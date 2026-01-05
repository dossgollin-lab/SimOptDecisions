@testset "Recorders" begin
    @testset "NoRecorder" begin
        r = NoRecorder()
        # Should not error and return nothing
        @test record!(r, "state", 1) === nothing
        @test record!(r, nothing, nothing) === nothing
        @test record!(r, 42, Date(2020)) === nothing
    end

    @testset "TraceRecorderBuilder and finalize" begin
        builder = TraceRecorderBuilder()
        record!(builder, nothing, nothing)  # Initial state
        record!(builder, 1.0, 1)
        record!(builder, 2.0, 2)
        record!(builder, 3.0, 3)

        recorder = finalize(builder)

        @test recorder isa TraceRecorder{Float64,Int}
        @test length(recorder.states) == 3
        @test length(recorder.times) == 3
        @test recorder.states == [1.0, 2.0, 3.0]
        @test recorder.times == [1, 2, 3]
    end

    @testset "TraceRecorder pre-allocation" begin
        recorder = TraceRecorder{Float64,Int}(10)
        @test length(recorder.states) == 10
        @test length(recorder.times) == 10
    end

    @testset "TraceRecorder Tables.jl interface" begin
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
