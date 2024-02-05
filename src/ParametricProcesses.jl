"""
#### ParametricProcesses -- versatile process managers for julia
Created in February, 2023 by
[chifi - an open source software dynasty.](https://github.com/orgs/ChifiSource)
- This software is MIT-licensed.

`ParametricProcesses` provides a high-level parametric worker interface for managing different types of parallel computing 
platforms. The results are process tracking and load/worker distribution for multi-threaded and asynchronous use-cases.
With extensions, this management framework could be used further with other forms of parallel computing.
---
###### contents
 - AbstractWorker
 - Process
 - WorkerProcess
 - Threaded
 - Async
 - AbstractJob
 - AbstractProcessManager
 - ProcessJob
 - new_job
 - Worker{T <: Process}
 - Workers{T}
 - ProcessManager
 - delete!(pm::ProcessManager, name::String)
 - delete!(pm::ProcessManager, pid::Int64)
 - push!(pm::ProcessManager, w::Worker{<:Any})
 - put!(pm::ProcessManager)
 - create_workers
 - add_workers!
 - processes
 - assign!
 - distribute!
 - waitfor
 - get_return
 - worker_pids
"""
module ParametricProcesses
import Base: show, getindex, push!, delete!, put!
using Distributed

"""
### abstract type AbstractWorker
The `AbstractWorker` is a worker that holds  a parametric `Process` type, 
an identifier, and finally task information such as whether the task is active or not.

- See also: `Worker`, `processes`, `assign!`, `new_job`, `ProcessManager`
##### consistencies
- pid**::Int64**
- active**::Bool**
"""
abstract type AbstractWorker end

"""
### abstract type Process
A `Process` is a type only by name, and is used to denote the type of a `Worker`.

- See also: `Worker`, `processes`, `Async`, `Threaded`
##### consistencies
- pid**::Int64**
- active**::Bool**
"""
abstract type Process end

"""
### abstract type WorkerProcess
A `Process` is a type only by name, and is used to denote the type of a `Worker`.

- See also: `Worker`, `processes`, `new_job`, `Async`, `Threaded`
##### consistencies
- pid**::Int64**
- active**::Bool**
"""
abstract type WorkerProcess <: Process end

"""
### abstract type Threaded
A `Process` is a type only by name, and is used to denote the type of a `Worker`. `Threaded` is 
used to denote a worker on its own thread, a `Worker` of type `Worker{Threaded}`.

- See also: `Worker`, `processes`, `new_job`, `Async`, `Threaded`
##### consistencies
- pid**::Int64**
- active**::Bool**
"""
abstract type Threaded <: Process end

"""
### abstract type Async
A `Process` is a type only by name, and is used to denote the type of a `Worker`. `Async` workers run 
on the same thread, able to run tasks on that thread only when it is required to run that task.

- See also: `Worker`, `processes`, `new_job`, `Threaded`
##### consistencies
- pid**::Int64**
- active**::Bool**
"""
abstract type Async <: Process end
abstract type AbstractJob end
abstract type AbstractProcessManager end

"""
```julia
ProcessJob <: AbstractJob
```
- f**::Function**
- args
- kwargs

The `ProcessJob` is the default `ParametericProcess` job type. This constructor is also defined as `new_job`. Provide a `Function` and 
the arguments for the `Function` to `new_job` (or this constructor), and then provide jobs to a process manager with `assign!` or `distribute!`.

- See also: Worker, processes, ProcessManager, assign!
```julia
- ProcessJob(f::Function, args ...; keyargs ...)
```
---
```example
# note this is `julia --threads >2`
newprocs = processes(3)
io = IOBuffer()
new_job = (io) do o
    write(o, "hello world!)
end

assign!(newprocs, 2, [new_job for e in 1:50] ...)
```
"""
mutable struct ProcessJob <: AbstractJob
    f::Function
    args
    kwargs
    function ProcessJob(f::Function, args ...; keyargs ...)
        new(f, args, keyargs)
    end
end

const new_job = ProcessJob

"""
```julia
Worker{T <: Process} <: AbstractWorker
```
- name**::String**
- pid**::String**
- ret**::Any**
- active**::Bool**
- task**::Any**

A `Worker` performs and tracks the progress of `AbstractJob`s. Workers may be created directly 
by providing a name and process identifier, or workers can be created using the `processes` `Function`.

- See also: assign!, distribute!, waitfor, add_workers!, get_return!, processes, ProcessManager
```julia
- Worker{T}(name::String, pid::Int64)
```
---
```example
newworker = Worker{Async}("example", 500)

jb = new_job() do
    println("hello from worker 500!")
end

pm = processes(3) # <- these are threads, but we will use `newworker`

push!(pm, newworker) # add our new worker.
assign!(pm, 500, jb)
```
"""
mutable struct Worker{T <: Process} <: AbstractWorker
    name::String
    pid::Int64
    ret::Any
    active::Bool
    task::Any
    Worker{T}(name::String, pid::Int64) where {T <: Process} = begin
        new{T}(name, pid, nothing, false, nothing)
    end
end

const Workers{T} = Vector{T} where {T <: AbstractWorker}

function show(io::IO, worker::Worker{<:Any})
    T = typeof(worker).parameters[1]
    activemessage = "inactive"
    if worker.active
        activemessage = "active"
    end
    println("$(worker.pid) |$T process: $(worker.name) ($(activemessage))")
end

"""
```julia
ProcessManager <: AbstractProcessManager
```
- workers**::Workers{<:Any}**

The `ProcessManager` is a wrapper for a `Vector{Worker{<:Any}}` (or `Workers{<:Any}`) 
that provides PID/name indexing and a process management API. Process management revolves 
primarily around the following methods:
- `delete!(pm::ProcessManager, identifier)`
- `add_workers!(pm::ProcessManager, n::Int64, of::Type{<:Process} = Threaded, names::String ...)`
- `processes(n::Int64, of::Type{<:Process} = Threaded, names::String ...)`
- `worker_pids(pm::ProcessManager)`
- `waitfor(pm::ProcessManager, pids::Any ...)`
- `get_return!(pm::ProcessManager, pids::Any ...)`

Though this constructor is meant to be used directly to create processes from scratch, high-level usage is 
simplified through the `processes` `Function`, which will provide us with initialized workers. 
```julia

```
```example

```
`processes` simply calls `create_workers` with the provided `of` and then a `ProcessManager` constructor.
- See also: assign!, distribute!, waitfor, add_workers!, get_return!, processes, Worker, use_with!, put!
```julia
- ProcessManager(workers::Worker{<:Any} ...)
- ProcessManager(workers::Vector{<:AbstractWorker})
```
---
```example

```
"""
mutable struct ProcessManager <: AbstractProcessManager
    workers::Workers{<:Any}
    function ProcessManager(workers::Worker{<:Any} ...)
        workers::Vector{Worker} = Vector{Worker{<:Any}}([w for w in workers])
        new(workers)
    end
    function ProcessManager(workers::Vector{<:AbstractWorker})
        new(workers)
    end
end

function show(io::IO, pm::AbstractProcessManager)
    [show(worker) for worker in pm.workers]
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

function delete!(pm::ProcessManager, pid::Int64)
    pos = findfirst(worker::Worker{<:Any} -> worker.pid == pid, pm.workers)
    if isnothing(pos)
        # throw
    end
    deleteat!(pm.workers, pos)
end

push!(pm::ProcessManager, w::Worker{<:Any}) = push!(pm.workers, w)

function delete!(pm::ProcessManager, name::String)
    pos = findfirst(worker::Worker{<:Any} -> worker.pid == pid, pm.workers)
    if isnothing(pos)
        # throw
    end
    deleteat!(pm.workers, pos)
end

"""
```julia
create_workers(n::Int64, of::Type{Threaded}, names::Vector{String} = ...) -> ::Workers
````
This function is used to create new workers with the process type `of`. 
    New workers will be named with `names`. Not passing names for each worker will name workers 
    by PID.
```julia
create_workers(n::Int64, of::Type{Async})
create_workers(n::Int64, of::Type{Async})
```
---
```example
workers = create_workers(3, ParametricProcesses.Async)
```
"""
function create_workers end

function create_workers(n::Int64, of::Type{Threaded}, 
    names::Vector{String} = ["$e" for e in 1:n])
    pids = addprocs(n)
    Vector{Worker{<:Any}}([Worker{of}(names[e], pid) for (e, pid) in enumerate(pids)])
end

function create_workers(n::Int64, of::Type{Async}, names::Vector{String} = ["$e" for e in 1:n])

end

"""
```julia
add_workers!(pm::ProcessManager, n::Int64, of::Type{<:Process} = Threaded, names::String ...)
````
Add workers adds workers to a `ProcessManager`. 
The `ProcessManager` can be created with or without workers. `add_workers!` is a 
quick way to add `Workers` of any `Process` type to an existing aggregation of 
`Workers`.
---
```example
pm = processes(2)
# 2 workers, three total processes (including `Main`)
add_workers!(pm, 2)
# now 4 workers, process id's 2-6
```
"""
function add_workers!(pm::ProcessManager, n::Int64, of::Type{<:Process} = Threaded, names::String ...)
    workers = Vector{Worker{<:Any}}()
    name_n = length(names)
    if name_n == 0
        workers = create_workers(n, of)
    elseif name_n != n
        # throw
    else
        workers = create_workers(n, of, [name for name in names])
    end
    pm.workers = vcat(pm.workers, workers)
end

"""
```julia
processes(n::Int64, of::Type{<:Process} = Threaded, names::String ...) -> ::ProcessManager
```
Creates `Workers` inside of a `ProcessManager` with the `Process` type `of`.
---
```example

```
"""
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

worker_pids(pm::ProcessManager) = [w.pid for w in pm.workers]

function waitfor(pm::ProcessManager, pids::Any ...)
    workers = [pm[pid] for pid in pids]
    while true
        next = findfirst(w -> w.active == true, workers)
        if isnothing(next)
            break
        end
        wait(workers[next].task)
    end
    [pm[pid].ret for pid in pids]
end

function get_return!(pm::ProcessManager, pids::Any ...)
    [pm[pid].ret for pid in pids]
end

function use_with!(pm::ProcessManager, pid::Any, mod::String)
    imprtjob = new_job() do 
        eval(Meta.parse("using $(name)"))
    end
    assign!(pm.workers[pid], imprtjob)
end

function put!(pm::ProcessManager, pids::Vector{Int64}, vals ...)

end

"""
```julia
assign!
```
`assign!` is used to distribute tasks to workers directly. This 
culminates in two forms; `assign!` is used to assign a worker directly to 
its job using its process type and it is also used to `assign!` a process 
manager's workers to jobs.
```julia
assign!(assigned_worker::Worker{Threaded}, job::AbstractJob)
assign!(f::Function, assigned_worker::Worker{:Threaded}, job::AbstractJob)
```
---
```example

```
"""
function assign! end

function assign!(assigned_worker::Worker{Threaded}, job::AbstractJob)
    if ~(assigned_worker.active)
        assigned_task = remotecall(job.f, assigned_worker.pid, job.args ...; job.kwargs ...)
        assigned_worker.task = assigned_task
        assigned_worker.active = true
        @async begin
            wait(assigned_task)
            assigned_worker.active = false
            assigned_worker.ret = fetch(assigned_task)
        end
        return assigned_worker.pid
    end
    @async begin
        wait(assigned_worker.task)
        sleep(1)
        assign!(assigned_worker, job)
    end
    assigned_worker.pid
end

function assign!(f::Function, assigned_worker::Worker{Threaded}, job::AbstractJob)
    if ~(assigned_worker.active)
        assigned_task = remotecall(job.f, assigned_worker.pid, job.args ...; job.kwargs ...)
        assigned_worker.task = assigned_task
        assigned_worker.active = true
        @async begin
            wait(worker.assigned_task)
            assigned_worker.active = false
        end
        return assigned_worker.pid
    end
    @async begin
        wait(assigned_worker.task)
        sleep(1)
        assign!(f, assigned_worker, job)
    end
    assigned_worker.pid
end

function assign!(f::Function, pm::ProcessManager, pid::Any, jobs::AbstractJob ...)
   [assign!(f, pm[pid], job) for job in jobs]::Vector{Int64}
end

function assign!(pm::ProcessManager, pid::Any, jobs::AbstractJob ...)
    [assign!(pm[pid], job) for job in jobs]::Vector{Int64}
 end

function distribute!(pm::ProcessManager, jobs::AbstractJob ...)
    jobs = [job for job in jobs]
    n_jobs = length(jobs)
    open = filter(w::AbstractWorker -> ~(w.active), pm.workers)
    at = 1
    n_open = length(open)
    [begin
        assign!(worker, job)
    end for job in jobs]
    [w.pid for w in open]
end

function distribute!(pm::ProcessManager, worker_pids::Vector{Int64}, jobs::AbstractJob ...)
    workers = [pm.workers[id] for id in worker_pids]
    return worker_pids
end

function distribute!(pm::ProcessManager, percentage::Float64, jobs::AbstractJob ...)
    total_workers = length(pm.workers)
    num_workers_to_use = round(Int, percentage * total_workers)
    
    open = filter(w -> ~w.active, pm.workers)
    num_open = length(open)
    
    if num_open < num_workers_to_use
        # If there aren't enough open workers, assign jobs asynchronously
        async_workers = filter(w -> w.active, pm.workers)
        for job in jobs
            if isempty(async_workers)
                error("Not enough open and active workers to distribute the jobs.")
            end
            worker = popfirst!(async_workers)
            assign!(worker, job)
        end
        return [w.pid for w in async_workers]
    end
    # Assign jobs to open workers
    for job in jobs
        worker = popfirst!(open)
        assign!(worker, job)
    end
    return [w.pid for w in open]
end

export processes, add_workers!, assign!, distribute!, Worker, ProcessManager, worker_pids
export Threaded, new_job, @everywhere, get_return!, waitfor, use_with!, Async, RemoteChannel

end # module BasicProcesses
