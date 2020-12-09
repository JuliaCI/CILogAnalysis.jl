module CILogAnalysis
using HTTP, JSON3, Scratch
export download_logs

include("http_utils.jl")
include("datasources/buildbot.jl")

"""
    download_logs(sources;
                  output_dir = @get_scratch!("logs"),
                  tail = 100,
                  verbose = false)

Sync the last `tail` number of logs out to `output_dir` (defaults to a scratch space),
partitioned by each data source given (defaults to the official Julia build server).
"""
function download_logs(sources::Vector = [BuildbotDatasource()];
                       output_dir::String = @get_scratch!("logs"),
                       tail::Int64 = 100,
                       verbose::Bool = false)
    if verbose
        @info("Downloading the last $(tail) logs from $(length(sources)) source(s)")
    end
    for source in sources
        download_logs(source, joinpath(output_dir, string(typeof(source))); tail=tail, verbose=verbose)
    end
    return output_dir
end

end # module CILogAnalysis
