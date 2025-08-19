using Pluto

# PlutoHub Configuration for Kubernetes
struct PlutoHubConfig
    port::Int
    host::String
    base_url::String
    user_home_base::String
end

function get_kubernetes_config()
    PlutoHubConfig(
        port = 8080,
        host = "0.0.0.0",
        base_url = "/user",
        user_home_base = "/home/pluto"
    )
end

function start_plutohub_server()
    # config = get_kubernetes_config()
    
    # Initialize user workspace
    user = "admin"
    user_home = joinpath(config.user_home_base, user)
    mkpath(user_home)
    
    @info "Starting PlutoHub server for user: $user"
    @info "User home directory: $user_home"
    @info "Base URL: $(config.base_url)"
    
    # Start Pluto with Kubernetes-specific settings
    Pluto.run(
        launch_browser=false,
        port=8080,
        host="0.0.0.0",
        # Add base_url support when available in Pluto
    )
end

start_plutohub_server()