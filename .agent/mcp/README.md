# MCP configuration

Claude Code reads project-scoped MCP servers from a single file at the project
root: `.mcp.json`. There is no `.claude/mcp/` directory, so this resource is not
a directory link like `skills/`, `rules/`, `agents/` and `commands/`.

Put the configuration in **`servers.json`** in this directory. The setup script
links it to the project root:

```text
.agent/mcp/servers.json  ->  .mcp.json
```

The file uses Claude Code's `.mcp.json` format verbatim, so no conversion step
is involved:

```json
{
  "mcpServers": {
    "example-http": {
      "type": "http",
      "url": "https://example.com/mcp"
    },
    "example-stdio": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@example/mcp-server"],
      "env": {}
    }
  }
}
```

If `servers.json` is absent the setup script reports `[SKIP]` and leaves the
project root alone; it never creates an empty `.mcp.json`.

Two scopes stay outside this file by design, because Claude Code keeps them in
your home directory rather than the project:

- **local** scope — private to you for this project, in `~/.claude.json`
- **user** scope — yours across all projects, in `~/.claude.json`

Adding a server with `claude mcp add --scope project` writes to `.mcp.json`.
Because that path is a link, the write lands in `servers.json` here, which is
the intended behaviour. On Windows, see the hard link caveat in the repository
`README.md` before editing either side.
