## This file contains utilities for scraping logs from buildbot

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
function get_builder_builds_list(ds::BuildbotDatasource, builder_id::Int)
    builders_json = get_json("$(ds.api_base)/builders/$(builder_id)/builds")
    # Only look at complete builds
    return sort(Int[b.buildid for b in builders_json.builds if b.complete])
end
