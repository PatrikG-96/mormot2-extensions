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

  TTestMcpSchema = class(TSynTestCase)
  protected
    procedure CheckSchema(aInfo: PRttiInfo; const aExpected: RawUtf8);
  public
    /// register the RTTI of the test types (needed on FPC 3.2.2)
    class procedure RegisterTypes;
  published
    procedure SimpleTypes;
    procedure NestedRecordsAndArrays;
    procedure NoParameters;
    procedure RecursiveTypes;
  end;

const
  SCHEMA_ADDRESS =
    '{"type":"object","properties":{"Street":{"type":"string"},' +
    '"City":{"type":"string"}},"required":["Street","City"]}';
  SCHEMA_COLOR =
    '{"type":"string","enum":["scRed","scGreen","scBlue"]}';


implementation

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

end.
