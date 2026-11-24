unit SYNC_SteamFX_FilterPlugin;

// Copyright (c) 2026 VRAMの魔術師
// SPDX-License-Identifier: GPL-3.0-only
// SYNC のメディアオブジェクトとして湯気を登録し、ホスト画像と時間軸を扱う。

interface

uses AviUtl2FilterTypes;

const
  STEAMFX_REQUIRED_VERSION = 2011600;

// DLL が所有する登録情報。呼出側では解放しない。
function GetSteamFXFilterTable: PFILTER_PLUGIN_TABLE;

implementation

uses
  System.SysUtils, System.Math, System.SyncObjs, Winapi.Windows,
  PluginFilterTable, SteamFX_Settings, SteamFX_Parameters, SteamFX_Field,
  SteamFX_GPU, SteamFX_Raster;

const
  MAX_SCENE_EDGE = 8192;
  MAX_SCENE_PIXELS = 33554432;

type
  TAmountContext = record
    ReadTrack: TGetEffectTrackValueFunc;
    Effect: EFFECT_HANDLE;
    FirstFrame, LastFrame, FPS, CurrentValue: Double;
  end;
  PAmountContext = ^TAmountContext;

  TSteamSession = class
  private
    FLock: TCriticalSection;
    FPixels: TSteamPixels;
  public
    constructor Create;
    destructor Destroy; override;
    // Video とその参照は呼出中だけ借用する。CPU バッファはインスタンス所有。
    function Render(Video: PFILTER_PROC_VIDEO): Byte;
  end;

var
  TableLock: TCriticalSection;
  TableInitialized: Boolean;

function ReadTimelineAmount(Context: Pointer; Time: Double): Double;
var History: PAmountContext; Frame, Value: Double;
begin
  History := PAmountContext(Context);
  Frame := EnsureRange(History^.FirstFrame + Time * History^.FPS,
    History^.FirstFrame, History^.LastFrame);
  if History^.ReadTrack(History^.Effect, STEAM_TRACKS[trAmount].Name, Frame, @Value) then
    Result := Value
  else
    Result := History^.CurrentValue;
end;

constructor TSteamSession.Create;
begin
  inherited;
  FLock := TCriticalSection.Create;
end;

destructor TSteamSession.Destroy;
begin
  FLock.Free;
  inherited;
end;

function TSteamSession.Render(Video: PFILTER_PROC_VIDEO): Byte;
var
  Width, Height: Integer;
  S: TSteamSettings;
  Frame: TSteamFrame;
  History: TAmountContext;
  Sampler: TSteamAmountSampler;
begin
  Result := 0;
  if (Video^.Scene = nil) or not Assigned(Video^.SetImageData) then Exit;
  Width := Video^.Scene^.Width;
  Height := Video^.Scene^.Height;
  if (Width <= 0) or (Height <= 0) or (Width > MAX_SCENE_EDGE) or
    (Height > MAX_SCENE_EDGE) or (Int64(Width) * Height > MAX_SCENE_PIXELS) then Exit;

  S := ReadSteamSettings;
  Sampler := nil;
  if (Video^.Edit <> nil) and Assigned(Video^.Edit^.GetEffectTrackValue) and
    (Video^.Object_^.EffectHandle <> nil) and (Video^.Scene^.Rate > 0) and
    (Video^.Scene^.Scale > 0) and (Video^.Object_^.FrameE >= Video^.Object_^.FrameS) then
  begin
    History.ReadTrack := Video^.Edit^.GetEffectTrackValue;
    History.Effect := Video^.Object_^.EffectHandle;
    History.FirstFrame := Video^.Object_^.FrameS;
    History.LastFrame := Video^.Object_^.FrameE;
    History.FPS := Video^.Scene^.Rate / Video^.Scene^.Scale;
    History.CurrentValue := S.Value[trAmount];
    Sampler := ReadTimelineAmount;
  end;
  // 中央を原点に画像を生成し、配置と全体透明度はホストの標準描画に任せる。
  BuildSteamFrame(S, Width, Height, Video^.Object_^.Time, Sampler, @History, Frame);
  if not TryRenderSteamGPU(Video, Width, Height, Frame) then
  begin
    FLock.Acquire;
    try
      RasterSteam(Frame, Width, Height, FPixels);
      Video^.SetImageData(@FPixels[0], Width, Height);
    finally
      FLock.Release;
    end;
  end;
  Result := 1;
end;

function SteamProcVideo(Video: PFILTER_PROC_VIDEO): Byte; cdecl;
begin
  Result := 0;
  if (Video = nil) or (Video^.Object_ = nil) or (Video^.UserData = nil) then Exit;
  try
    Result := TSteamSession(Video^.UserData).Render(Video);
  except
    on E: Exception do
      OutputDebugString(PWideChar('SYNC_SteamFX render: ' + E.Message));
  end;
end;

function SteamCreate(EffectID: Int64): Pointer; cdecl;
begin
  Result := nil;
  try
    Result := TSteamSession.Create;
  except
    // 生成に失敗した場合はホストへ nil を返す。
  end;
end;

procedure SteamDestroy(EffectID: Int64; UserData: Pointer); cdecl;
begin
  try
    TSteamSession(UserData).Free;
  except
    // DLL のコールバック境界で例外を捕捉する。
  end;
end;

function GetSteamFXFilterTable: PFILTER_PLUGIN_TABLE;
begin
  TableLock.Acquire;
  try
    if not TableInitialized then
    begin
      SetupPluginTable(FILTER_FLAG_VIDEO or FILTER_FLAG_INPUT or FILTER_FLAG_USERDATA,
        '湯気演出', 'SYNC', '湯気演出 / SYNC_SteamFX v1.0.0', SteamProcVideo, nil);
      RegisterSteamParameters;
      GetPluginTable^.Func_Create := SteamCreate;
      GetPluginTable^.Func_Destroy := SteamDestroy;
      TableInitialized := True;
    end;
    Result := GetPluginTable;
  finally
    TableLock.Release;
  end;
end;

initialization
  TableLock := TCriticalSection.Create;
finalization
  TableLock.Free;
end.
