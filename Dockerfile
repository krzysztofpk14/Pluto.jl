FROM julia:1.11.3

# TODO: Implement WORKDIR and USER management

COPY Project.toml Manifest.toml ./
COPY . .
RUN julia --project=@. -e   'using Pkg; Pkg.instantiate(); Pkg.precompile()'



CMD ["julia", "--project=@.", "start_pluto.jl"]