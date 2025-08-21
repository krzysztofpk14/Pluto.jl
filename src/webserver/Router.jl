using JSON
using Genie


function http_router_for(session::ServerSession)
    router = HTTP.Router(default_404_response)
    security = session.options.security
    
    function create_serve_onefile(path)
        return request::HTTP.Request -> asset_response(normpath(path))
    end

    # ### Check Genie ###
    # function serve_genie(request::HTTP.Request)
    #     name = "Mark"
    #     return Genie.Renderer.Html.html("<h1>Welcome $(name)</h1>", layout = "<div><% @yield %></div>", name = "Adrian")
    # end
    # HTTP.register!(router, "GET", "/genie", serve_genie)

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


    function get_user_pod_ip(username::String, namespace::String="plutohub")::Union{String, Nothing}
        try
            # Get pods with user label
            result = read(`kubectl get pods -n $namespace -l user=$username -o jsonpath='{.items[0].status.podIP}'`, String)
            pod_ip = strip(result)
            
            if isempty(pod_ip)
                @warn "No pod IP found for user: $username"
                return nothing
            end
            
            @info "Found pod IP for user $username: $pod_ip"
            return pod_ip
        catch e
            @error "Failed to get pod IP for user $username: $e"
            return nothing
        end
    end

    function proxy_to_user_pod(request::HTTP.Request, username::String)
        pod_ip = get_user_pod_ip(username)
        
        if pod_ip === nothing
            return error_response(503, "Pod Not Available", 
                "Your personal Pluto server is not ready. Please try again in a moment.")
        end
        
        # Parse the original request URI
        original_uri = HTTP.URI(request.target)
        original_path = original_uri.path
        
        @info "Original request path: $original_path"
        
        # Rewrite the path to remove the /user/{username} prefix
        user_prefix = "/user/$username"
        rewritten_path = if startswith(original_path, user_prefix)
            # Remove the user prefix from the path
            remaining_path = original_path[length(user_prefix)+1:end]
            # Ensure we have at least "/" 
            if isempty(remaining_path)
                "/"
            else
                # Make sure it starts with "/"
                startswith(remaining_path, "/") ? remaining_path : "/" * remaining_path
            end
        else
            # If path doesn't match expected pattern, default to root
            "/"
        end
        
        @info "Rewritten path: $rewritten_path"
        
        # Construct the pod URI with rewritten path
        pod_uri = HTTP.URI(
            scheme="http",
            host=pod_ip,
            port=8080,
            path=rewritten_path,
            query=original_uri.query
        )
        
        @info "Proxying request to user pod: $(string(pod_uri))"
        
        # Forward request to user's pod
        try
            # Copy headers but filter out problematic ones
            filtered_headers = filter(request.headers) do (name, value)
                lowercase(name) ∉ ["host", "connection", "upgrade", "content-length"]
            end
            
            # Add correct host header for the pod
            push!(filtered_headers, "Host" => "$pod_ip:8080")
            
            @info "Filtered headers: $filtered_headers"
            
            response = HTTP.request(
                request.method,
                string(pod_uri),
                filtered_headers,
                request.body;
                connect_timeout=15,  # Increased timeout
                readtimeout=30,
                status_exception=false  # Don't throw on 4xx/5xx status
            )
            
            @info "Successfully proxied request to user pod, status: $(response.status)"
            
            # Log response for debugging
            if response.status >= 400
                @warn "Pod returned error status: $(response.status)"
                @warn "Response headers: $(response.headers)"
                @warn "Response body (first 500 chars): $(String(response.body)[1:min(500, length(response.body))])"
            end
            
            return response
            
        catch e
            @error "Failed to proxy to user pod: $e"
            @error "Exception type: $(typeof(e))"
            
            # Provide more specific error message
            error_msg = if isa(e, HTTP.Exceptions.ConnectError)
                "Could not connect to your personal Pluto server. The server might still be starting up."
            else
                "Communication error with your personal Pluto server: $e"
            end
            
            return error_response(502, "Pod Communication Error", error_msg)
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
                # ip_address = HTTP.header(request, "X-Forwarded-For", 
                #                        HTTP.header(request, "Remote-Addr", "unknown")) # remove for now for testing
                ip_address = "FakeIPAdress"

                session_token = create_user_session(user, ip_address)

                ### Pod Spawner System in Kuberetes ###
                spawner = PlutoSpawner("plutohub", "plutohub:latest", "1", "2Gi", "5Gi"
                )
                
                
                pod_name = spawn_user_pod(spawner, user.username, string(user.id))
                @info "Spawned pod for user $(user.username): $pod_name"

                
                    
                
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
        # response = HTTP.Response(302)
        # HTTP.setheader(response, "Location" => "./login")
        # HTTP.setheader(response, "Set-Cookie" => "pluto_user_session=; path=/; expires=Thu, 01 Jan 1970 00:00:00 GMT")
        # response
        try
            @info "Processing logout request"
            
            # Get user from current session
            user = user_from_context(request)
            if user !== nothing
                @info "Logging out user: $(user.username)"
                
                # Shutdown all notebooks belonging to this user
                user_notebooks = get_user_notebooks(session, user.id)
                @info "Found $(length(user_notebooks)) notebooks to shutdown for user: $(user.username)"
                
                for notebook in user_notebooks
                    try
                        @info "Shutting down notebook: $(notebook.notebook_id) - $(basename(notebook.path))"
                        SessionActions.shutdown(session, notebook; keep_in_session=false, async=false, verbose=true)
                        remove_notebook_from_user(session, user.id, notebook.notebook_id)
                    catch e
                        @warn "Failed to shutdown notebook $(notebook.notebook_id): $e"
                    end
                end
                
                @info "All notebooks shutdown for user: $(user.username)"
                
                # Clear user session data (optional additional function)
                # clear_user_session_data(user)
            end
            
            # Create logout response with cleared cookies
            response = HTTP.Response(302)
            HTTP.setheader(response, "Location" => "./login")
            HTTP.setheader(response, "Set-Cookie" => "pluto_user_session=; path=/; expires=Thu, 01 Jan 1970 00:00:00 GMT; HttpOnly; SameSite=Strict")
            
            @info "Logout completed successfully"
            return response
            
        catch e
            @error "Logout failed:" exception=(e, catch_backtrace())
            # Even if logout fails, still clear the session cookie
            response = HTTP.Response(302)
            HTTP.setheader(response, "Location" => "./login?error=logout_failed")
            HTTP.setheader(response, "Set-Cookie" => "pluto_user_session=; path=/; expires=Thu, 01 Jan 1970 00:00:00 GMT")
            return response
        end
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

        @info frontend_directory()
        file_path = project_relative_path(frontend_directory(), "editor.jl.html")
        file_path = Genie.Renderer.filepath(file_path)
        layout_path = project_relative_path(frontend_directory(), "layout.jl.html")
        layout_path = Genie.Renderer.filepath(layout_path)
        @info file_path
        @info layout_path
        
        # return create_serve_html(project_relative_path(frontend_directory(), "editor.html"))(request)
        return Genie.Renderer.Html.html(file_path, layout=layout_path)
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
            # if user !== nothing
            #     add_notebook_to_user(session, user.id, nb.notebook_id)
            # end
            
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
        
        uri = HTTP.URI(request.target)
        query = HTTP.queryparams(uri)
        file_name = get(query, "name", nothing)
        folder_path = get(query, "folder", "")
        @info "File name: $file_name"
        @info "Folder path: $folder_path"

        # Set user-specific notebook directory
        original_notebook_dir = session.options.server.notebook

        # Determine target directory
        user_notebooks_dir = joinpath(user.home_directory, "notebooks")
        if !isempty(folder_path)
            # Create notebook in specified subfolder
            target_dir = joinpath(user_notebooks_dir, folder_path)
            # Ensure the target directory exists
            if !isdir(target_dir)
                mkpath(target_dir)
            end
        else
            target_dir = user_notebooks_dir
        end

        if file_name !== nothing
            # Ensure file name is safe and valid
            file_name = replace(file_name, r"[^a-zA-Z0-9_\-\.]" => "_")
            if !endswith(file_name, ".jl")
                file_name *= ".jl"  # Ensure it has .jl extension
            end
            save_path = joinpath(target_dir, file_name)
        else 
            save_path = nothing
        end
        
        try
            result = with_user_working_directory(user, () -> begin
                nb = if file_name !== nothing
                    # Create with specific filename
                    SessionActions.new(session; path=save_path, user_id=user.id)
                else
                    # Create with default name
                    SessionActions.new(session; user_id=user.id)
                end
                
                @info "Created notebook: $(nb.path) for user: $(user.username)"
                
                return notebook_response(nb; as_redirect=(request.method == "GET"))
            end)
            
            return result
            
        finally
            # Restore original notebook directory
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
                        risky_file_source=nothing,
                        user_id=user.id
                    )
                    return notebook_response(nb; as_redirect=(request.method == "GET"))
                else
                    return error_response(404, "Can't find a file here", "Please check whether <code>$(htmlesc(path))</code> exists.")
                end
            elseif haskey(query, "url")
                url = query["url"]
                nb = SessionActions.open_url(session, url;
                    execution_allowed,
                    as_sample, 
                    risky_file_source=url,
                    user_id=user.id
                )
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
        newpath = joinpath(user.home_directory, "notebooks", newpath)
        
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
    
    # Replace the existing serve_user_notebooks_json function with this enhanced version
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
                    "tree" => Dict(
                        "name" => "notebooks",
                        "type" => "directory",
                        "path" => "",
                        "contents" => []
                    ),
                    "user" => user.username,
                    "message" => "Notebooks directory not found"
                )))
            end
            
            # Build complete directory tree structure
            function build_directory_tree(dir_path, relative_path="")
                items = []
                
                try
                    # Read directory contents
                    dir_entries = readdir(dir_path, join=false)
                    
                    # Sort entries: directories first, then files, both alphabetically
                    sort!(dir_entries, by = name -> (isdir(joinpath(dir_path, name)) ? "0_$name" : "1_$name"))
                    
                    for entry in dir_entries
                        entry_path = joinpath(dir_path, entry)
                        entry_relative = isempty(relative_path) ? entry : joinpath(relative_path, entry)
                        
                        if isdir(entry_path)
                            # This is a directory - include it regardless of contents
                            subdirectory_contents = build_directory_tree(entry_path, entry_relative)
                            
                            push!(items, Dict(
                                "name" => entry,
                                "type" => "directory",
                                "path" => entry_path,
                                "shortpath" => entry_relative,
                                "contents" => subdirectory_contents,
                                "size" => 0,
                                "modified" => string(Dates.unix2datetime(stat(entry_path).mtime)),
                                "is_empty" => isempty(subdirectory_contents)
                            ))
                            
                        elseif isfile(entry_path)
                            # This is a file
                            file_stat = stat(entry_path)
                            
                            if endswith(lowercase(entry), ".jl")
                                # Check if it's a Pluto notebook
                                try
                                    file_content = read(entry_path, String)
                                    is_pluto_notebook = startswith(file_content, "### A Pluto.jl notebook ###")
                                    
                                    if is_pluto_notebook
                                        # Try to find existing notebook in session
                                        existing_notebook = nothing
                                        notebook_id = nothing
                                        process_status = "not_running"
                                        
                                        # Search for this notebook in the current session
                                        for (id, nb) in session.notebooks
                                            if nb.path == entry_path
                                                existing_notebook = nb
                                                notebook_id = string(id)
                                                process_status = "running"
                                                break
                                            end
                                        end
                                        
                                        push!(items, Dict(
                                            "name" => entry,
                                            "type" => "file",
                                            "file_type" => "pluto_notebook",
                                            "path" => entry_path,
                                            "shortpath" => entry_relative,
                                            "notebook_id" => notebook_id,
                                            "process_status" => process_status,
                                            "in_temp_dir" => false,
                                            "size" => file_stat.size,
                                            "modified" => string(Dates.unix2datetime(file_stat.mtime)),
                                            "is_running" => existing_notebook !== nothing,
                                            "is_pluto_notebook" => true
                                        ))
                                    else
                                        # Regular .jl file (not a Pluto notebook)
                                        push!(items, Dict(
                                            "name" => entry,
                                            "type" => "file",
                                            "file_type" => "julia_file",
                                            "path" => entry_path,
                                            "shortpath" => entry_relative,
                                            "notebook_id" => nothing,
                                            "process_status" => "not_applicable",
                                            "in_temp_dir" => false,
                                            "size" => file_stat.size,
                                            "modified" => string(Dates.unix2datetime(file_stat.mtime)),
                                            "is_running" => false,
                                            "is_pluto_notebook" => false
                                        ))
                                    end
                                catch e
                                    @warn "Error reading .jl file $entry_path: $e"
                                    # Still add it as a file but mark as unreadable
                                    push!(items, Dict(
                                        "name" => entry,
                                        "type" => "file",
                                        "file_type" => "julia_file",
                                        "path" => entry_path,
                                        "shortpath" => entry_relative,
                                        "notebook_id" => nothing,
                                        "process_status" => "unknown",
                                        "in_temp_dir" => false,
                                        "size" => file_stat.size,
                                        "modified" => string(Dates.unix2datetime(file_stat.mtime)),
                                        "is_running" => false,
                                        "is_pluto_notebook" => false,
                                        "error" => "Could not read file"
                                    ))
                                end
                            else
                                # Non-.jl file (text, markdown, etc.)
                                file_extension = lowercase(splitext(entry)[2])
                                file_type = if file_extension in [".md", ".txt", ".rst"]
                                    "text_file"
                                elseif file_extension in [".json", ".toml", ".yaml", ".yml"]
                                    "config_file"
                                elseif file_extension in [".png", ".jpg", ".jpeg", ".gif", ".svg"]
                                    "image_file"
                                else
                                    "other_file"
                                end
                                
                                push!(items, Dict(
                                    "name" => entry,
                                    "type" => "file",
                                    "file_type" => file_type,
                                    "path" => entry_path,
                                    "shortpath" => entry_relative,
                                    "notebook_id" => nothing,
                                    "process_status" => "not_applicable",
                                    "in_temp_dir" => false,
                                    "size" => file_stat.size,
                                    "modified" => string(Dates.unix2datetime(file_stat.mtime)),
                                    "is_running" => false,
                                    "is_pluto_notebook" => false,
                                    "file_extension" => file_extension
                                ))
                            end
                        end
                    end
                    
                catch e
                    @warn "Error reading directory $dir_path: $e"
                end
                
                return items
            end
            
            # Build the complete tree starting from notebooks directory
            tree_contents = build_directory_tree(user_notebooks_dir)
            
            # Count different types of items
            function count_items(items)
                counts = Dict("folders" => 0, "notebooks" => 0, "other_files" => 0, "total" => 0)
                
                for item in items
                    counts["total"] += 1
                    if item["type"] == "directory"
                        counts["folders"] += 1
                        # Recursively count items in subdirectories
                        sub_counts = count_items(item["contents"])
                        counts["folders"] += sub_counts["folders"]
                        counts["notebooks"] += sub_counts["notebooks"]
                        counts["other_files"] += sub_counts["other_files"]
                        counts["total"] += sub_counts["total"]
                    elseif item["type"] == "file"
                        if get(item, "is_pluto_notebook", false)
                            counts["notebooks"] += 1
                        else
                            counts["other_files"] += 1
                        end
                    end
                end
                
                return counts
            end
            
            item_counts = count_items(tree_contents)
            
            # Prepare response
            response_data = Dict(
                "tree" => Dict(
                    "name" => "notebooks",
                    "type" => "directory", 
                    "path" => user_notebooks_dir,
                    "shortpath" => "",
                    "contents" => tree_contents
                ),
                "user" => user.username,
                "counts" => item_counts,
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
            if !f_notebook(session, user.id, notebook.notebook_id)
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
                clear_frontmatter=haskey(query, "clear_frontmatter"),
                user_id=user.id
            )
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
                as_sample=true,
                user_id=user.id,
            )
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
        
        # Check if user has a running pod, if so proxy to it
        pod_ip = get_user_pod_ip(user.username)
        if pod_ip !== nothing
            @info "Proxying user home to pod for user: $(user.username)"
            return proxy_to_user_pod(request, user.username)
        end
        
        # Fallback to hub interface if no pod
        @info "No pod found, serving hub interface for user: $(user.username)"
        file_path = project_relative_path(frontend_directory(), "index.jl.html")
        file_path = Genie.Renderer.filepath(file_path)
        layout_path = project_relative_path(frontend_directory(), "layout.jl.html")
        layout_path = Genie.Renderer.filepath(layout_path)
        
        return Genie.Renderer.Html.html(file_path, layout=layout_path)
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

        @info frontend_directory()
        file_path = project_relative_path(frontend_directory(), "editor.jl.html")
        file_path = Genie.Renderer.filepath(file_path)
        layout_path = project_relative_path(frontend_directory(), "layout.jl.html")
        layout_path = Genie.Renderer.filepath(layout_path)
        @info file_path
        @info layout_path
        
        # return create_serve_html(project_relative_path(frontend_directory(), "editor.html"))(request)
        return Genie.Renderer.Html.html(file_path, layout=layout_path)
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



    # Folder management endpoints
    # Add this route after the existing routes, before the return statement

    # Folder creation route
    function serve_create_folder(request::HTTP.Request)
        user = user_from_context(request)
        if user === nothing
            return HTTP.Response(403, "Authentication required")
        end
        
        try
            uri = HTTP.URI(request.target)
            query = HTTP.queryparams(uri)
            
            # Get folder name from query parameters
            folder_name = get(query, "name", nothing)
            parent_path = get(query, "parent", "")  # Optional parent directory
            
            if folder_name === nothing || isempty(strip(folder_name))
                return error_response(400, "Invalid folder name", "Folder name cannot be empty")
            end
            
            # Sanitize folder name (remove invalid characters)
            sanitized_name = replace(folder_name, r"[<>:\"/\\|?*]" => "_")
            if sanitized_name != folder_name
                @info "Folder name sanitized: '$folder_name' -> '$sanitized_name'"
            end
            
            @info "Creating folder: '$sanitized_name' in parent: '$parent_path' for user: $(user.username)"
            
            # Create folder in user's directory
            result_path = with_user_working_directory(user, () -> begin
                user_notebooks_dir = joinpath(user.home_directory, "notebooks")
                
                # Ensure notebooks directory exists
                if !isdir(user_notebooks_dir)
                    mkpath(user_notebooks_dir)
                end
                
                # Determine target directory
                if !isempty(parent_path)
                    # Validate parent path is within user's directory
                    full_parent_path = joinpath(user_notebooks_dir, parent_path)
                    if !startswith(abspath(full_parent_path), abspath(user_notebooks_dir))
                        throw(ArgumentError("Invalid parent path: access denied"))
                    end
                    target_dir = full_parent_path
                else
                    target_dir = user_notebooks_dir
                end
                
                # Create the new folder path
                new_folder_path = joinpath(target_dir, sanitized_name)
                
                # Check if folder already exists
                if isdir(new_folder_path)
                    # Generate unique name if folder exists
                    counter = 1
                    while isdir(new_folder_path)
                        unique_name = "$(sanitized_name)_$(counter)"
                        new_folder_path = joinpath(target_dir, unique_name)
                        counter += 1
                    end
                    @info "Folder exists, using unique name: $(basename(new_folder_path))"
                end
                
                # Create the directory
                mkpath(new_folder_path)
                @info "Folder created successfully: $new_folder_path"
                
                return new_folder_path
            end)
            
            # Return success response with folder info
            relative_path = relpath(result_path, joinpath(user.home_directory, "notebooks"))
            response_data = Dict(
                "status" => "success",
                "message" => "Folder created successfully",
                "folder_name" => basename(result_path),
                "folder_path" => relative_path,
                "full_path" => result_path
            )
            
            response = HTTP.Response(200, JSON.json(response_data))
            HTTP.setheader(response, "Content-Type" => "application/json; charset=utf-8")
            return response
            
        catch e
            @error "Failed to create folder:" exception=(e, catch_backtrace())
            return error_response(500, "Folder Creation Failed", 
                "An error occurred while creating the folder: $(string(e))")
        end
    end
    HTTP.register!(router, "POST", "/api/create-folder", serve_create_folder)

    # Folder deletion route
    function serve_delete_folder(request::HTTP.Request)
        user = user_from_context(request)
        if user === nothing
            return HTTP.Response(403, "Authentication required")
        end
        
        try
            uri = HTTP.URI(request.target)
            query = HTTP.queryparams(uri)
            
            folder_path = get(query, "path", nothing)
            force_delete = haskey(query, "force")  # Force delete non-empty folders
            
            if folder_path === nothing || isempty(strip(folder_path))
                return error_response(400, "Invalid folder path", "Folder path cannot be empty")
            end
            
            @info "Deleting folder: '$folder_path' for user: $(user.username)"
            
            # Delete folder from user's directory
            with_user_working_directory(user, () -> begin
                user_notebooks_dir = joinpath(user.home_directory, "notebooks")
                full_folder_path = joinpath(user_notebooks_dir, folder_path)
                
                # Security check: ensure path is within user's directory
                if !startswith(abspath(full_folder_path), abspath(user_notebooks_dir))
                    throw(ArgumentError("Invalid folder path: access denied"))
                end
                
                if !isdir(full_folder_path)
                    throw(ArgumentError("Folder does not exist: $folder_path"))
                end
                
                # Check if folder is empty (unless force delete)
                if !force_delete && !isempty(readdir(full_folder_path))
                    throw(ArgumentError("Folder is not empty. Use force=true to delete non-empty folders."))
                end
                
                # Shutdown any running notebooks in this folder first
                for (notebook_id, notebook) in session.notebooks
                    if startswith(notebook.path, full_folder_path) && user_can_access_notebook(session, user.id, notebook_id)
                        try
                            @info "Shutting down notebook in deleted folder: $(notebook.path)"
                            SessionActions.shutdown(session, notebook; keep_in_session=false, async=false)
                            remove_notebook_from_user(session, user.id, notebook_id)
                        catch e
                            @warn "Failed to shutdown notebook $(notebook_id): $e"
                        end
                    end
                end
                
                # Delete the folder
                rm(full_folder_path; recursive=true, force=true)
                @info "Folder deleted successfully: $full_folder_path"
            end)
            
            response_data = Dict(
                "status" => "success",
                "message" => "Folder deleted successfully",
                "folder_path" => folder_path
            )
            
            response = HTTP.Response(200, JSON.json(response_data))
            HTTP.setheader(response, "Content-Type" => "application/json; charset=utf-8")
            return response
            
        catch e
            @error "Failed to delete folder:" exception=(e, catch_backtrace())
            error_msg = if isa(e, ArgumentError)
                string(e)
            else
                "An error occurred while deleting the folder: $(string(e))"
            end
            return error_response(500, "Folder Deletion Failed", error_msg)
        end
    end
    HTTP.register!(router, "POST", "/api/delete-folder", serve_delete_folder)

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