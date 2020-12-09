## This file contains utilities for scraping logs from buildbot
export BuildbotDatasource

struct BuildbotDatasource
    # Base URL this buildbot instance's API endpoints are located at.
    # Typically https://build.julialang.org/api/v2
    api_base::String

    # Mapping of builder name to ID, filled in by `load_builders!()`
    builders::Dict{String,Int}

    # Default constructor method to initialize with defaults
    # Automatically loads its builders upon construction, they
    # can be refreshed by a future `load_builders!()` invocation.
    function BuildbotDatasource(api_base::String = "https://build.julialang.org/api/v2")
        ds = new(api_base, Dict{String,Int}())
        load_builders!(ds)
        return ds
    end
end

"""
    load_builders!(ds::BuildbotDatasource)

Load the mapping of builder name (e.g. `package_linux64`) to its builder ID (an integer).
This should be fairly stable, but can change if the buildbot configuration gets changed.
This will be automatically called when a new `BuildbotDatasource` is constructed, but you
can manually refresh it by calling `load_builders!(ds)` directly.
"""
function load_builders!(ds::BuildbotDatasource)
    builders_json = get_json("$(ds.api_base)/builders")
    
    # We want to grab all builders that are a `package_*` or `tester_*` builder
    builders = filter(builders_json[:builders]) do builder
        return startswith(builder.name, "package_") ||
               startswith(builder.name, "tester_")
    end

    # Empty any previous `builders` that existed within the `BuildbotDatasource`
    empty!(ds.builders)

    # Load in our newly-gotten list of builders
    for builder in builders
        ds.builders[builder.name] = builder.builderid
    end
    return ds
end

"""
    get_builder_builds_list(ds::BuildbotDatasource, builder_name::String)
    get_builder_builds_list(ds::BuildbotDatasource, builder_id::Int)

Given a builder name or ID, return a sorted list of all completed builds.
"""
function get_builder_builds_list(ds::BuildbotDatasource, builder_name::String)
    return get_builder_builds_list(ds, ds.builders[builder_name])
end
function get_builder_builds_list(ds::BuildbotDatasource, builder_id::Int64)
    builders_json = get_json("$(ds.api_base)/builders/$(builder_id)/builds")
    # Only look at complete builds
    return sort(Int64[b.buildid for b in builders_json.builds if b.complete])
end

"""
    get_all_builder_builds(ds::BuildbotDatasource)

Get list of all build IDs that are stored within this `BuildbotDatasource`.
"""
function get_all_builder_builds(ds::BuildbotDatasource)
    builds = Dict{String,Vector{Int64}}()
    for (builder_name, builder_id) in ds.builders
        builds[builder_name] = get_builder_builds_list(ds, builder_id)
    end
    return builds
end

"""
    get_build_steps_list(ds::BuildbotDatasource, build_id::Int64)

Given a build ID, return the list of steps that we should download logs for.
"""
function get_build_steps_list(ds::BuildbotDatasource, build_id::Int64)
    steps_json = get_json("$(ds.api_base)/builds/$(build_id)/steps")
    return sort(Int64[s.number for s in steps_json.steps if s.complete])
end

function get_log_contents(ds::BuildbotDatasource, build_id::Int64, step::Int64)
    logs_json = get_json("$(ds.api_base)/builds/$(build_id)/steps/$(step)/logs")
    log_ids = Int64[l.logid for l in logs_json.logs if l.complete]

    content = ""
    for log_id in log_ids
        contents_json = get_json("$(ds.api_base)/logs/$(log_id)/contents")
        for chunk in contents_json.logchunks
            # Buildbot tags all lines with what stream it came from;
            #  - i for stdin
            #  - o for stdout
            #  - e for stderr
            #  - h for header (buildbot-generated textual content)
            # For now, we're just going to strip all these out.
            content = string(content, join([l[2:end] for l in split(chunk.content, "\n")], "\n"))
        end
    end
    return content
end

function download_logs(ds::BuildbotDatasource,
                       output_dir::String;
                       tail::Int64 = 100,
                       verbose::Bool = false)
    # We will store logs partitioned by `$builder_name/$build/$step.log`
    if verbose
        @info("Enumerating builders...")
    end
    builder_builds = get_all_builder_builds(ds)
    if verbose
        @info("Found $(length(keys(builder_builds))) builders")
    end

    for builder_name in keys(builder_builds)
        # Limit to only the last `tail` logs for each builder
        for build_id in builder_builds[builder_name][max(end-tail+1, 1):end]
            build_logdir = joinpath(output_dir, builder_name, string(build_id))
            mkpath(build_logdir)
            for step_id in get_build_steps_list(ds, build_id)
                log_filename = joinpath(build_logdir, "$(step_id).log")
                if isfile(log_filename)
                    continue
                end
                if verbose
                    @info("Downloading #$(build_id).$(step_id)")
                end

                data = get_log_contents(ds, build_id, step_id)
                open(log_filename, "w") do io
                    write(io, data)
                end
            end
        end
    end
end
