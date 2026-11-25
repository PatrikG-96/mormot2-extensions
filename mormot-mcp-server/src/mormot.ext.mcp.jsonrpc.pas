/// Model Context Protocol (MCP) JSON-RPC 2.0 Layer for mORMot v2
// - this unit is part of the mormot-mcp-server project
// - licensed under MPL/GPL/LGPL three license
unit mormot.ext.mcp.jsonrpc;

{
  *****************************************************************************

    - Protocol Versions, Error Codes and Exceptions
    - JSON-RPC 2.0 Protocol Processor

  *****************************************************************************
}

interface

{$I mormot.defines.inc}

uses
  mormot.core.base,
  mormot.core.unicode,
  mormot.core.text,
  mormot.core.variants,
  mormot.core.json;


{ ************ Protocol Versions, Error Codes and Exceptions }

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

  /// raise it from a tool to report a failure to the model
  // - e.g. EMcpToolError.CreateUtf8('No order %', [id]) or a bad input which
  // the model can correct: its message is sent as an "isError" tool result
  // - any other exception raised by a tool becomes a generic "Tool <name>
  // failed" result, with its details only in the log, except an EMcpException
  // with a Code, which is a JSON-RPC error raised on purpose
  // - to return a failure without raising, see TMcpResponseBuilder.SetError
  EMcpToolError = class(EMcpException);


{ ************ JSON-RPC 2.0 Protocol Processor }

type
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

/// true if aName is a JSON string member of aDoc (numbers are not converted)
// - shared by the mormot.ext.mcp units
function GetStringValue(const aDoc: TDocVariantData; const aName: RawUtf8;
  out aValue: RawUtf8): boolean;


implementation

{ ************ EMcpException }

constructor EMcpException.CreateCode(aCode: integer; const aFormat: RawUtf8;
  const aArgs: array of const);
begin
  CreateUtf8(aFormat, aArgs);
  fCode := aCode;
end;


{ ************ TMcpJsonRpcProcessor Implementation }

constructor TMcpJsonRpcProcessor.Create(const aServerName, aServerVersion: RawUtf8);
begin
  inherited Create;
  fServerName := aServerName;
  fServerVersion := aServerVersion;
  fProtocolVersion := MCP_PROTOCOL_VERSION;
end;

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


end.
