import UUIDs: UUID, uuid1
import .Configuration

###
# CLIENT
###

mutable struct ClientSession
    id::Symbol
    stream::Any
    connected_notebook::Union{Notebook,Nothing}
    pendingupdates::Channel
    simulated_lag::Float64
    user::Union{Pluto.User,Nothing} # Add user context - use Any to avoid type issues TODO:change to user
end

ClientSession(id::Symbol, stream, simulated_lag=0.0) = let
    ClientSession(id, stream, nothing, Channel(1024), simulated_lag, nothing)
end

# Add constructor with user
ClientSession(id::Symbol, stream, simulated_lag::Float64, user) = let
    ClientSession(id, stream, nothing, Channel(1024), simulated_lag, user)
end

"A combination of _client ID_ and a _request ID_. The front-end generates a unqique ID for every request that it sends. The back-end (the stuff you are currently reading) can respond to a specific request. In that case, the response does not go through the normal message handlers in the front-end, but it flies directly to the place where the message was sent. (It resolves the promise returned by `send(...)`.)"
struct Initiator
    client::ClientSession
    request_id::Symbol
end
function Base.getproperty(initiator::Initiator, property::Symbol)
    if property == :client_id
        getfield(initiator, :client).id
    else
        getfield(initiator, property)
    end
end

###
# SERVER
###

"""
The `ServerSession` keeps track of:

- `connected_clients`: connected (web) clients
- `notebooks`: running notebooks
- `secret`: the web access token
- `options`: global pluto configuration `Options` for this session.
- `user_notebooks`: mapping of user IDs to their notebooks (multi-user)
"""
Base.@kwdef mutable struct ServerSession
    connected_clients::Dict{Symbol,ClientSession} = Dict{Symbol,ClientSession}()
    notebooks::Dict{UUID,Notebook} = Dict{UUID,Notebook}()
    secret::String = String(rand(('a':'z') ∪ ('A':'Z') ∪ ('0':'9'), 8))
    binder_token::Union{String,Nothing} = nothing
    options::Configuration.Options = Configuration.Options()
    user_notebooks::Dict{UUID,Set{UUID}} = Dict{UUID,Set{UUID}}()  # user_id -> set of notebook_ids
end

function save_notebook(session::ServerSession, notebook::Notebook)
    
    # Notify event_listener from here
    try_event_call(session, FileSaveEvent(notebook))
    if !session.options.server.disable_writing_notebook_files
        save_notebook(notebook, notebook.path)
    end
end

###
# Multi-user notebook management
###
function add_notebook_to_user(session::ServerSession, user_id::UUID, notebook_id::UUID)
    if !haskey(session.user_notebooks, user_id)
        session.user_notebooks[user_id] = Set{UUID}()
    end
    push!(session.user_notebooks[user_id], notebook_id)
end

function remove_notebook_from_user(session::ServerSession, user_id::UUID, notebook_id::UUID)
    if haskey(session.user_notebooks, user_id)
        delete!(session.user_notebooks[user_id], notebook_id)
    end
end

function get_user_notebooks(session::ServerSession, user_id::UUID)
    user_notebook_ids = get(session.user_notebooks, user_id, Set{UUID}())
    return [session.notebooks[id] for id in user_notebook_ids if haskey(session.notebooks, id)]
end

function user_can_access_notebook(session::ServerSession, user_id::UUID, notebook_id::UUID)
    user_notebook_ids = get(session.user_notebooks, user_id, Set{UUID}())
    return notebook_id in user_notebook_ids
end

###
# UPDATE MESSAGE
###

struct UpdateMessage
    type::Symbol
    message::Any
    notebook::Union{Notebook,Nothing}
    cell::Union{Cell,Nothing}
    initiator::Union{Initiator,Nothing}
end

UpdateMessage(type::Symbol, message::Any) = UpdateMessage(type, message, nothing, nothing, nothing)
UpdateMessage(type::Symbol, message::Any, notebook::Notebook) = UpdateMessage(type, message, notebook, nothing, nothing)

function clientupdate_notebook_list(notebooks; initiator::Union{Initiator,Nothing}=nothing)
    UpdateMessage(:notebook_list,
        Dict(
            :notebooks => [
                Dict(
                    :notebook_id => notebook.notebook_id,
                    :path => notebook.path,
                    :in_temp_dir => startswith(notebook.path, new_notebooks_directory()),
                    :shortpath => basename(notebook.path),
                    :process_status => notebook.process_status,
                ) for notebook in values(notebooks)
            ]
        ), nothing, nothing, initiator)
end                