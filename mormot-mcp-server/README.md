# mormot.ext.mcp
Pure mORMot v2 implementation of the Model Context Protocol (MCP) with JSON‑RPC 2.0, HTTP/SSE and stdio transports.

## Quick start
- Build the demos and tests with Delphi or FPC.
- Run the tests: `mcp.tests`

### Next step
- Integrate the MCP server into your favorite tool - see [preview](#preview)

## Demos (each is a separate program)
- `demo.mcp.jsonrpc`  
  In‑process JSON‑RPC demo (no network).
- `demo.mcp.http [port]`  
  HTTP MCP server.
- `demo.mcp.sse [port]`  
  HTTP/SSE MCP server.
- `demo.mcp.stdio`  
  Line‑delimited JSON‑RPC over stdin/stdout (for CLI/agent/RPC integration).

## Tool parameter schemas
A `TMcpToolBase<T>` tool publishes the JSON Schema of its parameter record `T`,
generated from its RTTI: nested records, arrays, enumerations (by name), dates
and GUIDs. Field names keep their casing. Describe the record with `McpSchema()`
(on FPC 3.2.2, after `Rtti.RegisterFromText()`):
```pascal
McpSchema(TypeInfo(TSearchParams))
  .Description('Search the catalogue')
  .Field('Query').Description('Text to search for').Keyword('minLength', 1)
  .Field('Limit').Description('Maximum number of results').DefaultValue(10)
  .Field('Sort').Optional;
```
A field is required unless it is `Optional` or has a `DefaultValue`, which the
tool receives when the argument is missing. `Keyword()` sets any JSON Schema
2020-12 keyword, and `Replace()` replaces a generated schema (e.g. by a `$ref`).

## MCP Inspector
You can explore your MCP server using the official MCP Inspector. Just run `pnpx @modelcontextprotocol/inspector` (`NodeJS` is required)

## Notes
- `public_ip` uses `https://api.ipify.org?format=json`.
- The stdio transport accepts UTF‑8 and UTF‑16LE input.

## Tested compilers (2026-02-02)
- Delphi 12.3 Athens (Win32)
- Free Pascal 3.3.1 (Linux x64/Win64)

## TODO:
[ ] Add `TRestServerMCP`  
- **Authentication**  
  [ ] mORMot Native Auth  
  [ ] JWT  
  [ ] OAUTH2  
[ ] Implement Streamable HTTP (protocol version 2026-03-26)  

## Preview
<video src="https://github.com/user-attachments/assets/0c9fae49-b9c4-441e-a4ab-76e61e045404" controls muted></video>
### MCP Inspector
![MCP Inspector tools](https://github.com/user-attachments/assets/27734e42-16d0-433d-a70a-759da1dbdd6c)
