module ParametricProcesses
import Base: show, getindex, push!, delete!
using Distributed

abstract type AbstractWorker end
abstract type Process end
abstract type WorkerProcess <: Process end
abstract type Threaded <: Process end
abstract type AbstractJob end

mutable struct ProcessJob <: AbstractJob
    f::Function
    args
    kwargs
    function ProcessJob(f::Function, args ...; keyargs ...)
        new(f, args, keyargs)
    end
end

const new_job = ProcessJob

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
    function ProcessManager(workers::Vector{<:AbstractWorker})
        fs = Vector{Pair{LoadDistributor, Function}}()
        new(workers, fs)
    end
end

function show(io::IO, pm::ProcessManager)
    println("pid | process type | name | active")
    [show(io, worker) for worker in pm.workers]
end


function getindex(pm::ProcessManager, name::String)
    pos = findfirst(worker::Worker{<:Any} -> worker.name == name, pm.workers)
    if isnothing(pos)
        # throw
    end
    pm.workers[pos]
end

function getindex(pm::ProcessManager, pid::Int64)
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

function add_workers!(pm::ProcessManager, n::Int64, of::Type{<:Process} = Threaded, names::String ...)
    workers = Vector{Worker{<:Any}}()
    if name_n == 0
        workers = create_workers(n, of)
    elseif name_n != n
        # throw
    else
        workers = create_workers(n, of, [name for name in names])
    end
    pm.workers = vcat(pm.workers, workers)
end

function delete!(pm::ProcessManager, pid::Int64)
    pos = findfirst(worker::Worker{<:Any} -> worker.pid == pid, pm.workers)
    if isnothing(pos)
        # throw
    end
    deleteat!(pm.workers, pos)
end

function delete!(pm::ProcessManager, name::String)
    pos = findfirst(worker::Worker{<:Any} -> worker.pid == pid, pm.workers)
    if isnothing(pos)
        # throw
    end
    deleteat!(pm.workers, pos)
end


function processes(n::Int64, of::Type{<:Process} = Threaded, names::String ...)
    workers = Vector{Worker{<:Any}}()
    name_n = length(names)
    if name_n == 0
        workers = create_workers(n, of)
    elseif name_n != n
        # throw
    else
        workers = create_workers(n, of, [name for name in names])
    end
    ProcessManager(workers)
end

function assign!(f::Function, pm::ProcessManager, pid::Int64, job::AbstractJob)
    assigned_task = remotecall(job.f, pid, job.args ...; job.kwargs ...)
    assigned_worker = pm[pid]
    assigned_worker.active = true
    @async begin
        wait(assigned_task)
        f(fetch(assigned_task))
        assigned_worker.active = false
    end
end

function distribute!(pm::ProcessManager, job::AbstractJob ...)

end

function distribute!(pm::ProcessManager, jobs::Pair{Float64, <:AbstractJob} ...)

end

export processes, add_workers!, assign!, distribute!, Worker, ProcessManager
export Threaded

end # module BasicProcesses
