program SteamFX_RenderTests;

// Copyright (c) 2026 VRAMの魔術師
// SPDX-License-Identifier: GPL-3.0-only
// 本番 AUF2 を読み込み、AviUtl2 の編集と画像出力をテストプロセス内で再現する。

{$APPTYPE CONSOLE}
{$POINTERMATH ON}

uses
  System.SysUtils, System.Math, System.Hash,
  Winapi.Windows, Winapi.D3D11, Winapi.D3DCommon, Winapi.DXGI, Winapi.DXGIFormat,
  Winapi.D3DCompiler, Vcl.Imaging.pngimage,
  AviUtl2FilterTypes in '..\Source\Lib\AviUtl2FilterTypes.pas';

type
  TRequiredVersion = function: Cardinal; cdecl;
  TInitializePlugin = function(Version: Cardinal): Byte; cdecl;
  TUninitializePlugin = procedure; cdecl;
  TGetTable = function: PFILTER_PLUGIN_TABLE; cdecl;
  TPixels = TArray<TPIXEL_RGBA>;
  PSelectOption = ^TFILTER_ITEM_SELECT_ITEM;
  TBounds = record
    Left, Top, Right, Bottom: Integer;
    Alpha: Int64;
    Peak: Byte;
  end;

const
  START_FRAME = 140;
  PRESET_COUNT = 32;
  SELECT_PRESET = '湯気プリセット';
  ITEM_AMOUNT = '発生量';
  ITEM_ORIGIN_X = '発生位置X';
  ITEM_ORIGIN_Y = '発生位置Y';
  ITEM_COLOR = '湯気の色';
  TARGET_EFFECT = '湯気演出:0';
  VERTEX_SHADER: AnsiString =
    'float4 VertexMain(uint id : SV_VertexID) : SV_Position {' +
    '  return float4(id == 1 ? 3 : -1, id == 2 ? -3 : 1, 0, 1); }';

var
  Table: PFILTER_PLUGIN_TABLE;
  Video: TFILTER_PROC_VIDEO;
  Scene: TSCENE_INFO;
  Obj: TOBJECT_INFO;
  Edit: TEDIT_SECTION;
  ImageParam: TOBJECT_IMAGE_PARAM;
  HostPixels: TPixels;
  ImageDirectory: string;
  PixelWrites, GPUCalls, TrackReads, EditWrites, TimelineMode: Integer;
  OldText: UTF8String;
  FailingItem: string;
  ForceGPUFailure: Boolean;
  Device: ID3D11Device;
  DeviceContext: ID3D11DeviceContext;
  VertexShader: ID3D11VertexShader;
  DriverName: string;

procedure Check(Condition: Boolean; const Detail: string);
begin
  if not Condition then
    raise Exception.Create(Detail);
end;

procedure CheckHR(Code: HRESULT; const Detail: string);
begin
  Check(Succeeded(Code), Detail + ' (0x' + IntToHex(Cardinal(Code), 8) + ')');
end;

function IsBaseSetting(const Name: string): Boolean;
begin
  Result := (Name = 'X') or (Name = 'Y') or (Name = 'Z') or
    (Name = '拡大率') or (Name = '透明度');
end;

function FindItem(const Name: string): Pointer;
var Item: PPointer;
begin
  Item := PPointer(Table^.Items);
  while Item^ <> nil do
  begin
    if Name = PFILTER_ITEM_TRACK(Item^)^.Name then Exit(Item^);
    Inc(Item);
  end;
  raise Exception.Create('Missing item ' + Name);
end;

function Track(const Name: string): PFILTER_ITEM_TRACK;
begin
  Result := FindItem(Name);
  Check(Result^.ItemType = 'track', 'Wrong track type for ' + Name);
end;

function SelectItem(const Name: string): PFILTER_ITEM_SELECT;
begin
  Result := FindItem(Name);
  Check(Result^.ItemType = 'select', 'Wrong select type for ' + Name);
end;

function GetItemValue(Handle: OBJECT_HANDLE; Effect, Name: PWideChar): PAnsiChar; cdecl;
var
  Item: PFILTER_ITEM_TRACK;
  Choice: PFILTER_ITEM_SELECT;
  Option: PSelectOption;
  Color: PFILTER_ITEM_COLOR;
begin
  Check((Handle = Obj.Handle) and (string(Effect) = TARGET_EFFECT), 'Wrong preset read target');
  Item := FindItem(Name);
  Result := nil;
  if Item^.ItemType = 'track' then
    OldText := UTF8String(FloatToStr(Item^.Value, TFormatSettings.Invariant))
  else if Item^.ItemType = 'select' then
  begin
    Choice := Pointer(Item);
    Option := PSelectOption(Choice^.List);
    while (Option^.Name <> nil) and (Option^.Value <> Choice^.Value) do Inc(Option);
    if Option^.Name = nil then Exit;
    OldText := UTF8String(Option^.Name);
  end
  else if Item^.ItemType = 'color' then
  begin
    Color := Pointer(Item);
    OldText := UTF8String(IntToHex((Cardinal(Color^.R) shl 16) or
      (Cardinal(Color^.G) shl 8) or Color^.B, 6));
  end
  else Exit;
  Result := PAnsiChar(OldText);
end;

function SetItemValue(Handle: OBJECT_HANDLE; Effect, Name: PWideChar;
  Value: PAnsiChar): Boolean; cdecl;
var
  Item: PFILTER_ITEM_TRACK;
  Option: PSelectOption;
  Color: PFILTER_ITEM_COLOR;
  Text: string;
  RGB: Integer;
begin
  Check((Handle = Obj.Handle) and (string(Effect) = TARGET_EFFECT), 'Wrong preset write target');
  Check(not IsBaseSetting(Name), 'Preset touched a base object setting');
  if string(Name) = FailingItem then Exit(False);
  Item := FindItem(Name);
  Text := string(UTF8String(Value));
  if Item^.ItemType = 'track' then
  begin
    Item^.Value := StrToFloat(Text, TFormatSettings.Invariant);
    Check((Item^.Value >= Item^.S) and (Item^.Value <= Item^.E), 'Preset value out of range');
  end
  else if Item^.ItemType = 'select' then
  begin
    Option := PSelectOption(PFILTER_ITEM_SELECT(Item)^.List);
    while (Option^.Name <> nil) and (Text <> string(Option^.Name)) do Inc(Option);
    Check(Option^.Name <> nil, 'Unknown preset selector value');
    PFILTER_ITEM_SELECT(Item)^.Value := Option^.Value;
  end
  else if Item^.ItemType = 'color' then
  begin
    Color := Pointer(Item);
    RGB := StrToInt('$' + Text);
    Color^.R := (RGB shr 16) and 255;
    Color^.G := (RGB shr 8) and 255;
    Color^.B := RGB and 255;
  end
  else Exit(False);
  Inc(EditWrites);
  Result := True;
end;

function TimelineValue(Effect: EFFECT_HANDLE; Name: PWideChar;
  Frame: Double; Value: PDouble): Boolean; cdecl;
var T: Double;
begin
  Check(Effect = Obj.EffectHandle, 'Wrong timeline handle');
  Check(string(Name) = ITEM_AMOUNT, 'Wrong timeline track');
  Check((Frame >= START_FRAME) and (Frame <= Obj.FrameE), 'Wrong timeline frame');
  Inc(TrackReads);
  T := (Frame - START_FRAME) / Scene.Rate;
  case TimelineMode of
    1: if T < 1.5 then Value^ := 100 else Value^ := 0;
    2: if (T >= 3) and (T < 3.5) then Value^ := 100 else Value^ := 0;
    else Value^ := Track(ITEM_AMOUNT)^.Value;
  end;
  Result := True;
end;

procedure SetPixels(Buffer: PPIXEL_RGBA; Width, Height: Integer); cdecl;
begin
  Check((Width = Scene.Width) and (Height = Scene.Height), 'Output is not scene-sized');
  if Buffer = nil then Exit;
  Inc(PixelWrites);
  SetLength(HostPixels, Width * Height);
  Move(Buffer^, HostPixels[0], Length(HostPixels) * SizeOf(TPIXEL_RGBA));
end;

procedure InitializeD3D;
var Feature: D3D_FEATURE_LEVEL; Code, Errors: ID3DBlob;
begin
  DriverName := 'hardware';
  if Failed(D3D11CreateDevice(nil, D3D_DRIVER_TYPE_HARDWARE, 0, 0, nil, 0,
    D3D11_SDK_VERSION, Device, Feature, DeviceContext)) then
  begin
    DriverName := 'WARP';
    CheckHR(D3D11CreateDevice(nil, D3D_DRIVER_TYPE_WARP, 0, 0, nil, 0,
      D3D11_SDK_VERSION, Device, Feature, DeviceContext), 'D3D11 device creation');
  end;
  CheckHR(D3DCompile(PAnsiChar(VERTEX_SHADER), Length(VERTEX_SHADER), nil, nil, nil,
    'VertexMain', 'vs_5_0', 0, 0, Code, Errors), 'Test vertex shader compilation');
  CheckHR(Device.CreateVertexShader(Code.GetBufferPointer, Code.GetBufferSize, nil,
    @VertexShader), 'Test vertex shader creation');
end;

function ExecShader(Data: Pointer; DataSize: Integer; Target: PWideChar; Resources: Pointer;
  ResourceCount: Integer; Constants: Pointer; ConstantSize: Integer;
  BlendState, SamplerState: Pointer): Boolean; cdecl;
var
  Shader: ID3D11PixelShader;
  Output, Readback: ID3D11Texture2D;
  View: ID3D11RenderTargetView;
  Buffer: ID3D11Buffer;
  Desc: TD3D11_TEXTURE2D_DESC;
  BufferDesc: TD3D11_BUFFER_DESC;
  Initial: TD3D11_SUBRESOURCE_DATA;
  Viewport: TD3D11_VIEWPORT;
  Mapped: D3D11_MAPPED_SUBRESOURCE;
  Y: Integer;
begin
  Inc(GPUCalls);
  if ForceGPUFailure then Exit(False);
  Check((Target = nil) and (Resources = nil) and (ResourceCount = 0) and
    (BlendState = nil) and (SamplerState = nil), 'Wrong SDK shader arguments');
  Check((ConstantSize = 48 + 96 * 64) and (DataSize > 0), 'Wrong shader data sizes');
  CheckHR(Device.CreatePixelShader(Data, DataSize, nil, Shader), 'Production pixel shader creation');

  Desc := Default(TD3D11_TEXTURE2D_DESC);
  Desc.Width := Scene.Width;
  Desc.Height := Scene.Height;
  Desc.MipLevels := 1;
  Desc.ArraySize := 1;
  Desc.Format := DXGI_FORMAT_R8G8B8A8_UNORM;
  Desc.SampleDesc.Count := 1;
  Desc.BindFlags := D3D11_BIND_RENDER_TARGET;
  CheckHR(Device.CreateTexture2D(Desc, nil, Output), 'Render target creation');
  CheckHR(Device.CreateRenderTargetView(Output, nil, View), 'Render target view');
  Desc.BindFlags := 0;
  Desc.Usage := D3D11_USAGE_STAGING;
  Desc.CPUAccessFlags := D3D11_CPU_ACCESS_READ;
  CheckHR(Device.CreateTexture2D(Desc, nil, Readback), 'Readback target creation');

  BufferDesc := Default(TD3D11_BUFFER_DESC);
  BufferDesc.ByteWidth := ConstantSize;
  BufferDesc.BindFlags := D3D11_BIND_CONSTANT_BUFFER;
  Initial := Default(TD3D11_SUBRESOURCE_DATA);
  Initial.pSysMem := Constants;
  CheckHR(Device.CreateBuffer(BufferDesc, @Initial, Buffer), 'Constant buffer creation');
  Viewport := Default(TD3D11_VIEWPORT);
  Viewport.Width := Scene.Width;
  Viewport.Height := Scene.Height;
  Viewport.MaxDepth := 1;
  DeviceContext.RSSetViewports(1, @Viewport);
  DeviceContext.IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
  DeviceContext.OMSetRenderTargets(1, View, nil);
  DeviceContext.VSSetShader(VertexShader, nil, 0);
  DeviceContext.PSSetShader(Shader, nil, 0);
  DeviceContext.PSSetConstantBuffers(0, 1, Buffer);
  DeviceContext.Draw(3, 0);
  DeviceContext.OMSetRenderTargets(0, nil, nil);
  DeviceContext.CopyResource(Readback, Output);

  CheckHR(DeviceContext.Map(Readback, 0, D3D11_MAP_READ, 0, Mapped), 'D3D11 pixel readback');
  try
    SetLength(HostPixels, Scene.Width * Scene.Height);
    for Y := 0 to Scene.Height - 1 do
      Move((PByte(Mapped.pData) + NativeUInt(Y) * Mapped.RowPitch)^,
        HostPixels[Y * Scene.Width], Scene.Width * SizeOf(TPIXEL_RGBA));
  finally
    DeviceContext.Unmap(Readback, 0);
  end;
  Result := True;
end;

function Render(Seconds: Double): TPixels;
begin
  Obj.Time := Seconds;
  Obj.Frame := Round(Seconds * Scene.Rate);
  HostPixels := nil;
  Check(Table^.Func_Proc_Video(@Video) = 1, Format('Render failed at %.3fs', [Seconds]));
  Check(Length(HostPixels) = Scene.Width * Scene.Height, 'No complete image');
  Result := HostPixels;
end;

function BoundsOf(const Pixels: TPixels): TBounds;
var I, X, Y: Integer; A: Byte;
begin
  Result := Default(TBounds);
  Result.Left := Scene.Width;
  Result.Top := Scene.Height;
  for I := 0 to High(Pixels) do
  begin
    A := Pixels[I].A;
    if A = 0 then Continue;
    Inc(Result.Alpha, A);
    Result.Peak := Max(Result.Peak, A);
    if A < 3 then Continue;
    X := I mod Scene.Width;
    Y := I div Scene.Width;
    Result.Left := Min(Result.Left, X);
    Result.Right := Max(Result.Right, X);
    Result.Top := Min(Result.Top, Y);
    Result.Bottom := Max(Result.Bottom, Y);
  end;
end;

function Same(const A, B: TPixels): Boolean;
begin
  Result := (Length(A) = Length(B)) and CompareMem(@A[0], @B[0],
    Length(A) * SizeOf(TPIXEL_RGBA));
end;

procedure SavePNG(const Pixels: TPixels; const Name: string);
var PNG: TPngImage; X, Y, I: Integer; Row: PByte;
begin
  PNG := TPngImage.CreateBlank(COLOR_RGBALPHA, 8, Scene.Width, Scene.Height);
  try
    for Y := 0 to Scene.Height - 1 do
    begin
      Row := PNG.Scanline[Y];
      for X := 0 to Scene.Width - 1 do
      begin
        I := Y * Scene.Width + X;
        Row[X * 3] := Pixels[I].B;
        Row[X * 3 + 1] := Pixels[I].G;
        Row[X * 3 + 2] := Pixels[I].R;
        PNG.AlphaScanline[Y]^[X] := Pixels[I].A;
      end;
    end;
    PNG.SaveToFile(IncludeTrailingPathDelimiter(ImageDirectory) + Name + '.png');
  finally
    PNG.Free;
  end;
end;

procedure Apply(Index: Integer);
begin
  SelectItem(SELECT_PRESET)^.Value := Index;
  PFILTER_ITEM_BUTTON(FindItem('設定'))^.Callback2(@Edit, Obj.Handle, TARGET_EFFECT, '設定');
end;

procedure TestPresets;
var
  A, B: TPixels;
  ExpectedParam: TOBJECT_IMAGE_PARAM;
  I, J, Writes: Integer;
  T: Double;
  Extent: TBounds;
  Option: PSelectOption;
  Hash: THashSHA2;
  Digests: array[0..PRESET_COUNT - 1] of string;
begin
  Check(Track(ITEM_AMOUNT)^.S = 0, 'Wrong emission minimum');
  Check(Track(ITEM_AMOUNT)^.E = 150, 'Wrong emission maximum');
  Check(Abs(Track(ITEM_AMOUNT)^.Step - 0.01) < 0.00001, 'Wrong emission unit');
  A := Render(0);
  Extent := BoundsOf(A);
  SavePNG(A, 'placement_default');
  Check((Extent.Peak >= 10) and (Extent.Peak < 150),
    Format('Default steam density at placement (peak=%d, alpha=%d)', [Extent.Peak, Extent.Alpha]));
  Check((Extent.Top < Scene.Height div 2 - 45) and (Extent.Bottom < Scene.Height div 2 + 65),
    'Default steam does not rise from the image center');
  SelectItem(SELECT_PRESET)^.Value := 9;
  Check(Same(A, Render(0)), 'Choosing a preset changed the appearance');

  ImageParam.X := 47;
  ImageParam.Y := 36;
  ImageParam.Z := -18;
  ImageParam.SX := 1.14;
  ImageParam.SY := 1.14;
  ImageParam.SZ := 1.14;
  ImageParam.Alpha := 0.95;
  ExpectedParam := ImageParam;
  Check(Same(A, Render(0)), 'Host image parameters were applied inside the texture');
  Track(ITEM_ORIGIN_X)^.Value := -61;
  Track(ITEM_ORIGIN_Y)^.Value := 47;
  Writes := EditWrites;
  Apply(9);
  Check(EditWrites - Writes = 58, 'Wrong number of preset values applied');
  Check((Track(ITEM_ORIGIN_X)^.Value = -61) and (Track(ITEM_ORIGIN_Y)^.Value = 47),
    'Preset changed the source position');
  Track(ITEM_ORIGIN_X)^.Value := 0;
  Track(ITEM_ORIGIN_Y)^.Value := 0;
  B := Render(0.4);
  Check(CompareMem(@ImageParam, @ExpectedParam, SizeOf(ImageParam)),
    'Preset or render changed the host image parameters');
  FailingItem := '風速';
  Apply(11);
  FailingItem := '';
  Check(Same(B, Render(0.4)), 'Failed preset left partial changes');

  Option := PSelectOption(SelectItem(SELECT_PRESET)^.List);
  for I := 0 to PRESET_COUNT - 1 do
  begin
    Check((Option^.Name <> nil) and (Option^.Value = I), 'Preset missing from list');
    Inc(Option);
    Apply(I);
    if I in [17, 18, 20] then
      T := 0.65
    else
      T := 0.38;
    repeat
      A := Render(T);
      Extent := BoundsOf(A);
      if Extent.Peak >= 9 then Break;
      T := T + 0.18;
    until T > 8;
    Check(Extent.Peak >= 9, Format('No visible emission for preset %d', [I]));
    SavePNG(A, Format('preset_%.2d', [I]));
    Hash := THashSHA2.Create;
    Hash.Update(A[0], Length(A) * SizeOf(TPIXEL_RGBA));
    Digests[I] := Hash.HashAsString;
    for J := 0 to I - 1 do
      Check(Digests[I] <> Digests[J], 'Duplicate preset appearance');
  end;
  Check(Option^.Name = nil, 'Preset list is missing its sentinel');
  Writeln('PASS 32 distinct presets, defaults, selection, host placement, edit rollback');
end;

procedure TestSourcePosition;
var
  X, Y: PFILTER_ITEM_TRACK;
  Centered, Shifted: TBounds;
begin
  X := Track(ITEM_ORIGIN_X);
  Y := Track(ITEM_ORIGIN_Y);
  Check((X^.S = -8192) and (X^.E = 8192) and (X^.Step = 1) and
    (Y^.S = -8192) and (Y^.E = 8192) and (Y^.Step = 1), 'Wrong source coordinate range or unit');
  Check((X^.Value = 0) and (Y^.Value = 0), 'Wrong initial source position');
  Centered := BoundsOf(Render(0));
  Check(Centered.Peak >= 10, 'No visible steam at the center');
  X^.Value := -61;
  Y^.Value := 47;
  Shifted := BoundsOf(Render(0));
  Check((Abs(Shifted.Left - (Centered.Left - 61)) <= 1) and
    (Abs(Shifted.Right - (Centered.Right - 61)) <= 1) and
    (Abs(Shifted.Top - (Centered.Top + 47)) <= 1) and
    (Abs(Shifted.Bottom - (Centered.Bottom + 47)) <= 1),
    'Steam did not move by the specified offset');
  X^.Value := X^.E;
  Check(BoundsOf(Render(0)).Alpha = 0, 'Off-screen steam was not clipped');
  X^.Value := 0;
  Y^.Value := 0;
  Writeln('PASS relative source X/Y, default, and off-screen clipping');
end;

procedure TestTimeline;
var A, B: TPixels; Start, Residue, Strong: TBounds;
begin
  Apply(0);
  A := Render(1.18);
  Check(not Same(A, Render(1.4)), 'Steam does not move');
  Check(Same(A, Render(1.18)), 'Reverse seek changed the pixels');

  TimelineMode := 1;
  Track(ITEM_AMOUNT)^.Value := 0;
  Start := BoundsOf(Render(1.51));
  A := Render(2.4);
  Residue := BoundsOf(A);
  Check((Residue.Alpha > 0) and (Residue.Alpha < Start.Alpha),
    'Existing steam did not gradually disappear after the emission stopped');
  Check(BoundsOf(Render(6)).Alpha = 0, 'New steam after the emission stopped');
  B := Render(2.4);
  Check(Same(A, B), 'Animated emission depends on frame order');
  Check(TrackReads > 0, 'The host timeline was not consulted');
  TimelineMode := 0;
  Track(ITEM_AMOUNT)^.Value := 25;
  Residue := BoundsOf(Render(1.18));
  Track(ITEM_AMOUNT)^.Value := 150;
  Strong := BoundsOf(Render(1.18));
  Check((Residue.Alpha > 0) and (Residue.Alpha * 2 < Strong.Alpha),
    'Emission changes do not vary the density sufficiently');

  Apply(10);
  TimelineMode := 2;
  Check(BoundsOf(Render(2.8)).Alpha = 0, 'One-shot emitted before the animated trigger');
  Check(BoundsOf(Render(3.36)).Alpha > 0, 'One-shot did not react to rising emission');
  Check(BoundsOf(Render(7)).Alpha = 0, 'One-shot emitted twice for a single rise');
  TimelineMode := 0;
  Apply(17);
  Check(BoundsOf(Render(0)).Alpha = 0, 'Breath before its start');
  Check(BoundsOf(Render(0.68)).Alpha > 0, 'Breath did not appear');
  Check(BoundsOf(Render(2.9)).Alpha = 0, 'Breath did not leave a gap between pulses');
  Writeln('PASS motion, reverse seek, stopping, burst, breath');
end;

procedure TestGPU;
var
  CPU, GPU: TPixels;
  CPUStats, GPUStats: TBounds;
  I, OldWrites: Integer;
begin
  Apply(0);
  Track(ITEM_ORIGIN_X)^.Value := 72;
  Track(ITEM_ORIGIN_Y)^.Value := -28;
  CPU := Render(1.32);
  CPUStats := BoundsOf(CPU);
  InitializeD3D;
  Video.ExecPixelshaderData := ExecShader;
  OldWrites := PixelWrites;
  GPU := Render(1.32);
  GPUStats := BoundsOf(GPU);
  Check((GPUCalls = 1) and (PixelWrites = OldWrites), 'Production GPU path was bypassed');
  Check(Abs(GPUStats.Alpha - CPUStats.Alpha) < CPUStats.Alpha * 0.015, Format('CPU/GPU alpha mismatch (%d vs %d)', [CPUStats.Alpha, GPUStats.Alpha]));
  for I := 0 to High(GPU) do
  begin
    Check(Abs(Integer(GPU[I].A) - CPU[I].A) <= 1, 'CPU/GPU alpha differs at a pixel');
    Check(GPU[I].R <= GPU[I].A, 'GPU RGB must be premultiplied');
    Check(Abs(Integer(GPU[I].R) - Round(CPU[I].R * CPU[I].A / 255.0)) <= 2,
      'CPU/GPU premultiplied luminance differs at a pixel');
  end;
  ForceGPUFailure := True;
  Check(Same(CPU, Render(1.32)), 'Shader failure did not reproduce the CPU path');
  ForceGPUFailure := False;
  Track(ITEM_ORIGIN_X)^.Value := 0;
  Track(ITEM_ORIGIN_Y)^.Value := 0;
  Track(ITEM_AMOUNT)^.Value := 0;
  Check(BoundsOf(Render(1.32)).Alpha = 0, 'GPU did not clear an empty frame');
  Scene.Width := 1920;
  Scene.Height := 1080;
  Apply(11);
  Check(BoundsOf(Render(1.32)).Alpha > 0, 'D3D11 failed to render full-HD mist');
  Video.ExecPixelshaderData := nil;
  Writeln('PASS D3D11 ', DriverName, ', CPU/GPU pixel parity and fallback');
end;

procedure Run(const Plugin: string);
var
  LibraryHandle: HMODULE;
  Required: TRequiredVersion;
  Initialize: TInitializePlugin;
  Uninitialize: TUninitializePlugin;
  GetTable: TGetTable;
  Item: PPointer;
  ItemCount: Integer;
  ItemName: string;
begin
  LibraryHandle := LoadLibrary(PWideChar(Plugin));
  Check(LibraryHandle <> 0, 'Could not load production AUF2');
  try
    @Required := GetProcAddress(LibraryHandle, 'RequiredVersion');
    @Initialize := GetProcAddress(LibraryHandle, 'InitializePlugin');
    @Uninitialize := GetProcAddress(LibraryHandle, 'UninitializePlugin');
    @GetTable := GetProcAddress(LibraryHandle, 'GetFilterPluginTable');
    Check(Assigned(Required) and Assigned(Initialize) and Assigned(Uninitialize) and
      Assigned(GetTable), 'Missing SDK export');
    Check(Required() = 2011600, 'Wrong required host version');
    Check((Initialize(Required() - 1) = 0) and (Initialize(Required()) = 1), 'Wrong host gate');
    Table := GetTable();
    Check((Table <> nil) and (string(Table^.Name) = '湯気演出') and
      (string(Table^.Label_) = 'SYNC'), 'Wrong plugin registration');
    Check(string(Table^.Information) = '湯気演出 / SYNC_SteamFX v1.0.0', 'Wrong release version');
    Check(Table^.Flag = (FILTER_FLAG_VIDEO or FILTER_FLAG_INPUT or FILTER_FLAG_USERDATA),
      'SteamFX must be a standalone media object');
    Item := PPointer(Table^.Items);
    ItemCount := 0;
    while Item^ <> nil do
    begin
      Inc(ItemCount);
      Check(ItemCount < 128, 'Unterminated item table');
      ItemName := PFILTER_ITEM_TRACK(Item^)^.Name;
      Check(not IsBaseSetting(ItemName) and (ItemName <> '基本設定'),
        'Duplicate base object setting: ' + ItemName);
      Inc(Item);
    end;
    Check(ItemCount = 96, 'Unexpected number of registered settings');
    Check((NativeUInt(@Obj.EffectHandle) - NativeUInt(@Obj) = 112) and
      (NativeUInt(@@Edit.GetEffectTrackValue) - NativeUInt(@Edit) = 472) and
      (NativeUInt(@@Video.ExecPixelshaderData) - NativeUInt(@Video) = 224) and
      (NativeUInt(@Video.UserData) - NativeUInt(@Video) = 280), 'SDK offsets differ');

    Scene.Width := 640;
    Scene.Height := 480;
    Scene.Rate := 30;
    Scene.Scale := 1;
    Obj.FrameS := START_FRAME;
    Obj.FrameE := START_FRAME + 360;
    Obj.Width := 48;
    Obj.Height := 48;
    Obj.Handle := @Obj;
    Obj.EffectHandle := Table;
    Edit.GetObjectItemValue := GetItemValue;
    Edit.SetObjectItemValue := SetItemValue;
    Edit.GetEffectTrackValue := TimelineValue;
    Video.Scene := @Scene;
    Video.Object_ := @Obj;
    Video.Edit := @Edit;
    Video.Param := @ImageParam;
    Video.SetImageData := SetPixels;
    Video.UserData := Table^.Func_Create(1);
    Check(Video.UserData <> nil, 'Session creation failed');
    try
      TestSourcePosition;
      TestPresets;
      TestTimeline;
      TestGPU;
      Scene.Width := 0;
      Check(Table^.Func_Proc_Video(@Video) = 0, 'Invalid scene size was accepted');
    finally
      Table^.Func_Destroy(1, Video.UserData);
      Uninitialize();
    end;
  finally
    FreeLibrary(LibraryHandle);
  end;
end;

begin
  try
    Check(ParamCount = 2, 'Usage: SteamFX_RenderTests <plugin> <images>');
    ImageDirectory := ParamStr(2);
    ForceDirectories(ImageDirectory);
    Run(ParamStr(1));
  except
    on E: Exception do
    begin
      Writeln(E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
