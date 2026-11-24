unit SteamFX_Parameters;

// Copyright (c) 2026 VRAMの魔術師
// SPDX-License-Identifier: GPL-3.0-only
// 設定項目の登録、コールバック時のスナップショットとプリセットの編集を担当する。

interface

uses SteamFX_Settings;

procedure RegisterSteamParameters;
// ホストが描画コールバックに設定した値をコピーする。現在の編集中の値は変更しない。
function ReadSteamSettings: TSteamSettings;

implementation

uses
  System.Math, System.SysUtils, Winapi.Windows,
  AviUtl2FilterTypes, PluginFilterTable, SteamFX_Presets;

type
  TSteamGroup = (sgPreset, sgStyle, sgAmount, sgSource, sgSpace,
    sgShape, sgMotion, sgJet, sgRelease, sgWind, sgColor, sgLife);

const
  GROUP_NAMES: array[TSteamGroup] of PWideChar = (
    'プリセット', 'スタイル', '湯気の発生量', '発生源配置', '疑似立体',
    '湯気形状', '移動・拡散', '蒸気噴射', '間欠放出', '風', '色彩・透明度', '寿命・消失');
  STYLE_NAME = '湯気のスタイル';
  SOURCE_NAME = '発生源の配置';
  CIRCLE_NAME = '円形の発生位置';
  RELEASE_NAME = '発生方式';
  COLOR_NAME = '湯気の色';
  HIDE_EQUAL = 0;
  HIDE_NOT_EQUAL = 1;
  HIDE_LESS = 3;

var
  Tracks: array[TSteamTrack] of TFILTER_ITEM_TRACK;
  Groups, GroupEnds: array[TSteamGroup] of TFILTER_ITEM_GROUP;
  PresetSelect, StyleSelect, SourceSelect, CircleSelect, ReleaseSelect: TFILTER_ITEM_SELECT;
  PresetOptions: array[0..Ord(High(TSteamPreset)) + 1] of TFILTER_ITEM_SELECT_ITEM;
  StyleOptions: array[0..Ord(High(TSteamStyle)) + 1] of TFILTER_ITEM_SELECT_ITEM;
  SourceOptions: array[0..Ord(High(TSteamSource)) + 1] of TFILTER_ITEM_SELECT_ITEM;
  CircleOptions: array[0..Ord(High(TSteamCircle)) + 1] of TFILTER_ITEM_SELECT_ITEM;
  ReleaseOptions: array[0..Ord(High(TSteamRelease)) + 1] of TFILTER_ITEM_SELECT_ITEM;
  PresetButton: TFILTER_ITEM_BUTTON;
  ColorItem: TFILTER_ITEM_COLOR;
  HideRules: array[0..9] of TFILTER_ITEM_HIDE_RULE;

procedure ApplyPreset(Edit: PEDIT_SECTION; Obj: OBJECT_HANDLE; Effect, Item: PWideChar); cdecl;
type
  TChange = record
    Name: PWideChar;
    Before, After: UTF8String;
  end;
var
  S: TSteamSettings;
  Track: TSteamTrack;
  Changes: array[0..Ord(High(TSteamTrack)) + 5] of TChange;
  Count, Applied: Integer;
  Target: string;

  procedure Plan(Name: PWideChar; const Value: UTF8String);
  var Previous: PAnsiChar;
  begin
    Previous := Edit^.GetObjectItemValue(Obj, PWideChar(Target), Name);
    if Previous = nil then
      raise EInvalidOp.CreateFmt('Could not read preset item %s', [string(Name)]);
    Changes[Count].Name := Name;
    Changes[Count].Before := UTF8String(Previous);
    Changes[Count].After := Value;
    Inc(Count);
  end;

begin
  if (Edit = nil) or (Obj = nil) or (Effect = nil) then Exit;
  if not Assigned(Edit^.SetObjectItemValue) or not Assigned(Edit^.GetObjectItemValue) then Exit;
  Count := 0;
  Applied := 0;
  try
    Target := Effect;
    S := SteamPreset(TSteamPreset(EnsureRange(PresetSelect.Value, 0, Ord(High(TSteamPreset)))));
    Plan(STYLE_NAME, UTF8String(STEAM_STYLE_NAMES[S.Style]));
    Plan(SOURCE_NAME, UTF8String(STEAM_SOURCE_NAMES[S.Source]));
    Plan(CIRCLE_NAME, UTF8String(STEAM_CIRCLE_NAMES[S.Circle]));
    Plan(RELEASE_NAME, UTF8String(STEAM_RELEASE_NAMES[S.Release]));
    Plan(COLOR_NAME, UTF8String(IntToHex(S.Color, 6)));
    for Track := Low(TSteamTrack) to High(TSteamTrack) do
      Plan(STEAM_TRACKS[Track].Name,
        UTF8String(FloatToStr(S.Value[Track], TFormatSettings.Invariant)));
    while Applied < Count do
    begin
      if not Edit^.SetObjectItemValue(Obj, PWideChar(Target), Changes[Applied].Name,
        PAnsiChar(Changes[Applied].After)) then
        raise EInvalidOp.CreateFmt('Could not apply preset item %s', [string(Changes[Applied].Name)]);
      Inc(Applied);
    end;
  except
    on E: Exception do
    begin
      while Applied > 0 do
      begin
        Dec(Applied);
        if not Edit^.SetObjectItemValue(Obj, PWideChar(Target), Changes[Applied].Name,
          PAnsiChar(Changes[Applied].Before)) then
          OutputDebugString('SYNC_SteamFX: preset rollback failed');
      end;
      OutputDebugString(PWideChar('SYNC_SteamFX preset: ' + E.Message));
    end;
  end;
end;

procedure FillOptions(const Names: array of PWideChar;
  var Options: array of TFILTER_ITEM_SELECT_ITEM);
var I: Integer;
begin
  for I := 0 to High(Names) do
  begin
    Options[I].Name := Names[I];
    Options[I].Value := I;
  end;
  Options[High(Options)] := Default(TFILTER_ITEM_SELECT_ITEM);
end;

procedure RegisterSteamParameters;
var
  Rule: Integer;
  S: TSteamSettings;

  procedure BeginGroup(Group: TSteamGroup; Expanded: Boolean = False);
  begin
    AddGroup(Groups[Group], GROUP_NAMES[Group], Ord(Expanded));
  end;

  procedure EndGroup(Group: TSteamGroup);
  begin
    AddGroup(GroupEnds[Group], '', 0);
  end;

  procedure AddTracks(First, Last: TSteamTrack);
  var Track: TSteamTrack;
  begin
    for Track := First to Last do
      AddTrack(Tracks[Track], STEAM_TRACKS[Track].Name, S.Value[Track],
        STEAM_TRACKS[Track].Min, STEAM_TRACKS[Track].Max, STEAM_TRACKS[Track].Step);
  end;

  procedure TrackGroup(Group: TSteamGroup; First, Last: TSteamTrack;
    Expanded: Boolean = False);
  begin
    BeginGroup(Group, Expanded);
    AddTracks(First, Last);
    EndGroup(Group);
  end;

  procedure Hide(Name, Condition: PWideChar; Comparison, Value: Integer);
  begin
    AddHideRule(HideRules[Rule], Name, Condition, Comparison, Value);
    Inc(Rule);
  end;

begin
  S := DefaultSteamSettings;
  FillOptions(STEAM_PRESET_NAMES, PresetOptions);
  FillOptions(STEAM_STYLE_NAMES, StyleOptions);
  FillOptions(STEAM_SOURCE_NAMES, SourceOptions);
  FillOptions(STEAM_CIRCLE_NAMES, CircleOptions);
  FillOptions(STEAM_RELEASE_NAMES, ReleaseOptions);

  BeginGroup(sgPreset, True);
  AddSelect(PresetSelect, '湯気プリセット', Ord(spFood), @PresetOptions[0]);
  AddButton(PresetButton, '設定', ApplyPreset);
  EndGroup(sgPreset);
  BeginGroup(sgStyle, True);
  AddSelect(StyleSelect, STYLE_NAME, Ord(S.Style), @StyleOptions[0]);
  EndGroup(sgStyle);
  TrackGroup(sgAmount, trAmount, trAmount, True);
  BeginGroup(sgSource);
  AddSelect(SourceSelect, SOURCE_NAME, Ord(S.Source), @SourceOptions[0]);
  AddSelect(CircleSelect, CIRCLE_NAME, Ord(S.Circle), @CircleOptions[0]);
  AddTracks(trSources, trSourceVariation);
  EndGroup(sgSource);
  TrackGroup(sgSpace, trTilt, trSpaceDepth);
  TrackGroup(sgShape, trThickness, trShapeVariation);
  TrackGroup(sgMotion, trRise, trHang);
  TrackGroup(sgJet, trJetDirection, trJetDrag);
  BeginGroup(sgRelease);
  AddSelect(ReleaseSelect, RELEASE_NAME, Ord(S.Release), @ReleaseOptions[0]);
  AddTracks(trReleaseTime, trPhase);
  EndGroup(sgRelease);
  TrackGroup(sgWind, trWindDirection, trWindChange);
  BeginGroup(sgColor);
  AddColor(ColorItem, COLOR_NAME, Byte(S.Color and 255),
    Byte((S.Color shr 8) and 255), Byte((S.Color shr 16) and 255));
  AddTracks(trConcentration, trSoftness);
  EndGroup(sgColor);
  TrackGroup(sgLife, trLife, trDiffusionFade);

  Rule := 0;
  Hide(GROUP_NAMES[sgJet], STYLE_NAME, HIDE_NOT_EQUAL, Ord(ssJet));
  Hide(CIRCLE_NAME, SOURCE_NAME, HIDE_NOT_EQUAL, Ord(scCircle));
  Hide(STEAM_TRACKS[trDiameter].Name, SOURCE_NAME, HIDE_NOT_EQUAL, Ord(scCircle));
  Hide(STEAM_TRACKS[trSources].Name, SOURCE_NAME, HIDE_EQUAL, Ord(scPoint));
  Hide(STEAM_TRACKS[trWidth].Name, SOURCE_NAME, HIDE_EQUAL, Ord(scPoint));
  Hide(STEAM_TRACKS[trWidth].Name, SOURCE_NAME, HIDE_EQUAL, Ord(scCircle));
  Hide(STEAM_TRACKS[trDepth].Name, SOURCE_NAME, HIDE_LESS, Ord(scRectangle));
  Hide(STEAM_TRACKS[trInterval].Name, RELEASE_NAME, HIDE_EQUAL, Ord(srOneShot));
  Hide(STEAM_TRACKS[trIntervalVar].Name, RELEASE_NAME, HIDE_EQUAL, Ord(srOneShot));
  Hide(STEAM_TRACKS[trReleaseTimeVar].Name, RELEASE_NAME, HIDE_EQUAL, Ord(srContinuous));
end;

function ReadSteamSettings: TSteamSettings;
var Track: TSteamTrack;
begin
  Result.Style := TSteamStyle(EnsureRange(StyleSelect.Value, 0, Ord(High(TSteamStyle))));
  Result.Source := TSteamSource(EnsureRange(SourceSelect.Value, 0, Ord(High(TSteamSource))));
  Result.Circle := TSteamCircle(EnsureRange(CircleSelect.Value, 0, Ord(High(TSteamCircle))));
  Result.Release := TSteamRelease(EnsureRange(ReleaseSelect.Value, 0, Ord(High(TSteamRelease))));
  Result.Color := (Cardinal(ColorItem.R) shl 16) or (Cardinal(ColorItem.G) shl 8) or ColorItem.B;
  for Track := Low(TSteamTrack) to High(TSteamTrack) do
    Result.Value[Track] := ClampSteamTrack(Track, Tracks[Track].Value);
end;

end.
