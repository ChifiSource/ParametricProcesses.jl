module ParametricProcesses
import Base: show, getindex, push!, delete!
using Distributed

abstract type AbstractWorker end
abstract type Process end
abstract type WorkerProcess <: Process end
abstract type Threaded <: Process end

mutable struct Worker{T <: Process} <: AbstractWorker
    name::String
    pid::Int64
    active::Bool
    task::Any
    Worker{T}(name::String, pid::Int64) where {T <: Process} = begin
        new{T}(name, pid, false, nothing)
    end
end

const Workers{T} = Vector{T} where {T <: AbstractWorker}

function show(io::IO, worker::Worker{<:Any})
    T = typeof(worker).parameters[1]
    activemessage = "inactive"
    if worker.active
        activemessage = "inactive"
    end
    println("$(worker.pid) |$T process: $(worker.name) ($(activemessage))")
end

abstract type LoadDistributor end

mutable struct BasicDistributor{N <: Real} <: LoadDistributor
    value::N
    NumericalDistributor(val::Number) = new{typeof(val)}(val)
end

mutable struct ProcessManager
    workers::Workers{<:Any}
    f::Vector{Pair{LoadDistributor, Function}}
    function ProcessManager(workers::Worker{<:Any} ...)
        fs = Vector{Pair{LoadDistributor, Function}}()
        workers::Vector{Worker} = [w for w in workers]
        new(workers, fs)
    end
    function ProcessManager(workers::Vector{<:AbstractWorker}) where {T <: Process}
        fs = Vector{Pair{LoadDistributor, Function}}()
        new(workers, fs)
    end
end

function show(io::IO, pm::ProcessManager{<:Any})
    println("pid | process type | name | active")
    [show(io, worker) for worker in pm.workers]
end


function getindex(pm::ProcessManager{<:Any}, name::String)
    pos = findfirst(worker::Worker{<:Any} -> worker.name == name, pm.workers)
    if isnothing(pos)
        # throw
    end
    pm.workers[pos]
end

function getindex(pm::ProcessManager{<:Any}, pid::Int64)
    pos = findfirst(worker::Worker{<:Any} -> worker.pid == pid, pm.workers)
    if isnothing(pos)
        # throw
    end
    pm.workers[pos]
end

function create_workers(n::Int64, of::Type{Threaded}, 
    names::Vector{String} = ["$e" for e in 1:n])
    pids = addprocs(n)
    [Worker{of}(names[e], pid) for (e, pid) in enumerate(pids)]
end

function add_workers!(pm::ProcessManager, n::Int64, of::Type{<:Process} = Threaded)

end

function processes(n::Int64, of::Type{<:Process} = Threaded, names::String ...)
    workers = Vector{Worker{<:Any}}()
    name_n = length(names)
    if name_n == 0
        workers = create_workers(n, of)
    elseif name_n != N
        # throw
    else
        workers = create_workers(n, of, [name for name in names])
    end
    ProcessManager(workers)
end

function assign!(f::Function, pm::ProcessManager, nsorpids::Tuple, args ...; keyargs ...)

end

function distribute!(pm::ProcessManager{}, fs::Pair{Function, Tuple} ...; keyargs ...)

end

function distribute!(f::Function, pm::ProcessManager{})

end


function kill!()

end

export processes, assign!, distribute!, Worker, ProcessManager
export Async, Threads

end # module BasicProcesses
