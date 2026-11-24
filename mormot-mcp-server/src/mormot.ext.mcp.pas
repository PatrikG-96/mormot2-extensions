/// Model Context Protocol (MCP) Server Implementation for mORMot v2
// - this unit is part of the mormot-mcp-server project
// - licensed under MPL/GPL/LGPL three license
unit mormot.ext.mcp;

{
  *****************************************************************************

    - Core Types and Authentication Context
    - IInvokable Interfaces for Tools and Resources
    - RTTI-based Schema Generation
    - JSON-RPC 2.0 Protocol Processor
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
  mormot.core.rtti,
  mormot.core.buffers,
  mormot.core.data,
  mormot.core.variants,
  mormot.core.json,
  mormot.core.collections,
  mormot.core.threads,
  mormot.core.interfaces,
  mormot.core.log;


{ ************ Core Types and Authentication Context }

const
  /// MCP Protocol Version
  MCP_PROTOCOL_VERSION = '2024-11-05';

  /// MCP Protocol Version (2025-03-26 - Streamable HTTP)
  MCP_PROTOCOL_VERSION_20250326 = '2025-03-26';

  /// JSON-RPC 2.0 Error Codes
  JSONRPC_PARSE_ERROR = -32700;
  JSONRPC_INVALID_REQUEST = -32600;
  JSONRPC_METHOD_NOT_FOUND = -32601;
  JSONRPC_INVALID_PARAMS = -32602;
  JSONRPC_INTERNAL_ERROR = -32603;

  /// MCP error code for an unknown resource in resources/read
  // - a SHOULD in the 2025-11-25 specification, which also expects
  // error.data.uri; the 2026-07-28 revision uses JSONRPC_INVALID_PARAMS instead
  MCP_RESOURCE_NOT_FOUND = -32002;

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

  /// MCP-specific error information
  TMcpError = packed record
    /// JSON-RPC error code
    Code: integer;
    /// human-readable error message
    Message: RawUtf8;
    /// optional additional error data
    Data: variant;
  end;

  /// MCP-specific exception class
  // - raise it with CreateCode() for an error meant for the client: its code,
  // message and Data are sent back as the JSON-RPC error
  // - any other exception, including an EMcpException without a Code, is
  // answered with a generic JSONRPC_INTERNAL_ERROR and only logged
  EMcpException = class(ESynException)
  protected
    fCode: integer;
    fData: variant;
  public
    /// raise an error meant for the client, with its JSON-RPC error code
    constructor CreateCode(aCode: integer; const aFormat: RawUtf8;
      const aArgs: array of const);
    /// the JSON-RPC error code, or 0 if the error is not meant for the client
    property Code: integer
      read fCode;
    /// optional value sent as the "data" member of the JSON-RPC error
    property Data: variant
      read fData write fData;
  end;

  /// the kinds of incoming JSON-RPC message, as identified by
  // TMcpJsonRpcProcessor.ParseMessage
  // - mmkParseError: the input is not valid JSON
  // - mmkInvalid: valid JSON, but not a valid JSON-RPC 2.0 message
  // - mmkRequest: has a method and an id, and expects a response
  // - mmkNotification: has a method but no id, and expects no response
  // - mmkResponse: a response from the client (result or error, no method)
  TMcpMessageKind = (
    mmkParseError,
    mmkInvalid,
    mmkRequest,
    mmkNotification,
    mmkResponse);

  /// an incoming JSON-RPC message, as parsed by TMcpJsonRpcProcessor.ParseMessage
  TMcpJsonRpcMessage = record
    /// what kind of message this is
    Kind: TMcpMessageKind;
    /// the method name of a request or notification
    Method: RawUtf8;
    /// the params object, or Unassigned if absent
    Params: variant;
    /// the request id (an integer or a string), or Unassigned if absent
    // or invalid
    Id: variant;
    /// why the message is invalid, for mmkParseError and mmkInvalid
    Error: RawUtf8;
  end;


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
    // - returns a TDocVariantData with 'content' array field
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


{ ************ RTTI-based Schema Generation }

type
  /// JSON Schema metadata, common to TMcpSchemaType and TMcpSchemaField
  TMcpSchemaMeta = class(TSynPersistent)
  protected
    fKeywords: TDocVariantData;
    fReplace: variant;
    procedure SetKeyword(const aName: RawUtf8; const aValue: variant);
    procedure SetReplace(const aSchemaJson: RawUtf8);
    // initialize aSchema from Replace() and return true, or return false
    function InitReplaced(var aSchema: TDocVariantData): boolean;
    procedure AddKeywords(var aSchema: TDocVariantData);
  public
    /// initialize the instance
    constructor Create; override;
  end;

  TMcpSchemaType = class;

  /// JSON Schema metadata of one field of a record (or property of a class)
  // - returned by TMcpSchemaType.Field(): its methods return the same instance,
  // and its Field() method the next field, so that calls can be chained
  TMcpSchemaField = class(TMcpSchemaMeta)
  protected
    fOwner: TMcpSchemaType;
    fName: RawUtf8;
    fOptional: boolean;
  public
    /// set the "description" of this field
    function Description(const aText: RawUtf8): TMcpSchemaField;
    /// set any JSON Schema 2020-12 keyword of this field
    // - e.g. Keyword('minimum', 1), Keyword('pattern', '^[a-z]+$') or
    // Keyword('enum', _ArrFast(['asc', 'desc']))
    // - replaces a generated keyword of the same name
    function Keyword(const aName: RawUtf8; const aValue: variant): TMcpSchemaField;
    /// set the "default" value of this field, and make it optional
    // - the value is in its JSON form, e.g. an enumeration name
    // - same as Keyword('default', aValue)
    function DefaultValue(const aValue: variant): TMcpSchemaField;
    /// make this field optional, i.e. not listed in "required"
    // - by default, a field is required unless it has a default value
    function Optional: TMcpSchemaField;
    /// replace the generated schema of this field by a JSON object
    // - e.g. '{"$ref":"#/$defs/Address"}', with "$defs" set by a Keyword() of
    // the type which contains this field
    // - the Description(), Keyword() and DefaultValue() of this field are
    // still added to this JSON object
    // - raise EMcpException if aSchemaJson is not a JSON object
    function Replace(const aSchemaJson: RawUtf8): TMcpSchemaField;
    /// return the metadata of another field of the same type
    // - as TMcpSchemaType.Field(), to chain the calls
    function Field(const aName: RawUtf8): TMcpSchemaField;
    /// false if this field was made Optional or has a default value
    function IsRequired: boolean;
    /// the type which contains this field
    property Owner: TMcpSchemaType
      read fOwner;
    /// the name of this field, as in the RTTI
    property Name: RawUtf8
      read fName;
  end;

  /// JSON Schema metadata of a type, and its generated schema
  // - retrieve the single instance of a type with McpSchema(), e.g.
  // ! McpSchema(TypeInfo(TSearchParams))
  // !   .Description('Search the catalogue')
  // !   .Field('Query').Description('Text to search for')
  // !   .Field('Limit').Description('Maximum number of results').DefaultValue(10)
  // !   .Field('Sort').Optional;
  // - on FPC 3.2.2, call Rtti.RegisterFromText() first, so that the record
  // has its field names
  // - the metadata applies wherever the type is used, e.g. as a nested record
  // - set the metadata once at startup: it is thread-safe, but any change
  // makes all the schemas be generated again
  TMcpSchemaType = class(TMcpSchemaMeta)
  protected
    fRtti: TRttiCustom;
    fFields: array of TMcpSchemaField;
    fSchema: variant;
    fDefaults: RawUtf8;
    fVersion: integer;
    procedure Prepare; // caller should have locked SchemaSafe
  public
    /// initialize the metadata of a type - use McpSchema() instead
    constructor CreateFrom(aRtti: TRttiCustom);
    /// finalize the instance and its fields metadata
    destructor Destroy; override;
    /// set the "description" of this type
    // - a field of this type may override it with its own description
    function Description(const aText: RawUtf8): TMcpSchemaType;
    /// set any JSON Schema 2020-12 keyword of this type
    // - e.g. Keyword('title', 'Search'), or Keyword('$defs', ...) for the
    // "$ref" of a TMcpSchemaField.Replace()
    // - replaces a generated keyword of the same name
    function Keyword(const aName: RawUtf8; const aValue: variant): TMcpSchemaType;
    /// replace the generated schema of this type by a JSON object
    // - e.g. for a type with a custom JSON serializer
    // - the Description() and Keyword() of this type are still added
    // - raise EMcpException if aSchemaJson is not a JSON object
    function Replace(const aSchemaJson: RawUtf8): TMcpSchemaType;
    /// return the metadata of a field of this record or class
    // - the field name is case-insensitive
    // - raise EMcpException if the type has no such field in its RTTI
    function Field(const aName: RawUtf8): TMcpSchemaField;
    /// return the metadata of a field, or nil if none was set
    function FindField(const aName: RawUtf8): TMcpSchemaField;
    /// the JSON Schema of this type, as a TDocVariant object
    // - generated on first call, then cached until any metadata changes
    // - the returned variant is shared: make a _Copy() before modifying it
    function Schema: variant;
    /// reset a record of this type, then set the DefaultValue() of its
    // fields, including the fields of its nested records
    // - TMcpToolBase<T> calls it before reading the tool arguments, so that
    // a missing argument gets its published default value, or zero
    procedure ClearWithDefaults(var aRecord);
    /// the RTTI of this type
    property Rtti: TRttiCustom
      read fRtti;
  end;

  /// generate a JSON Schema (2020-12 dialect) from the RTTI of a type
  // - records and classes are objects, with "properties" in the casing of
  // their fields and all fields "required"; a record without any field (a
  // tool without parameters) is {"type":"object","additionalProperties":false}
  // - dynamic and static arrays have "items", enumerations an "enum" of their
  // names without the lowercase prefix (scRed -> Red) or their custom texts,
  // sets an array of those names, nested records their own properties
  // - mORMot reads both these names and the full RTTI names
  // - TDateTime, TTimeLog, TUnixTime and TUnixMSTime are "date-time" strings,
  // TDate a "date" string, TGuid a "uuid" string and RawByteString a base64
  // string: the text forms which mORMot reads from JSON
  // - a type which refers to itself (e.g. through a dynamic array) is written
  // once, in "$defs", then referenced with "$ref"
  // - variant, RawJson, interfaces and custom types accept any JSON value ({})
  // - descriptions, optional fields, default values and any other keyword
  // come from the McpSchema() metadata of each type
  TMcpSchemaGenerator = class
  public
    /// return the JSON Schema of a type, as a TDocVariant object
    // - same as McpSchema(aTypeInfo).Schema: generated once, then cached
    // - the returned variant is shared: make a _Copy() before modifying it
    class function GenerateSchema(aTypeInfo: PRttiInfo): variant;
  end;

/// return the JSON Schema metadata of a type, to describe it and its fields
// - there is a single instance per type, owned by its TRttiCustom
// - raise EMcpException if aTypeInfo is nil
function McpSchema(aTypeInfo: PRttiInfo): TMcpSchemaType;


{ ************ JSON-RPC 2.0 Protocol Processor }

type
  /// Stateless JSON-RPC 2.0 request/response processor for MCP
  // - handles all MCP protocol methods
  TMcpJsonRpcProcessor = class
  private
    fServerName: RawUtf8;
    fServerVersion: RawUtf8;
    fProtocolVersion: RawUtf8;
  public
    /// initialize with server information
    constructor Create(const aServerName, aServerVersion: RawUtf8);
    /// parse and validate one incoming JSON-RPC message
    // - never raises: returns mmkParseError or mmkInvalid (with aMessage.Error)
    // for input which is not a valid JSON-RPC 2.0 message
    class function ParseMessage(const aJson: RawUtf8;
      out aMessage: TMcpJsonRpcMessage): TMcpMessageKind;
    /// parse a JSON-RPC body, which may be a JSON object or a JSON array
    // - the input must be strict JSON: trailing text, comments or unquoted
    // names are a parse error
    // - returns false, with aMessage.Kind set to mmkParseError or mmkInvalid,
    // if aJson is not a JSON object or array
    class function ParseJson(const aJson: RawUtf8; var aDoc: TDocVariantData;
      out aMessage: TMcpJsonRpcMessage): boolean;
    /// validate one already parsed JSON-RPC message
    // - aDoc should have been parsed with JSON_FAST_FLOAT, so that a floating
    // point id is not mistaken for a string
    class function ParseMessageDoc(const aDoc: TDocVariantData;
      out aMessage: TMcpJsonRpcMessage): TMcpMessageKind;
    /// create a successful JSON-RPC response
    class function CreateSuccessResponse(const aRequestId, aResult: variant): RawUtf8;
    /// create an error JSON-RPC response
    // - the "id" member is omitted if aRequestId is Unassigned or Null
    // - the "data" member is omitted if aData is Unassigned or Null
    class function CreateError(const aRequestId: variant; aErrorCode: integer;
      const aErrorMsg: RawUtf8; const aData: variant): RawUtf8; overload;
    /// create an error JSON-RPC response, with no "data" member
    class function CreateError(const aRequestId: variant; aErrorCode: integer;
      const aErrorMsg: RawUtf8): RawUtf8; overload;
    /// create the error response for a mmkParseError or mmkInvalid message
    // - JSONRPC_PARSE_ERROR or JSONRPC_INVALID_REQUEST, with the id if readable
    class function CreateMessageError(const aMessage: TMcpJsonRpcMessage): RawUtf8;
    /// handle 'initialize' method
    function HandleInitialize(const aParams: variant): variant;
    /// handle 'ping' method
    function HandlePing: variant;
    /// the server name exposed in initialize response
    property ServerName: RawUtf8 read fServerName write fServerName;
    /// the server version exposed in initialize response
    property ServerVersion: RawUtf8 read fServerVersion write fServerVersion;
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
    function ExecuteToolCall(const aParams: variant; const aAuthCtx: TMcpAuthContext): variant;
    function ExecuteResourceRead(const aParams: variant): variant;
    function ListTools: variant;
    function ListResources: variant;
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
  end;


{ ************ Response Builder Helper }

type
  /// Helper to build MCP tool responses with content array
  TMcpResponseBuilder = class
  private
    fContent: TDocVariantData;
  public
    /// initialize builder
    constructor Create;
    /// add text content block
    function AddText(const aText: RawUtf8): TMcpResponseBuilder;
    /// add base64-encoded file content
    function AddFile(const aFilePath: RawUtf8; const aFileName: RawUtf8 = ''): TMcpResponseBuilder;
    /// build final response as variant
    function Build: variant;
  end;


implementation


{ ************ EMcpException }

constructor EMcpException.CreateCode(aCode: integer; const aFormat: RawUtf8;
  const aArgs: array of const);
begin
  CreateUtf8(aFormat, aArgs);
  fCode := aCode;
end;


{ ************ TMcpSchemaGenerator Implementation }

var
  // protects all TMcpSchemaMeta instances and the cached schemas
  SchemaSafe: TLightLock;
  // incremented on each metadata change, to generate the schemas again
  SchemaVersion: integer;

{ TMcpSchemaMeta }

constructor TMcpSchemaMeta.Create;
begin
  inherited Create;
  fKeywords.InitFast(dvObject);
end;

procedure TMcpSchemaMeta.SetKeyword(const aName: RawUtf8; const aValue: variant);
begin
  SchemaSafe.Lock;
  try
    fKeywords.AddOrUpdateValue(aName, aValue);
    inc(SchemaVersion);
  finally
    SchemaSafe.UnLock;
  end;
end;

procedure TMcpSchemaMeta.SetReplace(const aSchemaJson: RawUtf8);
var
  schema: variant;
begin
  schema := _JsonFast(aSchemaJson);
  if not _Safe(schema)^.IsObject then
    raise EMcpException.CreateUtf8('%.Replace(%): not a JSON object',
      [self, aSchemaJson]);
  SchemaSafe.Lock;
  try
    fReplace := schema;
    inc(SchemaVersion);
  finally
    SchemaSafe.UnLock;
  end;
end;

function TMcpSchemaMeta.InitReplaced(var aSchema: TDocVariantData): boolean;
begin
  result := not VarIsEmptyOrNull(fReplace);
  if result then
    aSchema.InitCopy(fReplace, JSON_FAST); // never modify fReplace itself
end;

procedure TMcpSchemaMeta.AddKeywords(var aSchema: TDocVariantData);
var
  i: PtrInt;
begin
  for i := 0 to fKeywords.Count - 1 do
    aSchema.AddOrUpdateValue(fKeywords.Names[i], fKeywords.Values[i]);
end;

{ TMcpSchemaField }

function TMcpSchemaField.Description(const aText: RawUtf8): TMcpSchemaField;
begin
  SetKeyword('description', RawUtf8ToVariant(aText));
  result := self;
end;

function TMcpSchemaField.Keyword(const aName: RawUtf8;
  const aValue: variant): TMcpSchemaField;
begin
  SetKeyword(aName, aValue);
  result := self;
end;

function TMcpSchemaField.DefaultValue(const aValue: variant): TMcpSchemaField;
begin
  SetKeyword('default', aValue);
  result := self;
end;

function TMcpSchemaField.Optional: TMcpSchemaField;
begin
  SchemaSafe.Lock;
  try
    fOptional := true;
    inc(SchemaVersion);
  finally
    SchemaSafe.UnLock;
  end;
  result := self;
end;

function TMcpSchemaField.Replace(const aSchemaJson: RawUtf8): TMcpSchemaField;
begin
  SetReplace(aSchemaJson);
  result := self;
end;

function TMcpSchemaField.Field(const aName: RawUtf8): TMcpSchemaField;
begin
  result := fOwner.Field(aName);
end;

function TMcpSchemaField.IsRequired: boolean;
begin
  result := not fOptional and
            not fKeywords.Exists('default');
end;

{ TMcpSchemaType }

constructor TMcpSchemaType.CreateFrom(aRtti: TRttiCustom);
begin
  Create;
  fRtti := aRtti;
end;

destructor TMcpSchemaType.Destroy;
begin
  ObjArrayClear(fFields);
  inherited Destroy;
end;

function TMcpSchemaType.Description(const aText: RawUtf8): TMcpSchemaType;
begin
  SetKeyword('description', RawUtf8ToVariant(aText));
  result := self;
end;

function TMcpSchemaType.Keyword(const aName: RawUtf8;
  const aValue: variant): TMcpSchemaType;
begin
  SetKeyword(aName, aValue);
  result := self;
end;

function TMcpSchemaType.Replace(const aSchemaJson: RawUtf8): TMcpSchemaType;
begin
  SetReplace(aSchemaJson);
  result := self;
end;

function TMcpSchemaType.FindField(const aName: RawUtf8): TMcpSchemaField;
var
  i: PtrInt;
begin
  for i := 0 to length(fFields) - 1 do
  begin
    result := fFields[i];
    if IdemPropNameU(result.fName, aName) then
      exit;
  end;
  result := nil;
end;

function TMcpSchemaType.Field(const aName: RawUtf8): TMcpSchemaField;
var
  p: PRttiCustomProp;
begin
  p := fRtti.Props.Find(aName);
  if p = nil then
    raise EMcpException.CreateUtf8('McpSchema(%).Field(%): unknown field ' +
      '(on FPC, call Rtti.RegisterFromText first)', [fRtti.Name, aName]);
  SchemaSafe.Lock;
  try
    result := FindField(p^.Name);
    if result = nil then
    begin
      result := TMcpSchemaField.Create;
      result.fOwner := self;
      result.fName := p^.Name;
      ObjArrayAdd(fFields, result);
    end;
  finally
    SchemaSafe.UnLock;
  end;
end;

function McpSchema(aTypeInfo: PRttiInfo): TMcpSchemaType;
var
  rc: TRttiCustom;
begin
  rc := Rtti.RegisterType(aTypeInfo);
  if rc = nil then
    raise EMcpException.Create('McpSchema(nil)');
  result := rc.GetPrivateSlot(TMcpSchemaType);
  if result = nil then
    result := rc.SetPrivateSlot(TMcpSchemaType.CreateFrom(rc));
end;

type
  /// a record or class being written, to detect recursive types
  PSchemaFrame = ^TSchemaFrame;
  TSchemaFrame = record
    Rtti: TRttiCustom;
    Parent: PSchemaFrame;
  end;

  /// write the JSON Schema of one type from its RTTI and McpSchema() metadata
  TSchemaWriter = record
    Root: TRttiCustom;
    Top: PSchemaFrame;
    Defs: TPointerDynArray; // recursive types, to be written in "$defs"
    function IsRecursive(aRtti: TRttiCustom): boolean;
    procedure AddEnum(aRtti: TRttiCustom; var aSchema: TDocVariantData);
    procedure WriteRef(aRtti: TRttiCustom; var aSchema: TDocVariantData);
    procedure WriteObject(aRtti: TRttiCustom; aMeta: TMcpSchemaType;
      var aSchema: TDocVariantData);
    procedure WriteType(aRtti: TRttiCustom; var aSchema: TDocVariantData);
    procedure WriteRoot(aRtti: TRttiCustom; var aSchema: TDocVariantData);
  end;

function TSchemaWriter.IsRecursive(aRtti: TRttiCustom): boolean;
var
  f: PSchemaFrame;
begin
  result := true;
  f := Top;
  while f <> nil do
    if f^.Rtti = aRtti then
      exit
    else
      f := f^.Parent;
  result := false;
end;

procedure TSchemaWriter.AddEnum(aRtti: TRttiCustom; var aSchema: TDocVariantData);
var
  names: TRawUtf8DynArray;
  enum: TDocVariantData;
  i: PtrInt;
begin
  // custom texts, or the names without their lowercase prefix (scRed -> Red),
  // which GetEnumFromText() and SetNamesValue() read as well as the full names
  if aRtti.Cache.EnumCustomText <> nil then
  begin
    enum.InitFast(dvArray);
    for i := aRtti.Cache.EnumMin to aRtti.Cache.EnumMax do
      if aRtti.Cache.EnumCustomText^[i] <> '' then
        enum.AddItemText(aRtti.Cache.EnumCustomText^[i]);
  end
  else
  begin
    aRtti.Cache.EnumInfo^.GetEnumNames(names, scTrimLeft);
    enum.InitArrayFrom(names, JSON_FAST);
  end;
  aSchema.AddValueText('type', 'string');
  aSchema.AddValue('enum', variant(enum));
end;

procedure TSchemaWriter.WriteRef(aRtti: TRttiCustom; var aSchema: TDocVariantData);
begin
  if aRtti = Root then
    aSchema.AddValueText('$ref', '#')
  else
  begin
    PtrArrayAddOnce(Defs, aRtti);
    aSchema.AddValueText('$ref', '#/$defs/' + aRtti.Name);
  end;
end;

procedure TSchemaWriter.WriteObject(aRtti: TRttiCustom; aMeta: TMcpSchemaType;
  var aSchema: TDocVariantData);
var
  frame: TSchemaFrame;
  props, required, schema: TDocVariantData;
  field: TMcpSchemaField;
  p: PRttiCustomProp;
  i: PtrInt;
begin
  frame.Rtti := aRtti;
  frame.Parent := Top;
  Top := @frame;
  props.InitFast(dvObject);
  required.InitFast(dvArray);
  p := pointer(aRtti.Props.List);
  for i := 1 to aRtti.Props.Count do
  begin
    if p^.Name <> '' then
    begin
      field := nil;
      if aMeta <> nil then
        field := aMeta.FindField(p^.Name);
      if (field = nil) or
         not field.InitReplaced(schema) then
        WriteType(p^.Value, schema);
      if field <> nil then
        field.AddKeywords(schema);
      props.AddValue(p^.Name, variant(schema));
      schema.Clear;
      if (field = nil) or
         field.IsRequired then
        required.AddItemText(p^.Name);
    end;
    inc(p);
  end;
  aSchema.AddValueText('type', 'object');
  if props.Count <> 0 then
  begin
    aSchema.AddValue('properties', variant(props));
    if required.Count <> 0 then
      aSchema.AddValue('required', variant(required));
  end
  else if (aRtti.Kind in rkRecordTypes) and
          (aRtti.Size <> 0) then
    // e.g. on FPC 3.2.2, which has no field names in its record RTTI
    TSynLog.Add.Log(sllWarning, 'TMcpSchemaGenerator: % has no field ' +
      'RTTI - call Rtti.RegisterFromText()', [aRtti.Name])
  else
    aSchema.AddValue('additionalProperties', false);
  Top := frame.Parent;
end;

procedure TSchemaWriter.WriteType(aRtti: TRttiCustom; var aSchema: TDocVariantData);
var
  meta: TMcpSchemaType;
  items: TDocVariantData;
begin
  meta := nil;
  if aRtti <> nil then
    meta := aRtti.GetPrivateSlot(TMcpSchemaType);
  if (meta = nil) or
     not meta.InitReplaced(aSchema) then
  begin
    aSchema.InitFast(dvObject);
    if aRtti <> nil then
      case aRtti.Parser of
        ptBoolean:
          aSchema.AddValueText('type', 'boolean');
        ptByte, ptWord, ptCardinal, ptInteger, ptInt64, ptQWord, ptOrm:
          aSchema.AddValueText('type', 'integer');
        ptCurrency, ptSingle, ptDouble, ptExtended:
          aSchema.AddValueText('type', 'number');
        ptRawUtf8, ptString, ptSynUnicode, ptUnicodeString, ptWideString,
        ptWinAnsi, ptPUtf8Char, ptHash128, ptHash256, ptHash512:
          aSchema.AddValueText('type', 'string');
        ptRawByteString:
          aSchema.Update(['type', 'string', 'contentEncoding', 'base64']);
        ptGuid:
          aSchema.Update(['type', 'string', 'format', 'uuid']);
        ptDateTime, ptDateTimeMS:
          if aRtti.Cache.IsPureDate then
            aSchema.Update(['type', 'string', 'format', 'date'])
          else
            aSchema.Update(['type', 'string', 'format', 'date-time']);
        ptTimeLog, ptUnixTime, ptUnixMSTime:
          // stored as integers, but read from ISO-8601 text
          aSchema.Update(['type', 'string', 'format', 'date-time']);
        ptEnumeration:
          AddEnum(aRtti, aSchema);
        ptSet:
          begin
            items.InitFast(dvObject);
            AddEnum(aRtti, items);
            aSchema.AddValueText('type', 'array');
            aSchema.AddValue('items', variant(items));
            aSchema.AddValue('uniqueItems', true);
          end;
        ptArray, ptDynArray:
          begin
            aSchema.AddValueText('type', 'array');
            if aRtti.ArrayRtti <> nil then
            begin
              WriteType(aRtti.ArrayRtti, items);
              aSchema.AddValue('items', variant(items));
            end;
            if aRtti.Parser = ptArray then
              aSchema.Update(['minItems', aRtti.Cache.ItemCount,
                              'maxItems', aRtti.Cache.ItemCount]);
          end;
        ptRecord, ptClass:
          if IsRecursive(aRtti) then
          begin
            WriteRef(aRtti, aSchema);
            exit; // the keywords are in the referenced schema
          end
          else
            WriteObject(aRtti, meta, aSchema);
      end; // ptVariant, ptRawJson, ptInterface, ptCustom: any JSON value
  end;
  if meta <> nil then
    meta.AddKeywords(aSchema);
end;

procedure TSchemaWriter.WriteRoot(aRtti: TRttiCustom; var aSchema: TDocVariantData);
var
  all, def: TDocVariantData;
  i: PtrInt;
begin
  Root := aRtti;
  Top := nil;
  Defs := nil;
  WriteType(aRtti, aSchema);
  if Defs = nil then
    exit;
  all.InitFast(dvObject);
  i := 0;
  while i < length(Defs) do // Defs may grow during the loop
  begin
    WriteType(Defs[i], def);
    all.AddValue(TRttiCustom(Defs[i]).Name, variant(def));
    def.Clear;
    inc(i);
  end;
  aSchema.AddValue('$defs', variant(all));
end;

// add the DefaultValue() of the fields of aRtti, and of its nested records
procedure AddDefaults(aRtti: TRttiCustom; var aDefaults: TDocVariantData);
var
  meta: TMcpSchemaType;
  field: TMcpSchemaField;
  nested: TDocVariantData;
  value: PVariant;
  p: PRttiCustomProp;
  i: PtrInt;
begin
  meta := aRtti.GetPrivateSlot(TMcpSchemaType);
  p := pointer(aRtti.Props.List);
  for i := 1 to aRtti.Props.Count do
  begin
    if p^.Name <> '' then
    begin
      field := nil;
      if meta <> nil then
        field := meta.FindField(p^.Name);
      if (field <> nil) and
         field.fKeywords.GetAsPVariant('default', value) then
        aDefaults.AddValue(p^.Name, value^)
      else if p^.Value.Parser = ptRecord then
      begin
        nested.InitFast(dvObject);
        AddDefaults(p^.Value, nested);
        if nested.Count <> 0 then
          aDefaults.AddValue(p^.Name, variant(nested));
        nested.Clear;
      end;
    end;
    inc(p);
  end;
end;

procedure TMcpSchemaType.Prepare;
var
  w: TSchemaWriter;
  defaults: TDocVariantData;
begin
  if not VarIsEmptyOrNull(fSchema) and
     (fVersion = SchemaVersion) then
    exit;
  VarClear(fSchema);
  w.WriteRoot(fRtti, TDocVariantData(fSchema));
  defaults.InitFast(dvObject);
  if fRtti.Kind in rkRecordTypes then
    AddDefaults(fRtti, defaults);
  if defaults.Count = 0 then
    fDefaults := ''
  else
    fDefaults := defaults.ToJson;
  fVersion := SchemaVersion;
end;

function TMcpSchemaType.Schema: variant;
begin
  SchemaSafe.Lock;
  try
    Prepare;
    result := fSchema;
  finally
    SchemaSafe.UnLock;
  end;
end;

procedure TMcpSchemaType.ClearWithDefaults(var aRecord);
var
  defaults: RawUtf8;
begin
  if not (fRtti.Kind in rkRecordTypes) then
    raise EMcpException.CreateUtf8('McpSchema(%).ClearWithDefaults: ' +
      'not a record', [fRtti.Name]);
  fRtti.ValueFinalizeAndClear(@aRecord);
  SchemaSafe.Lock;
  try
    Prepare;
    defaults := fDefaults;
  finally
    SchemaSafe.UnLock;
  end;
  if defaults <> '' then
    RecordLoadJson(aRecord, defaults, fRtti.Info);
end;

class function TMcpSchemaGenerator.GenerateSchema(aTypeInfo: PRttiInfo): variant;
begin
  result := McpSchema(aTypeInfo).Schema;
end;


{ ************ TMcpJsonRpcProcessor Implementation }

constructor TMcpJsonRpcProcessor.Create(const aServerName, aServerVersion: RawUtf8);
begin
  inherited Create;
  fServerName := aServerName;
  fServerVersion := aServerVersion;
  fProtocolVersion := MCP_PROTOCOL_VERSION;
end;

// true if aName is a JSON string member of aDoc (numbers are not converted)
function GetStringValue(const aDoc: TDocVariantData; const aName: RawUtf8;
  out aValue: RawUtf8): boolean;
var
  v: PVariant;
begin
  result := aDoc.GetAsPVariant(aName, v) and VarIsString(v^);
  if result then
    aValue := VariantToUtf8(v^);
end;

// start a message with "jsonrpc" and the "id" member, if any
// - the id is left out when unknown: MCP doesn't allow "id": null
procedure InitMessage(var aDoc: TDocVariantData; const aRequestId: variant);
begin
  aDoc.InitFast;
  aDoc.AddValue('jsonrpc', '2.0');
  if not VarIsEmptyOrNull(aRequestId) then
    aDoc.AddValue('id', aRequestId);
end;

class function TMcpJsonRpcProcessor.ParseMessage(const aJson: RawUtf8;
  out aMessage: TMcpJsonRpcMessage): TMcpMessageKind;
var
  doc: TDocVariantData;
begin
  if ParseJson(aJson, doc, aMessage) then
    result := ParseMessageDoc(doc, aMessage)
  else
    result := aMessage.Kind;
end;

class function TMcpJsonRpcProcessor.ParseJson(const aJson: RawUtf8;
  var aDoc: TDocVariantData; out aMessage: TMcpJsonRpcMessage): boolean;
var
  valid: boolean;
begin
  // InitJson alone accepts trailing text, comments and unquoted names:
  // check the whole input as strict JSON first
  valid := IsValidJson(aJson, {strict=}true);
  // JSON_FAST_FLOAT: with JSON_FAST, 1e5 would be parsed as a string
  result := valid and
            aDoc.InitJson(aJson, JSON_FAST_FLOAT);
  if result then
    exit;
  if valid and
     not (GotoNextNotSpace(pointer(aJson))^ in ['{', '[']) then
  begin
    // valid JSON, but neither an object nor an array (e.g. "ping" or 1)
    aMessage.Kind := mmkInvalid;
    aMessage.Error := 'Invalid Request: not a JSON object';
  end
  else
  begin
    aMessage.Kind := mmkParseError;
    aMessage.Error := 'Parse error';
  end;
end;

class function TMcpJsonRpcProcessor.ParseMessageDoc(const aDoc: TDocVariantData;
  out aMessage: TMcpJsonRpcMessage): TMcpMessageKind;
var
  v: PVariant;
  hasId: boolean;
  version: RawUtf8;
begin
  result := mmkInvalid;
  aMessage.Kind := mmkInvalid;
  if not aDoc.IsObject then
  begin
    aMessage.Error := 'Invalid Request: not a JSON object';
    exit;
  end;
  // read the id first, so that it can be echoed in an error response
  hasId := aDoc.GetAsPVariant('id', v);
  if hasId then
    case TVarData(v^).VType of
      varInteger, varInt64, varString:
        aMessage.Id := v^;
    end;
  if not GetStringValue(aDoc, 'jsonrpc', version) or
     (version <> '2.0') then
    aMessage.Error := 'Invalid Request: jsonrpc must be "2.0"'
  else if not aDoc.GetAsPVariant('method', v) then
    if aDoc.Exists('result') or
       aDoc.Exists('error') then
      result := mmkResponse
    else
      aMessage.Error := 'Invalid Request: missing method'
  else if not VarIsString(v^) then
    aMessage.Error := 'Invalid Request: method must be a string'
  else if hasId and VarIsEmptyOrNull(aMessage.Id) then
    aMessage.Error := 'Invalid Request: id must be a string or an integer'
  else
  begin
    aMessage.Method := VariantToUtf8(v^);
    if aDoc.GetAsPVariant('params', v) then
      if _Safe(v^)^.IsObject then
        aMessage.Params := v^
      else
      begin
        aMessage.Error := 'Invalid Request: params must be an object';
        exit;
      end;
    if hasId then
      result := mmkRequest
    else
      result := mmkNotification;
  end;
  aMessage.Kind := result;
end;

class function TMcpJsonRpcProcessor.CreateSuccessResponse(
  const aRequestId, aResult: variant): RawUtf8;
var
  doc: TDocVariantData;
begin
  InitMessage(doc, aRequestId);
  doc.AddValue('result', aResult);
  result := doc.ToJson;
end;

class function TMcpJsonRpcProcessor.CreateError(const aRequestId: variant;
  aErrorCode: integer; const aErrorMsg: RawUtf8; const aData: variant): RawUtf8;
var
  doc: TDocVariantData;
  error: variant;
begin
  error := _ObjFast(['code', aErrorCode, 'message', aErrorMsg]);
  if not VarIsEmptyOrNull(aData) then
    TDocVariantData(error).AddValue('data', aData);
  InitMessage(doc, aRequestId);
  doc.AddValue('error', error);
  result := doc.ToJson;
end;

class function TMcpJsonRpcProcessor.CreateError(const aRequestId: variant;
  aErrorCode: integer; const aErrorMsg: RawUtf8): RawUtf8;
begin
  result := CreateError(aRequestId, aErrorCode, aErrorMsg, Null);
end;

class function TMcpJsonRpcProcessor.CreateMessageError(
  const aMessage: TMcpJsonRpcMessage): RawUtf8;
begin
  if aMessage.Kind = mmkParseError then
    result := CreateError(Unassigned, JSONRPC_PARSE_ERROR, aMessage.Error)
  else
    result := CreateError(aMessage.Id, JSONRPC_INVALID_REQUEST, aMessage.Error);
end;

function TMcpJsonRpcProcessor.HandleInitialize(const aParams: variant): variant;
var
  result_doc, capabilities, serverInfo: TDocVariantData;
begin
  result_doc.InitObject(['protocolVersion', fProtocolVersion], JSON_FAST);
  
  // Add capabilities
  capabilities.InitObject([], JSON_FAST);
  capabilities.AddValue('tools', _ObjFast([]));
  capabilities.AddValue('resources', _ObjFast([]));
  result_doc.AddValue('capabilities', variant(capabilities));
  
  // Add server info
  serverInfo.InitObject(['name', fServerName, 'version', fServerVersion], JSON_FAST);
  result_doc.AddValue('serverInfo', variant(serverInfo));
  
  result := variant(result_doc);
end;

function TMcpJsonRpcProcessor.HandlePing: variant;
begin
  result := _Obj([]);
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
  result := fSchema.Schema;
end;

function TMcpToolBase<T>.Execute(const aArgs: variant; 
  const aAuthCtx: TMcpAuthContext): variant;
var
  params: T;
  doc: PDocVariantData;
  json: RawUtf8;
begin
  // Deserialize arguments into typed record, over the default values
  if _Safe(aArgs, doc) then
    json := doc^.ToJson
  else
    json := '{}';
  fSchema.ClearWithDefaults(params);
  RecordLoadJson(params, json, TypeInfo(T));
  
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


{ ************ TMcpServer Implementation }

constructor TMcpServer.Create(const aServerName, aServerVersion: RawUtf8);
begin
  inherited Create;
  fSafe.Init;
  fProcessor := TMcpJsonRpcProcessor.Create(aServerName, aServerVersion);
  fTools := Collections.NewPlainKeyValue<RawUtf8, IMcpTool>;
  fResources := Collections.NewPlainKeyValue<RawUtf8, IMcpResource>;
  fActive := false;
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

function TMcpServer.ListTools: variant;
var
  doc, toolsList: TDocVariantData;
  toolObj: TDocVariantData;
  pair: TPair<RawUtf8, IMcpTool>;
begin
  doc.InitObject([], JSON_FAST);
  toolsList.InitArray([], JSON_FAST);

  fSafe.Lock;
  try
    for pair in fTools do
    begin
      toolObj.InitObject([
        'name', pair.Key,
        'description', pair.Value.GetDescription,
        'inputSchema', pair.Value.GetInputSchema
      ], JSON_FAST);
      toolsList.AddItem(variant(toolObj));
    end;
  finally
    fSafe.UnLock;
  end;

  doc.AddValue('tools', variant(toolsList));
  result := variant(doc);
end;

function TMcpServer.ListResources: variant;
var
  doc, resourcesList: TDocVariantData;
  resourceObj: TDocVariantData;
  pair: TPair<RawUtf8, IMcpResource>;
begin
  doc.InitObject([], JSON_FAST);
  resourcesList.InitArray([], JSON_FAST);

  fSafe.Lock;
  try
    for pair in fResources do
    begin
      resourceObj.InitObject([
        'uri', pair.Value.GetUri,
        'name', pair.Value.GetName,
        'description', pair.Value.GetDescription,
        'mimeType', pair.Value.GetMimeType
      ], JSON_FAST);
      resourcesList.AddItem(variant(resourceObj));
    end;
  finally
    fSafe.UnLock;
  end;

  doc.AddValue('resources', variant(resourcesList));
  result := variant(doc);
end;

function TMcpServer.ExecuteToolCall(const aParams: variant;
  const aAuthCtx: TMcpAuthContext): variant;
var
  doc: PDocVariantData;
  toolName: RawUtf8;
  args: variant;
  tool: IMcpTool;
begin
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

  result := tool.Execute(args, aAuthCtx);
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
            resultData := ListTools
          else if msg.Method = 'tools/call' then
            resultData := ExecuteToolCall(msg.Params, authCtx)
          else if msg.Method = 'resources/list' then
            resultData := ListResources
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


{ ************ TMcpResponseBuilder Implementation }

constructor TMcpResponseBuilder.Create;
begin
  inherited Create;
  fContent.InitArray([], JSON_FAST);
end;

function TMcpResponseBuilder.AddText(const aText: RawUtf8): TMcpResponseBuilder;
var
  textItem: TDocVariantData;
begin
  textItem.InitObject(['type', 'text', 'text', aText], JSON_FAST);
  fContent.AddItem(variant(textItem));
  result := self;
end;

function TMcpResponseBuilder.AddFile(const aFilePath, aFileName: RawUtf8): TMcpResponseBuilder;
var
  fileItem: variant;
  content: RawByteString;
  base64: RawUtf8;
  mimeType, fileName: RawUtf8;
begin
  if not FileExists(Utf8ToString(aFilePath)) then
    raise EMcpException.CreateUtf8('File not found: %', [aFilePath]);

  content := StringFromFile(Utf8ToString(aFilePath));
  base64 := BinToBase64(content);
  
  if aFileName = '' then
    fileName := ExtractNameU(aFilePath)
  else
    fileName := aFileName;
    
  mimeType := GetMimeContentType(content, Utf8ToString(aFilePath));

  fileItem := _ObjFast([
    'type', 'resource',
    'mimeType', mimeType,
    'data', base64,
    'fileName', fileName
  ]);
  
  fContent.AddItem(fileItem);
  result := self;
end;

function TMcpResponseBuilder.Build: variant;
var
  contentCopy: TDocVariantData;
  i: integer;
begin
  SetVariantNull(result);

  contentCopy.InitArray([], JSON_FAST);
  for i := 0 to fContent.Count - 1 do
    contentCopy.AddItem(fContent.Values[i]);

  _ObjAddProp('content', contentCopy, result);
end;


end.
