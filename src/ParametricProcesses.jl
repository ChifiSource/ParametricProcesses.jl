"""
#### ParametricProcesses -- versatile process managers for julia
Created in February, 2023 by
[chifi - an open source software dynasty.](https://github.com/orgs/ChifiSource)
- This software is MIT-licensed.

`ParametricProcesses` provides a high-level parametric worker interface for managing different types of parallel computing 
platforms. The results are process tracking and load/worker distribution for multi-threaded and asynchronous use-cases.
With extensions, this management framework could be used further with other forms of parallel computing.
###### contents
 - `AbstractWorker`
 - `Process`
 - `WorkerProcess`
 - `Threaded`
 - `Async`
 - `AbstractJob`
 - `AbstractProcessManager`
 - `ProcessJob`
 - `new_job`
 - `Worker{T <: Process}`
 - `Workers{T}`
 - `ProcessManager`
 - `close(pm::ProcessManager)`
 - `close(w::Worker)`
 - `close_workers!`
 - `delete!(pm::ProcessManager, name::String)`
 - `delete!(pm::ProcessManager, pid::Int64)`
 - `push!(pm::ProcessManager, w::Worker{<:Any})`
 - `put!(pm::ProcessManager, pids::Vector{Int64}, vals ...)`
 - `create_workers`
 - `add_workers!`
 - `processes`
 - `assign!`
 - `distribute!`
 - `ProcessError`
 - `waitfor`
 - `get_return`
 - `worker_pids`
 - `assign_open!`
 - `distribute_open!`
"""
module ParametricProcesses
import Base: show, getindex, push!, delete!, put!, take!, close
using Distributed

"""
```julia
abstract type AbstractWorker
```
The `AbstractWorker` is a worker that holds  a parametric `Process` type, 
an identifier, and finally task information such as whether the task is active or not.

- See also: `Worker`, `processes`, `assign!`, `new_job`, `ProcessManager`
- pid**::Int64**
- active**::Bool**
"""
abstract type AbstractWorker end

"""
```julia
abstract type Process
```
A `Process` is a type only by name, and is used to denote the type of a `Worker`.

- See also: `Worker`, `processes`, `Async`, `Threaded`, `assign!`, `assign_open!`

- pid**::Int64**
- active**::Bool**
"""
abstract type Process end


"""
```julia
ProcessError <: Base.Exception
```
- message**::String**
- ptype**::Process**

The `ProcessError` is meant to be thrown when something goes wrong 
while creating or using a `Worker` with `assign!` or `create_workers`. 
    This is *not* meant to facilitate error handling on threads, 
    `waitfor` alongside `try`/`catch` facilitates this -- this is for 
    driver errors. In the case of base `ParametricProcesses`, 
    this error is thrown when there are not enough threads to spawn 
    the number of threaded workers.
```julia
ProcessError(message::String, ptype::Process)
```
"""
mutable struct ProcessError <: Exception
    message::String
    ptype::Process
end

"""
```julia
abstract type WorkerProcess
```
A `Process` is a type only by name, and is used to denote the type of a `Worker`. 
This is used with *parametric dispatch* to load different types of parallel processes. 
`ParametricProcesses` implements `Async` and `Threaded`.

- pid**::Int64**
- active**::Bool**

- See also: `Worker`, `processes`, `new_job`, `Async`, `Threaded`
"""
abstract type WorkerProcess <: Process end

"""
```julia
abstract type Threaded
```
A `Process` is a type only by name, and is used to denote the type of a `Worker`. `Threaded` is 
used to denote a worker on its own thread, a `Worker` of type `Worker{Threaded}`.

- pid**::Int64**
- active**::Bool**

- See also: `Worker`, `processes`, `new_job`, `Async`, `Threaded`
"""
abstract type Threaded <: Process end

"""
```julia
abstract type Async
```
A `Process` is a type only by name, and is used to denote the type of a `Worker`. `Async` workers run 
on the same thread, able to run tasks on that thread only when it is required to run that task. Note that 
you will need to add `yield` to your task to make it *yielding*.

- pid**::Int64**
- active**::Bool**

- See also: `Worker`, `processes`, `new_job`, `Threaded`
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

- See also: `Worker`, `processes`, `ProcessManager`, `assign!`
```julia
- ProcessJob(f::Function, args ...; keyargs ...)
```
```julia
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
```julia
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

"""
```julia
Workers{T} (Alias for Vector{T} where {T <: AbstractWorker})
```
`Workers` represents an allocation of workers, typically of a certain type. 
For `Workers` multiple types, use `Workers{<:Process}` or `Workers{<:Any}`.
"""
const Workers{T} = Vector{T} where {T <: Worker{<:Any}}

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
that provides PID/name indexing and a process management API. This type may be indexed with a `String` to 
retrieve workers by name and an `In64` to get workers by process id (`pid`)Process management revolves 
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
processes(n::Int64, of::Type{<:Process} = Threaded, names::String ...)
```
```julia
myprocs = processes(5)
asyncprocs = processes(2, Async, "first", "second")
```
`processes` simply calls `create_workers` with the provided `of` and then a `ProcessManager` constructor.
- See also: assign!, distribute!, waitfor, add_workers!, get_return!, processes, Worker, put!, `close`
```julia
- ProcessManager(workers::Worker{<:Any} ...)
- ProcessManager(workers::Vector{<:AbstractWorker})
```
---
```julia
# threaded workers
pm = processes(2)
# asynchronous worker.
pm2 = ProcessManager(Worker{Async}("my worker", 50))

job = new_job() do
    println("hello")
    sleep(10)
    println("world")
end

assign!(pm2, 50, job)

assign!(pm, 2, job)

distribute!(pm, job, job, job, job, job, job)
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

function getindex(pm::AbstractProcessManager, name::AbstractString)
    pos = findfirst(worker::Worker{<:Any} -> worker.name == name, pm.workers)
    if isnothing(pos)
        throw(KeyError(name))
    end
    pm.workers[pos]
end

function getindex(pm::AbstractProcessManager, pid::Integer)
    pos = findfirst(worker::Worker{<:Any} -> worker.pid == pid, pm.workers)
    if isnothing(pos)
        throw(KeyError(pid))
    end
    pm.workers[pos]
end

function close(w::Worker{Threaded})
    rmprocs(w.pid)
end

"""
```julia
close(w::Worker{<:Any}) -> ::Nothing
```
Closes a worker directly. For example, the `Worker{Threaded}` here will close 
your process IDs. `async` will simply get rid of the task. This function is not 
necessarily intended to be called directly. Also take note of `delete!` -- this 
function only *closes* the workers.
```julia
close(w::Worker{<:Any})
close(w::Worker{Async})
close(w::Worker{Threaded})
```
```julia
using ParametricProcesses
pm = processes(5)
[close(w) for w in pm.workers] # (or `close_workers`) on `pm`.
```
- See also: `close_workers!`, `processes`, `create_workers`
"""
function close(w::Worker{<:Any})

end

function close(w::Worker{Async})
    close(w.task)
end


"""
```julia
close(pm::ProcessManager) -> ::ProcessManager
```
Strips a process manager of all current workers (closes all workers.)
```julia

```
```julia

```
"""
close(pm::AbstractProcessManager) = [delete!(pm, pid) for pid in worker_pids(pm)]; GC.gc(); nothing

close_workers!(pm::AbstractProcessManager, pids::Vector{Int64} = worker_pids(pm)) = begin
    for worker in 1:length(pids)
        close(pm.workers[worker])
    end
end

function delete!(pm::AbstractProcessManager, pid::Int64)
    pos = findfirst(worker::Worker{<:Any} -> worker.pid == pid, pm.workers)
    if isnothing(pos)
        throw(KeyError(pid))
    end
    close(pm.workers[pos])
    deleteat!(pm.workers, pos)
    pm::AbstractProcessManager
end

push!(pm::AbstractProcessManager, w::Worker{<:Any}) = begin
    push!(pm.workers, w)
    pm::AbstractProcessManager
end

function delete!(pm::AbstractProcessManager, name::String)
    pos = findfirst(worker::Worker{<:Any} -> worker.name == name, pm.workers)
    if isnothing(pos)
        throw(KeyError(name))
    end
    rmprocs(pm.workers[pos].pid)
    deleteat!(pm.workers, pos)
    pm
end

"""
```julia
create_workers(n::Int64, of::Type{Threaded}, names::Vector{String} = ...) -> ::Workers
```
This function is used to create new workers with the process type `of`. 
    New workers will be named with `names`. Not passing names for each worker will name workers 
    by PID.
```julia
create_workers(n::Int64, of::Type{Threaded})
create_workers(n::Int64, of::Type{Async})
```
```julia
workers = create_workers(3, ParametricProcesses.Async)
```
"""
function create_workers end

function create_workers(n::Int64, of::Type{Threaded}, 
    names::Vector{String} = ["$e" for e in 1:n])
    pids = Vector{Int64}()
    try
        pids = addprocs(n, exeflags=`--project=$(Base.active_project())`)
    catch e
        throw(ProcessError("could not start $n workers.", Threaded))
    end
    Vector{Worker{<:Any}}([Worker{of}(names[e], pid) for (e, pid) in enumerate(pids)])
end

function create_workers(n::Int64, of::Type{Async}, names::Vector{String} = ["$e" for e in 1:n])
    Vector{Worker{<:Any}}([Worker{Async}(name, rand(1000:3000)) for (name, x) in zip(names, 1:n)])
end

"""
```julia
add_workers!(pm::ProcessManager, n::Int64, of::Type{<:Process} = Threaded, names::String ...)
```
Add workers adds workers to a `ProcessManager`. 
The `ProcessManager` can be created with or without workers. `add_workers!` is a 
quick way to add `Workers` of any `Process` type to an existing aggregation of 
`Workers`.
```julia
pm = processes(2)
# 2 workers, three total processes (including `Main`)
add_workers!(pm, 2)
# now 4 workers, process id's 2-6
```
"""
function add_workers!(pm::AbstractProcessManager, n::Int64, of::Type{<:Process} = Threaded, names::String ...)
    workers = Vector{Worker{<:Any}}()
    name_n = length(names)
    if name_n == 0
        workers = create_workers(n, of)
    elseif name_n != n
        throw(ProcessError("not enough names provided for all workers.", Threaded))
    else
        workers = create_workers(n, of, [name for name in names])
    end
    pm.workers = vcat(pm.workers, workers)
    pm
end

"""
```julia
processes(n::Int64, of::Type{<:Process} = Threaded, names::String ...) -> ::ProcessManager
```
Creates `Workers` inside of a `ProcessManager` with the `Process` type `of`.
```julia
myprocs = processes(5)
2 |Threaded process: 1 (inactive)
3 |Threaded process: 2 (inactive)
4 |Threaded process: 3 (inactive)
5 |Threaded process: 4 (inactive)
6 |Threaded process: 5 (inactive)
```
"""
function processes(n::Int64, of::Type{<:Process} = Threaded, names::String ...)
    workers = Vector{Worker{<:Any}}()
    name_n = length(names)
    if name_n == 0
        workers = create_workers(n, of)
    elseif name_n != n
        throw(ProcessError("not enough names provided for all workers.", of))
    else
        workers = create_workers(n, of, [name for name in names])
    end
    ProcessManager(workers)
end

"""
```julia
worker_pids(pm::ProcessManager) -> ::Vector{Int64}
```
Gives the pid of each `Worker` in a `ProcessManager`'s `Workers` in the 
form of a `Vector{Int64}`.
```julia
pm = processes(3)

worker_pids(pm)
[2, 3, 4]
```
"""
worker_pids(pm::AbstractProcessManager) = [w.pid for w in pm.workers]

worker_pids(pm::AbstractProcessManager, type::Type{<:Process} ...) = begin
    pids = Vector{Int64}()
    for worker in pm.workers
        if typeof(worker).parameters[1] in type
            push!(pids, worker.pid)
        end
    end
    return(pids)::Vector{Int64}
end

"""
```julia
waitfor(pm::ProcessManager, pids::Any ...) -> ::Vector{Any}
waitfor(pm::ProcessManager) -> ::Vector{<:Any}
waitfor(f::Function, pm::ProcessManager, pids::Any ...) -> ::Vector{<:Any}
```
Stalls the main thread process to wait for all pids provided to `pids`. 
Will return a `Vector{Any}` containing the completed returns for each `Worker`. Providing 
    no pids will `waitfor` all busy workers. Using `waitfor(f::Function, ...)` will run `f` 
    after `pids` are complete.
```julia
pm = processes(4)

jb = new_job() do 
    sleep(10)
    @info "hello world!"
    return 55
end

assign!(pm, 2, jb)

ret = waitfor(pm, 2); println("worker 2 completed, it returned: ", ret[1])

# From worker 2:	[ Info: hello world!
# worker 2 completed, it returned: 55
```
"""
function waitfor(pm::ProcessManager, pids::Any ...)
    workers = [pm[pid] for pid in pids]
    @sync while true
        next = findfirst(w -> w.active == true, workers)
        if isnothing(next)
            break
        end
        wait(workers[next].task)
        workers[next].active = false
    end
    [pm[pid].ret for pid in pids]
end

waitfor(f::Function, pm::ProcessManager, pids::Any ...) = begin
    ret = waitfor(pm, pids ...)
    f(ret)
end

function waitfor(pm::ProcessManager)
    workers = filter(w -> w.active, pm.workers)
    if length(workers) == 0
        return(Vector{Any}())
    end
    while true
        next = findfirst(w -> w.active == true, workers)
        if isnothing(next)
            break
        end
        wait(workers[next].task)
    end
    [worker.pid for worker in workers]
end

"""
```julia
get_return!(pm::ProcessManager, pids::Any ...) -> ::Vector{<:Any}
```
Gets the return of all the workers with the pids of `pids` from `pm`, the `ProcessManager`. Note that 
`waitfor` will also give the return of each `Worker` it waits for. `get_return!` is used to grab the `ret` return 
from each `Worker` without waiting for the process to stop. This means that the return may remain unchanged. In the 
    following example, `get_return!` is essentially redundant, as we could simply call `waitfor` and anticipate a return. 
    However, we probably usually want to make sure a task is done before trying to get the return. This can be monitored with 
    the `Worker.active` field.
```julia
myprocs = processes(4)
jb = new_job(+, 5, 5)
assign!(myprocs, 2, jb)
waitfor(pm, 2); x = get_return!(pm, 2)[1]

assign!(myprocs, 2, jb)
x2 = waitfor(myprocs, 2)
```
"""
function get_return!(pm::ProcessManager, pids::Any ...)
    [pm[pid].ret for pid in pids]
end

put!(w::Worker{<:Any}, vals ...) = begin
    channel = RemoteChannel(w.pid)
    put!(channel, vals ...)
end

"""
```julia
put!(pm::ProcessManager, pids::Vector{Int64}, vals ...) -> ::Nothing
```
Puts different objects directly into a `Worker`, defines them on that thread's `Main`.
```julia
myprocs = processes(4)
message = "hello"
put!(myprocs, 2, message)
jb = new_job() do 
    println(message)
end

assign!(myprocs, 2, jb)

From worker 2:	hello
```
"""
function put!(pm::AbstractProcessManager, pids::Vector{Int64}, vals ...)
    for pid in pids
        channel = RemoteChannel(pid)
        put!(channel, vals ...)
    end
end

function put!(pm::AbstractProcessManager, vals ...)
    for w in pm.workers
        pid = w.pid
        channel = RemoteChannel(pid)
        put!(channel, vals ...)
    end
end

put!(pid::Integer, pm::AbstractProcessManager, vals ...) = begin
    channel = RemoteChannel(pid)
    put!(channel, vals ...)
end

"""
```julia
assign!(...; sync::Bool = false)
```
`assign!` is used to distribute tasks to workers directly. This 
culminates in two forms; `assign!` is used to assign a worker directly to 
its job using its process type and it is also used to `assign!` a process 
manager's workers to jobs.
```julia
# used to assign workers directly:
assign!(assigned_worker::Worker{Threaded}, job::AbstractJob)
assign!(f::Function, assigned_worker::Worker{:Threaded}, job::AbstractJob)
# used to assign via a `ProcessManager`:
   #   vvv does `f` on completion of `jobs`.
assign!(f::Function, pm::ProcessManager, pid::Any, jobs::AbstractJob ...)

assign!(pm::ProcessManager, pid::Any, jobs::AbstractJob ...)
```
- See also: `processes`, `distribute!`, `waitfor`, `put!`, `new_job`, `assign_open!`
---
```julia
procs = processes(5)

jb1 = new_job(println, "hello world!")
jb2 = new_job() do
    sleep(5)
    println("job 2")
jb3 = new_job() do 
    sleep(5)
    println("job 3")
end

assign!(procs, 2, jb2)
```
"""
function assign! end

function assign!(assigned_worker::Worker{Threaded}, job::AbstractJob; sync::Bool = false)
    if ~(assigned_worker.active)
        if sync
            @sync assigned_task = remotecall(job.f, assigned_worker.pid, job.args ...; job.kwargs ...)
        else
            assigned_task = remotecall(job.f, assigned_worker.pid, job.args ...; job.kwargs ...)
        end
        assigned_worker.task = assigned_task
        assigned_worker.active = true
        if sync
            @sync begin
                yield()
                wait(assigned_task)
                assigned_worker.ret = fetch(assigned_task)
                assigned_worker.active = false
            end
        else
            @async begin
                yield()
                wait(assigned_task)
                assigned_worker.ret = fetch(assigned_task)
                assigned_worker.active = false
            end
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

function assign!(assigned_worker::Worker{Async}, job::AbstractJob; sync::Bool = false)
    assigned_worker.active = true
    if sync
        job.f(job.args ...; job.keyargs ...)
        assigned_worker.active = false
        return
    end
    assigned_worker.task = @async begin
        job.f(job.args ...; job.keyargs ...)
        assigned_worker.active = false
    end
end

function assign!(f::Function, assigned_worker::Worker{Threaded}, job::AbstractJob; kargs ...)
    if ~(assigned_worker.active)
        assigned_task = remotecall(job.f, assigned_worker.pid, job.args ...; job.kwargs ...)
        assigned_worker.task = assigned_task
        assigned_worker.active = true
        @async begin
            wait(assigned_task)
            assigned_worker.ret = fetch(assigned_task)
            assigned_worker.active = false
        end
        return assigned_worker.pid
    end
    @async begin
        wait(assigned_worker.task)
        sleep(1)
        assign!(f, assigned_worker, job; kargs ...)
    end
    assigned_worker.pid
end

function assign!(f::Function, pm::AbstractProcessManager, pid::Any, jobs::AbstractJob ...; keyargs ...)
   [assign!(f, pm[pid], job; keyargs ...) for job in jobs]
end

function assign!(pm::AbstractProcessManager, pid::Any, jobs::AbstractJob ...; keyargs ...)

    [assign!(pm[pid], job; keyargs ...) for job in jobs]
end

"""
```julia
assign_open!(pm::ProcessManager, job::AbstractJob ...; ; not::Process = Async, sync::Bool = false) -> ::Int64
```
Assigns a single `AbstractJob` to an open worker. If no open workers are available, `distribute!` will be called.
- See also: `processes`, `assign!`, `new_job`, `waitfor`, `put!`, `distribute!`
```julia
using ParametricProcesses

procs = processes(5)

jb1 = new_job(println, "hello world!")
jb2 = new_job() do
    sleep(5)
    println("job 2")
jb3 = new_job() do 
    sleep(5)
    println("job 3")
end
```
"""
function assign_open!(pm::AbstractProcessManager, job::AbstractJob ...; not::Type{<:Process} = Async, 
    sync::Bool = false)
    ws = pm.workers
    ws = filter(w -> typeof(w) != Worker{not}, ws)
    open = findfirst(w -> ~(w.active), ws)
    if ~(isnothing(open))
        w = ws[open]
        [assign!(w, j, sync = sync) for j in job]
        return([w.pid])
    end
    distribute!(pm, job ..., not = not)
end

"""
```julia
distribute!(pm::ProcessManager, ..., jobs::AbstractJob ...; not::Process = Async, sync::Bool = false) -> ::Vector{Int64}
```
The `distribute!` Function will distribute jobs amongst all workers or amongst 
the provided workers.
```julia
# distribute to all available workers
distribute!(pm::ProcessManager, jobs::AbstractJob ...)
# distribute only to certain workers:
distribute!(pm::ProcessManager, worker_pids::Vector{Int64}, jobs::AbstractJob ...)
# distribute a percentage of workers:
distribute!(pm::ProcessManager, percentage::Float64, jobs::AbstractJob ...)
```
- See also: `processes`, `assign!`, `new_job`, `waitfor`, `put!`, `distribute_open!`
```julia
using ParametricProcesses

procs = processes(5)

jb1 = new_job(println, "hello world!")
jb2 = new_job() do
    sleep(5)
    println("job 2")
jb3 = new_job() do 
    sleep(5)
    println("job 3")
end

distribute!(pm, jb1, jb2, jb3)

# distribute to only `1` and `2`
distribute!(pm, [1, 2], jb2, jb3, jb3, jb2, jb1)
```
"""
function distribute! end

function distribute!(pm::AbstractProcessManager, worker_pids::Vector{Int64}, jobs::AbstractJob ...; not = Async, sync::Bool = false)
    ws = filter(w -> typeof(w) != Worker{not}, [pm[pid] for pid in worker_pids])
    at::Int64 = 1
    stop::Int64 = length(ws) + 1
    [begin
        worker = ws[at]
        assign!(worker, job, sync = sync)
        at += 1
        if at == stop
            at = 1
        end
        if ~(worker.pid in worker_pids)
            push!(worker_pids, worker.pid)
        end
    end for job in jobs]
    worker_pids::Vector{Int64}
end

distribute!(pm::AbstractProcessManager, jobs::AbstractJob ...; not = Async) = distribute!(pm, [w.pid for w in pm.workers], jobs ...; not = not)

function distribute!(pm::AbstractProcessManager, percentage::Float64, jobs::AbstractJob ...; not = Async, keyargs ...)
    total_workers = length(pm.workers)
    num_workers = round(Int, percentage * total_workers)
    ws = [pm.workers[rand(1:total_workers)] for e in num_workers]
    distribute!(pm, (w.pid for w in ws) ...; not = not, keyargs ...)
end

"""
```julia
distribute_open!(pm::AbstractProcessManager, job::AbstractJob ...; not::Process = Async, sync::Bool = false) -> ::Vector{Int64}
```

- See also: `processes`, `assign!`, `new_job`, `waitfor`, `put!`, `distribute!`, `Worker`, `ProcessManager`
"""

function distribute_open!(pm::AbstractProcessManager, jobs::AbstractJob ...; not = Async, keyargs ...)
    open = filter(w::AbstractWorker -> ~(w.active), pm.workers)
    distribute!(pm, [w.pid for w in open], jobs ...; not = not; keyargs ...)
end



export processes, add_workers!, assign!, distribute!, Worker, ProcessManager, worker_pids, Workers, distribute_open!, assign_open!
export Threaded, new_job, @everywhere, get_return!, waitfor, Async, RemoteChannel, @distributed, @spawnat
end # module
