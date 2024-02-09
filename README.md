<div align="center">
  <img src="https://github.com/ChifiSource/image_dump/blob/main/parametricprocesses/parproc.png" width="375"></img>
</div>

`ParametricProcesses` offers a parametric `Worker` type capable of facilitating multiple forms of parallel processing and high-level declarative `Distributed` worker management.
```julia
using Pkg; Pkg.add("ParametricProcesses")
# Unstable:
using Pkg; Pkg.add("ParametricProcesses", rev = "Unstable")
```
---
- [usage](#usage)
  -  [workers](#workers)
  -  [jobs](#jobs)
- [contributing](#contributing)
  - [adding workers](#extensions)
  - [contributing guidelines](#contributing-guidelines)
### usage
Before trying to use threaded `Workers` (`Workers{Threaded}`), make sure to start **julia with multiple threads**!
```julia
julia --threads 6
```
```julia
using ParametricProcesses
procs = processes(5)
x = 5
firstjob = new_job(x) do x::Int64
   for n in 1:x
       println("hello")
       sleep(2)
   end 
end
secondjob = new_job(x) do x::Int64
   sleep(1)
   for n in 1:x
       println("world")
       sleep(2)
   end 
end

distribute!(procs, firstjob, secondjob)
```
```julia
julia> distribute!(procs, firstjob, secondjob)
2-element Vector{Int64}:
 7
 8

julia>       From worker 7:	hello
      From worker 8:	world
      From worker 7:	hello
      From worker 8:	world
      From worker 7:	hello
      From worker 8:	world
      From worker 7:	hello
      From worker 8:	world
      From worker 7:	hello
      From worker 8:	world

```
##### workers
The *typical* `ParametricProcesses` workflow involves creating a process manager with workers, then creating jobs and distributing them amongst those workers using `assign!` and `distribute!`.  To get started, we can create a `ProcessManager` by using the `processes` Function. This `Function` will take an `Int64` and optionally, a `Process` type. The default process type will be `Threaded`, so ensure you have multiple threads.
```julia
procs = processes(5)
```
We can create a process manager with workers of any type using this same `Function`, `processes`.
```julia
async_procs = processes(2, Async)
```
`Workers` are held in the `w.Workers` field, we can also add workers directly, or create workers and `push!` them.
```julia

```
##### jobs


