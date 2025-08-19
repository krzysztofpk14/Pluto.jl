using YAML

struct PlutoSpawner
    namespace::String
    image::String
    cpu_limit::String
    memory_limit::String
    storage_size::String
end

function spawn_user_pod(spawner::PlutoSpawner, username::String, user_id::String)
    pod_name = "pluto-$(username)-randomstring"
    pvc_name = "pluto-$(username)-home"
    
    @info "Creating PVC for user: $username"
    
    # First create the PVC
    pvc_spec = Dict(
        "apiVersion" => "v1",
        "kind" => "PersistentVolumeClaim",
        "metadata" => Dict(
            "name" => pvc_name,
            "namespace" => spawner.namespace,
            "labels" => Dict(
                "app" => "plutohub-user",
                "user" => username
            )
        ),
        "spec" => Dict(
            "accessModes" => ["ReadWriteOnce"],
            "resources" => Dict(
                "requests" => Dict(
                    "storage" => spawner.storage_size
                )
            ),
            "storageClassName" => "hostpath"
        )
    )
    
    # Create PVC first
    create_kubernetes_resource(pvc_spec, "PVC")
    
    @info "Creating Pod Dict for user: $username"
    pod_spec = Dict(
        "apiVersion" => "v1",
        "kind" => "Pod",
        "metadata" => Dict(
            "name" => pod_name,
            "namespace" => spawner.namespace,
            "labels" => Dict(
                "app" => "plutohub-user",
                "user" => username
            )
        ),
        "spec" => Dict(
            "containers" => [Dict(
                "name" => "pluto-server",
                "image" => spawner.image,
                "imagePullPolicy" => "Never",  # For local Docker images
                "ports" => [Dict("containerPort" => 8080)],
                "env" => [
                    Dict("name" => "JUPYTERHUB_USER", "value" => username),
                    Dict("name" => "PLUTO_HOST", "value" => "0.0.0.0"),
                    Dict("name" => "PLUTO_PORT", "value" => "8080"),
                    Dict("name" => "PLUTO_MODE", "value" => "singleuser")
                ],
                "resources" => Dict(
                    "limits" => Dict(
                        "cpu" => spawner.cpu_limit,
                        "memory" => spawner.memory_limit
                    ),
                    "requests" => Dict(
                        "cpu" => "50m",
                        "memory" => "128Mi"
                    )
                ),
                "volumeMounts" => [Dict(
                    "name" => "user-home",
                    "mountPath" => "/home/pluto/users/$(username)"
                )]
            )],
            "volumes" => [Dict(
                "name" => "user-home",
                "persistentVolumeClaim" => Dict(
                    "claimName" => pvc_name  # Use the PVC we created
                )
            )],
            "restartPolicy" => "Never"
        )
    )
    
    # Create Pod after PVC is created
    create_kubernetes_resource(pod_spec, "Pod")
    
    return pod_name
end

function create_kubernetes_resource(resource_spec::Dict, resource_type::String)
    @info "Creating $resource_type"
    
    temp_file = tempname() * ".yaml"

    # if directory does not exist, create it
    if !isdir(dirname(temp_file))
        @info "Creating directory: $(dirname(temp_file))"
        mkpath(dirname(temp_file))
    end

    @info "Writing $resource_type to file: $temp_file"
    YAML.write_file(temp_file, resource_spec)

    try
        @info "Running kubectl apply for $resource_type"
        Base.run(`kubectl apply -f $temp_file`)
        @info "$resource_type created successfully"
    catch e
        @error "Failed to create $resource_type: $e"
        # Don't delete temp file on error for debugging
        @error "Temp file saved for debugging: $temp_file"
        rethrow(e)
    end
    
    @info "Removing temp file: $temp_file"
    # Clean up temp file
    rm(temp_file; force=true)
end

# Keep backward compatibility
function create_kubernetes_pod(pod_spec::Dict)
    create_kubernetes_resource(pod_spec, "Pod")
end

# Utility function to check if PVC exists
function pvc_exists(namespace::String, pvc_name::String)::Bool
    try
        Base.run(`kubectl get pvc $pvc_name -n $namespace`)
        return true
    catch
        return false
    end
end

# Utility function to delete user resources
function cleanup_user_resources(spawner::PlutoSpawner, username::String)
    pvc_name = "pluto-$(username)-home"
    
    try
        @info "Cleaning up resources for user: $username"
        
        # Delete pods with user label
        Base.run(`kubectl delete pods -n $(spawner.namespace) -l user=$username`)
        
        # Delete PVC
        if pvc_exists(spawner.namespace, pvc_name)
            Base.run(`kubectl delete pvc $pvc_name -n $(spawner.namespace)`)
        end
        
        @info "Cleanup completed for user: $username"
    catch e
        @error "Error during cleanup for user $username: $e"
    end
end