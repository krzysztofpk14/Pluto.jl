function secure_workspace_filesystem(workspace::Workspace, session::ServerSession, notebook::Notebook, user::User)
    @info "Securing workspace filesystem for notebook $(notebook.notebook_id) in workspace $(workspace.module_name)"
    
    if user === nothing
        throw(ErrorException("Cannot secure workspace: no user context"))
    end
    
    user_home = user.home_directory
    notebook_dir = dirname(notebook.path)
    
    Malt.remote_eval_wait(workspace.worker, quote
        # Store all original functions using @generated macros to avoid recursion
        @generated __original_pwd() = Base.pwd()
        @generated __original_cd(args...) = Base.cd(args...)
        @generated __original_readdir(args...) = Base.readdir(args...)
        @generated __original_mkdir(args...; kwargs...) = Base.mkdir(args...; kwargs...)
        @generated __original_rm(args...; kwargs...) = Base.rm(args...; kwargs...)
        @generated __original_cp(args...; kwargs...) = Base.cp(args...; kwargs...)
        @generated __original_mv(args...; kwargs...) = Base.mv(args...; kwargs...)
        @generated __original_open(args...; kwargs...) = Base.open(args...; kwargs...)
        @generated __original_read(args...; kwargs...) = Base.read(args...; kwargs...)
        @generated __original_write(args...; kwargs...) = Base.write(args...; kwargs...)
        @generated __original_touch(args...) = Base.touch(args...)
        @generated __original_isfile(args...) = Base.isfile(args...)
        @generated __original_isdir(args...) = Base.isdir(args...)
        @generated __original_run(args...; kwargs...) = Base.run(args...; kwargs...)
        @generated __original_pipeline(args...; kwargs...) = Base.pipeline(args...; kwargs...)
        @generated __original_abspath(args...) = Base.abspath(args...)
        @generated __original_expanduser(args...) = Base.expanduser(args...)
        @generated __original_startswith(args...) = Base.startswith(args...)
        @generated __original_isempty(args...) = Base.isempty(args...)
        @generated __original_realpath(args...) = Base.realpath(args...)
        @generated __original_splitpath(args...) = Base.splitpath(args...)
        
        # Define security constants
        const USER_HOME = $(user_home)
        const NOTEBOOK_DIR = $(notebook_dir)
        
        @info "Security constants set: USER_HOME=$USER_HOME, NOTEBOOK_DIR=$NOTEBOOK_DIR"
        
        # Enhanced path validation function
        function __is_path_allowed(path::AbstractString)::Bool
            try
                # Handle empty or "." paths using @generated original
                if __original_isempty(path) || path == "."
                    abs_path = __original_pwd()
                else
                    # Resolve all symbolic links and relative paths
                    abs_path = __original_realpath(__original_expanduser(path))
                end
                
                # Must be within user's home directory
                if !__original_startswith(abs_path, USER_HOME)
                    @debug "Path denied - outside USER_HOME" path abs_path USER_HOME
                    return false
                end
                
                # Additional checks for sensitive subdirectories
                sensitive_dirs = [".ssh", ".aws", ".docker", "bin", "sbin", ".gnupg", ".config/systemd"]
                path_parts = __original_splitpath(abs_path)
                
                for sensitive in sensitive_dirs
                    if sensitive in path_parts
                        @debug "Path denied - sensitive directory" path abs_path sensitive
                        return false
                    end
                end
                
                @debug "Path allowed" path abs_path USER_HOME
                return true
            catch e
                @warn "Path validation failed - denying access" path exception=e
                return false
            end
        end
        
        function __validate_path_or_throw(path::AbstractString, operation::String="access")
            if !__is_path_allowed(path)
                error_msg = "Permission denied: Cannot $operation path outside user directory: $path (USER_HOME=$USER_HOME)"
                @warn error_msg
                throw(ArgumentError(error_msg))
            end
        end
        
        function __validate_command(cmd::Base.AbstractCmd)
            cmd_string = string(cmd)
            @info "Command validation" cmd_string
            
            # Block potentially dangerous commands
            dangerous_patterns = [
                r"sudo\s", r"su\s", r"chmod\s.*[+\-=].*[xs]", r"chown\s", r"chgrp\s",
                r"rm\s+(-rf\s+)?/", r"dd\s", r"mkfs\s", r"fdisk\s",
                r"mount\s", r"umount\s", r"systemctl\s", r"service\s",
                r"iptables\s", r"ufw\s", r"firewall-cmd\s",
                r"passwd\s", r"usermod\s", r"useradd\s", r"userdel\s",
                r"crontab\s", r"at\s", r"batch\s",
                r"nc\s", r"netcat\s", r"ncat\s", r"socat\s",
                r"curl\s.*(-o|--output)", r"wget\s.*(-O|--output-document)",
                r"ssh\s", r"scp\s", r"rsync\s", r"sftp\s"
            ]
            
            for pattern in dangerous_patterns
                if occursin(pattern, cmd_string)
                    @warn "Command blocked" cmd_string pattern
                    throw(ArgumentError("Command blocked for security: $cmd_string"))
                end
            end
        end

        # === FILE SYSTEM OPERATIONS ===
        
        function Base.pwd()::String
            current = __original_pwd()
            
            # Use original functions to avoid recursion
            abs_current = __original_abspath(current)
            is_allowed = __original_startswith(abs_current, USER_HOME)
                
            if !is_allowed
                @warn "Workspace outside user directory: $current, resetting to: $NOTEBOOK_DIR"
                __original_cd(NOTEBOOK_DIR)
                return NOTEBOOK_DIR
            else
                @info "pwd() returning valid directory: $current"
                return current
            end
        end
        
        function Base.cd(path::AbstractString=".")
            @info "cd() called with path: $path"
            __validate_path_or_throw(path, "change directory to")
            result = __original_cd(path)
            @info "cd() successful, new pwd: $(__original_pwd())"
            return result
        end
        
        function Base.cd(f::Function, path::AbstractString)
            @info "cd(function, path) called with path: $path"
            __validate_path_or_throw(path, "change directory to")
            return __original_cd(f, path)
        end
        
        function Base.readdir(path::AbstractString=".")
            @debug "readdir() called with path: $path"
            __validate_path_or_throw(path, "read directory")
            return __original_readdir(path)
        end
        
        function Base.mkdir(path::AbstractString; mode::Integer=0o777)
            @debug "mkdir() called with path: $path"
            __validate_path_or_throw(path, "create directory")
            return __original_mkdir(path; mode=mode)
        end
        
        function Base.rm(path::AbstractString; force::Bool=false, recursive::Bool=false)
            @debug "rm() called with path: $path"
            __validate_path_or_throw(path, "remove")
            return __original_rm(path; force=force, recursive=recursive)
        end
        
        function Base.cp(src::AbstractString, dst::AbstractString; force::Bool=false, follow_symlinks::Bool=false)
            @debug "cp() called: $src -> $dst"
            __validate_path_or_throw(src, "copy from")
            __validate_path_or_throw(dst, "copy to")
            return __original_cp(src, dst; force=force, follow_symlinks=follow_symlinks)
        end
        
        function Base.mv(src::AbstractString, dst::AbstractString; force::Bool=false)
            @debug "mv() called: $src -> $dst"
            __validate_path_or_throw(src, "move from")
            __validate_path_or_throw(dst, "move to")
            return __original_mv(src, dst; force=force)
        end
        
        # === FILE I/O OPERATIONS ===
        
        function Base.open(path::AbstractString, args...; kwargs...)
            @debug "open() called with path: $path"
            __validate_path_or_throw(path, "open file")
            return __original_open(path, args...; kwargs...)
        end
        
        function Base.open(f::Function, path::AbstractString, args...; kwargs...)
            @debug "open(function, path) called with path: $path"
            __validate_path_or_throw(path, "open file")
            return __original_open(f, path, args...; kwargs...)
        end
        
        function Base.read(path::AbstractString, args...; kwargs...)
            @debug "read() called with path: $path"
            __validate_path_or_throw(path, "read file")
            return __original_read(path, args...; kwargs...)
        end
        
        function Base.write(path::AbstractString, args...; kwargs...)
            @debug "write() called with path: $path"
            __validate_path_or_throw(path, "write to file")
            return __original_write(path, args...; kwargs...)
        end
        
        function Base.touch(path::AbstractString)
            @debug "touch() called with path: $path"
            __validate_path_or_throw(path, "touch file")
            return __original_touch(path)
        end
        
        function Base.isfile(path::AbstractString)
            @debug "isfile() called with path: $path"
            # Allow checking existence but validate path - don't reveal paths outside user dir
            if !__is_path_allowed(path)
                return false
            end
            return __original_isfile(path)
        end
        
        function Base.isdir(path::AbstractString)
            @debug "isdir() called with path: $path"
            if !__is_path_allowed(path)
                return false
            end
            return __original_isdir(path)
        end
        
        # === PROCESS EXECUTION ===
        
        function Base.run(cmd::Base.AbstractCmd, args...; kwargs...)
            @info "run() called with command: $cmd"
            __validate_command(cmd)
            return __original_run(cmd, args...; kwargs...)
        end
        
        function Base.pipeline(cmd, args...; kwargs...)
            @info "pipeline() called with command: $cmd"
            # Validate each command in the pipeline if it's a complex command
            if isa(cmd, Base.AbstractCmd)
                __validate_command(cmd)
            end
            return __original_pipeline(cmd, args...; kwargs...)
        end
        
        # For maximum security, you could instead completely block external processes:
        # function Base.run(cmd::Base.AbstractCmd, args...; kwargs...)
        #     @warn "External process execution blocked for security" cmd
        #     throw(ArgumentError("External process execution is disabled for security"))
        # end
    end)
    
    @info "Workspace filesystem security completed successfully"
end