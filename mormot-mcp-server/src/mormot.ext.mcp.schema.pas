/// Model Context Protocol (MCP) Tool Schema Generation for mORMot v2
// - this unit is part of the mormot-mcp-server project
// - licensed under MPL/GPL/LGPL three license
unit mormot.ext.mcp.schema;

{
  *****************************************************************************

    - RTTI-based Schema Generation

  *****************************************************************************
}

interface

{$I mormot.defines.inc}

uses
  mormot.core.base,
  mormot.core.os,
  mormot.core.unicode,
  mormot.core.text,
  mormot.core.rtti,
  mormot.core.data,
  mormot.core.variants,
  mormot.core.json,
  mormot.core.log,
  mormot.ext.mcp.jsonrpc;


{ ************ RTTI-based Schema Generation }

type
  /// how TMcpSchemaType adds a default value to the tool arguments
  // - internal type: see TMcpSchemaType.ArgumentsJson
  TMcpSchemaDefault = record
    /// the field name
    Name: RawUtf8;
    /// the DefaultValue() of this field, used when it is missing
    Value: variant;
    /// if Value is set
    HasValue: boolean;
    /// how many array layers contain the Node records, e.g. 1 for an array
    // of records, 2 for an array of arrays of records, 0 for a record
    Depth: integer;
    /// the index of the defaults of the nested record type, or -1
    Node: integer;
  end;
  /// the defaults of a record type (index 0) and of the record types it uses
  TMcpSchemaDefaults = array of array of TMcpSchemaDefault;

  /// JSON Schema metadata, common to TMcpSchemaType and TMcpSchemaField
  // - the "$defs" keywords of all types and fields, and the "$defs" of their
  // Replace() schemas, are moved to the root of the generated schema, where
  // a "$ref" finds them
  TMcpSchemaMeta = class(TSynPersistent)
  protected
    fKeywords: TDocVariantData;
    fReplace: variant;
    procedure SetKeyword(const aName: RawUtf8; const aValue: variant);
    procedure SetReplace(const aSchemaJson: RawUtf8);
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
    function GetRequired: boolean; // caller should have locked SchemaSafe
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
    // - TMcpToolBase<T> adds it to the arguments when this field is missing,
    // also in nested records and in the record items of arrays
    function DefaultValue(const aValue: variant): TMcpSchemaField;
    /// make this field optional, i.e. not listed in "required"
    // - by default, a field is required unless it has a default value
    function Optional: TMcpSchemaField;
    /// replace the generated schema of this field by a JSON object
    // - e.g. '{"$ref":"#/$defs/Address"}', with "$defs" set by a Keyword() of
    // a type or field (written at the root of the schema)
    // - fractional numbers are kept as numbers (JSON_FAST_FLOAT)
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
  // - set the metadata once at startup: all methods are thread-safe, but any
  // change makes all the schemas be generated again
  TMcpSchemaType = class(TMcpSchemaMeta)
  protected
    fRtti: TRttiCustom;
    fFields: array of TMcpSchemaField;
    fSchema: variant;
    fDefaults: TMcpSchemaDefaults;
    fVersion: integer;
    // caller should have locked SchemaSafe
    procedure Prepare;
    function GetField(const aName: RawUtf8): TMcpSchemaField;
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
    // "$ref" of a TMcpSchemaField.Replace(): "$defs" is written at the root of
    // the schema, even for a nested type
    // - replaces a generated keyword of the same name
    // - raise EMcpException for 'default': set default values on the fields
    function Keyword(const aName: RawUtf8; const aValue: variant): TMcpSchemaType;
    /// replace the generated schema of this type by a JSON object
    // - e.g. for a type with a custom JSON serializer
    // - the Description() and Keyword() of this type are still added
    // - fractional numbers are kept as numbers (JSON_FAST_FLOAT)
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
    // - the returned variant is shared with the cache: make a _Copy() before
    // modifying it (TMcpSchemaGenerator.GenerateSchema returns a copy)
    // - raise EMcpException if two "$defs" have the same name but differ
    function Schema: variant;
    /// return the JSON of the aArgs object, with the DefaultValue() of its
    // missing fields added
    // - also for the fields of nested records and of the record items of
    // arrays which aArgs contains; a field present in aArgs is kept as is
    // - returns '{}' (with the defaults) if aArgs is not a JSON object
    // - TMcpToolBase<T> loads the tool arguments from it
    function ArgumentsJson(const aArgs: variant): RawUtf8;
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
    // - a copy of McpSchema(aTypeInfo).Schema, which is generated once and
    // cached: the caller may modify it
    class function GenerateSchema(aTypeInfo: PRttiInfo): variant;
  end;

/// return the JSON Schema metadata of a type, to describe it and its fields
// - there is a single instance per type, owned by its TRttiCustom
// - raise EMcpException if aTypeInfo is nil
function McpSchema(aTypeInfo: PRttiInfo): TMcpSchemaType;


implementation

type
  /// a record or class being written, to detect recursive types
  PSchemaFrame = ^TSchemaFrame;
  TSchemaFrame = record
    Rtti: TRttiCustom;
    Parent: PSchemaFrame;
  end;

  /// write the JSON Schema of one type from its RTTI and McpSchema() metadata
  // - called with SchemaSafe locked
  TSchemaWriter = record
    Root: TRttiCustom;
    Top: PSchemaFrame;
    Recursive: TPointerDynArray; // recursive types, to be written in "$defs"
    Defs: TDocVariantData;       // all "$defs", written at the root
    function IsRecursive(aRtti: TRttiCustom): boolean;
    procedure AddDefs(const aDefs: variant);
    function InitReplaced(aMeta: TMcpSchemaMeta; var aSchema: TDocVariantData): boolean;
    procedure AddKeywords(aMeta: TMcpSchemaMeta; var aSchema: TDocVariantData);
    procedure AddEnum(aRtti: TRttiCustom; var aSchema: TDocVariantData);
    procedure WriteRef(aRtti: TRttiCustom; var aSchema: TDocVariantData);
    procedure WriteObject(aRtti: TRttiCustom; aMeta: TMcpSchemaType;
      var aSchema: TDocVariantData);
    procedure WriteType(aRtti: TRttiCustom; var aSchema: TDocVariantData);
    procedure WriteRoot(aRtti: TRttiCustom; var aSchema: TDocVariantData);
  end;


{ ************ TMcpSchemaGenerator Implementation }

var
  // protects all TMcpSchemaMeta instances and the cached schemas
  // - a TLightLock is not reentrant: the methods called with SchemaSafe
  // locked use the non-locking GetField/GetRequired helpers
  SchemaSafe: TLightLock;
  // incremented on each metadata change, to generate the schemas again
  SchemaVersion: integer;

{ TMcpSchemaMeta }

constructor TMcpSchemaMeta.Create;
begin
  inherited Create;
  fKeywords.InitFast(dvObject);
end;

// raise EMcpException if a "$defs" value is not a JSON object
// - TSchemaWriter.AddDefs merges its members into the root "$defs"
procedure CheckDefs(aMeta: TMcpSchemaMeta; const aDefs: variant);
begin
  if not _Safe(aDefs)^.IsObject then
    raise EMcpException.CreateUtf8('%: "$defs" is not a JSON object', [aMeta]);
end;

procedure TMcpSchemaMeta.SetKeyword(const aName: RawUtf8; const aValue: variant);
begin
  if aName = '$defs' then
    CheckDefs(self, aValue);
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
  schema: TDocVariantData;
  ndx: PtrInt;
begin
  // InitJson alone accepts trailing text, and 'null' as a void object: check
  // the whole input as strict JSON, which starts with '{', first
  // - JSON_FAST_FLOAT: with JSON_FAST, 0.000001 would be parsed as a string
  if not IsValidJson(aSchemaJson, {strict=}true) or
     (GotoNextNotSpace(pointer(aSchemaJson))^ <> '{') or
     not schema.InitJson(aSchemaJson, JSON_FAST_FLOAT) or
     not schema.IsObject then
    raise EMcpException.CreateUtf8('%.Replace(%): not a JSON object',
      [self, aSchemaJson]);
  ndx := schema.GetValueIndex('$defs');
  if ndx >= 0 then
    CheckDefs(self, schema.Values[ndx]);
  SchemaSafe.Lock;
  try
    fReplace := variant(schema);
    inc(SchemaVersion);
  finally
    SchemaSafe.UnLock;
  end;
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

function TMcpSchemaField.GetRequired: boolean;
begin
  result := not fOptional and
            not fKeywords.Exists('default');
end;

function TMcpSchemaField.IsRequired: boolean;
begin
  SchemaSafe.Lock;
  try
    result := GetRequired;
  finally
    SchemaSafe.UnLock;
  end;
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
  if aName = 'default' then
    // it would be published for each field of this type, but not applied
    raise EMcpException.CreateUtf8('McpSchema(%).Keyword(default): set ' +
      'the default values on the fields', [fRtti.Name]);
  SetKeyword(aName, aValue);
  result := self;
end;

function TMcpSchemaType.Replace(const aSchemaJson: RawUtf8): TMcpSchemaType;
begin
  SetReplace(aSchemaJson);
  result := self;
end;

function TMcpSchemaType.GetField(const aName: RawUtf8): TMcpSchemaField;
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

function TMcpSchemaType.FindField(const aName: RawUtf8): TMcpSchemaField;
begin
  SchemaSafe.Lock;
  try
    result := GetField(aName);
  finally
    SchemaSafe.UnLock;
  end;
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
    result := GetField(p^.Name);
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

procedure TSchemaWriter.AddDefs(const aDefs: variant);
var
  src: PDocVariantData;
  i, ndx: PtrInt;
begin
  src := _Safe(aDefs);
  for i := 0 to src^.Count - 1 do
  begin
    ndx := Defs.GetValueIndex(src^.Names[i]);
    if ndx < 0 then
      Defs.AddValue(src^.Names[i], src^.Values[i])
    else if VariantSaveJson(Defs.Values[ndx]) <> VariantSaveJson(src^.Values[i]) then
      raise EMcpException.CreateUtf8('McpSchema(%): two different "$defs/%"',
        [Root.Name, src^.Names[i]]);
  end;
end;

function TSchemaWriter.InitReplaced(aMeta: TMcpSchemaMeta;
  var aSchema: TDocVariantData): boolean;
var
  ndx: PtrInt;
begin
  result := not VarIsEmptyOrNull(aMeta.fReplace);
  if not result then
    exit;
  aSchema.InitCopy(aMeta.fReplace, JSON_FAST); // never modify fReplace itself
  ndx := aSchema.GetValueIndex('$defs');
  if ndx < 0 then
    exit;
  AddDefs(aSchema.Values[ndx]);
  aSchema.Delete(ndx);
end;

procedure TSchemaWriter.AddKeywords(aMeta: TMcpSchemaMeta;
  var aSchema: TDocVariantData);
var
  i: PtrInt;
begin
  for i := 0 to aMeta.fKeywords.Count - 1 do
    if aMeta.fKeywords.Names[i] = '$defs' then
      AddDefs(aMeta.fKeywords.Values[i])
    else
      aSchema.AddOrUpdateValue(aMeta.fKeywords.Names[i], aMeta.fKeywords.Values[i]);
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
    PtrArrayAddOnce(Recursive, aRtti);
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
        field := aMeta.GetField(p^.Name);
      if (field = nil) or
         not InitReplaced(field, schema) then
        WriteType(p^.Value, schema);
      if field <> nil then
        AddKeywords(field, schema);
      props.AddValue(p^.Name, variant(schema));
      schema.Clear;
      if (field = nil) or
         field.GetRequired then
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
     not InitReplaced(meta, aSchema) then
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
    AddKeywords(meta, aSchema);
end;

procedure TSchemaWriter.WriteRoot(aRtti: TRttiCustom; var aSchema: TDocVariantData);
var
  def: TDocVariantData;
  generated: TDocVariantData;
  i: PtrInt;
begin
  Root := aRtti;
  Top := nil;
  Recursive := nil;
  Defs.Init(JSON_FAST + [dvoNameCaseSensitive], dvObject); // as JSON pointers
  WriteType(aRtti, aSchema);
  if Recursive <> nil then
  begin
    generated.InitFast(dvObject);
    i := 0;
    while i < length(Recursive) do // Recursive may grow during the loop
    begin
      WriteType(Recursive[i], def);
      generated.AddValue(TRttiCustom(Recursive[i]).Name, variant(def));
      def.Clear;
      inc(i);
    end;
    AddDefs(variant(generated));
  end;
  if Defs.Count <> 0 then
    aSchema.AddValue('$defs', variant(Defs));
end;

{ default values }

// build the defaults of aRtti (node 0) and of the record types it uses
// - aTypes[n] is the type of node n
procedure BuildDefaults(aRtti: TRttiCustom; out aDefaults: TMcpSchemaDefaults;
  out aTypes: TPointerDynArray);
var
  used: TBooleanDynArray;  // if a node has some default value, maybe nested
  entries: array of TMcpSchemaDefault;
  e: TMcpSchemaDefault;
  pe: ^TMcpSchemaDefault;
  rc, item: TRttiCustom;
  meta: TMcpSchemaType;
  field: TMcpSchemaField;
  value: PVariant;
  p: PRttiCustomProp;
  n, i, j, count: PtrInt;
  changed: boolean;
begin
  PtrArrayAdd(aTypes, aRtti);
  n := 0;
  while n < length(aTypes) do // aTypes may grow during the loop
  begin
    rc := aTypes[n];
    meta := rc.GetPrivateSlot(TMcpSchemaType);
    entries := nil;
    p := pointer(rc.Props.List);
    for i := 1 to rc.Props.Count do
    begin
      if p^.Name <> '' then
      begin
        e.Name := p^.Name;
        field := nil;
        if meta <> nil then
          field := meta.GetField(p^.Name);
        e.HasValue := (field <> nil) and
                      field.fKeywords.GetAsPVariant('default', value);
        if e.HasValue then
          e.Value := value^
        else
          VarClear(e.Value);
        e.Depth := 0;
        e.Node := -1;
        item := p^.Value;
        while (item.Parser in [ptArray, ptDynArray]) and
              (item.ArrayRtti <> nil) do
        begin
          inc(e.Depth); // as TSchemaWriter.WriteType, through all layers
          item := item.ArrayRtti;
        end;
        if item.Kind in rkRecordTypes then
          e.Node := PtrArrayAddOnce(aTypes, item);
        if e.HasValue or
           (e.Node >= 0) then
        begin
          SetLength(entries, length(entries) + 1);
          entries[high(entries)] := e;
        end;
      end;
      inc(p);
    end;
    SetLength(aDefaults, length(aTypes));
    aDefaults[n] := entries;
    inc(n);
  end;
  // keep only the nested records which have some default value
  SetLength(used, length(aTypes));
  repeat
    changed := false;
    for n := 0 to high(aDefaults) do
      if not used[n] then
        for i := 0 to high(aDefaults[n]) do
        begin
          pe := @aDefaults[n][i];
          if pe^.HasValue or
             ((pe^.Node >= 0) and used[pe^.Node]) then
          begin
            used[n] := true;
            changed := true;
            break;
          end;
        end;
  until not changed;
  if not used[0] then
  begin
    aDefaults := nil; // nothing to add to the arguments
    exit;
  end;
  for n := 0 to high(aDefaults) do
  begin
    count := 0;
    for i := 0 to high(aDefaults[n]) do
    begin
      e := aDefaults[n][i];
      if (e.Node >= 0) and
         not used[e.Node] then
        e.Node := -1;
      if e.HasValue or
         (e.Node >= 0) then
      begin
        aDefaults[n][count] := e;
        inc(count);
      end;
    end;
    SetLength(aDefaults[n], count);
  end;
  for j := 0 to high(aDefaults) do
    if not used[j] then
      aDefaults[j] := nil;
end;

// add the missing default values of node aNode to aArgs
procedure AddDefaults(const aDefaults: TMcpSchemaDefaults; aNode: PtrInt;
  var aArgs: TDocVariantData);
var
  i, ndx: PtrInt;
  e: ^TMcpSchemaDefault;
  nested: TDocVariantData;

  // complete a supplied record, or the records of supplied arrays
  procedure Complete(var aValue: TDocVariantData; aDepth: integer);
  var
    j: PtrInt;
  begin
    if aDepth = 0 then
    begin
      if aValue.IsObject then
        AddDefaults(aDefaults, e^.Node, aValue);
    end
    else if aValue.IsArray then
      for j := 0 to aValue.Count - 1 do
        Complete(_Safe(aValue.Values[j])^, aDepth - 1);
  end;

begin
  for i := 0 to high(aDefaults[aNode]) do
  begin
    e := @aDefaults[aNode][i];
    ndx := aArgs.GetValueIndex(e^.Name);
    if ndx < 0 then
    begin
      if e^.HasValue then
        aArgs.AddValue(e^.Name, e^.Value)
      else if e^.Depth = 0 then
      begin
        // a missing record: the default values of its own fields
        nested.InitFast(dvObject);
        AddDefaults(aDefaults, e^.Node, nested);
        if nested.Count <> 0 then
          aArgs.AddValue(e^.Name, variant(nested));
        nested.Clear;
      end;
    end
    else if e^.Node >= 0 then
      Complete(_Safe(aArgs.Values[ndx])^, e^.Depth);
  end;
end;

// log the default values which can't be read into their record, once
procedure CheckDefaults(const aDefaults: TMcpSchemaDefaults;
  const aTypes: TPointerDynArray);
var
  n: PtrInt;
  rc: TRttiCustom;
  doc: TDocVariantData;
  json: RawUtf8;
  tmp: pointer;
  ok: boolean;
begin
  for n := 0 to high(aDefaults) do
    if aDefaults[n] <> nil then
    begin
      rc := aTypes[n];
      doc.InitFast(dvObject);
      AddDefaults(aDefaults, n, doc);
      json := doc.ToJson;
      doc.Clear;
      tmp := AllocMem(rc.Size);
      try
        ok := RecordLoadJson(tmp^, json, rc.Info, nil, {tolerant=}false);
      finally
        rc.ValueFinalize(tmp);
        FreeMem(tmp);
      end;
      if not ok then
        TSynLog.Add.Log(sllWarning, 'McpSchema(%): the default values % ' +
          'can''t be read', [rc.Name, json]);
    end;
end;

procedure TMcpSchemaType.Prepare;
var
  w: TSchemaWriter;
  schema: variant;
  types: TPointerDynArray;
begin
  if not VarIsEmptyOrNull(fSchema) and
     (fVersion = SchemaVersion) then
    exit;
  w.WriteRoot(fRtti, TDocVariantData(schema)); // may raise EMcpException
  fSchema := schema;
  fDefaults := nil;
  if fRtti.Kind in rkRecordTypes then
  begin
    BuildDefaults(fRtti, fDefaults, types);
    CheckDefaults(fDefaults, types);
  end;
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

function TMcpSchemaType.ArgumentsJson(const aArgs: variant): RawUtf8;
var
  defaults: TMcpSchemaDefaults;
  args: TDocVariantData;
  src: PDocVariantData;
begin
  SchemaSafe.Lock;
  try
    Prepare;
    defaults := fDefaults; // by reference: a new Prepare won't change it
  finally
    SchemaSafe.UnLock;
  end;
  src := _Safe(aArgs);
  if defaults = nil then
    if src^.IsObject then
      result := src^.ToJson
    else
      result := '{}'
  else
  begin
    if src^.IsObject then
      args.InitCopy(aArgs, JSON_FAST) // never modify the request
    else
      args.InitFast(dvObject);
    AddDefaults(defaults, 0, args);
    result := args.ToJson;
  end;
end;

class function TMcpSchemaGenerator.GenerateSchema(aTypeInfo: PRttiInfo): variant;
begin
  result := _CopyFast(McpSchema(aTypeInfo).Schema);
end;


end.
