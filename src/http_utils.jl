function get_json(url::String; retries=3)
    r = HTTP.get(url)
    if r.status != 200
        if retries > 0
            return get_json(url; retries=retries-1)
        end
        error("Unable to GET $(url)")
    end
    return JSON3.read(r.body)
end
