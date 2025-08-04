import .Throttled
using UUIDs: UUID, uuid4
using Dates: DateTime, now, Hour  # Import specific functions instead of using Dates

struct User
    id::UUID
    username::String
    password_hash::String
    email::String
    created_at::DateTime
    last_login::DateTime
    is_active::Bool
    home_directory::String
    max_notebooks::Int
    max_processes::Int
end

struct UserSession # This should be moved to Session.jl
    user_id::UUID
    session_token::String
    created_at::DateTime
    expires_at::DateTime
    last_accessed::DateTime
    ip_address::String
end

# User database (in production, use proper database)
const USERS = Dict{UUID, User}()
const USER_SESSIONS = Dict{String, UserSession}()
const USERNAME_TO_ID = Dict{String, UUID}()

# Initialize default users
function initialize_default_users()
    if isempty(USERS)
        create_user("admin", "admin123", "admin@pluto.jl", max_notebooks=50, max_processes=10)
        create_user("user1", "password1", "user1@pluto.jl", max_notebooks=10, max_processes=3)
        create_user("user2", "password2", "user2@pluto.jl", max_notebooks=10, max_processes=3)
    end
end

function create_user(username::String, password::String, email::String; 
                    max_notebooks::Int=10, max_processes::Int=3)
    user_id = uuid4()
    password_hash = hash_password(password)
    home_dir = create_user_directory(username)
    
    user = User(
        user_id, username, password_hash, email,
        now(), DateTime(0), true, home_dir,
        max_notebooks, max_processes
    )
    
    USERS[user_id] = user
    USERNAME_TO_ID[username] = user_id
    return user
end

function create_user_directory(username::String)::String
    base_dir = joinpath(pwd(), "pluto_user")
    user_dir = joinpath(base_dir, username)
    mkpath(user_dir) 
    mkpath(joinpath(user_dir, "notebooks"))
    mkpath(joinpath(user_dir, "cache"))
    return user_dir
end

function hash_password(password::String)::String
    return string(hash(password * "pluto_salt_$(length(password))"))  # Simple hash, use bcrypt in production
end

function verify_password(password::String, hash::String)::Bool
    return hash_password(password) == hash
end

function authenticate_user(username::String, password::String)::Union{User, Nothing}
    user_id = get(USERNAME_TO_ID, username, nothing)
    user_id === nothing && return nothing
    
    user = USERS[user_id]
    if user.is_active && verify_password(password, user.password_hash)
        # Update last login
        USERS[user_id] = User(user.id, user.username, user.password_hash, 
                             user.email, user.created_at, now(), user.is_active,
                             user.home_directory, user.max_notebooks, user.max_processes)
        return USERS[user_id]
    end
    return nothing
end

function create_user_session(user::User, ip_address::String)::String
    session_token = string(uuid4()) * "_" * string(hash(user.id))
    expires_at = now() + Hour(8)  # 8-hour sessions
    
    session = UserSession(
        user.id, session_token, now(), expires_at, now(), ip_address
    )
    
    USER_SESSIONS[session_token] = session
    return session_token
end

function get_user_from_session(session_token::String)::Union{User, Nothing}
    session = get(USER_SESSIONS, session_token, nothing)
    session === nothing && return nothing
    
    if now() > session.expires_at
        delete!(USER_SESSIONS, session_token)
        return nothing
    end
    
    # Update last accessed
    USER_SESSIONS[session_token] = UserSession(
        session.user_id, session.session_token, session.created_at,
        session.expires_at, now(), session.ip_address
    )
    
    return get(USERS, session.user_id, nothing)
end

function cleanup_expired_sessions()
    current_time = now()
    to_delete = String[]
    for (token, session) in USER_SESSIONS
        if current_time > session.expires_at
            push!(to_delete, token)
        end
    end
    for token in to_delete
        delete!(USER_SESSIONS, token)
    end
end