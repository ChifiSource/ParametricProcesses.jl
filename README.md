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
###### usage
```julia
using ParametricProcesses
procs = processes(5)
x = 5
firstjob = new_job(x) do num::Int64
    x += 5
end
secondjob = new_job(x) do num::Int64
    println(x)
end

distribute!(procs, firstjob, secondjob)
```
The *typical* `ParametricProcesses` workflow involves creating a process manager with workers, then creating jobs and distributing them amongst those workers using `assign!` and `distribute!`.  To get started, we can create a `ProcessManager` by using the `processes` Function. This `Function` will take an `Int64` and optionally, a `Process` type. The default process type will be `Threaded`, so ensure you have multiple threads.
```julia
procs = processes(5)
```
