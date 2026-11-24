// - regression tests for mormot.ext.mcp
unit test.mcp.core;

interface

{$I mormot.defines.inc}

uses
  sysutils,
  classes,
  mormot.core.base,
  mormot.core.os,
  mormot.core.unicode,
  mormot.core.text,
  mormot.core.buffers,
  mormot.core.rtti,
  mormot.core.variants,
  mormot.core.json,
  mormot.core.test,
  mormot.ext.mcp;

type
  TCalcParams = packed record
    A: integer;
    B: integer;
    Enabled: boolean;
    Name: RawUtf8;
  end;

  TCalcTool = class(TMcpToolBase<TCalcParams>)
  protected
    function ExecuteTyped(const aParams: TCalcParams;
      const aAuthCtx: TMcpAuthContext): variant; override;
  end;

  /// raises a different exception, or returns a different result, depending
  // on the Name argument
  TFailTool = class(TMcpToolBase<TCalcParams>)
  protected
    function ExecuteTyped(const aParams: TCalcParams;
      const aAuthCtx: TMcpAuthContext): variant; override;
  end;

  TVersionResource = class(TMcpResourceBase)
  protected
    function GetContent: RawUtf8; override;
  end;

  TTestMcpCore = class(TSynTestCase)
  protected
    procedure EnsureCalcParamsRtti;
    function VariantToInt64Loose(const V: variant; out aValue: Int64): boolean;
    procedure CheckErrorResponse(const aResponse: RawUtf8;
      aExpectedCode: integer; const aMessageContains: RawUtf8);
    function DocPropType(const props: PDocVariantData;
      const propName: RawUtf8): RawUtf8;
    function NewServer: TMcpServer;
    // - aIdJson is the expected JSON of the "id" member, or '' if it must be absent
    procedure CheckError(aServer: TMcpServer; const aRequest: RawUtf8;
      aExpectedCode: integer; const aIdJson: RawUtf8;
      const aMessageContains: RawUtf8 = '');
    // - return the "name" (or "uri") members of one list page, comma separated
    function ListPage(aServer: TMcpServer; const aMethod, aCursor: RawUtf8;
      out aNextCursor: RawUtf8): RawUtf8;
    // call the "fail" tool with aName, and check its isError result text
    procedure CheckToolError(aServer: TMcpServer; const aName,
      aExpectedText: RawUtf8);
  published
    procedure SchemaFromRecord;
    procedure JsonRpcProcessor;
    procedure ServerToolsResources;
    procedure ResponseBuilderTextAndFile;
    procedure ServerNotActive;
    procedure BadRequests;
    procedure NotificationsNoResponse;
    procedure ParseErrors;
    procedure InvalidRequests;
    procedure RequestIdEchoed;
    procedure ClientResponsesIgnored;
    procedure MissingParams;
    procedure ResourceNotFoundData;
    procedure ToolExceptions;
    procedure ToolErrorResults;
    procedure InvalidToolResults;
    procedure ContentBlocks;
    procedure AnnotationsAndIcons;
    procedure NotificationWhileStopped;
    procedure NotificationMethodAsRequest;
    procedure Pagination;
    procedure PaginationInvalidCursor;
  end;

implementation

{ TCalcTool }

function TCalcTool.ExecuteTyped(const aParams: TCalcParams;
  const aAuthCtx: TMcpAuthContext): variant;
var
  builder: TMcpResponseBuilder;
begin
  builder := TMcpResponseBuilder.Create;
  try
    builder.AddText(FormatUtf8('% + % = %', [aParams.A, aParams.B, aParams.A + aParams.B]));
    result := builder.Build;
  finally
    builder.Free;
  end;
end;

{ TFailTool }

function TFailTool.ExecuteTyped(const aParams: TCalcParams;
  const aAuthCtx: TMcpAuthContext): variant;
var
  builder: TMcpResponseBuilder;
begin
  if aParams.Name = 'convert' then
    raise EConvertError.Create('secret /etc/passwd')
  else if aParams.Name = 'plain' then
    raise EMcpException.Create('secret plain')
  else if aParams.Name = 'coded' then
    raise EMcpException.CreateCode(JSONRPC_INVALID_PARAMS, 'bad %', ['input'])
  else if aParams.Name = 'tool' then
    raise EMcpToolError.CreateUtf8('No order %', [42]);
  // the results of an unknown name are valid, the others invalid
  if aParams.Name = 'flagged' then
  begin
    builder := TMcpResponseBuilder.Create;
    try
      result := builder.AddText('nothing found').SetError.Build;
    finally
      builder.Free;
    end;
  end
  else if aParams.Name = 'null' then
    result := Null
  else if aParams.Name = 'nocontent' then
    result := _ObjFast(['text', 'x'])
  else if aParams.Name = 'notarray' then
    result := _ObjFast(['content', _ObjFast(['type', 'text', 'text', 'x'])])
  else if aParams.Name = 'notbool' then
    result := _ObjFast(['content', _ArrFast([]), 'isError', 'yes'])
  else if aParams.Name = 'notobject' then
    result := _ObjFast(['content', _ArrFast(['x'])])
  else if aParams.Name = 'notype' then
    result := _JsonFast('{"content":[{"text":"x"}]}')
  else if aParams.Name = 'badtype' then
    result := _JsonFast('{"content":[{"type":"video","data":"eA=="}]}')
  else if aParams.Name = 'badtext' then
    result := _JsonFast('{"content":[{"type":"text","text":1}]}')
  else if aParams.Name = 'badimage' then
    result := _JsonFast('{"content":[{"type":"image","data":"eA=="}]}')
  else if aParams.Name = 'badlink' then
    result := _JsonFast('{"content":[{"type":"resource_link","uri":"a://b"}]}')
  else if aParams.Name = 'badcase' then
    result := _JsonFast('{"Content":[{"type":"text","text":"x"}]}')
  else if aParams.Name = 'badcaseblock' then
    result := _JsonFast('{"content":[{"Type":"text","Text":"x"}]}')
  else if aParams.Name = 'badresource' then
    result := _JsonFast('{"content":[{"type":"resource","resource":{"uri":"a://b"}}]}')
  else
    result := _JsonFast('{"content":[{"type":"text","text":"x"},' +
      '{"type":"image","data":"eA==","mimeType":"image/png"},' +
      '{"type":"audio","data":"eA==","mimeType":"audio/wav"},' +
      '{"type":"resource_link","uri":"a://b","name":"b"},' +
      '{"type":"resource","resource":{"uri":"a://b","text":"x"}},' +
      '{"type":"resource","resource":{"uri":"a://b","blob":"eA=="}}],' +
      '"isError":false}');
end;

{ TVersionResource }

function TVersionResource.GetContent: RawUtf8;
begin
  result := '{"version":"1.0.0","protocol":"MCP"}';
end;

{ TTestMcpCore }

procedure TTestMcpCore.EnsureCalcParamsRtti;
begin
  //{$ifndef HASEXTRECORDRTTI}
  if not RecordHasFields(TypeInfo(TCalcParams)) then
    Rtti.RegisterFromText(TypeInfo(TCalcParams),
      'A,B:integer Enabled:boolean Name:RawUtf8');
  //{$endif HASEXTRECORDRTTI}
end;

function TTestMcpCore.VariantToInt64Loose(const V: variant; out aValue: Int64): boolean;
var
  d: double;
  s: RawUtf8;
  wasString: boolean;
begin
  result := VariantToInt64(V, aValue);
  if result then
    exit;
  if VariantToDouble(V, d) then
  begin
    aValue := trunc(d);
    exit(true);
  end;
  VariantToUtf8(V, s, wasString);
  s := TrimU(s);
  if s = '' then
    exit(false);
  if ToInt64(s, aValue) then
    exit(true);
  if ToDouble(s, d) then
  begin
    aValue := trunc(d);
    exit(true);
  end;
  result := false;
end;

procedure TTestMcpCore.CheckErrorResponse(const aResponse: RawUtf8;
  aExpectedCode: integer; const aMessageContains: RawUtf8);
var
  doc, errDoc: PDocVariantData;
  docVar, errVar: variant;
  code: integer;
  code64: Int64;
  okCode: boolean;
  msg: RawUtf8;
begin
  docVar := _JsonFast(aResponse);
  doc := _Safe(docVar);
  errVar := doc^.GetValueOrNull('error');
  errDoc := _Safe(errVar);
  Check(errDoc^.IsObject);
  okCode := VariantToInt64Loose(errDoc^.GetValueOrDefault('code', 0), code64);
  if okCode then
    code := integer(code64)
  else
    code := 0;
  if aExpectedCode <> 0 then
    CheckEqual(code, aExpectedCode)
  else
    Check(code <> 0);
  if aMessageContains <> '' then
  begin
    errDoc^.GetAsRawUtf8('message', msg);
    Check(PosEx(aMessageContains, msg) > 0);
  end;
end;

function TTestMcpCore.DocPropType(const props: PDocVariantData;
  const propName: RawUtf8): RawUtf8;
var
  prop: variant;
  propDoc: PDocVariantData;
begin
  result := '';
  if (props = nil) or not props^.IsObject then
    exit;
  prop := props^.GetValueOrNull(propName);
  propDoc := _Safe(prop);
  if propDoc^.IsObject then
    propDoc^.GetAsRawUtf8('type', result);
end;

function TTestMcpCore.NewServer: TMcpServer;
begin
  EnsureCalcParamsRtti;
  result := TMcpServer.Create('TestServer', '1.0');
  result.RegisterTool(TCalcTool.Create('calc', 'Add two numbers'));
  result.RegisterTool(TFailTool.Create('fail', 'Raise an exception'));
  result.RegisterResource(TVersionResource.Create('version://info', 'Version',
    'Server version information', 'application/json'));
  result.Start;
end;

procedure TTestMcpCore.CheckError(aServer: TMcpServer; const aRequest: RawUtf8;
  aExpectedCode: integer; const aIdJson: RawUtf8; const aMessageContains: RawUtf8);
var
  response: RawUtf8;
  doc: TDocVariantData;
  ndx: PtrInt;
begin
  response := aServer.ExecuteRequest(aRequest);
  CheckErrorResponse(response, aExpectedCode, aMessageContains);
  if CheckFailed(doc.InitJson(response, JSON_FAST_FLOAT), aRequest) then
    exit;
  ndx := doc.GetValueIndex('id');
  if aIdJson = '' then
    Check(ndx < 0, 'id must be absent')
  else if not CheckFailed(ndx >= 0, 'id missing') then
    CheckEqual(VariantSaveJson(doc.Values[ndx]), aIdJson, 'id');
end;

procedure TTestMcpCore.CheckToolError(aServer: TMcpServer;
  const aName, aExpectedText: RawUtf8);
var
  response: RawUtf8;
  doc: TDocVariantData;
begin
  response := aServer.ExecuteRequest(FormatJson(
    '{"jsonrpc":"2.0","id":?,"method":"tools/call","params":' +
    '{"name":"fail","arguments":{"name":?}}}', [], [aName, aName]));
  if CheckFailed(doc.InitJson(response, JSON_FAST), response) then
    exit;
  CheckEqual(VariantSaveJson(doc.Values[doc.GetValueIndex('id')]),
    '"' + aName + '"', 'id');
  CheckEqual(doc.O['result']^.ToJson, FormatJson(
    '{"content":[{"type":"text","text":?}],"isError":true}', [], [aExpectedText]),
    aName);
  Check(PosEx('secret', response) = 0, 'no exception message leaked');
end;

procedure TTestMcpCore.SchemaFromRecord;
var
  schema: variant;
  doc, props, req: PDocVariantData;
  propsVar: variant;
  typ: RawUtf8;
begin
  EnsureCalcParamsRtti;
  schema := TMcpSchemaGenerator.GenerateSchema(TypeInfo(TCalcParams));
  doc := _Safe(schema);
  Check(doc^.IsObject);
  Check(doc^.GetAsRawUtf8('type', typ));
  CheckEqual(typ, 'object');

  propsVar := doc^.GetValueOrNull('properties');
  props := _Safe(propsVar);
  Check(props^.IsObject);
  // the field names keep the casing of the record
  CheckEqual(DocPropType(props, 'A'), 'integer');
  CheckEqual(DocPropType(props, 'B'), 'integer');
  CheckEqual(DocPropType(props, 'Enabled'), 'boolean');
  CheckEqual(DocPropType(props, 'Name'), 'string');
  CheckEqual(VariantSaveJson(schema), '{"type":"object","properties":' +
    '{"A":{"type":"integer"},"B":{"type":"integer"},"Enabled":' +
    '{"type":"boolean"},"Name":{"type":"string"}},' +
    '"required":["A","B","Enabled","Name"]}');
end;

procedure TTestMcpCore.JsonRpcProcessor;
var
  proc: TMcpJsonRpcProcessor;
  msg: TMcpJsonRpcMessage;
  response: RawUtf8;
  doc, resultDoc: PDocVariantData;
  responseVar, resultVar: variant;
  jsonrpc: RawUtf8;
  v: variant;
  okFlag: boolean;
begin
  proc := TMcpJsonRpcProcessor.Create('TestServer', '1.0');
  try
    Check(proc.ParseMessage('{"jsonrpc":"2.0","id":1,"method":"ping","params":{}}',
      msg) = mmkRequest);
    CheckEqual(msg.Method, 'ping');
    Check(VariantToIntegerDef(msg.Id, 0) = 1);

    v := _ObjFast(['ok', true]);
    response := proc.CreateSuccessResponse(msg.Id, v);
    responseVar := _JsonFast(response);
    doc := _Safe(responseVar);
    Check(doc^.GetAsRawUtf8('jsonrpc', jsonrpc));
    CheckEqual(jsonrpc, '2.0');
    resultVar := doc^.GetValueOrNull('result');
    resultDoc := _Safe(resultVar);
    Check(resultDoc^.IsObject);
    Check(resultDoc^.GetAsBoolean('ok', okFlag));
    Check(okFlag);
  finally
    proc.Free;
  end;
end;

procedure TTestMcpCore.ServerToolsResources;
var
  server: TMcpServer;
  tool: IMcpTool;
  res: IMcpResource;
  response: RawUtf8;
  doc, resultDoc, listDoc, itemDoc, contentDoc: PDocVariantData;
  responseVar, resultVar, listVar, contentVar, itemVar: variant;
  toolName: RawUtf8;
  tmp: RawUtf8;
begin
  EnsureCalcParamsRtti;
  server := TMcpServer.Create('TestServer', '1.0');
  try
    tool := TCalcTool.Create('calc', 'Add two numbers');
    res := TVersionResource.Create('version://info', 'Version',
      'Server version information', 'application/json');
    server.RegisterTool(tool);
    server.RegisterResource(res);
    server.Start;

    response := server.ExecuteRequest(
      '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}');
    responseVar := _JsonFast(response);
    doc := _Safe(responseVar);
    resultVar := doc^.GetValueOrNull('result');
    resultDoc := _Safe(resultVar);
    listVar := resultDoc^.GetValueOrNull('tools');
    listDoc := _Safe(listVar);
    Check(listDoc^.IsArray);
    Check(listDoc^.Count >= 1);
    itemVar := listDoc^.Values[0];
    itemDoc := _Safe(itemVar);
    Check(itemDoc^.GetAsRawUtf8('name', toolName));
    CheckEqual(toolName, 'calc');

    response := server.ExecuteRequest(
      '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"calc",' +
      '"arguments":{"a":5,"b":3,"enabled":true,"name":"x"}}}');
    responseVar := _JsonFast(response);
    doc := _Safe(responseVar);
    resultVar := doc^.GetValueOrNull('result');
    resultDoc := _Safe(resultVar);
    contentVar := resultDoc^.GetValueOrNull('content');
    contentDoc := _Safe(contentVar);
    Check(contentDoc^.IsArray);
    Check(contentDoc^.Count = 1);
    itemVar := contentDoc^.Values[0];
    itemDoc := _Safe(itemVar);
    Check(itemDoc^.GetAsRawUtf8('type', tmp));
    CheckEqual(tmp, 'text');
    Check(itemDoc^.GetAsRawUtf8('text', tmp));
    CheckEqual(tmp, '5 + 3 = 8');

    response := server.ExecuteRequest(
      '{"jsonrpc":"2.0","id":3,"method":"resources/list","params":{}}');
    responseVar := _JsonFast(response);
    doc := _Safe(responseVar);
    resultVar := doc^.GetValueOrNull('result');
    resultDoc := _Safe(resultVar);
    listVar := resultDoc^.GetValueOrNull('resources');
    listDoc := _Safe(listVar);
    Check(listDoc^.IsArray);
    Check(listDoc^.Count = 1);
    itemVar := listDoc^.Values[0];
    itemDoc := _Safe(itemVar);
    Check(itemDoc^.GetAsRawUtf8('uri', tmp));
    CheckEqual(tmp, 'version://info');

    response := server.ExecuteRequest(
      '{"jsonrpc":"2.0","id":4,"method":"resources/read","params":{"uri":"version://info"}}');
    responseVar := _JsonFast(response);
    doc := _Safe(responseVar);
    resultVar := doc^.GetValueOrNull('result');
    resultDoc := _Safe(resultVar);
    listVar := resultDoc^.GetValueOrNull('contents');
    listDoc := _Safe(listVar);
    Check(listDoc^.IsArray);
    itemVar := listDoc^.Values[0];
    itemDoc := _Safe(itemVar);
    Check(itemDoc^.GetAsRawUtf8('uri', tmp));
    CheckEqual(tmp, 'version://info');
    Check(itemDoc^.GetAsRawUtf8('text', tmp));
    Check(tmp <> '');
  finally
    server.Free;
  end;
end;

procedure TTestMcpCore.ResponseBuilderTextAndFile;
const
  PNG: RawByteString = #$89'PNG'#13#10#$1a#10'data';
  WAV: RawByteString = 'RIFF'#4#0#0#0'WAVEfmt data';
var
  builder: TMcpResponseBuilder;
  binFile, pngFile, wavFile: TFileName;
  content: RawByteString;
  response: variant;
begin
  binFile := TemporaryFileName;
  pngFile := binFile + '.png';
  content := 'mcp-test';
  Check(FileFromString(content, binFile));
  Check(FileFromString(PNG, pngFile));
  wavFile := binFile + '.wav';
  Check(FileFromString(WAV, wavFile));
  try
    builder := TMcpResponseBuilder.Create;
    try
      builder.AddText('hello');
      // a file which is not an image or audio: an embedded binary resource,
      // with its name (not its server path) in the URI
      builder.AddFile(StringToUtf8(binFile), 'my report.bin');
      // an image file: an image block
      builder.AddFile(StringToUtf8(pngFile));
      // a WAV file: an audio block
      builder.AddFile(StringToUtf8(wavFile));
      response := builder.Build;
    finally
      builder.Free;
    end;
    CheckEqual(VariantSaveJson(response), FormatJson('{"content":[' +
      '{"type":"text","text":"hello"},' +
      '{"type":"resource","resource":{"uri":?,"mimeType":?,"blob":?}},' +
      '{"type":"image","data":?,"mimeType":"image/png"},' +
      '{"type":"audio","data":?,"mimeType":"audio/wav"}]}', [],
      ['file:///my%20report.bin', GetMimeContentType(content, binFile),
       BinToBase64(content),
       BinToBase64(PNG), BinToBase64(WAV)]));
  finally
    DeleteFile(binFile);
    DeleteFile(pngFile);
    DeleteFile(wavFile);
  end;
end;

procedure TTestMcpCore.ServerNotActive;
var
  server: TMcpServer;
  response: RawUtf8;
  doc, errDoc: PDocVariantData;
  docVar, errVar: variant;
  code: integer;
begin
  server := TMcpServer.Create('TestServer', '1.0');
  try
    response := server.ExecuteRequest(
      '{"jsonrpc":"2.0","id":1,"method":"ping","params":{}}');
    docVar := _JsonFast(response);
    doc := _Safe(docVar);
    errVar := doc^.GetValueOrNull('error');
    errDoc := _Safe(errVar);
    Check(errDoc^.IsObject);
    code := errDoc^.GetValueOrDefault('code', 0);
    Check(code = JSONRPC_INTERNAL_ERROR);
    CheckEqual(VariantToIntegerDef(doc^.GetValueOrNull('id'), 0), 1, 'id echoed');
  finally
    server.Free;
  end;
end;

procedure TTestMcpCore.BadRequests;
var
  server: TMcpServer;
  tool: IMcpTool;
  res: IMcpResource;
  response: RawUtf8;
begin
  EnsureCalcParamsRtti;
  server := TMcpServer.Create('TestServer', '1.0');
  try
    tool := TCalcTool.Create('calc', 'Add two numbers');
    res := TVersionResource.Create('version://info', 'Version',
      'Server version information', 'application/json');
    server.RegisterTool(tool);
    server.RegisterResource(res);
    server.Start;

    response := server.ExecuteRequest('{');
    CheckErrorResponse(response, JSONRPC_PARSE_ERROR, '');

    response := server.ExecuteRequest('{"jsonrpc":"2.0","id":1}');
    CheckErrorResponse(response, JSONRPC_INVALID_REQUEST, '');

    response := server.ExecuteRequest('{"jsonrpc":"2.0","id":2,"method":"nope"}');
    CheckErrorResponse(response, JSONRPC_METHOD_NOT_FOUND, 'Method not found');

    response := server.ExecuteRequest(
      '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{}}');
    CheckErrorResponse(response, JSONRPC_INVALID_PARAMS, 'Missing tool name');

    response := server.ExecuteRequest(
      '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"missing","arguments":{}}}');
    CheckErrorResponse(response, JSONRPC_INVALID_PARAMS, 'Tool not found');

    response := server.ExecuteRequest(
      '{"jsonrpc":"2.0","id":5,"method":"resources/read","params":{}}');
    CheckErrorResponse(response, JSONRPC_INVALID_PARAMS, 'Missing uri');

    response := server.ExecuteRequest(
      '{"jsonrpc":"2.0","id":6,"method":"resources/read","params":{"uri":"missing://info"}}');
    CheckErrorResponse(response, MCP_RESOURCE_NOT_FOUND, 'Resource not found');
  finally
    server.Free;
  end;
end;

procedure TTestMcpCore.NotificationsNoResponse;
var
  server: TMcpServer;
  response: RawUtf8;
begin
  server := TMcpServer.Create('TestServer', '1.0');
  try
    server.Start;
    response := server.ExecuteRequest('{"jsonrpc":"2.0","method":"ping","params":{}}');
    Check(TrimU(response) = '');
  finally
    server.Free;
  end;
end;

procedure TTestMcpCore.ParseErrors;
var
  server: TMcpServer;
begin
  server := NewServer;
  try
    CheckError(server, '{', JSONRPC_PARSE_ERROR, '');
    CheckError(server, '{"jsonrpc":', JSONRPC_PARSE_ERROR, '');
    CheckError(server, 'xx', JSONRPC_PARSE_ERROR, '');
    CheckError(server, '', JSONRPC_PARSE_ERROR, '');
    // not strict JSON: trailing text, extended syntax, comments
    CheckError(server, '{"jsonrpc":"2.0","id":1,"method":"ping"} garbage',
      JSONRPC_PARSE_ERROR, '');
    CheckError(server, '{"jsonrpc":"2.0","id":1,"method":"ping"}{"x":1}',
      JSONRPC_PARSE_ERROR, '');
    CheckError(server, '{jsonrpc:"2.0",id:1,method:"ping"}', JSONRPC_PARSE_ERROR, '');
    CheckError(server, '{''jsonrpc'':''2.0'',''id'':1,''method'':''ping''}',
      JSONRPC_PARSE_ERROR, '');
    CheckError(server, '{"jsonrpc":"2.0",/*c*/"id":1,"method":"ping"}',
      JSONRPC_PARSE_ERROR, '');
    CheckError(server, '{"jsonrpc":"2.0","id":1,"method":"ping",}',
      JSONRPC_PARSE_ERROR, '');
    CheckError(server, '{"jsonrpc":"2.0","id":01,"method":"ping"}',
      JSONRPC_PARSE_ERROR, '');
    // surrounding whitespace is fine
    CheckEqual(server.ExecuteRequest(' {"jsonrpc":"2.0","id":1,"method":"ping"}'#13#10),
      '{"jsonrpc":"2.0","id":1,"result":{}}');
  finally
    server.Free;
  end;
end;

procedure TTestMcpCore.InvalidRequests;
var
  server: TMcpServer;
begin
  server := NewServer;
  try
    // not an object (batches are not supported)
    CheckError(server, '[]', JSONRPC_INVALID_REQUEST, '');
    CheckError(server, '[{"jsonrpc":"2.0","id":1,"method":"ping"}]',
      JSONRPC_INVALID_REQUEST, '');
    CheckError(server, '"ping"', JSONRPC_INVALID_REQUEST, '');
    CheckError(server, ' 1 ', JSONRPC_INVALID_REQUEST, '');
    // wrong or missing jsonrpc version: id is echoed when it is valid
    CheckError(server, '{"jsonrpc":"1.0","id":1,"method":"ping"}',
      JSONRPC_INVALID_REQUEST, '1');
    CheckError(server, '{"id":2,"method":"ping"}', JSONRPC_INVALID_REQUEST, '2');
    CheckError(server, '{"jsonrpc":2,"id":3,"method":"ping"}',
      JSONRPC_INVALID_REQUEST, '3');
    // invalid id: must be a string or an integer, never null
    CheckError(server, '{"jsonrpc":"2.0","id":null,"method":"ping"}',
      JSONRPC_INVALID_REQUEST, '');
    CheckError(server, '{"jsonrpc":"2.0","id":2.5,"method":"ping"}',
      JSONRPC_INVALID_REQUEST, '');
    CheckError(server, '{"jsonrpc":"2.0","id":1e5,"method":"ping"}',
      JSONRPC_INVALID_REQUEST, '');
    CheckError(server, '{"jsonrpc":"2.0","id":true,"method":"ping"}',
      JSONRPC_INVALID_REQUEST, '');
    CheckError(server, '{"jsonrpc":"2.0","id":{},"method":"ping"}',
      JSONRPC_INVALID_REQUEST, '');
    CheckError(server, '{"jsonrpc":"2.0","id":[1],"method":"ping"}',
      JSONRPC_INVALID_REQUEST, '');
    // method must be a string
    CheckError(server, '{"jsonrpc":"2.0","id":4,"method":5}',
      JSONRPC_INVALID_REQUEST, '4');
    CheckError(server, '{"jsonrpc":"2.0","id":5,"method":null}',
      JSONRPC_INVALID_REQUEST, '5');
    // params must be an object when present
    CheckError(server, '{"jsonrpc":"2.0","id":6,"method":"ping","params":[1]}',
      JSONRPC_INVALID_REQUEST, '6');
    CheckError(server, '{"jsonrpc":"2.0","id":7,"method":"ping","params":"x"}',
      JSONRPC_INVALID_REQUEST, '7');
    // neither a request nor a response
    CheckError(server, '{"jsonrpc":"2.0","id":8}', JSONRPC_INVALID_REQUEST, '8');
  finally
    server.Free;
  end;
end;

procedure TTestMcpCore.RequestIdEchoed;
var
  server: TMcpServer;
  response: RawUtf8;
begin
  server := NewServer;
  try
    response := server.ExecuteRequest('{"jsonrpc":"2.0","id":"abc","method":"ping"}');
    CheckEqual(response, '{"jsonrpc":"2.0","id":"abc","result":{}}');
    response := server.ExecuteRequest('{"jsonrpc":"2.0","id":"1","method":"ping"}');
    CheckEqual(response, '{"jsonrpc":"2.0","id":"1","result":{}}');
    response := server.ExecuteRequest('{"jsonrpc":"2.0","id":-3,"method":"ping"}');
    CheckEqual(response, '{"jsonrpc":"2.0","id":-3,"result":{}}');
    response := server.ExecuteRequest(
      '{"jsonrpc":"2.0","id":9007199254740993,"method":"ping"}');
    CheckEqual(response, '{"jsonrpc":"2.0","id":9007199254740993,"result":{}}');
    // message is JSON-escaped (no string concatenation)
    CheckError(server, '{"jsonrpc":"2.0","id":"q\"","method":"a\"b"}',
      JSONRPC_METHOD_NOT_FOUND, '"q\""', 'a"b');
  finally
    server.Free;
  end;
end;

procedure TTestMcpCore.ClientResponsesIgnored;
var
  server: TMcpServer;
begin
  server := NewServer;
  try
    CheckEqual(server.ExecuteRequest('{"jsonrpc":"2.0","id":1,"result":{}}'), '');
    CheckEqual(server.ExecuteRequest(
      '{"jsonrpc":"2.0","id":"x","error":{"code":-32601,"message":"no"}}'), '');
    CheckEqual(server.ExecuteRequest(
      '{"jsonrpc":"2.0","error":{"code":-32700,"message":"parse"}}'), '');
  finally
    server.Free;
  end;
end;

procedure TTestMcpCore.MissingParams;
var
  server: TMcpServer;
begin
  server := NewServer;
  try
    // regression: tools/call without params dereferenced a nil document
    CheckError(server, '{"jsonrpc":"2.0","id":1,"method":"tools/call"}',
      JSONRPC_INVALID_PARAMS, '1', 'Missing tool name');
    CheckError(server, '{"jsonrpc":"2.0","id":2,"method":"resources/read"}',
      JSONRPC_INVALID_PARAMS, '2', 'Missing uri');
    CheckError(server, '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":5}}',
      JSONRPC_INVALID_PARAMS, '3');
    CheckError(server, '{"jsonrpc":"2.0","id":4,"method":"resources/read","params":{"uri":[]}}',
      JSONRPC_INVALID_PARAMS, '4');
    // the server still works afterwards
    CheckEqual(server.ExecuteRequest('{"jsonrpc":"2.0","id":5,"method":"ping"}'),
      '{"jsonrpc":"2.0","id":5,"result":{}}');
  finally
    server.Free;
  end;
end;

procedure TTestMcpCore.ResourceNotFoundData;
var
  server: TMcpServer;
  response, uri: RawUtf8;
  doc: TDocVariantData;
begin
  server := NewServer;
  try
    response := server.ExecuteRequest(
      '{"jsonrpc":"2.0","id":1,"method":"resources/read","params":{"uri":"nope://x"}}');
    CheckErrorResponse(response, MCP_RESOURCE_NOT_FOUND, 'Resource not found');
    Check(doc.InitJson(response, JSON_FAST));
    Check(doc.O['error']^.O['data']^.GetAsRawUtf8('uri', uri), 'error.data.uri');
    CheckEqual(uri, 'nope://x');
  finally
    server.Free;
  end;
end;

procedure TTestMcpCore.ToolExceptions;
var
  server: TMcpServer;
begin
  server := NewServer;
  try
    // not an ESynException: an isError result with a generic text, and the
    // details only in the log
    CheckToolError(server, 'convert', 'Tool fail failed');
    // EMcpException without a code: not meant for the client either
    CheckToolError(server, 'plain', 'Tool fail failed');
    // EMcpException with a code: a JSON-RPC error raised on purpose
    CheckError(server, '{"jsonrpc":"2.0","id":3,"method":"tools/call",' +
      '"params":{"name":"fail","arguments":{"name":"coded"}}}',
      JSONRPC_INVALID_PARAMS, '3', 'bad input');
    // a notification never gets an answer, even when it fails
    CheckEqual(server.ExecuteRequest('{"jsonrpc":"2.0","method":"tools/call",' +
      '"params":{"name":"fail","arguments":{"name":"convert"}}}'), '');
    // protocol errors stay JSON-RPC errors
    CheckError(server, '{"jsonrpc":"2.0","id":4,"method":"tools/call",' +
      '"params":{"name":"nope","arguments":{}}}', JSONRPC_INVALID_PARAMS, '4',
      'Tool not found');
  finally
    server.Free;
  end;
end;

procedure TTestMcpCore.ToolErrorResults;
var
  server: TMcpServer;
  response: RawUtf8;
begin
  server := NewServer;
  try
    // EMcpToolError: raised on purpose for the model, message kept
    CheckToolError(server, 'tool', 'No order 42');
    // TMcpResponseBuilder.SetError: a failure without an exception
    CheckToolError(server, 'flagged', 'nothing found');
    // a valid result is sent as it is, with every kind of content block
    response := server.ExecuteRequest('{"jsonrpc":"2.0","id":1,' +
      '"method":"tools/call","params":{"name":"fail","arguments":{}}}');
    Check(PosEx('"result":{"content":[{"type":"text"', response) > 0, response);
    Check(PosEx('"isError":false}', response) > 0, response);
  finally
    server.Free;
  end;
end;

procedure TTestMcpCore.InvalidToolResults;
const
  INVALID: array[0..12] of RawUtf8 = ('null', 'nocontent', 'notarray',
    'notbool', 'notobject', 'notype', 'badtype', 'badtext', 'badimage',
    'badlink', 'badresource', 'badcase', 'badcaseblock');
var
  server: TMcpServer;
  i: PtrInt;
begin
  server := NewServer;
  try
    // a malformed tool result is a server bug: an internal error
    for i := 0 to high(INVALID) do
      CheckError(server, FormatJson('{"jsonrpc":"2.0","id":?,"method":' +
        '"tools/call","params":{"name":"fail","arguments":{"name":?}}}', [],
        [i, INVALID[i]]), JSONRPC_INTERNAL_ERROR, Int32ToUtf8(i), 'Internal error');
  finally
    server.Free;
  end;
end;

procedure TTestMcpCore.ContentBlocks;
var
  builder: TMcpResponseBuilder;
  first: variant;
begin
  builder := TMcpResponseBuilder.Create;
  try
    builder.AddText('hi');
    first := builder.Build;
    builder
      .AddImage('png', 'image/png')
        .Annotate(McpAnnotations([mrUser, mrAssistant], 0.5,
          EncodeDate(2025, 1, 12) + EncodeTime(15, 0, 58, 0)))
      .AddAudio('wav', 'audio/wav')
        .Annotate(McpAnnotations([], 0))
      .AddResourceLink('file:///a.txt', 'a.txt', 'The A file', 'text/plain')
        .Annotate(McpAnnotations([mrAssistant]))
      .AddResourceLink('db://x', 'x')
        .Annotate(McpAnnotations([])) // nothing set: no "annotations"
      .AddEmbeddedText('memo://1', 'text/plain', 'memo "1"')
      .AddEmbeddedBlob('blob://1', '', 'bin');
    CheckEqual(VariantSaveJson(builder.Build), '{"content":[' +
      '{"type":"text","text":"hi"},' +
      '{"type":"image","data":"cG5n","mimeType":"image/png","annotations":' +
        '{"audience":["user","assistant"],"priority":0.5,' +
        '"lastModified":"2025-01-12T15:00:58Z"}},' +
      '{"type":"audio","data":"d2F2","mimeType":"audio/wav",' +
        '"annotations":{"priority":0}},' +
      '{"type":"resource_link","uri":"file:///a.txt","name":"a.txt",' +
        '"description":"The A file","mimeType":"text/plain",' +
        '"annotations":{"audience":["assistant"]}},' +
      '{"type":"resource_link","uri":"db://x","name":"x"},' +
      '{"type":"resource","resource":{"uri":"memo://1","mimeType":"text/plain",' +
        '"text":"memo \"1\""}},' +
      '{"type":"resource","resource":{"uri":"blob://1","blob":"Ymlu"}}]}');
    // a previous Build is not changed by the blocks added afterwards
    CheckEqual(VariantSaveJson(first), '{"content":[{"type":"text","text":"hi"}]}');
    builder.SetError;
    CheckEqual(VariantSaveJson(builder.Build), '{"content":[' +
      '{"type":"text","text":"hi"},' +
      '{"type":"image","data":"cG5n","mimeType":"image/png","annotations":' +
        '{"audience":["user","assistant"],"priority":0.5,' +
        '"lastModified":"2025-01-12T15:00:58Z"}},' +
      '{"type":"audio","data":"d2F2","mimeType":"audio/wav",' +
        '"annotations":{"priority":0}},' +
      '{"type":"resource_link","uri":"file:///a.txt","name":"a.txt",' +
        '"description":"The A file","mimeType":"text/plain",' +
        '"annotations":{"audience":["assistant"]}},' +
      '{"type":"resource_link","uri":"db://x","name":"x"},' +
      '{"type":"resource","resource":{"uri":"memo://1","mimeType":"text/plain",' +
        '"text":"memo \"1\""}},' +
      '{"type":"resource","resource":{"uri":"blob://1","blob":"Ymlu"}}],' +
      '"isError":true}');
  finally
    builder.Free;
  end;
  // Annotate after Build does not change the result already built
  builder := TMcpResponseBuilder.Create;
  try
    builder.AddText('a');
    first := builder.Build;
    builder.Annotate(McpAnnotations([mrUser]));
    CheckEqual(VariantSaveJson(first), '{"content":[{"type":"text","text":"a"}]}');
    CheckEqual(VariantSaveJson(builder.Build), '{"content":[{"type":"text",' +
      '"text":"a","annotations":{"audience":["user"]}}]}');
  finally
    builder.Free;
  end;
  // Annotate needs a block
  builder := TMcpResponseBuilder.Create;
  try
    try
      builder.Annotate(McpAnnotations([mrUser]));
      Check(false, 'Annotate without a block');
    except
      on E: EMcpException do
        Check(true);
    end;
    CheckEqual(VariantSaveJson(builder.Build), '{"content":[]}');
  finally
    builder.Free;
  end;
end;

procedure TTestMcpCore.AnnotationsAndIcons;
var
  icons: TMcpIcons;

  procedure CheckRaises(const aSrc: RawUtf8);
  begin
    try
      McpIcon(aSrc);
      Check(false, aSrc);
    except
      on E: EMcpException do
        Check(true);
    end;
  end;

begin
  // nothing set
  Check(VarIsEmptyOrNull(McpAnnotations([]).ToVariant));
  CheckEqual(VariantSaveJson(McpAnnotations([mrUser], 1).ToVariant),
    '{"audience":["user"],"priority":1}');
  // a date without a time is still a date-time
  CheckEqual(VariantSaveJson(McpAnnotations([], -1,
    EncodeDate(2026, 11, 24)).ToVariant), '{"lastModified":"2026-11-24T00:00:00Z"}');
  try
    McpAnnotations([], 1.5);
    Check(false, 'priority > 1');
  except
    on E: EMcpException do
      Check(true);
  end;
  // icons: only https: and data: URIs
  SetLength(icons, 3);
  icons[0] := McpIcon('https://example.com/icon.png', 'image/png',
    '48x48  96x96', mitDark);
  icons[1] := McpIcon('data:image/svg+xml;base64,PHN2Zy8+', '', 'any', mitLight);
  icons[2] := McpIcon('HTTPS://example.com/icon');
  CheckEqual(VariantSaveJson(McpIconsToVariant(icons)), '[' +
    '{"src":"https://example.com/icon.png","mimeType":"image/png",' +
      '"sizes":["48x48","96x96"],"theme":"dark"},' +
    '{"src":"data:image/svg+xml;base64,PHN2Zy8+","sizes":["any"],' +
      '"theme":"light"},' +
    '{"src":"HTTPS://example.com/icon"}]');
  CheckEqual(VariantSaveJson(McpIconsToVariant([])), '[]');
  CheckRaises('http://example.com/icon.png');
  CheckRaises('javascript:alert(1)');
  CheckRaises('file:///icon.png');
  CheckRaises('');
end;

procedure TTestMcpCore.NotificationWhileStopped;
var
  server: TMcpServer;
begin
  server := TMcpServer.Create('TestServer', '1.0');
  try
    CheckEqual(server.ExecuteRequest(
      '{"jsonrpc":"2.0","method":"notifications/initialized"}'), '');
    CheckEqual(server.ExecuteRequest('{"jsonrpc":"2.0","id":1,"result":{}}'), '');
    CheckError(server, '{"jsonrpc":"2.0","id":"s","method":"ping"}',
      JSONRPC_INTERNAL_ERROR, '"s"', 'Server not active');
  finally
    server.Free;
  end;
end;

procedure TTestMcpCore.NotificationMethodAsRequest;
var
  server: TMcpServer;
begin
  server := NewServer;
  try
    // as a notification: no response
    CheckEqual(server.ExecuteRequest(
      '{"jsonrpc":"2.0","method":"notifications/initialized"}'), '');
    // as a request: not a known method (and never "result": null)
    CheckError(server, '{"jsonrpc":"2.0","id":1,"method":"notifications/initialized"}',
      JSONRPC_METHOD_NOT_FOUND, '1');
  finally
    server.Free;
  end;
end;

function TTestMcpCore.ListPage(aServer: TMcpServer;
  const aMethod, aCursor: RawUtf8; out aNextCursor: RawUtf8): RawUtf8;
var
  params, request: variant;
  response, listName, key, item: RawUtf8;
  doc: TDocVariantData;
  res, list: PDocVariantData;
  v: PVariant;
  i: PtrInt;
begin
  result := '';
  aNextCursor := '';
  params := _ObjFast([]);
  if aCursor <> '' then
    _ObjAddProp('cursor', aCursor, params);
  request := _ObjFast(['jsonrpc', '2.0', 'id', 1, 'method', aMethod,
    'params', params]);
  response := aServer.ExecuteRequest(VariantSaveJson(request));
  if CheckFailed(doc.InitJson(response, JSON_FAST), response) or
     CheckFailed(doc.GetAsObject('result', res), response) then
    exit;
  if aMethod = 'tools/list' then
  begin
    listName := 'tools';
    key := 'name';
  end
  else
  begin
    listName := 'resources';
    key := 'uri';
  end;
  if CheckFailed(res^.GetAsPVariant(listName, v), response) then
    exit;
  list := _Safe(v^); // may be an empty array
  if CheckFailed(list^.Kind = dvArray, response) then
    exit;
  for i := 0 to list^.Count - 1 do
  begin
    item := _Safe(list^.Values[i])^.U[key];
    if result = '' then
      result := item
    else
      result := result + ',' + item;
  end;
  if res^.GetAsRawUtf8('nextCursor', aNextCursor) then
    Check(aNextCursor <> '', 'nextCursor must not be empty');
end;

procedure TTestMcpCore.Pagination;
var
  server: TMcpServer;
  cursor, first, next: RawUtf8;
begin
  EnsureCalcParamsRtti;
  server := TMcpServer.Create('TestServer', '1.0');
  try
    CheckEqual(server.PageSize, MCP_DEFAULT_PAGE_SIZE, 'default page size');
    // registration order is not the listing order: pages follow the names
    server.RegisterTool(TCalcTool.Create('e', 'tool e'));
    server.RegisterTool(TCalcTool.Create('b', 'tool b'));
    server.RegisterTool(TCalcTool.Create('d', 'tool d'));
    server.RegisterTool(TCalcTool.Create('a', 'tool a'));
    server.RegisterTool(TCalcTool.Create('c', 'tool c'));
    server.RegisterResource(TVersionResource.Create('v://3', '3', '', 'text/plain'));
    server.RegisterResource(TVersionResource.Create('v://1', '1', '', 'text/plain'));
    server.RegisterResource(TVersionResource.Create('v://2', '2', '', 'text/plain'));
    server.Start;
    // fewer items than a page: one page, no nextCursor
    CheckEqual(ListPage(server, 'tools/list', '', cursor), 'a,b,c,d,e');
    CheckEqual(cursor, '', 'no nextCursor on the only page');
    // page through all items
    server.PageSize := 2;
    CheckEqual(ListPage(server, 'tools/list', '', cursor), 'a,b', 'page 1');
    Check(cursor <> '', 'page 1 nextCursor');
    first := cursor;
    CheckEqual(ListPage(server, 'tools/list', first, next), 'c,d', 'page 2');
    CheckEqual(ListPage(server, 'tools/list', next, cursor), 'e', 'page 3');
    CheckEqual(cursor, '', 'no nextCursor on the last page');
    // a page which ends exactly at the last item has no nextCursor either
    server.PageSize := 5;
    CheckEqual(ListPage(server, 'tools/list', '', cursor), 'a,b,c,d,e');
    CheckEqual(cursor, '', 'full last page');
    // the cursor carries its own position: it survives list changes
    server.PageSize := 2;
    Check(server.UnregisterTool('b'));
    server.RegisterTool(TCalcTool.Create('aa', 'tool aa'));
    CheckEqual(ListPage(server, 'tools/list', first, next), 'c,d',
      'cursor after a removed item');
    server.PageSize := 0; // 0 = no pagination
    CheckEqual(ListPage(server, 'tools/list', '', next), 'a,aa,c,d,e');
    CheckEqual(next, '', 'PageSize=0 sends everything');
    CheckEqual(ListPage(server, 'tools/list', first, next), 'c,d,e',
      'PageSize=0 still honours a cursor');
    // resources/list
    server.PageSize := 2;
    CheckEqual(ListPage(server, 'resources/list', '', cursor), 'v://1,v://2');
    CheckEqual(ListPage(server, 'resources/list', cursor, next), 'v://3');
    CheckEqual(next, '');
  finally
    server.Free;
  end;
  // a cursor is not bound to the server instance which made it
  server := TMcpServer.Create('Other', '1.0');
  try
    server.RegisterTool(TCalcTool.Create('z', 'tool z'));
    server.Start;
    CheckEqual(ListPage(server, 'tools/list', first, next), 'z',
      'cursor from another instance');
  finally
    server.Free;
  end;
  // a valid continuation page may be empty (the rest was unregistered)
  server := TMcpServer.Create('Empty', '1.0');
  try
    server.PageSize := 1;
    server.RegisterTool(TCalcTool.Create('a', 'tool a'));
    server.RegisterTool(TCalcTool.Create('b', 'tool b'));
    server.Start;
    CheckEqual(ListPage(server, 'tools/list', '', cursor), 'a');
    Check(cursor <> '');
    Check(server.UnregisterTool('b'));
    CheckEqual(ListPage(server, 'tools/list', cursor, next), '', 'empty page');
    CheckEqual(next, '', 'no nextCursor on the empty page');
  finally
    server.Free;
  end;
end;

procedure TTestMcpCore.PaginationInvalidCursor;
var
  server: TMcpServer;
  toolsCursor, resCursor: RawUtf8;
begin
  server := NewServer;
  try
    server.PageSize := 1;
    ListPage(server, 'tools/list', '', toolsCursor);
    ListPage(server, 'resources/list', '', resCursor); // single resource
    Check(toolsCursor <> '');
    CheckEqual(resCursor, '');
    CheckError(server, '{"jsonrpc":"2.0","id":1,"method":"tools/list",' +
      '"params":{"cursor":"not a cursor!"}}', JSONRPC_INVALID_PARAMS, '1',
      'cursor');
    // valid base64url, but not one of our cursors
    CheckError(server, '{"jsonrpc":"2.0","id":2,"method":"tools/list",' +
      '"params":{"cursor":"' + BinToBase64uri('hello') + '"}}',
      JSONRPC_INVALID_PARAMS, '2', 'cursor');
    CheckError(server, '{"jsonrpc":"2.0","id":3,"method":"tools/list",' +
      '"params":{"cursor":"' + BinToBase64uri('{"list":"tools"}') + '"}}',
      JSONRPC_INVALID_PARAMS, '3', 'cursor');
    CheckError(server, '{"jsonrpc":"2.0","id":4,"method":"tools/list",' +
      '"params":{"cursor":12}}', JSONRPC_INVALID_PARAMS, '4', 'cursor');
    CheckError(server, '{"jsonrpc":"2.0","id":5,"method":"tools/list",' +
      '"params":{"cursor":""}}', JSONRPC_INVALID_PARAMS, '5', 'cursor');
    // trailing data after the JSON object, or a number instead of a string
    CheckError(server, '{"jsonrpc":"2.0","id":9,"method":"tools/list",' +
      '"params":{"cursor":"' + BinToBase64uri(
        '{"list":"tools","after":"a"} x') + '"}}',
      JSONRPC_INVALID_PARAMS, '9', 'cursor');
    CheckError(server, '{"jsonrpc":"2.0","id":10,"method":"tools/list",' +
      '"params":{"cursor":"' + BinToBase64uri(
        '{"list":"tools","after":1e5}') + '"}}',
      JSONRPC_INVALID_PARAMS, '10', 'cursor');
    // unquoted names, or an embedded NUL followed by garbage
    CheckError(server, '{"jsonrpc":"2.0","id":11,"method":"tools/list",' +
      '"params":{"cursor":"' + BinToBase64uri(
        '{list:"tools",after:"a"}') + '"}}',
      JSONRPC_INVALID_PARAMS, '11', 'cursor');
    CheckError(server, '{"jsonrpc":"2.0","id":12,"method":"tools/list",' +
      '"params":{"cursor":"' + BinToBase64uri(
        '{"list":"tools","after":"a"}'#0'garbage') + '"}}',
      JSONRPC_INVALID_PARAMS, '12', 'cursor');
    // a tools/list cursor is not a resources/list cursor
    CheckError(server, '{"jsonrpc":"2.0","id":6,"method":"resources/list",' +
      '"params":{"cursor":"' + toolsCursor + '"}}',
      JSONRPC_INVALID_PARAMS, '6', 'cursor');
    // "params" may be absent, and a null cursor means none
    Check(PosEx('"tools"', server.ExecuteRequest(
      '{"jsonrpc":"2.0","id":7,"method":"tools/list"}')) > 0);
    Check(PosEx('"tools"', server.ExecuteRequest(
      '{"jsonrpc":"2.0","id":8,"method":"tools/list","params":{"cursor":null}}')) > 0);
  finally
    server.Free;
  end;
end;


end.
