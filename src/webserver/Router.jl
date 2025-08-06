using JSON


function http_router_for(session::ServerSession)
    router = HTTP.Router(default_404_response)
    security = session.options.security
    
    function create_serve_onefile(path)
        return request::HTTP.Request -> asset_response(normpath(path))
    end

    """
    Helper function to handle user-specific operations 
    and execute them in user's folder
    """
    function with_user_working_directory(user, operation)
        """Execute operation in user's notebooks directory"""
        @info "User object type: $(typeof(user))"
        @info "User fields: $(fieldnames(typeof(user)))"
        # Check if user has home_directory field
        if !hasfield(typeof(user), :home_directory)
            @error "User struct missing home_directory field. Available fields: $(fieldnames(typeof(user)))"
            # Fallback - construct home directory from username
            user_directory = joinpath(pwd(), "pluto_users", user.username)
        else
            user_directory = user.home_directory
        end
        
        @info "Switching to user directory: $user_directory"
        user_notebooks_dir = joinpath(user_directory, "notebooks")
        original_pwd = pwd()
        
        try
            cd(user_notebooks_dir)
            @info "Executing operation in user directory: $(pwd())"
            return operation()
        finally
            cd(original_pwd)
            @info "Restored working directory to: $(pwd())"
        end
    end

    # Login system routes
    HTTP.register!(router, "GET", "/login", create_serve_onefile(project_relative_path(frontend_directory(), "login.html")))
    
    # Authentication route
    function serve_authenticate(request::HTTP.Request)
        try
            body_str = String(request.body)
            params = Dict{String,String}()
            if !isempty(body_str)
                for pair in split(body_str, '&')
                    if contains(pair, '=')
                        key_val = split(pair, '=', limit=2)
                        if length(key_val) == 2
                            key = HTTP.unescapeuri(key_val[1])
                            val = HTTP.unescapeuri(key_val[2])
                            params[key] = val
                        end
                    end
                end
            end
            
            username = get(params, "username", "")
            password = get(params, "password", "")
            
            user = authenticate_user(username, password)
            if user !== nothing
                ip_address = HTTP.header(request, "X-Forwarded-For", 
                                       HTTP.header(request, "Remote-Addr", "unknown"))
                session_token = create_user_session(user, ip_address)
                
                response = HTTP.Response(302)
                uri = HTTP.URI(request.target)
                query = HTTP.queryparams(uri)
                redirect_path = get(query, "redirect", "/user/$(user.username)/")
                
                HTTP.setheader(response, "Location" => redirect_path)
                add_set_login_cookie!(response, session_token)
                @info "User $(user.username) logged in successfully"
                response
            else
                response = HTTP.Response(302)
                error_msg = HTTP.escapeuri("Invalid username or password")
                HTTP.setheader(response, "Location" => "./login?error=$error_msg")
                response
            end
        catch e
            @warn "Authentication failed" exception = (e, catch_backtrace())
            error_response(500, "Authentication Error", "Login failed", sprint(showerror, e))
        end
    end
    HTTP.register!(router, "POST", "/authenticate", serve_authenticate)
    
    # Logout route
    function serve_logout(request::HTTP.Request)
        response = HTTP.Response(302)
        HTTP.setheader(response, "Location" => "./login")
        HTTP.setheader(response, "Set-Cookie" => "pluto_user_session=; path=/; expires=Thu, 01 Jan 1970 00:00:00 GMT")
        response
    end
    HTTP.register!(router, "GET", "/logout", serve_logout)
    HTTP.register!(router, "POST", "/logout", serve_logout)

    # Helper function to create HTML with base tag
    function create_serve_html(html_path::String)
        return function(request::HTTP.Request)
            html_content = read(html_path, String)
            base_tag = "<base href=\"/\">"
            
            if contains(html_content, "<head>")
                html_content = replace(html_content, "<head>" => "<head>\n    $base_tag")
            elseif contains(html_content, r"<head[^>]*>"i)
                html_content = replace(html_content, r"<head[^>]*>"i => m -> "$m\n    $base_tag")
            end
            
            response = HTTP.Response(200, html_content)
            HTTP.setheader(response, "Content-Type" => "text/html; charset=utf-8")
            return response
        end
    end

    # Root redirect - redirect to user area if authenticated, otherwise to login
    function serve_root(request::HTTP.Request)
        user = user_from_context(request)
        if user !== nothing
            response = HTTP.Response(302)
            HTTP.setheader(response, "Location" => "/user/$(user.username)/")
            return response
        else
            response = HTTP.Response(302)
            HTTP.setheader(response, "Location" => "./login")
            return response
        end
    end
    HTTP.register!(router, "GET", "/", serve_root)

    # LEGACY ROUTES - These routes work within user context but use the old paths
    # This ensures frontend compatibility while maintaining multi-user security

    # Legacy main routes - redirect to user-specific versions or serve directly for authenticated users
    function serve_main_edit(request::HTTP.Request)
        user = user_from_context(request)
        if user === nothing
            response = HTTP.Response(302)
            HTTP.setheader(response, "Location" => "./login")
            return response
        end
        return create_serve_html(project_relative_path(frontend_directory(), "editor.html"))(request)
    end
    HTTP.register!(router, "GET", "/edit", serve_main_edit)

    # Helper function for notebook operations with user context
    function try_launch_notebook_response(
        action::Function, path_or_url::AbstractString; 
        as_redirect=true,
        title="", advice="", home_url="./", 
        action_kwargs...
    )
        try
            nb = action(session, path_or_url; action_kwargs...)
            
            # Get user from context and associate notebook
            user = user_from_context(request)  # This should be passed as parameter
            if user !== nothing
                add_notebook_to_user(session, user.id, nb.notebook_id)
            end
            
            notebook_response(nb; home_url, as_redirect)
        catch e
            if e isa SessionActions.NotebookIsRunningException
                notebook_response(e.notebook; home_url, as_redirect)
            else
                error_response(500, title, advice, sprint(showerror, e, stacktrace(catch_backtrace())))
            end
        end
    end

    # Legacy /new route
    function serve_newfile(request::HTTP.Request)
        user = user_from_context(request)
        if user === nothing
            return HTTP.Response(403, "Authentication required")
        end

        @info user.home_directory

        # Set user-specific notebook directory
        original_notebook_dir = session.options.server.notebook
        session.options.server.notebook = joinpath(user.home_directory, "notebooks")
        
        try
            result = with_user_working_directory(user, () -> begin
                nb = SessionActions.new(session)
                add_notebook_to_user(session, user.id, nb.notebook_id)
                return notebook_response(nb; as_redirect=(request.method == "GET"))
        end)
        return result
            # end
            # return result
        catch e
            if e isa SessionActions.NotebookIsRunningException
                notebook_response(e.notebook; as_redirect=(request.method == "GET"))
            else
                error_response(500, "Failed to create notebook", "Please try again", sprint(showerror, e, stacktrace(catch_backtrace())))
            end
        finally
            session.options.server.notebook = original_notebook_dir
        end
    end
    HTTP.register!(router, "GET", "/new", serve_newfile)
    HTTP.register!(router, "POST", "/new", serve_newfile)

    # Legacy /open route
    function serve_openfile(request::HTTP.Request)
        user = user_from_context(request)
        if user === nothing
            return HTTP.Response(403, "Authentication required")
        end
        
        try
            uri = HTTP.URI(request.target)
            query = HTTP.queryparams(uri)
            as_sample = haskey(query, "as_sample")
            execution_allowed = haskey(query, "execution_allowed")
            
            if haskey(query, "path")
                path = tamepath(maybe_convert_path_to_wsl(query["path"]))
                
                # Ensure path is within user's directory (unless it's a sample)
                if !as_sample && !startswith(path, user.home_directory)
                    return error_response(403, "Access Denied", "You can only access notebooks in your directory.")
                end
                
                if isfile(path)
                    nb = SessionActions.open(session, path; 
                        execution_allowed,
                        as_sample, 
                        risky_file_source=nothing
                    )
                    add_notebook_to_user(session, user.id, nb.notebook_id)
                    return notebook_response(nb; as_redirect=(request.method == "GET"))
                else
                    return error_response(404, "Can't find a file here", "Please check whether <code>$(htmlesc(path))</code> exists.")
                end
            elseif haskey(query, "url")
                url = query["url"]
                nb = SessionActions.open_url(session, url;
                    execution_allowed,
                    as_sample, 
                    risky_file_source=url
                )
                add_notebook_to_user(session, user.id, nb.notebook_id)
                return notebook_response(nb; as_redirect=(request.method == "GET"))
            else
                maybe_notebook_response = try_event_call(session, CustomLaunchEvent(query, request, try_launch_notebook_response))
                isnothing(maybe_notebook_response) && return error("Empty request")
                return maybe_notebook_response
            end
        catch e
            if e isa SessionActions.NotebookIsRunningException
                return notebook_response(e.notebook; as_redirect=(request.method == "GET"))
            else
                return error_response(400, "Bad query", "Please <a href='https://github.com/fonsp/Pluto.jl/issues'>report this error</a>!", sprint(showerror, e, stacktrace(catch_backtrace())))
            end
        end
    end
    HTTP.register!(router, "GET", "/open", serve_openfile)
    HTTP.register!(router, "POST", "/open", serve_openfile)

    # Legacy /shutdown route
    function serve_shutdown(request::HTTP.Request)
        user = user_from_context(request)
        if user === nothing
            return HTTP.Response(403, "Authentication required")
        end
        
        notebook = notebook_from_uri(request)
        
        # Check if user can access this notebook
        if !user_can_access_notebook(session, user.id, notebook.notebook_id)
            return HTTP.Response(403, "Access denied")
        end
        
        SessionActions.shutdown(session, notebook)
        remove_notebook_from_user(session, user.id, notebook.notebook_id)
        return HTTP.Response(200)
    end
    HTTP.register!(router, "GET", "/shutdown", serve_shutdown)
    HTTP.register!(router, "POST", "/shutdown", serve_shutdown)

    # Legacy /move route
    function serve_move(request::HTTP.Request)
        user = user_from_context(request)
        if user === nothing
            return HTTP.Response(403, "Authentication required")
        end
        
        uri = HTTP.URI(request.target)        
        query = HTTP.queryparams(uri)
        notebook = notebook_from_uri(request)
        newpath = query["newpath"]
        
        # Check if user can access this notebook
        if !user_can_access_notebook(session, user.id, notebook.notebook_id)
            return HTTP.Response(403, "Access denied")
        end
        
        # Ensure new path is within user's directory
        if !startswith(newpath, user.home_directory)
            return error_response(403, "Access Denied", "You can only move notebooks within your directory.")
        end
        
        try
            SessionActions.move(session, notebook, newpath)
            HTTP.Response(200, notebook.path)
        catch e
            error_response(400, "Bad query", "Please <a href='https://github.com/fonsp/Pluto.jl/issues'>report this error</a>!", sprint(showerror, e, stacktrace(catch_backtrace())))
        end
    end
    HTTP.register!(router, "GET", "/move", serve_move)
    HTTP.register!(router, "POST", "/move", serve_move)

    # Legacy /notebooklist route - return only user's notebooks
    function serve_notebooklist(request::HTTP.Request)
        user = user_from_context(request)
        if user === nothing
            return HTTP.Response(200, pack(Dict{String,String}()))
        end
        
        user_notebooks = get_user_notebooks(session, user.id)
        notebook_dict = Dict(string(nb.notebook_id) => nb.path for nb in user_notebooks)
        return HTTP.Response(200, pack(notebook_dict))
    end
    HTTP.register!(router, "GET", "/notebooklist", serve_notebooklist)

    # Utility function for notebook URI parsing
    notebook_from_uri(request) = let
        uri = HTTP.URI(request.target)        
        query = HTTP.queryparams(uri)
        id = UUID(query["id"])
        session.notebooks[id]
    end
    
    # New route to return all notebooks in user's folder as JSON
    function serve_user_notebooks_json(request::HTTP.Request)
        user = user_from_context(request)
        if user === nothing
            return HTTP.Response(401, JSON.json(Dict("error" => "Authentication required")))
        end
        
        try
            # Get user's notebooks directory
            user_notebooks_dir = joinpath(user.home_directory, "notebooks")
            
            if !isdir(user_notebooks_dir)
                return HTTP.Response(200, JSON.json(Dict(
                    "notebooks" => [],
                    "user" => user.username,
                    "message" => "Notebooks directory not found"
                )))
            end
            
            notebooks = []
            
            # Recursively find all .jl files in the notebooks directory
            function scan_directory(dir_path, relative_path="")
                for item in readdir(dir_path, join=false)
                    item_path = joinpath(dir_path, item)
                    item_relative = isempty(relative_path) ? item : joinpath(relative_path, item)
                    
                    if isdir(item_path)
                        # Recursively scan subdirectories
                        scan_directory(item_path, item_relative)
                    elseif isfile(item_path) && endswith(lowercase(item), ".jl")
                        # Check if it's a Pluto notebook by looking for the header
                        try
                            file_content = read(item_path, String)
                            if startswith(file_content, "### A Pluto.jl notebook ###")
                                # Try to find existing notebook in session
                                existing_notebook = nothing
                                notebook_id = nothing
                                process_status = "not_running"
                                
                                # Search for this notebook in the current session
                                for (id, nb) in session.notebooks
                                    if nb.path == item_path
                                        existing_notebook = nb
                                        notebook_id = string(id)
                                        process_status = "running"
                                        break
                                    end
                                end
                                
                                # # If not found in session, generate a consistent ID based on file path
                                # if notebook_id === nothing
                                #     notebook_id = string(hash(item_path))
                                # end
                                
                                # Get file info
                                file_stat = stat(item_path)
                                
                                push!(notebooks, Dict(
                                    "notebook_id" => notebook_id,
                                    "name" => item,
                                    "shortpath" => item_relative,
                                    "process_status" => process_status,
                                    "in_temp_dir" => false, # User files are not in temp
                                    "size" => file_stat.size,
                                    "modified" => string(Dates.unix2datetime(file_stat.mtime)),
                                    "is_running" => existing_notebook !== nothing
                                ))
                            end
                        catch e
                            @warn "Error reading file $item_path: $e"
                            # Still add it as a potential notebook file
                            push!(notebooks, Dict(
                                "notebook_id" => nothing,
                                "name" => item,
                                "shortpath" => item_relative,
                                "process_status" => "unknown",
                                "in_temp_dir" => false,
                                "size" => 0,
                                "modified" => "",
                                "is_running" => false,
                                "error" => "Could not read file"
                            ))
                        end
                    end
                end
            end
            
            # Scan the user's notebooks directory
            scan_directory(user_notebooks_dir)
            
            # Sort notebooks by name
            sort!(notebooks, by = nb -> nb["name"])
            
            response_data = Dict(
                "notebooks" => notebooks,
                "user" => user.username,
                "count" => length(notebooks),
                "timestamp" => string(now())
            )
            
            response = HTTP.Response(200, JSON.json(response_data))
            HTTP.setheader(response, "Content-Type" => "application/json; charset=utf-8")
            return response
            
        catch e
            @error "Error scanning user notebooks directory" exception = (e, catch_backtrace())
            error_response = Dict(
                "error" => "Failed to scan notebooks directory",
                "message" => string(e),
                "user" => user.username
            )
            response = HTTP.Response(500, JSON.json(error_response))
            HTTP.setheader(response, "Content-Type" => "application/json; charset=utf-8")
            return response
        end
    end
    HTTP.register!(router, "GET", "/api/notebooks", serve_user_notebooks_json)

    # Legacy file serving routes
    function serve_notebookfile(request::HTTP.Request)
        user = user_from_context(request)
        if user === nothing
            return HTTP.Response(403, "Authentication required")
        end
        
        try
            notebook = notebook_from_uri(request)
            if !user_can_access_notebook(session, user.id, notebook.notebook_id)
                return HTTP.Response(403, "Access denied")
            end
            
            response = HTTP.Response(200, sprint(save_notebook, notebook))
            HTTP.setheader(response, "Content-Type" => "text/julia; charset=utf-8")
            HTTP.setheader(response, "Content-Disposition" => "inline; filename=\"$(basename(notebook.path))\"")
            response
        catch e
            return error_response(400, "Bad query", "Please <a href='https://github.com/fonsp/Pluto.jl/issues'>report this error</a>!", sprint(showerror, e, stacktrace(catch_backtrace())))
        end
    end
    HTTP.register!(router, "GET", "/notebookfile", serve_notebookfile)

    function serve_statefile(request::HTTP.Request)
        user = user_from_context(request)
        if user === nothing
            return HTTP.Response(403, "Authentication required")
        end
        
        try
            notebook = notebook_from_uri(request)
            if !user_can_access_notebook(session, user.id, notebook.notebook_id)
                return HTTP.Response(403, "Access denied")
            end
            
            response = HTTP.Response(200, Pluto.pack(Pluto.notebook_to_js(notebook)))
            HTTP.setheader(response, "Content-Type" => "application/octet-stream")
            HTTP.setheader(response, "Content-Disposition" => "attachment; filename=\"$(without_pluto_file_extension(basename(notebook.path))).plutostate\"")
            response
        catch e
            return error_response(400, "Bad query", "Please <a href='https://github.com/fonsp/Pluto.jl/issues'>report this error</a>!", sprint(showerror, e, stacktrace(catch_backtrace())))
        end
    end
    HTTP.register!(router, "GET", "/statefile", serve_statefile)

    function serve_notebookexport(request::HTTP.Request)
        user = user_from_context(request)
        if user === nothing
            return HTTP.Response(403, "Authentication required")
        end
        
        try
            notebook = notebook_from_uri(request)
            if !user_can_access_notebook(session, user.id, notebook.notebook_id)
                return HTTP.Response(403, "Access denied")
            end
            
            response = HTTP.Response(200, generate_html(notebook))
            HTTP.setheader(response, "Content-Type" => "text/html; charset=utf-8")
            HTTP.setheader(response, "Content-Disposition" => "attachment; filename=\"$(without_pluto_file_extension(basename(notebook.path))).html\"")
            response
        catch e
            return error_response(400, "Bad query", "Please <a href='https://github.com/fonsp/Pluto.jl/issues'>report this error</a>!", sprint(showerror, e, stacktrace(catch_backtrace())))
        end
    end
    HTTP.register!(router, "GET", "/notebookexport", serve_notebookexport)
    
    function serve_notebookupload(request::HTTP.Request)
        user = user_from_context(request)
        if user === nothing
            return HTTP.Response(403, "Authentication required")
        end
        
        @info "Handling notebook upload for user: $(user.username)"
        uri = HTTP.URI(request.target)
        @info uri
        query = HTTP.queryparams(uri)
        @info "Query parameters: $(query)"

        save_path = with_user_working_directory(user, () -> begin 
            return SessionActions.save_upload(request.body; 
                filename_base=get(query, "name", nothing)
            )
        end
        ) 
        @info "File saved to: $save_path"

        try
            nb = SessionActions.open(session, save_path;
                execution_allowed=haskey(query, "execution_allowed"),
                as_sample=false,
                clear_frontmatter=haskey(query, "clear_frontmatter")
            )
            add_notebook_to_user(session, user.id, nb.notebook_id)
            return notebook_response(nb; as_redirect=false)
        catch e
            if e isa SessionActions.NotebookIsRunningException
                return notebook_response(e.notebook; as_redirect=false)
            else
                return error_response(400, "Failed to load notebook", "The contents could not be read as a Pluto notebook file.", sprint(showerror, e, stacktrace(catch_backtrace())))
            end
        end
    end
    HTTP.register!(router, "POST", "/notebookupload", serve_notebookupload)

    # Sample notebooks
    function serve_sample(request::HTTP.Request)
        user = user_from_context(request)
        if user === nothing
            return HTTP.Response(403, "Authentication required")
        end
        
        uri = HTTP.URI(request.target)
        sample_filename = split(HTTP.unescapeuri(uri.path), "sample/")[2]
        sample_path = project_relative_path("sample", sample_filename)
        
        try
            nb = SessionActions.open(session, sample_path; 
                as_redirect=(request.method == "GET"), 
                as_sample=true
            )
            add_notebook_to_user(session, user.id, nb.notebook_id)
            return notebook_response(nb; home_url="../", as_redirect=(request.method == "GET"))
        catch e
            if e isa SessionActions.NotebookIsRunningException
                return notebook_response(e.notebook; home_url="../", as_redirect=(request.method == "GET"))
            else
                return error_response(500, "Failed to load sample", "Please <a href='https://github.com/fonsp/Pluto.jl/issues'>report this error</a>!", sprint(showerror, e, stacktrace(catch_backtrace())))
            end
        end
    end
    HTTP.register!(router, "GET", "/sample/*", serve_sample)
    HTTP.register!(router, "POST", "/sample/*", serve_sample)

    # Standard utility routes
    HTTP.register!(router, "GET", "/ping", r -> HTTP.Response(200, "OK!"))
    HTTP.register!(router, "GET", "/possible_binder_token_please", r -> session.binder_token === nothing ? HTTP.Response(200,"") : HTTP.Response(200, session.binder_token))

    # USER-SPECIFIC ROUTES (for URL organization, but they redirect to main routes)
    function serve_user_home(request::HTTP.Request)
        user = user_from_context(request)
        if user === nothing
            response = HTTP.Response(302)
            HTTP.setheader(response, "Location" => "../login")
            return response
        end
        
        path_parts = split(HTTP.URI(request.target).path, '/')
        if length(path_parts) >= 3 && path_parts[2] == "user"
            username_from_url = path_parts[3]
            if user.username != username_from_url
                return HTTP.Response(403, "Access denied: You can only access your own notebooks")
            end
        end
        
        return create_serve_html(project_relative_path(frontend_directory(), "index.html"))(request)
    end
    
    function serve_user_edit(request::HTTP.Request)
        user = user_from_context(request)
        if user === nothing
            response = HTTP.Response(302)
            HTTP.setheader(response, "Location" => "../../login")
            return response
        end
        
        path_parts = split(HTTP.URI(request.target).path, '/')
        if length(path_parts) >= 3 && path_parts[2] == "user"
            username_from_url = path_parts[3]
            if user.username != username_from_url
                return HTTP.Response(403, "Access denied")
            end
        end
        
        return create_serve_html(project_relative_path(frontend_directory(), "editor.html"))(request)
    end

    # Register user-specific routes
    HTTP.register!(router, "GET", "/user/*/", serve_user_home)
    HTTP.register!(router, "GET", "/user/*/edit", serve_user_edit)

    # Asset serving - this is crucial for CSS/JS files
    function serve_asset(request::HTTP.Request)
        uri = HTTP.URI(request.target)
        filepath = project_relative_path(frontend_directory(), relpath(HTTP.unescapeuri(uri.path), "/"))
        asset_response(filepath; cacheable=should_cache(filepath))
    end
    HTTP.register!(router, "GET", "/**", serve_asset)
    HTTP.register!(router, "GET", "/favicon.ico", create_serve_onefile(project_relative_path(frontend_directory(allow_bundled=false), "img", "favicon.ico")))

    return scoped_router(session.options.server.base_url, router)
end


"""
    scoped_router(base_url::String, base_router::HTTP.Router)::HTTP.Router

Returns a new `HTTP.Router` which delegates all requests to `base_router` but with requests trimmed
so that they seem like they arrived at `/**` instead of `/\$base_url/**`.
"""
function scoped_router(base_url, base_router)
    base_url == "/" && return base_router

    @assert startswith(base_url, '/') "base_url \"$base_url\" should start with a '/'"
    @assert endswith(base_url, '/')  "base_url \"$base_url\" should end with a '/'"
    @assert !occursin('*', base_url) "'*' not allowed in base_url \"$base_url\" "

    function handler(request)
        request.target = request.target[length(base_url):end]
        return base_router(request)
    end

    router = HTTP.Router(base_router._404, base_router._405)
    HTTP.register!(router, base_url * "**", handler)
    HTTP.register!(router, base_url, handler)

    return router
end