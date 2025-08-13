# TODO
- [ ] Ensure compatibility with tests

## User Area
- [ ] Implement user area
- [ ] Implement Move File
- [ ] Filter files by name does not search files in folders
- [ ] Modify Search and Save notebook in Pluto to view only user folders
- [ ] Download notebook without it running
- [ ] Rename notebook without it running
- [ ] Remove any Full Directory Paths in Backend

## Admin area
- [ ] Develop admin area
- [x] Set up separate Julia processes - already implemented in Pluto
- - [x] Investigate how web client works, maybe we cen insert user there?
- - [x] Workspace Manager
- - [x] Check if `open_url` works correctly

## Security
- [ ] Delete full `path` in `Dynamic.jl`. We don't want to show it to the user
- [ ] Add SSL Certificate in Google Cloud
- [ ] Use proper Docket USER and WORKDIR
- [ ] New container per USER 