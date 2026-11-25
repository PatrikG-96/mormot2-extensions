/// Model Context Protocol (MCP) Server Implementation for mORMot v2
// - this unit is part of the mormot-mcp-server project
// - licensed under MPL/GPL/LGPL three license
unit mormot.ext.mcp;

{
  *****************************************************************************

    - Core Types and Authentication Context
    - Types of the JSON-RPC, Schema and Content Units
    - IInvokable Interfaces for Tools and Resources
    - Generic Tool and Resource Base Classes
    - Main MCP Server with Tool/Resource Registry

  *****************************************************************************
}

interface

{$I mormot.defines.inc}

uses
  sysutils,
  mormot.core.base,
  mormot.core.os,
  mormot.core.unicode,
  mormot.core.text,
  mormot.core.datetime,
  mormot.core.rtti,
  mormot.core.buffers,
  mormot.core.data,
  mormot.core.variants,
  mormot.core.json,
  mormot.core.collections,
  mormot.core.threads,
  mormot.core.interfaces,
  mormot.core.log,
  mormot.ext.mcp.jsonrpc,
  mormot.ext.mcp.schema,
  mormot.ext.mcp.content;


{ ************ Core Types and Authentication Context }

const
  /// default TMcpServer.PageSize: how many items one list page holds
  MCP_DEFAULT_PAGE_SIZE = 100;

type
  /// Authentication context passed to tool/resource execution
  // - provides user identity and authorization information
  TMcpAuthContext = packed record
    /// whether the request has been authenticated
    IsAuthenticated: boolean;
    /// unique user identifier
    UserID: RawUtf8;
    /// user display name
    UserName: RawUtf8;
    /// assigned roles for authorization
    Roles: TRawUtf8DynArray;
  end;


{ ************ Types of the JSON-RPC, Schema and Content Units }

// - they are defined in the mormot.ext.mcp.jsonrpc, mormot.ext.mcp.schema and
// mormot.ext.mcp.content units: these aliases let code which only uses
// mormot.ext.mcp compile as before

const
  MCP_PROTOCOL_VERSION = mormot.ext.mcp.jsonrpc.MCP_PROTOCOL_VERSION;
  MCP_PROTOCOL_VERSION_20250326 = mormot.ext.mcp.jsonrpc.MCP_PROTOCOL_VERSION_20250326;
  JSONRPC_PARSE_ERROR = mormot.ext.mcp.jsonrpc.JSONRPC_PARSE_ERROR;
  JSONRPC_INVALID_REQUEST = mormot.ext.mcp.jsonrpc.JSONRPC_INVALID_REQUEST;
  JSONRPC_METHOD_NOT_FOUND = mormot.ext.mcp.jsonrpc.JSONRPC_METHOD_NOT_FOUND;
  JSONRPC_INVALID_PARAMS = mormot.ext.mcp.jsonrpc.JSONRPC_INVALID_PARAMS;
  JSONRPC_INTERNAL_ERROR = mormot.ext.mcp.jsonrpc.JSONRPC_INTERNAL_ERROR;
  MCP_RESOURCE_NOT_FOUND = mormot.ext.mcp.jsonrpc.MCP_RESOURCE_NOT_FOUND;
  mmkParseError = mormot.ext.mcp.jsonrpc.mmkParseError;
  mmkInvalid = mormot.ext.mcp.jsonrpc.mmkInvalid;
  mmkRequest = mormot.ext.mcp.jsonrpc.mmkRequest;
  mmkNotification = mormot.ext.mcp.jsonrpc.mmkNotification;
  mmkResponse = mormot.ext.mcp.jsonrpc.mmkResponse;
  mrUser = mormot.ext.mcp.content.mrUser;
  mrAssistant = mormot.ext.mcp.content.mrAssistant;
  mitAny = mormot.ext.mcp.content.mitAny;
  mitLight = mormot.ext.mcp.content.mitLight;
  mitDark = mormot.ext.mcp.content.mitDark;

type
  TMcpError = mormot.ext.mcp.jsonrpc.TMcpError;
  EMcpException = mormot.ext.mcp.jsonrpc.EMcpException;
  EMcpToolError = mormot.ext.mcp.jsonrpc.EMcpToolError;
  TMcpMessageKind = mormot.ext.mcp.jsonrpc.TMcpMessageKind;
  TMcpJsonRpcMessage = mormot.ext.mcp.jsonrpc.TMcpJsonRpcMessage;
  TMcpJsonRpcProcessor = mormot.ext.mcp.jsonrpc.TMcpJsonRpcProcessor;
  TMcpRole = mormot.ext.mcp.content.TMcpRole;
  TMcpRoles = mormot.ext.mcp.content.TMcpRoles;
  TMcpAnnotations = mormot.ext.mcp.content.TMcpAnnotations;
  TMcpIconTheme = mormot.ext.mcp.content.TMcpIconTheme;
  TMcpIcon = mormot.ext.mcp.content.TMcpIcon;
  TMcpIcons = mormot.ext.mcp.content.TMcpIcons;
  TMcpResponseBuilder = mormot.ext.mcp.content.TMcpResponseBuilder;
  TMcpSchemaDefault = mormot.ext.mcp.schema.TMcpSchemaDefault;
  TMcpSchemaDefaults = mormot.ext.mcp.schema.TMcpSchemaDefaults;
  TMcpSchemaMeta = mormot.ext.mcp.schema.TMcpSchemaMeta;
  TMcpSchemaField = mormot.ext.mcp.schema.TMcpSchemaField;
  TMcpSchemaType = mormot.ext.mcp.schema.TMcpSchemaType;
  TMcpSchemaGenerator = mormot.ext.mcp.schema.TMcpSchemaGenerator;

/// return the annotations of a content block or resource
// - see mormot.ext.mcp.content.McpAnnotations()
function McpAnnotations(aAudience: TMcpRoles; aPriority: double = -1;
  aLastModified: TDateTime = 0): TMcpAnnotations;

/// return an icon
// - see mormot.ext.mcp.content.McpIcon()
function McpIcon(const aSrc: RawUtf8; const aMimeType: RawUtf8 = '';
  const aSizes: RawUtf8 = ''; aTheme: TMcpIconTheme = mitAny): TMcpIcon;

/// return the "icons" JSON array of some icons, as a TDocVariant
// - see mormot.ext.mcp.content.McpIconsToVariant()
function McpIconsToVariant(const aIcons: array of TMcpIcon): variant;

/// return the JSON Schema metadata of a type, to describe it and its fields
// - see mormot.ext.mcp.schema.McpSchema()
function McpSchema(aTypeInfo: PRttiInfo): TMcpSchemaType;


{ ************ IInvokable Interfaces for Tools and Resources }

type
  /// MCP Tool interface - represents an executable operation
  IMcpTool = interface(IInvokable)
    ['{8F3C5A1D-9E2B-4F7C-A6D8-3B9E4C5F6A7D}']
    /// return the unique tool name
    function GetName: RawUtf8;
    /// return the human-readable description
    function GetDescription: RawUtf8;
    /// return the JSON schema for input parameters as TDocVariant
    function GetInputSchema: variant;
    /// execute the tool with given arguments and auth context
    // - Args is a TDocVariantData containing the input parameters
    // - returns a CallToolResult TDocVariantData, i.e. a 'content' array of
    // content blocks and an optional 'isError' boolean: see TMcpResponseBuilder
    // - a failure for the model is an 'isError' result: raise EMcpToolError or
    // use TMcpResponseBuilder.SetError; any other exception is logged, and
    // returned as a generic 'isError' result
    // - an invalid result is a JSON-RPC internal error
    function Execute(const Args: variant; const AuthCtx: TMcpAuthContext): variant;
  end;

  /// MCP Resource interface - represents readable data
  IMcpResource = interface(IInvokable)
    ['{7E4D3B2C-8A1F-4E9D-B5C6-2A8E3D4F5B6C}']
    /// return the unique resource URI
    function GetUri: RawUtf8;
    /// return the human-readable name
    function GetName: RawUtf8;
    /// return the resource description
    function GetDescription: RawUtf8;
    /// return the MIME type of the resource content
    function GetMimeType: RawUtf8;
    /// read and return the resource content
    function Read: RawUtf8;
  end;


{ ************ Generic Tool Base Class }

type
  /// Generic base class for strongly-typed MCP tools
  // - T is the input parameters record type
  // - its inputSchema is generated from T's RTTI and McpSchema(TypeInfo(T))
  // metadata, see TMcpSchemaGenerator
  TMcpToolBase<T: record> = class(TInterfacedObject, IMcpTool)
  protected
    fName: RawUtf8;
    fDescription: RawUtf8;
    fSchema: TMcpSchemaType;
    /// override this to implement tool logic
    // - return a CallToolResult, and raise EMcpToolError for a failure which
    // the model should see: see IMcpTool.Execute
    function ExecuteTyped(const aParams: T; const aAuthCtx: TMcpAuthContext): variant; virtual; abstract;
  public
    /// initialize with tool name and description
    constructor Create(const aName, aDescription: RawUtf8); virtual;
    /// IMcpTool implementation
    function GetName: RawUtf8;
    function GetDescription: RawUtf8;
    function GetInputSchema: variant;
    function Execute(const aArgs: variant; const aAuthCtx: TMcpAuthContext): variant;
  end;


{ ************ Resource Base Class }

type
  /// Abstract base class for MCP resources
  TMcpResourceBase = class(TInterfacedObject, IMcpResource)
  protected
    fUri: RawUtf8;
    fName: RawUtf8;
    fDescription: RawUtf8;
    fMimeType: RawUtf8;
    /// override this to provide resource content
    function GetContent: RawUtf8; virtual; abstract;
  public
    /// initialize with resource metadata
    constructor Create(const aUri, aName, aDescription, aMimeType: RawUtf8); virtual;
    /// IMcpResource implementation
    function GetUri: RawUtf8;
    function GetName: RawUtf8;
    function GetDescription: RawUtf8;
    function GetMimeType: RawUtf8;
    function Read: RawUtf8;
  end;


{ ************ Main MCP Server with Registry }

type
  /// Main MCP server with tool/resource registry
  // - thread-safe registration and execution
  // - processes JSON-RPC requests
  TMcpServer = class(TSynPersistent)
  private
    fTools: IKeyValue<RawUtf8, IMcpTool>; // name -> IMcpTool
    fResources: IKeyValue<RawUtf8, IMcpResource>; // uri -> IMcpResource
    fProcessor: TMcpJsonRpcProcessor;
    fActive: boolean;
    fSafe: TLightLock;
    fPageSize: integer;
    function ExecuteToolCall(const aParams: variant; const aAuthCtx: TMcpAuthContext): variant;
    function ExecuteResourceRead(const aParams: variant): variant;
    function ListTools(const aParams: variant): variant;
    function ListResources(const aParams: variant): variant;
    function ExceptionToError(E: Exception;
      const aMessage: TMcpJsonRpcMessage): RawUtf8;
  public
    /// initialize the MCP server
    constructor Create(const aServerName: RawUtf8 = 'M-MCP-Server';
      const aServerVersion: RawUtf8 = '1.0.0'); reintroduce;
    /// finalize and release resources
    destructor Destroy; override;
    /// register a tool implementation
    // - thread-safe, can be called before or after Start
    procedure RegisterTool(const aTool: IMcpTool);
    /// register a resource implementation
    // - thread-safe
    procedure RegisterResource(const aResource: IMcpResource);
    /// unregister a tool by name
    function UnregisterTool(const aName: RawUtf8): boolean;
    /// unregister a resource by URI
    function UnregisterResource(const aUri: RawUtf8): boolean;
    /// start the server (activates tool/resource access)
    procedure Start;
    /// stop the server
    procedure Stop;
    /// process a JSON-RPC request and return JSON response
    // - aSessionId can be used for session-specific operations
    function ExecuteRequest(const aRequestJson: RawUtf8; 
      const aSessionId: RawUtf8 = ''): RawUtf8;
    /// check if server is active
    function IsActive: boolean;
    /// how many items one page of tools/list or resources/list holds
    // - MCP_DEFAULT_PAGE_SIZE by default; 0 sends all items in one page
    // - a client gets the next page by sending back the "nextCursor" it received
    property PageSize: integer
      read fPageSize write fPageSize;
  end;


implementation

type
  /// one page of a list result (tools/list, resources/list, ...)
  // - items are listed in the byte order of their unique key (name or URI)
  // - the cursor is the base64url of {"list":..,"after":..}: the list name and
  // the last key of the previous page, so the server keeps no state per session
  // or per client, and a page continues correctly after items were added or
  // removed in the meantime
  TMcpListPage = record
    List: RawUtf8;      // the result member, e.g. 'tools'
    After: RawUtf8;     // the last key of the previous page
    Continued: boolean; // true if a cursor was sent, i.e. After is set
    Keys: TRawUtf8DynArray;     // all keys, sorted by Select
    Indexes: TIntegerDynArray;  // the registry index of each key
    Count: integer;     // number of Keys
    First, Last: PtrInt; // this page is Keys[First..Last]
    /// read the optional "cursor" param, or raise JSONRPC_INVALID_PARAMS
    procedure Init(const aList: RawUtf8; const aParams: variant);
    /// add the key of the registry item number Count
    procedure Add(const aKey: RawUtf8);
    /// sort the keys and compute First and Last; aPageSize = 0 means no limit
    procedure Select(aPageSize: integer);
    /// return {List: aItems} with a "nextCursor" if more items follow
    function Done(const aItems: TDocVariantData): variant;
  end;


{ ************ Types of the JSON-RPC, Schema and Content Units }

function McpAnnotations(aAudience: TMcpRoles; aPriority: double;
  aLastModified: TDateTime): TMcpAnnotations;
begin
  result := mormot.ext.mcp.content.McpAnnotations(aAudience, aPriority,
    aLastModified);
end;

function McpIcon(const aSrc, aMimeType, aSizes: RawUtf8;
  aTheme: TMcpIconTheme): TMcpIcon;
begin
  result := mormot.ext.mcp.content.McpIcon(aSrc, aMimeType, aSizes, aTheme);
end;

function McpIconsToVariant(const aIcons: array of TMcpIcon): variant;
begin
  result := mormot.ext.mcp.content.McpIconsToVariant(aIcons);
end;

function McpSchema(aTypeInfo: PRttiInfo): TMcpSchemaType;
begin
  result := mormot.ext.mcp.schema.McpSchema(aTypeInfo);
end;


{ ************ TMcpToolBase<T> Implementation }

constructor TMcpToolBase<T>.Create(const aName, aDescription: RawUtf8);
begin
  inherited Create;
  fName := aName;
  fDescription := aDescription;
  fSchema := McpSchema(TypeInfo(T));
end;

function TMcpToolBase<T>.GetName: RawUtf8;
begin
  result := fName;
end;

function TMcpToolBase<T>.GetDescription: RawUtf8;
begin
  result := fDescription;
end;

function TMcpToolBase<T>.GetInputSchema: variant;
begin
  result := _CopyFast(fSchema.Schema); // the caller may modify it
end;

function TMcpToolBase<T>.Execute(const aArgs: variant; 
  const aAuthCtx: TMcpAuthContext): variant;
var
  params: T;
begin
  // Deserialize arguments into typed record, with the missing default values
  // - a missing field without default value is zero
  fSchema.Rtti.ValueFinalizeAndClear(@params);
  RecordLoadJson(params, fSchema.ArgumentsJson(aArgs), TypeInfo(T));

  // Execute typed implementation
  result := ExecuteTyped(params, aAuthCtx);
end;


{ ************ TMcpResourceBase Implementation }

constructor TMcpResourceBase.Create(const aUri, aName, aDescription, aMimeType: RawUtf8);
begin
  inherited Create;
  fUri := aUri;
  fName := aName;
  fDescription := aDescription;
  fMimeType := aMimeType;
end;

function TMcpResourceBase.GetUri: RawUtf8;
begin
  result := fUri;
end;

function TMcpResourceBase.GetName: RawUtf8;
begin
  result := fName;
end;

function TMcpResourceBase.GetDescription: RawUtf8;
begin
  result := fDescription;
end;

function TMcpResourceBase.GetMimeType: RawUtf8;
begin
  result := fMimeType;
end;

function TMcpResourceBase.Read: RawUtf8;
begin
  result := GetContent;
end;


{ ************ TMcpListPage }

procedure TMcpListPage.Init(const aList: RawUtf8; const aParams: variant);
var
  cursor: PVariant;
  doc: TDocVariantData;
  name, json: RawUtf8;
  eoj: AnsiChar;
begin
  List := aList;
  Continued := false;
  Count := 0;
  if not _Safe(aParams)^.GetAsPVariant('cursor', cursor) or
     VarIsEmptyOrNull(cursor^) then
    exit;
  if VarIsString(cursor^) then
  begin
    json := Base64uriToBin(VariantToUtf8(cursor^)); // a private buffer
    // strict parsing: the whole span must be valid JSON (no unquoted names,
    // no NUL or trailing data), and numbers stay numbers
    if IsValidJson(json, true) and
       (doc.InitJsonInPlace(pointer(json), JSON_FAST_FLOAT, @eoj) <> nil) and
       (eoj = #0) and
       GetStringValue(doc, 'list', name) and
       (name = aList) and
       GetStringValue(doc, 'after', After) then
    begin
      Continued := true;
      exit;
    end;
  end;
  raise EMcpException.CreateCode(JSONRPC_INVALID_PARAMS,
    'Invalid cursor for %', [aList]);
end;

procedure TMcpListPage.Add(const aKey: RawUtf8);
begin
  if Count = length(Keys) then
  begin
    SetLength(Keys, NextGrow(Count));
    SetLength(Indexes, length(Keys));
  end;
  Keys[Count] := aKey;
  Indexes[Count] := Count;
  inc(Count);
end;

procedure TMcpListPage.Select(aPageSize: integer);
begin
  QuickSortRawUtf8(Keys, Count, @Indexes); // StrComp order, as below
  First := 0;
  if Continued then
    while (First < Count) and
          (StrComp(pointer(Keys[First]), pointer(After)) <= 0) do
      inc(First);
  Last := Count - 1;
  if (aPageSize > 0) and
     (Last - First >= aPageSize) then
    Last := First + aPageSize - 1;
end;

function TMcpListPage.Done(const aItems: TDocVariantData): variant;
var
  res, cursor: TDocVariantData;
begin
  res.InitFast;
  res.AddValue(List, variant(aItems));
  if Last < Count - 1 then
  begin
    cursor.InitFast;
    cursor.AddValue('list', List);
    cursor.AddValue('after', Keys[Last]);
    res.AddValue('nextCursor', BinToBase64uri(cursor.ToJson));
  end;
  result := variant(res);
end;


{ ************ TMcpServer Implementation }

constructor TMcpServer.Create(const aServerName, aServerVersion: RawUtf8);
begin
  inherited Create;
  fSafe.Init;
  fProcessor := TMcpJsonRpcProcessor.Create(aServerName, aServerVersion);
  fTools := Collections.NewPlainKeyValue<RawUtf8, IMcpTool>;
  fResources := Collections.NewPlainKeyValue<RawUtf8, IMcpResource>;
  fActive := false;
  fPageSize := MCP_DEFAULT_PAGE_SIZE;
end;

destructor TMcpServer.Destroy;
begin
  Stop;
  fTools := nil;
  fResources := nil;
  fProcessor.Free;
  fSafe.Done;
  inherited;
end;

procedure TMcpServer.RegisterTool(const aTool: IMcpTool);
var
  name: RawUtf8;
begin
  if aTool = nil then
    exit;
  name := aTool.GetName;
  fSafe.Lock;
  try
    fTools.Add(name, aTool);
  finally
    fSafe.UnLock;
  end;
end;

procedure TMcpServer.RegisterResource(const aResource: IMcpResource);
var
  uri: RawUtf8;
begin
  if aResource = nil then
    exit;
  uri := aResource.GetUri;
  fSafe.Lock;
  try
    fResources.Add(uri, aResource);
  finally
    fSafe.UnLock;
  end;
end;

function TMcpServer.UnregisterTool(const aName: RawUtf8): boolean;
begin
  fSafe.Lock;
  try
    result := fTools.Remove(aName);
  finally
    fSafe.UnLock;
  end;
end;

function TMcpServer.UnregisterResource(const aUri: RawUtf8): boolean;
begin
  fSafe.Lock;
  try
    result := fResources.Remove(aUri);
  finally
    fSafe.UnLock;
  end;
end;

procedure TMcpServer.Start;
begin
  fSafe.Lock;
  try
    fActive := true;
  finally
    fSafe.UnLock;
  end;
end;

procedure TMcpServer.Stop;
begin
  fSafe.Lock;
  try
    fActive := false;
  finally
    fSafe.UnLock;
  end;
end;

function TMcpServer.IsActive: boolean;
begin
  result := fActive;
end;

function TMcpServer.ListTools(const aParams: variant): variant;
var
  page: TMcpListPage;
  tools: TDocVariantData;
  tool: IMcpTool;
  i: PtrInt;
begin
  page.Init('tools', aParams);
  tools.InitArray([], JSON_FAST);
  fSafe.Lock;
  try
    for i := 0 to fTools.Count - 1 do
      page.Add(fTools.Key[i]);
    page.Select(fPageSize);
    for i := page.First to page.Last do
    begin
      tool := fTools.Value[page.Indexes[i]];
      tools.AddItem(_ObjFast([
        'name', page.Keys[i],
        'description', tool.GetDescription,
        'inputSchema', tool.GetInputSchema]));
    end;
  finally
    fSafe.UnLock;
  end;
  result := page.Done(tools);
end;

function TMcpServer.ListResources(const aParams: variant): variant;
var
  page: TMcpListPage;
  resources: TDocVariantData;
  resource: IMcpResource;
  i: PtrInt;
begin
  page.Init('resources', aParams);
  resources.InitArray([], JSON_FAST);
  fSafe.Lock;
  try
    for i := 0 to fResources.Count - 1 do
      page.Add(fResources.Key[i]);
    page.Select(fPageSize);
    for i := page.First to page.Last do
    begin
      resource := fResources.Value[page.Indexes[i]];
      resources.AddItem(_ObjFast([
        'uri', resource.GetUri,
        'name', resource.GetName,
        'description', resource.GetDescription,
        'mimeType', resource.GetMimeType]));
    end;
  finally
    fSafe.UnLock;
  end;
  result := page.Done(resources);
end;

// case-sensitive lookup, whatever the dvoNameCaseSensitive option of aDoc is
// - JSON_FAST documents find names case-insensitively, but "Content" or "Text"
// would be sent as-is, and are not valid MCP member names
function FindMember(const aDoc: TDocVariantData; const aName: RawUtf8;
  out aValue: PVariant): boolean;
var
  i: integer;
begin
  i := aDoc.GetValueIndex(pointer(aName), length(aName), {casesens=}true);
  result := i >= 0;
  if result then
    aValue := @aDoc.Values[i];
end;

// true if aName is a JSON string member of aDoc
function HasString(const aDoc: TDocVariantData; const aName: RawUtf8): boolean;
var
  v: PVariant;
begin
  result := FindMember(aDoc, aName, v) and
            VarIsString(v^);
end;

// returns '' if aBlock is a valid content block, or why it is not
function CheckContentBlock(const aBlock: variant): RawUtf8;
var
  block, resource: PDocVariantData;
  v: PVariant;
  typ: RawUtf8;
begin
  result := '';
  if not _SafeObject(aBlock, block) then
    result := 'not a JSON object'
  else if not HasString(block^, 'type') then
    result := 'no "type"'
  else
  begin
    FindMember(block^, 'type', v);
    VariantToUtf8(v^, typ);
    if typ = 'text' then
    begin
      if not HasString(block^, 'text') then
        result := 'no "text"';
    end
    else if (typ = 'image') or
            (typ = 'audio') then
    begin
      if not HasString(block^, 'data') or
         not HasString(block^, 'mimeType') then
        result := 'no "data" or "mimeType"';
    end
    else if typ = 'resource_link' then
    begin
      if not HasString(block^, 'uri') or
         not HasString(block^, 'name') then
        result := 'no "uri" or "name"';
    end
    else if typ = 'resource' then
    begin
      if not FindMember(block^, 'resource', v) or
         not _SafeObject(v^, resource) or
         not HasString(resource^, 'uri') or
         not (HasString(resource^, 'text') or
              HasString(resource^, 'blob')) then
        result := 'no "resource" with "uri" and "text" or "blob"';
    end
    else
      result := 'unknown "type"';
  end;
end;

// returns '' if aResult is a valid CallToolResult, or why it is not
function CheckToolResult(const aResult: variant): RawUtf8;
var
  res, content: PDocVariantData;
  v: PVariant;
  i: PtrInt;
begin
  result := '';
  if not _SafeObject(aResult, res) then
    result := 'not a JSON object'
  else if not FindMember(res^, 'content', v) or
          not _SafeArray(v^, content) then
    result := 'no "content" array'
  else if FindMember(res^, 'isError', v) and
          (TVarData(v^).VType <> varBoolean) then
    result := '"isError" is not a boolean'
  else
    for i := 0 to content^.Count - 1 do
    begin
      result := CheckContentBlock(content^.Values[i]);
      if result <> '' then
      begin
        result := FormatUtf8('content[%]: %', [i, result]);
        exit;
      end;
    end;
end;

// the isError result of a tool which raised an exception
// - only an EMcpToolError has its message sent to the model: any other
// exception may have internal details, which only go to the log
function ToolExceptionToResult(E: Exception; const aToolName: RawUtf8): variant;
var
  text: RawUtf8;
begin
  if E is EMcpToolError then
    text := StringToUtf8(E.Message)
  else
  begin
    TSynLog.Add.Log(sllError, 'tools/call %: % raised %',
      [aToolName, ClassNameShort(E)^, E.Message]);
    FormatUtf8('Tool % failed', [aToolName], text);
  end;
  result := _ObjFast([
    'content', _ArrFast([_ObjFast(['type', 'text', 'text', text])]),
    'isError', true]);
end;

function TMcpServer.ExecuteToolCall(const aParams: variant;
  const aAuthCtx: TMcpAuthContext): variant;
var
  doc: PDocVariantData;
  toolName, error: RawUtf8;
  args: variant;
  tool: IMcpTool;
begin
  // protocol errors are JSON-RPC errors
  doc := _Safe(aParams);
  if not GetStringValue(doc^, 'name', toolName) then
    raise EMcpException.CreateCode(JSONRPC_INVALID_PARAMS,
      'Missing tool name in tools/call', []);

  args := doc^.GetValueOrDefault('arguments', Null);

  fSafe.Lock;
  try
    if not fTools.TryGetValue(toolName, tool) then
      raise EMcpException.CreateCode(JSONRPC_INVALID_PARAMS,
        'Tool not found: %', [toolName]);
  finally
    fSafe.UnLock;
  end;

  // tool execution errors are "isError" results, which the model can see
  try
    result := tool.Execute(args, aAuthCtx);
  except
    on E: Exception do
    begin
      if not (E is EMcpToolError) and
         (E is EMcpException) and
         (EMcpException(E).Code <> 0) then
        raise; // a JSON-RPC error raised on purpose
      result := ToolExceptionToResult(E, toolName);
      exit;
    end;
  end;

  // a malformed result is a server bug: an internal error, logged
  error := CheckToolResult(result);
  if error <> '' then
    raise EMcpException.CreateUtf8('Tool % returned an invalid result: %',
      [toolName, error]);
end;

function TMcpServer.ExecuteResourceRead(const aParams: variant): variant;
var
  doc: PDocVariantData;
  uri, content: RawUtf8;
  resource: IMcpResource;
  result_doc, contentsList, contentItem: TDocVariantData;
  notFound: EMcpException;
begin
  doc := _Safe(aParams);
  if not GetStringValue(doc^, 'uri', uri) then
    raise EMcpException.CreateCode(JSONRPC_INVALID_PARAMS,
      'Missing uri in resources/read', []);

  fSafe.Lock;
  try
    if not fResources.TryGetValue(uri, resource) then
    begin
      notFound := EMcpException.CreateCode(MCP_RESOURCE_NOT_FOUND,
        'Resource not found: %', [uri]);
      notFound.Data := _ObjFast(['uri', uri]);
      raise notFound;
    end;
  finally
    fSafe.UnLock;
  end;

  content := resource.Read;

  // Build response
  result_doc.InitObject([], JSON_FAST);
  contentsList.InitArray([], JSON_FAST);
  
  contentItem.InitObject([
    'uri', uri,
    'mimeType', resource.GetMimeType,
    'text', content
  ], JSON_FAST);
  
  contentsList.AddItem(variant(contentItem));
  result_doc.AddValue('contents', variant(contentsList));
  
  result := variant(result_doc);
end;

function TMcpServer.ExecuteRequest(const aRequestJson, aSessionId: RawUtf8): RawUtf8;
var
  msg: TMcpJsonRpcMessage;
  resultData: variant;
  authCtx: TMcpAuthContext;
begin
  result := '';
  case fProcessor.ParseMessage(aRequestJson, msg) of
    mmkParseError, mmkInvalid:
      result := fProcessor.CreateMessageError(msg);
    mmkResponse:
      ; // this server sends no requests yet, so there is nothing to match
    mmkRequest, mmkNotification:
      if not fActive then
      begin
        // notifications MUST NOT receive a response
        if msg.Kind = mmkRequest then
          result := fProcessor.CreateError(msg.Id, JSONRPC_INTERNAL_ERROR,
            'Server not active');
      end
      else
        try
          // Setup auth context (stub for now)
          FillCharFast(authCtx, SizeOf(authCtx), 0);
          authCtx.IsAuthenticated := (aSessionId <> '');
          authCtx.UserID := aSessionId;

          // Dispatch to handler
          if msg.Method = 'initialize' then
            resultData := fProcessor.HandleInitialize(msg.Params)
          else if msg.Method = 'ping' then
            resultData := fProcessor.HandlePing
          else if msg.Method = 'tools/list' then
            resultData := ListTools(msg.Params)
          else if msg.Method = 'tools/call' then
            resultData := ExecuteToolCall(msg.Params, authCtx)
          else if msg.Method = 'resources/list' then
            resultData := ListResources(msg.Params)
          else if msg.Method = 'resources/read' then
            resultData := ExecuteResourceRead(msg.Params)
          else if msg.Kind = mmkNotification then
            // e.g. notifications/initialized: nothing to do yet
            resultData := Null
          else
            raise EMcpException.CreateCode(JSONRPC_METHOD_NOT_FOUND,
              'Method not found: %', [msg.Method]);

          if msg.Kind = mmkRequest then
            result := fProcessor.CreateSuccessResponse(msg.Id, resultData);
        except
          on E: Exception do
            result := ExceptionToError(E, msg);
        end;
  end;
end;

function TMcpServer.ExceptionToError(E: Exception;
  const aMessage: TMcpJsonRpcMessage): RawUtf8;
begin
  result := '';
  if (E is EMcpException) and
     (EMcpException(E).Code <> 0) then
  begin
    // raised on purpose for the client: send its code, message and data
    if aMessage.Kind = mmkRequest then
      result := fProcessor.CreateError(aMessage.Id, EMcpException(E).Code,
        StringToUtf8(E.Message), EMcpException(E).Data);
  end
  else
  begin
    // unexpected: the details may be internal, so they only go to the log
    TSynLog.Add.Log(sllError, '% %: % raised %',
      [aMessage.Method, aMessage.Id, ClassNameShort(E)^, E.Message], self);
    if aMessage.Kind = mmkRequest then
      result := fProcessor.CreateError(aMessage.Id, JSONRPC_INTERNAL_ERROR,
        'Internal error');
  end;
end;


end.
