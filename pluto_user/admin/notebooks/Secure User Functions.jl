### A Pluto.jl notebook ###
# v0.20.13

using Markdown
using InteractiveUtils

# ╔═╡ ecb8fd77-0acf-4d19-8aca-1fac352a8908
md"Updated `pwd()` returns only path in user's folder"

# ╔═╡ 28bef88e-21bd-4ed3-97d3-0f947e96d514
pwd()

# ╔═╡ c959b914-76e1-4395-877c-09b34c73b204
md"Tryig to call private function ('normal' `pwd()`) returns an error"

# ╔═╡ b7fa999f-6015-4846-99b5-e21cf826c4b6
__original_pwd()

# ╔═╡ a958cde7-a39b-4db7-8c88-739e95518443
md"This was achieved using [`@generated`](https://docs.julialang.org/en/v1/base/base/#Base.@generated) function. See [tutorial](https://docs.julialang.org/en/v1/manual/metaprogramming/#Code-Generation)"

# ╔═╡ fd53b8c7-af0e-4960-b466-589dc4659c64


# ╔═╡ 6a821fab-137a-4ad3-8144-b4e71a916285


# ╔═╡ bcb02c6b-0f30-47ec-91ed-dd25536abaae


# ╔═╡ f66937cf-5702-43e9-8d23-3ae67fd062af


# ╔═╡ f1634bd8-3649-4981-852b-e8442f5ea356


# ╔═╡ 00000000-0000-0000-0000-000000000001
PLUTO_PROJECT_TOML_CONTENTS = """
[deps]
"""

# ╔═╡ 00000000-0000-0000-0000-000000000002
PLUTO_MANIFEST_TOML_CONTENTS = """
# This file is machine-generated - editing it directly is not advised

julia_version = "1.11.3"
manifest_format = "2.0"
project_hash = "da39a3ee5e6b4b0d3255bfef95601890afd80709"

[deps]
"""

# ╔═╡ Cell order:
# ╟─ecb8fd77-0acf-4d19-8aca-1fac352a8908
# ╠═28bef88e-21bd-4ed3-97d3-0f947e96d514
# ╟─c959b914-76e1-4395-877c-09b34c73b204
# ╠═b7fa999f-6015-4846-99b5-e21cf826c4b6
# ╟─a958cde7-a39b-4db7-8c88-739e95518443
# ╠═fd53b8c7-af0e-4960-b466-589dc4659c64
# ╠═6a821fab-137a-4ad3-8144-b4e71a916285
# ╠═bcb02c6b-0f30-47ec-91ed-dd25536abaae
# ╠═f66937cf-5702-43e9-8d23-3ae67fd062af
# ╠═f1634bd8-3649-4981-852b-e8442f5ea356
# ╟─00000000-0000-0000-0000-000000000001
# ╟─00000000-0000-0000-0000-000000000002
