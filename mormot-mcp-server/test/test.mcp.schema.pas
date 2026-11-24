// - regression tests for the JSON Schema generation of mormot.ext.mcp
unit test.mcp.schema;

interface

{$I mormot.defines.inc}

uses
  sysutils,
  mormot.core.base,
  mormot.core.os,
  mormot.core.unicode,
  mormot.core.text,
  mormot.core.rtti,
  mormot.core.variants,
  mormot.core.json,
  mormot.core.test,
  mormot.ext.mcp;

type
  TSchemaColor = (scRed, scGreen, scBlue);
  TSchemaColors = set of TSchemaColor;

  TSchemaAddress = packed record
    Street: RawUtf8;
    City: RawUtf8;
  end;
  TSchemaAddressDynArray = array of TSchemaAddress;
  TSchemaRgb = array[0..2] of byte;

  /// one field of each kind of type the generator knows
  TSchemaAll = packed record
    Flag: boolean;
    Count: integer;
    Big: Int64;
    Ratio: double;
    Price: currency;
    Name: RawUtf8;
    Data: RawByteString;
    Id: TGuid;
    When: TDateTime;
    Stamp: TTimeLog;
    Color: TSchemaColor;
    Colors: TSchemaColors;
    Tags: TRawUtf8DynArray;
    Home: TSchemaAddress;
    Others: TSchemaAddressDynArray;
    Extra: variant;
  end;

  /// a tool without parameters
  TSchemaNone = packed record
  end;

  /// a record whose fields are not registered: no field names on FPC 3.2.2
  TSchemaNoRtti = packed record
    X: integer;
  end;

  /// a recursive type, through a dynamic array of itself
  TSchemaNode = packed record
    Name: RawUtf8;
    Children: array of TSchemaNode;
  end;
  TSchemaNodeDynArray = array of TSchemaNode;

  /// a recursive type, which is not the root of the schema
  TSchemaTree = packed record
    Root: TSchemaNode;
  end;

  /// a type with its own schema, set with TMcpSchemaType.Replace
  TSchemaCode = type RawUtf8;

  TSchemaPlace = packed record
    Street: RawUtf8;
    City: RawUtf8;
  end;

  /// parameters described with McpSchema()
  TSchemaSearch = packed record
    Query: RawUtf8;
    Limit: integer;
    Color: TSchemaColor;
    Place: TSchemaPlace;
    Code: TSchemaCode;
    Colors: TSchemaColors;
  end;

  /// nested records referenced with "$ref"
  TSchemaOrder = packed record
    Billing: TSchemaPlace;
    Shipping: TSchemaPlace;
  end;

  TSchemaCached = packed record
    Value: integer;
  end;

  /// returns its parameters as JSON text
  TSchemaSearchTool = class(TMcpToolBase<TSchemaSearch>)
  protected
    function ExecuteTyped(const aParams: TSchemaSearch;
      const aAuthCtx: TMcpAuthContext): variant; override;
  end;

  TTestMcpSchema = class(TSynTestCase)
  protected
    procedure CheckSchema(aInfo: PRttiInfo; const aExpected: RawUtf8);
  public
    /// register the RTTI of the test types (needed on FPC 3.2.2)
    class procedure RegisterTypes;
    /// describe TSchemaPlace, TSchemaCode and TSchemaSearch with McpSchema()
    class procedure RegisterMetadata;
  published
    procedure SimpleTypes;
    procedure NestedRecordsAndArrays;
    procedure NoParameters;
    procedure RecursiveTypes;
    procedure Metadata;
    procedure MetadataErrors;
    procedure ReplaceAndRef;
    procedure SchemaCache;
    procedure ToolsList;
    procedure ToolsCallDefaults;
  end;

const
  SCHEMA_ADDRESS =
    '{"type":"object","properties":{"Street":{"type":"string"},' +
    '"City":{"type":"string"}},"required":["Street","City"]}';
  SCHEMA_COLOR =
    '{"type":"string","enum":["Red","Green","Blue"]}';
  SCHEMA_PLACE_PROPS =
    '"properties":{"Street":{"type":"string"},' +
    '"City":{"type":"string","default":"Paris"}},"required":["Street"]';
  SCHEMA_PLACE =
    '{"type":"object",' + SCHEMA_PLACE_PROPS +
    ',"description":"A postal address"}';
  SCHEMA_SEARCH =
    '{"type":"object","properties":{' +
    '"Query":{"type":"string","description":"Text to search for",' +
    '"minLength":1},' +
    '"Limit":{"type":"integer","description":"Maximum number of results",' +
    '"default":10},' +
    '"Color":' + SCHEMA_COLOR + ',' +
    '"Place":{"type":"object",' + SCHEMA_PLACE_PROPS +
    ',"description":"Where to search"},' +
    '"Code":{"type":"string","pattern":"^[A-Z]{3}$"},' +
    '"Colors":{"type":"array","items":' + SCHEMA_COLOR +
    ',"uniqueItems":true}},' +
    '"required":["Query","Place","Code"],' +
    '"description":"Search the catalogue"}';


implementation

{ TSchemaSearchTool }

function TSchemaSearchTool.ExecuteTyped(const aParams: TSchemaSearch;
  const aAuthCtx: TMcpAuthContext): variant;
begin
  result := _ObjFast(['content', _ArrFast([_ObjFast(['type', 'text',
    'text', RecordSaveJson(aParams, TypeInfo(TSchemaSearch))])])]);
end;

{ TTestMcpSchema }

class procedure TTestMcpSchema.RegisterTypes;
begin
  Rtti.RegisterTypes([TypeInfo(TSchemaColor), TypeInfo(TSchemaColors)]);
  if not RecordHasFields(TypeInfo(TSchemaAddress)) then
    Rtti.RegisterFromText(TypeInfo(TSchemaAddress), 'Street,City:RawUtf8');
  Rtti.RegisterType(TypeInfo(TSchemaAddressDynArray));
  if not RecordHasFields(TypeInfo(TSchemaAll)) then
    Rtti.RegisterFromText(TypeInfo(TSchemaAll),
      'Flag:boolean Count:integer Big:Int64 Ratio:double Price:currency ' +
      'Name:RawUtf8 Data:RawByteString Id:TGuid When:TDateTime ' +
      'Stamp:TTimeLog Color:TSchemaColor Colors:TSchemaColors ' +
      'Tags:TRawUtf8DynArray Home:TSchemaAddress ' +
      'Others:TSchemaAddressDynArray Extra:variant');
  Rtti.RegisterType(TypeInfo(TSchemaNodeDynArray));
  if not RecordHasFields(TypeInfo(TSchemaNode)) then
    Rtti.RegisterFromText(TypeInfo(TSchemaNode),
      'Name:RawUtf8 Children:TSchemaNodeDynArray');
  if not RecordHasFields(TypeInfo(TSchemaTree)) then
    Rtti.RegisterFromText(TypeInfo(TSchemaTree), 'Root:TSchemaNode');
  Rtti.RegisterType(TypeInfo(TSchemaCode));
  if not RecordHasFields(TypeInfo(TSchemaPlace)) then
    Rtti.RegisterFromText(TypeInfo(TSchemaPlace), 'Street,City:RawUtf8');
  if not RecordHasFields(TypeInfo(TSchemaSearch)) then
    Rtti.RegisterFromText(TypeInfo(TSchemaSearch), 'Query:RawUtf8 ' +
      'Limit:integer Color:TSchemaColor Place:TSchemaPlace Code:TSchemaCode ' +
      'Colors:TSchemaColors');
  if not RecordHasFields(TypeInfo(TSchemaOrder)) then
    Rtti.RegisterFromText(TypeInfo(TSchemaOrder),
      'Billing,Shipping:TSchemaPlace');
  if not RecordHasFields(TypeInfo(TSchemaCached)) then
    Rtti.RegisterFromText(TypeInfo(TSchemaCached), 'Value:integer');
end;

class procedure TTestMcpSchema.RegisterMetadata;
begin
  RegisterTypes;
  McpSchema(TypeInfo(TSchemaPlace))
    .Description('A postal address')
    .Field('City').DefaultValue('Paris');
  McpSchema(TypeInfo(TSchemaCode))
    .Replace('{"type":"string","pattern":"^[A-Z]{3}$"}');
  McpSchema(TypeInfo(TSchemaSearch))
    .Description('Search the catalogue')
    .Field('Query').Description('Text to search for').Keyword('minLength', 1)
    .Field('Limit').Description('Maximum number of results').DefaultValue(10)
    .Field('Color').Optional
    .Field('Place').Description('Where to search')
    .Field('Colors').Optional;
end;

procedure TTestMcpSchema.CheckSchema(aInfo: PRttiInfo; const aExpected: RawUtf8);
begin
  CheckEqual(VariantSaveJson(TMcpSchemaGenerator.GenerateSchema(aInfo)),
    aExpected, aInfo^.RawName);
end;

procedure TTestMcpSchema.SimpleTypes;
begin
  RegisterTypes;
  CheckSchema(TypeInfo(boolean), '{"type":"boolean"}');
  CheckSchema(TypeInfo(integer), '{"type":"integer"}');
  CheckSchema(TypeInfo(double), '{"type":"number"}');
  CheckSchema(TypeInfo(RawUtf8), '{"type":"string"}');
  CheckSchema(TypeInfo(TGuid), '{"type":"string","format":"uuid"}');
  CheckSchema(TypeInfo(TDateTime), '{"type":"string","format":"date-time"}');
  CheckSchema(TypeInfo(TDate), '{"type":"string","format":"date"}');
  CheckSchema(TypeInfo(TTimeLog), '{"type":"string","format":"date-time"}');
  CheckSchema(TypeInfo(TSchemaColor), SCHEMA_COLOR);
  CheckSchema(TypeInfo(TSchemaColors),
    '{"type":"array","items":' + SCHEMA_COLOR + ',"uniqueItems":true}');
  CheckSchema(TypeInfo(TRawUtf8DynArray),
    '{"type":"array","items":{"type":"string"}}');
  CheckSchema(TypeInfo(TSchemaRgb),
    '{"type":"array","items":{"type":"integer"},"minItems":3,"maxItems":3}');
  CheckSchema(TypeInfo(variant), '{}');
end;

procedure TTestMcpSchema.NestedRecordsAndArrays;
begin
  RegisterTypes;
  CheckSchema(TypeInfo(TSchemaAddress), SCHEMA_ADDRESS);
  // the field names keep the casing of the record
  CheckSchema(TypeInfo(TSchemaAll),
    '{"type":"object","properties":{' +
    '"Flag":{"type":"boolean"},' +
    '"Count":{"type":"integer"},' +
    '"Big":{"type":"integer"},' +
    '"Ratio":{"type":"number"},' +
    '"Price":{"type":"number"},' +
    '"Name":{"type":"string"},' +
    '"Data":{"type":"string","contentEncoding":"base64"},' +
    '"Id":{"type":"string","format":"uuid"},' +
    '"When":{"type":"string","format":"date-time"},' +
    '"Stamp":{"type":"string","format":"date-time"},' +
    '"Color":' + SCHEMA_COLOR + ',' +
    '"Colors":{"type":"array","items":' + SCHEMA_COLOR + ',"uniqueItems":true},' +
    '"Tags":{"type":"array","items":{"type":"string"}},' +
    '"Home":' + SCHEMA_ADDRESS + ',' +
    '"Others":{"type":"array","items":' + SCHEMA_ADDRESS + '},' +
    '"Extra":{}},' +
    '"required":["Flag","Count","Big","Ratio","Price","Name","Data","Id",' +
    '"When","Stamp","Color","Colors","Tags","Home","Others","Extra"]}');
end;

procedure TTestMcpSchema.NoParameters;
begin
  RegisterTypes;
  // recommended by the MCP specification for a tool without parameters
  CheckSchema(TypeInfo(TSchemaNone),
    '{"type":"object","additionalProperties":false}');
  // a record with fields but no field RTTI is not mistaken for "no parameters"
  if not RecordHasFields(TypeInfo(TSchemaNoRtti)) then
    CheckSchema(TypeInfo(TSchemaNoRtti), '{"type":"object"}');
end;

procedure TTestMcpSchema.RecursiveTypes;
const
  NODE_PROPS =
    '"properties":{"Name":{"type":"string"},"Children":{"type":"array",' +
    '"items":{"$ref":"#/$defs/TSchemaNode"}}},"required":["Name","Children"]';
begin
  RegisterTypes;
  // the root type refers to itself as "#"
  CheckSchema(TypeInfo(TSchemaNode),
    '{"type":"object","properties":{"Name":{"type":"string"},' +
    '"Children":{"type":"array","items":{"$ref":"#"}}},' +
    '"required":["Name","Children"]}');
  // a nested recursive type is defined once in "$defs"
  CheckSchema(TypeInfo(TSchemaTree),
    '{"type":"object","properties":{"Root":{"type":"object",' + NODE_PROPS +
    '}},"required":["Root"],"$defs":{"TSchemaNode":{"type":"object",' +
    NODE_PROPS + '}}}');
end;

procedure TTestMcpSchema.Metadata;
var
  search: TMcpSchemaType;
begin
  RegisterMetadata;
  CheckSchema(TypeInfo(TSchemaPlace), SCHEMA_PLACE);
  CheckSchema(TypeInfo(TSchemaCode), '{"type":"string","pattern":"^[A-Z]{3}$"}');
  CheckSchema(TypeInfo(TSchemaSearch), SCHEMA_SEARCH);
  // registering the same metadata again changes nothing
  RegisterMetadata;
  CheckSchema(TypeInfo(TSchemaSearch), SCHEMA_SEARCH);
  // the metadata can be read back, e.g. to validate arguments
  search := McpSchema(TypeInfo(TSchemaSearch));
  Check(search = McpSchema(TypeInfo(TSchemaSearch)), 'one instance per type');
  Check(search.Rtti.Info = TypeInfo(TSchemaSearch));
  Check(search.FindField('Code') = nil, 'no metadata');
  if CheckFailed(search.FindField('limit') <> nil, 'case insensitive') then
    exit;
  CheckEqual(search.FindField('limit').Name, 'Limit');
  Check(search.FindField('Query').IsRequired);
  Check(not search.FindField('Limit').IsRequired, 'a default value');
  Check(not search.FindField('Color').IsRequired, 'optional');
  Check(search.FindField('Place').IsRequired);
end;

procedure TTestMcpSchema.MetadataErrors;
var
  search: TMcpSchemaType;
  raised: boolean;
begin
  RegisterTypes;
  search := McpSchema(TypeInfo(TSchemaSearch));
  raised := false;
  try
    search.Field('Unknown');
  except
    on EMcpException do
      raised := true;
  end;
  Check(raised, 'unknown field');
  raised := false;
  try
    search.Field('Query').Replace('[1,2]');
  except
    on EMcpException do
      raised := true;
  end;
  Check(raised, 'Replace() expects a JSON object');
  raised := false;
  try
    McpSchema(nil);
  except
    on EMcpException do
      raised := true;
  end;
  Check(raised, 'no type');
end;

procedure TTestMcpSchema.ReplaceAndRef;
begin
  RegisterMetadata;
  // a reused nested record, defined once and referenced with "$ref"
  McpSchema(TypeInfo(TSchemaOrder))
    .Keyword('$defs', _ObjFast(['Place', McpSchema(TypeInfo(TSchemaPlace)).Schema]))
    .Field('Billing').Replace('{"$ref":"#/$defs/Place"}')
    .Field('Shipping').Replace('{"$ref":"#/$defs/Place"}')
      .Description('Defaults to the billing address').Optional;
  CheckSchema(TypeInfo(TSchemaOrder),
    '{"type":"object","properties":{"Billing":{"$ref":"#/$defs/Place"},' +
    '"Shipping":{"$ref":"#/$defs/Place",' +
    '"description":"Defaults to the billing address"}},' +
    '"required":["Billing"],"$defs":{"Place":' + SCHEMA_PLACE + '}}');
end;

procedure TTestMcpSchema.SchemaCache;
const
  BEFORE = '{"type":"object","properties":{"Value":{"type":"integer"}},' +
    '"required":["Value"]}';
var
  s1, s2: variant;
begin
  RegisterTypes;
  s1 := TMcpSchemaGenerator.GenerateSchema(TypeInfo(TSchemaCached));
  s2 := TMcpSchemaGenerator.GenerateSchema(TypeInfo(TSchemaCached));
  CheckEqual(VariantSaveJson(s1), BEFORE);
  Check(pointer(_Safe(s1)^.Values) = pointer(_Safe(s2)^.Values),
    'generated once');
  // any metadata change regenerates the schemas
  McpSchema(TypeInfo(TSchemaCached)).Field('Value').Keyword('minimum', 0);
  s2 := TMcpSchemaGenerator.GenerateSchema(TypeInfo(TSchemaCached));
  Check(pointer(_Safe(s1)^.Values) <> pointer(_Safe(s2)^.Values),
    'generated again');
  CheckEqual(VariantSaveJson(s1), BEFORE);
  CheckEqual(VariantSaveJson(s2), '{"type":"object","properties":{"Value":' +
    '{"type":"integer","minimum":0}},"required":["Value"]}');
end;

procedure TTestMcpSchema.ToolsList;
var
  server: TMcpServer;
  response: TDocVariantData;
begin
  RegisterMetadata;
  server := TMcpServer.Create('TestServer', '1.0');
  try
    server.RegisterTool(TSchemaSearchTool.Create('search', 'Search'));
    server.Start;
    Check(response.InitJson(server.ExecuteRequest(
      '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'), JSON_FAST));
    CheckEqual(response.O['result']^.A['tools']^._[0]^.
      O['inputSchema']^.ToJson, SCHEMA_SEARCH);
  finally
    server.Free;
  end;
end;

procedure TTestMcpSchema.ToolsCallDefaults;
var
  server: TMcpServer;

  procedure CheckCall(const aArgs, aExpected: RawUtf8);
  var
    response: TDocVariantData;
  begin
    if CheckFailed(response.InitJson(server.ExecuteRequest(
         '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":' +
         '{"name":"search","arguments":' + aArgs + '}}'), JSON_FAST), aArgs) then
      exit;
    CheckEqual(response.O['result']^.A['content']^._[0]^.U['text'],
      aExpected, aArgs);
  end;

begin
  RegisterMetadata;
  server := TMcpServer.Create('TestServer', '1.0');
  try
    server.RegisterTool(TSchemaSearchTool.Create('search', 'Search'));
    server.Start;
    // missing fields get their default value, also in nested records,
    // or zero if they have none
    CheckCall('{"Query":"x"}', '{"Query":"x","Limit":10,"Color":0,' +
      '"Place":{"Street":"","City":"Paris"},"Code":"","Colors":0}');
    CheckCall('{"Query":"x","Place":{"Street":"s"},"Code":"ABC"}',
      '{"Query":"x","Limit":10,"Color":0,' +
      '"Place":{"Street":"s","City":"Paris"},"Code":"ABC","Colors":0}');
    // the arguments override the default values; enumerations and sets are
    // read from the names published in the schema
    CheckCall('{"Query":"y","Limit":3,"Color":"Blue","Colors":["Red","Blue"],' +
      '"Place":{"Street":"s","City":"Lyon"}}',
      '{"Query":"y","Limit":3,"Color":2,' +
      '"Place":{"Street":"s","City":"Lyon"},"Code":"","Colors":5}');
    // the full RTTI names are still accepted
    CheckCall('{"Query":"z","Color":"scGreen","Colors":["scGreen"]}',
      '{"Query":"z","Limit":10,"Color":1,' +
      '"Place":{"Street":"","City":"Paris"},"Code":"","Colors":2}');
  finally
    server.Free;
  end;
end;

end.
