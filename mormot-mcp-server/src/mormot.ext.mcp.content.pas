/// Model Context Protocol (MCP) Content Blocks for mORMot v2
// - this unit is part of the mormot-mcp-server project
// - licensed under MPL/GPL/LGPL three license
unit mormot.ext.mcp.content;

{
  *****************************************************************************

    - Icon and Annotation Types
    - Response Builder Helper

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
  mormot.core.buffers,
  mormot.core.variants,
  mormot.ext.mcp.jsonrpc;


{ ************ Icon and Annotation Types }

type
  /// the sender or recipient of messages and data, e.g. in TMcpAnnotations
  TMcpRole = (
    mrUser,
    mrAssistant);
  /// a set of TMcpRole, e.g. TMcpAnnotations.Audience
  TMcpRoles = set of TMcpRole;

  /// optional annotations of a content block or resource
  // - tell the client how to use or display the data
  // - fill it with McpAnnotations(), then see TMcpResponseBuilder.Annotate
  TMcpAnnotations = record
    /// who the data is intended for, or [] if not set
    Audience: TMcpRoles;
    /// how important the data is, from 0 (entirely optional) to 1 (most
    // important), or a negative value if not set
    Priority: double;
    /// when the data was last modified, in UTC, or 0 if not set
    LastModified: TDateTime;
    /// the "annotations" JSON object, or Unassigned if nothing is set
    function ToVariant: variant;
  end;

  /// the background an icon is designed for
  TMcpIconTheme = (
    mitAny,
    mitLight,
    mitDark);

  /// an icon which a client may display for a tool, resource, prompt or server
  // - fill it with McpIcon()
  TMcpIcon = record
    /// a https: URL or a data: URI with base64 image data
    Src: RawUtf8;
    /// optional MIME type, if Src does not tell it
    MimeType: RawUtf8;
    /// optional sizes, e.g. '48x48', or 'any' for scalable formats
    Sizes: TRawUtf8DynArray;
    /// the background the icon is designed for
    Theme: TMcpIconTheme;
    /// the Icon JSON object
    function ToVariant: variant;
  end;
  /// a list of icons, as published in an "icons" JSON array
  TMcpIcons = array of TMcpIcon;

/// return the annotations of a content block or resource
// - aPriority is from 0 to 1, or negative if not set
// - aLastModified is in UTC, or 0 if not set
// - raise EMcpException if aPriority is greater than 1
function McpAnnotations(aAudience: TMcpRoles; aPriority: double = -1;
  aLastModified: TDateTime = 0): TMcpAnnotations;

/// return an icon
// - aSrc is a https: URL or a data: URI, e.g. 'data:image/png;base64,...'
// - aSizes is a space-separated list, as the HTML "sizes" attribute,
// e.g. '48x48 96x96' or 'any'
// - raise EMcpException if aSrc is not a https: or data: URI
function McpIcon(const aSrc: RawUtf8; const aMimeType: RawUtf8 = '';
  const aSizes: RawUtf8 = ''; aTheme: TMcpIconTheme = mitAny): TMcpIcon;

/// return the "icons" JSON array of some icons, as a TDocVariant
function McpIconsToVariant(const aIcons: array of TMcpIcon): variant;


{ ************ Response Builder Helper }

type
  /// Helper to build MCP tool results, i.e. a "content" array of blocks
  // - e.g.
  // ! builder := TMcpResponseBuilder.Create;
  // ! try
  // !   builder.AddText('Chart of the sales')
  // !     .AddImage(png, 'image/png').Annotate(McpAnnotations([mrUser]));
  // !   result := builder.Build;
  // ! finally
  // !   builder.Free;
  // ! end;
  TMcpResponseBuilder = class
  private
    fContent: TDocVariantData;
    fIsError: boolean;
    function AddBlock(const aType: RawUtf8;
      const aNameValuePairs: array of const): TMcpResponseBuilder;
  public
    /// initialize builder
    constructor Create;
    /// add a "text" content block
    function AddText(const aText: RawUtf8): TMcpResponseBuilder;
    /// add an "image" content block
    // - aData is the binary image, sent base64-encoded
    function AddImage(const aData: RawByteString;
      const aMimeType: RawUtf8): TMcpResponseBuilder;
    /// add an "audio" content block
    // - aData is the binary audio, sent base64-encoded
    function AddAudio(const aData: RawByteString;
      const aMimeType: RawUtf8): TMcpResponseBuilder;
    /// add a "resource_link" content block, i.e. a resource which the client
    // may read
    // - the resource need not be listed by resources/list
    function AddResourceLink(const aUri, aName: RawUtf8;
      const aDescription: RawUtf8 = '';
      const aMimeType: RawUtf8 = ''): TMcpResponseBuilder;
    /// add a "resource" content block, with the text of an embedded resource
    // - aMimeType is optional
    function AddEmbeddedText(const aUri, aMimeType,
      aText: RawUtf8): TMcpResponseBuilder;
    /// add a "resource" content block, with the binary content of an
    // embedded resource, sent base64-encoded
    // - aMimeType is optional
    function AddEmbeddedBlob(const aUri, aMimeType: RawUtf8;
      const aData: RawByteString): TMcpResponseBuilder;
    /// add the content of a file, as an "image", "audio" or else an embedded
    // binary "resource" block, depending on its MIME type
    // - the URI of an embedded resource is 'file:///' + the URI-encoded
    // aFileName, or the name of aFilePath if aFileName is '': the server
    // folder is not published
    // - raise EMcpException if the file does not exist
    function AddFile(const aFilePath: RawUtf8;
      const aFileName: RawUtf8 = ''): TMcpResponseBuilder;
    /// set the annotations of the last added block
    // - does nothing if aAnnotations has nothing set
    // - raise EMcpException if no block was added yet
    function Annotate(const aAnnotations: TMcpAnnotations): TMcpResponseBuilder;
    /// mark the result as a tool failure, reported to the model
    // - i.e. "isError": true: add some text explaining the failure, so that
    // the model can correct its request
    // - same as raising EMcpToolError, without an exception
    function SetError: TMcpResponseBuilder;
    /// build final response as variant
    function Build: variant;
  end;


implementation


{ ************ Icon and Annotation Types }

const
  ROLE_TEXT: array[TMcpRole] of RawUtf8 = (
    'user',
    'assistant');
  THEME_TEXT: array[TMcpIconTheme] of RawUtf8 = (
    '',
    'light',
    'dark');

function TMcpAnnotations.ToVariant: variant;
var
  doc, list: TDocVariantData;
  r: TMcpRole;
begin
  doc.InitFast(dvObject);
  if Audience <> [] then
  begin
    list.InitFast(dvArray);
    for r := low(r) to high(r) do
      if r in Audience then
        list.AddItemText(ROLE_TEXT[r]);
    doc.AddValue('audience', variant(list));
  end;
  if Priority >= 0 then
    doc.AddValue('priority', Priority);
  if LastModified <> 0 then
    // always a date and a time, in UTC
    doc.AddValueText('lastModified',
      DateTimeToIso8601(LastModified, {expanded=}true) + 'Z');
  if doc.Count = 0 then
    VarClear(result)
  else
    result := variant(doc);
end;

function McpAnnotations(aAudience: TMcpRoles; aPriority: double;
  aLastModified: TDateTime): TMcpAnnotations;
begin
  if aPriority > 1 then
    raise EMcpException.CreateUtf8('McpAnnotations: priority % > 1', [aPriority]);
  result.Audience := aAudience;
  result.Priority := aPriority;
  result.LastModified := aLastModified;
end;

function TMcpIcon.ToVariant: variant;
var
  doc, list: TDocVariantData;
begin
  doc.InitFast(dvObject);
  doc.AddValueText('src', Src);
  if MimeType <> '' then
    doc.AddValueText('mimeType', MimeType);
  if Sizes <> nil then
  begin
    list.InitArrayFrom(Sizes, JSON_FAST);
    doc.AddValue('sizes', variant(list));
  end;
  if Theme <> mitAny then
    doc.AddValueText('theme', THEME_TEXT[Theme]);
  result := variant(doc);
end;

function McpIcon(const aSrc, aMimeType, aSizes: RawUtf8;
  aTheme: TMcpIconTheme): TMcpIcon;
begin
  if not IdemPChar(pointer(aSrc), 'HTTPS://') and
     not IdemPChar(pointer(aSrc), 'DATA:') then
    raise EMcpException.CreateUtf8('McpIcon(%): not a https: or data: URI', [aSrc]);
  result.Src := aSrc;
  result.MimeType := aMimeType;
  result.Sizes := nil;
  CsvToRawUtf8DynArray(pointer(aSizes), result.Sizes, ' ');
  result.Theme := aTheme;
end;

function McpIconsToVariant(const aIcons: array of TMcpIcon): variant;
var
  list: TDocVariantData;
  i: PtrInt;
begin
  list.InitFast(dvArray);
  for i := 0 to high(aIcons) do
    list.AddItem(aIcons[i].ToVariant);
  result := variant(list);
end;


{ ************ TMcpResponseBuilder Implementation }

// the TextResourceContents or BlobResourceContents of a resource
// - aKind is 'text' or 'blob' (then aValue is base64-encoded)
function ResourceContents(const aUri, aMimeType, aKind, aValue: RawUtf8): variant;
var
  doc: TDocVariantData;
begin
  doc.InitFast(dvObject);
  doc.AddValueText('uri', aUri);
  if aMimeType <> '' then
    doc.AddValueText('mimeType', aMimeType);
  doc.AddValueText(aKind, aValue);
  result := variant(doc);
end;

constructor TMcpResponseBuilder.Create;
begin
  inherited Create;
  fContent.InitFast(dvArray);
end;

function TMcpResponseBuilder.AddBlock(const aType: RawUtf8;
  const aNameValuePairs: array of const): TMcpResponseBuilder;
var
  block: TDocVariantData;
begin
  block.InitFast(dvObject);
  block.AddValueText('type', aType);
  block.Update(aNameValuePairs);
  fContent.AddItem(variant(block));
  result := self;
end;

function TMcpResponseBuilder.AddText(const aText: RawUtf8): TMcpResponseBuilder;
begin
  result := AddBlock('text', ['text', aText]);
end;

function TMcpResponseBuilder.AddImage(const aData: RawByteString;
  const aMimeType: RawUtf8): TMcpResponseBuilder;
begin
  result := AddBlock('image', ['data', BinToBase64(aData), 'mimeType', aMimeType]);
end;

function TMcpResponseBuilder.AddAudio(const aData: RawByteString;
  const aMimeType: RawUtf8): TMcpResponseBuilder;
begin
  result := AddBlock('audio', ['data', BinToBase64(aData), 'mimeType', aMimeType]);
end;

function TMcpResponseBuilder.AddResourceLink(const aUri, aName, aDescription,
  aMimeType: RawUtf8): TMcpResponseBuilder;
var
  block: PDocVariantData;
begin
  result := AddBlock('resource_link', ['uri', aUri, 'name', aName]);
  block := _Safe(fContent.Values[fContent.Count - 1]);
  if aDescription <> '' then
    block^.AddValueText('description', aDescription);
  if aMimeType <> '' then
    block^.AddValueText('mimeType', aMimeType);
end;

function TMcpResponseBuilder.AddEmbeddedText(const aUri, aMimeType,
  aText: RawUtf8): TMcpResponseBuilder;
begin
  result := AddBlock('resource',
    ['resource', ResourceContents(aUri, aMimeType, 'text', aText)]);
end;

function TMcpResponseBuilder.AddEmbeddedBlob(const aUri, aMimeType: RawUtf8;
  const aData: RawByteString): TMcpResponseBuilder;
begin
  result := AddBlock('resource',
    ['resource', ResourceContents(aUri, aMimeType, 'blob', BinToBase64(aData))]);
end;

function TMcpResponseBuilder.AddFile(const aFilePath,
  aFileName: RawUtf8): TMcpResponseBuilder;
var
  fileName: TFileName;
  content: RawByteString;
  mimeType, name: RawUtf8;
begin
  fileName := Utf8ToString(aFilePath);
  if not FileExists(fileName) then
    raise EMcpException.CreateUtf8('File not found: %', [aFilePath]);
  content := StringFromFile(fileName);
  mimeType := GetMimeContentType(content, fileName);
  // the framework knows no audio format (it may guess "application/wav"
  // from the extension): recognize the WAV files by their RIFF/WAVE tag
  if not IdemPChar(pointer(mimeType), 'AUDIO/') then
    if (length(content) > 12) and
       (PCardinal(content)^ = $46464952) and // 'RIFF'
       (PCardinalArray(content)^[2] = $45564157) then
      mimeType := 'audio/wav';
  if IdemPChar(pointer(mimeType), 'IMAGE/') then
    result := AddImage(content, mimeType)
  else if IdemPChar(pointer(mimeType), 'AUDIO/') then
    result := AddAudio(content, mimeType)
  else
  begin
    if aFileName = '' then
      name := ExtractNameU(aFilePath)
    else
      name := aFileName;
    result := AddEmbeddedBlob('file:///' + UrlEncodeName(name), mimeType, content);
  end;
end;

function TMcpResponseBuilder.Annotate(
  const aAnnotations: TMcpAnnotations): TMcpResponseBuilder;
var
  annotations, block: variant;
begin
  if fContent.Count = 0 then
    raise EMcpException.Create('TMcpResponseBuilder.Annotate: no block yet');
  annotations := aAnnotations.ToVariant;
  if not VarIsEmptyOrNull(annotations) then
  begin
    // copy the block: a previous Build shares it, and must not change
    block := _Copy(fContent.Values[fContent.Count - 1]);
    _Safe(block)^.AddOrUpdateValue('annotations', annotations);
    fContent.Values[fContent.Count - 1] := block;
  end;
  result := self;
end;

function TMcpResponseBuilder.SetError: TMcpResponseBuilder;
begin
  fIsError := true;
  result := self;
end;

function TMcpResponseBuilder.Build: variant;
var
  doc, content: TDocVariantData;
  i: PtrInt;
begin
  // copy the list of blocks, so that adding blocks won't change this result
  content.InitFast(dvArray);
  for i := 0 to fContent.Count - 1 do
    content.AddItem(fContent.Values[i]);
  doc.InitFast(dvObject);
  doc.AddValue('content', variant(content));
  if fIsError then
    doc.AddValue('isError', true);
  result := variant(doc);
end;


end.
