"""
Check if the request has a valid login sesson cookie.
"""
# Update authentication functions for multi-user
function is_authenticated(session::ServerSession, request::HTTP.Request)::Union{User, Nothing}
    # Check for user session token
    try
        cookies = HTTP.cookies(request)
        for cookie in cookies
            if cookie.name == "pluto_user_session"
                user = get_user_from_session(cookie.value)
                if user !== nothing
                    return user
                end
            end
        end
    catch e
        @warn "Failed to authenticate user session" exception = (e, catch_backtrace())
    end
    return nothing
end

"""
Validate login token (simple implementation - in production use proper JWT or session management)
"""
function is_valid_login_token(token::String)
    # Simple token validation - should be replaced with proper session management
    expected_token = "login_authenticated_$(hash("pluto_login_session", UInt(12345)))"
    return token == expected_token
end

"""
Create a login session cookie
"""
function create_login_cookie()
    token = "login_authenticated_$(hash("pluto_login_session", UInt(12345)))"
    return HTTP.Cookie("pluto_login", token, path="/", httponly=true, maxage=3600) # 1 hour
end

"""
Validate user credentials
"""
function validate_credentials(username::String, password::String)
    return haskey(LOGIN_CREDENTIALS, username) && LOGIN_CREDENTIALS[username] == password
end

"""
Check if login is required for this session
"""
function login_required(session::ServerSession)
    # Enable login if credentials are configured and security is enabled
    return true
    # return !isempty(LOGIN_CREDENTIALS) && (
    #     session.options.security.require_secret_for_access ||
    #     session.options.security.require_secret_for_open_links
    # )
end


# # Function to log the url with secret on the Julia CLI when a request comes to the server without the secret. Executes at most once every 5 seconds
# const log_secret_throttled = Throttled.simple_leading_throttle(5) do session::ServerSession, request::HTTP.Request
#     host = HTTP.header(request, "Host")
#     target = request.target
#     url = Text(string(HTTP.URI(HTTP.URI("http://$host/"); query=Dict("secret" => session.secret))))
#     @info("No longer authenticated? Visit this URL to continue:", url)
# end

# Update the log function to be more appropriate for login-based authentication
const log_login_required_throttled = Throttled.simple_leading_throttle(5) do session::ServerSession, request::HTTP.Request
    host = HTTP.header(request, "Host")
    login_url = "http://$host/login"
    @info("Authentication required. Please visit the login page:", login_url)
end

# # Update add_set_secret_cookie! to also handle login cookies
# function add_set_secret_cookie!(session::ServerSession, response::HTTP.Response)
#     HTTP.setheader(response, "Set-Cookie" => "secret=$(session.secret); SameSite=Strict; HttpOnly")
#     response
# end

# function add_set_login_cookie!(response::HTTP.Response)
#     # HTTP.setheader(response, "Set-Cookie" => string(create_login_cookie()))
#     cookie = create_login_cookie()
#     cookie_string = "$(cookie.name)=$(cookie.value); Path=$(cookie.path); HttpOnly; Max-Age=$(cookie.maxage)"
#     HTTP.setheader(response, "Set-Cookie" => cookie_string)
#     @info "Setting login cookie: $cookie_string"  # Debug output
#     response
# end

function add_set_login_cookie!(response::HTTP.Response, session_token::String)
    cookie_string = "pluto_user_session=$session_token; Path=/; HttpOnly; Max-Age=28800"  # 8 hours
    HTTP.setheader(response, "Set-Cookie" => cookie_string)
    @info "Setting user session cookie: $session_token"
    response
end

# too many layers i know
"""
Generate a middleware (i.e. a function `HTTP.Handler -> HTTP.Handler`) that stores the `session` in every `request`'s context.
"""
function create_session_context_middleware(session::ServerSession)
    function session_context_middleware(handler::Function)::Function
        function(request::HTTP.Request)
            request.context[:pluto_session] = session
            # Add user context if authenticated
            user = is_authenticated(session, request)
            if user !== nothing
                request.context[:pluto_user] = user
            end
            handler(request)
        end
    end
end


session_from_context(request::HTTP.Request) = request.context[:pluto_session]::ServerSession

user_from_context(request::HTTP.Request) = get(request.context, :pluto_user, nothing)

# Update auth_required to consider login authentication
function auth_required(session::ServerSession, request::HTTP.Request)
    path = HTTP.URI(request.target).path
    ext = splitext(path)[2]
    # security = session.options.security

    # Skip authentication for login-related paths
    if path ∈ ("/login", "/authenticate", "/logout") || 
       path ∈ ("/ping", "/possible_binder_token_please") || 
       ext ∈ (".ico", ".js", ".css", ".png", ".gif", ".svg", ".ico", ".woff2", ".woff", ".ttf", ".eot", ".otf", ".json", ".map")
        false
    # elseif path ∈ ("", "/")
    #     # For root path, check if login is required or just secret
    #     login_required(session) || security.require_secret_for_access
    else
        # login_required(session) || security.require_secret_for_access || 
        # security.require_secret_for_open_links
        true
    end
end

# Update the auth_middleware function's error response to redirect to login if available
function auth_middleware(handler)
    return function (request::HTTP.Request)
        session = session_from_context(request)
        required = auth_required(session, request)
        
        # Fix: Check authentication properly - is_authenticated returns User or nothing
        authenticated_user = is_authenticated(session, request)
        is_user_authenticated = authenticated_user !== nothing

        if !required || is_user_authenticated
            response = handler(request)
            if !required
                filter!(p -> p[1] != "Access-Control-Allow-Origin", response.headers)
                HTTP.setheader(response, "Access-Control-Allow-Origin" => "*")
            end
            # if required || HTTP.URI(request.target).path ∈ ("", "/")
            # if required && is_authenticated(session, request)
            #     # add_set_secret_cookie!(session, response)
            #     add_set_login_cookie!(response)
            # end
            response
        else
            log_login_required_throttled(session, request)
            # Redirect to login if login system is enabled, otherwise show the original error
            response = HTTP.Response(302)
            # Preserve the intended destination in the redirect
            original_path = HTTP.URI(request.target).path
            redirect_url = if original_path == "/" || original_path == ""
                "./login"
            else
                "./login?redirect=" * HTTP.escapeuri(original_path)
            end
            HTTP.setheader(response, "Location" => redirect_url)
            response
        end
    end
end
