unit SteamFX_Settings;

// Copyright (c) 2026 VRAMの魔術師
// SPDX-License-Identifier: GPL-3.0-only
// 湯気演出の設定、単位と有効範囲を定義する。描画用の値はホストから独立している。

interface

type
  TSteamStyle = (ssPoint, ssSurface, ssLingering, ssJet, ssIntermittent, ssBurst);
  TSteamSource = (scPoint, scLine, scCircle, scRectangle, scRandom);
  TSteamCircle = (ciArea, ciRim);
  TSteamRelease = (srContinuous, srPeriodic, srRandom, srOneShot);
  TSteamTrack = (
    trAmount,
    trSources, trWidth, trDepth, trDiameter, trPositionVariation, trSourceVariation,
    trTilt, trRotation, trPerspective, trSpaceDepth,
    trThickness, trHeight, trDensity, trSpread, trSway, trSwaySpeed, trVortex,
    trDetail, trShapeVariation,
    trRise, trDiffusion, trHorizontal, trSpeedVariation, trRiseDrag, trHang,
    trJetDirection, trJetPitch, trJetSpeed, trJetRange, trNozzle, trJetForce,
    trJetDiffusion, trJetDrag,
    trReleaseTime, trInterval, trReleaseTimeVar, trIntervalVar, trReleaseAmountVar, trPhase,
    trWindDirection, trWindSpeed, trWindVariation, trWindChange,
    trConcentration, trContrast, trBlur, trSoftness,
    trLife, trLifeVariation, trFadeIn, trFadeOut, trDiffusionFade);

  TSteamSettings = record
    Style: TSteamStyle;
    Source: TSteamSource;
    Circle: TSteamCircle;
    Release: TSteamRelease;
    Color: Cardinal; // 0xRRGGBB
    Value: array[TSteamTrack] of Double;
  end;

  TSteamTrackSpec = record
    Name: PWideChar;
    Initial, Min, Max, Step: Double;
  end;

const
  STEAM_STYLE_NAMES: array[TSteamStyle] of PWideChar =
    ('単点上昇型', '面上昇型', '広範囲滞留型', '指向性噴射型', '間欠放出型', '瞬間放出型');
  STEAM_SOURCE_NAMES: array[TSteamSource] of PWideChar =
    ('単点', '直線', '円形', '矩形', 'ランダム');
  STEAM_CIRCLE_NAMES: array[TSteamCircle] of PWideChar = ('円の内部全体', '円周');
  STEAM_RELEASE_NAMES: array[TSteamRelease] of PWideChar =
    ('連続', '周期的', 'ランダム', '瞬間放出');
  // 形状は px、移動速度は px/秒、時間は秒。割合は 100 が基準。
  STEAM_TRACKS: array[TSteamTrack] of TSteamTrackSpec = (
    (Name:'発生量'; Initial:100; Min:0; Max:150; Step:0.01),
    (Name:'発生源の数'; Initial:7; Min:1; Max:32; Step:1),
    (Name:'発生範囲の幅'; Initial:180; Min:0; Max:8192; Step:1),
    (Name:'発生範囲の奥行'; Initial:100; Min:0; Max:8192; Step:1),
    (Name:'円の直径'; Initial:145; Min:0; Max:8192; Step:1),
    (Name:'発生位置のばらつき'; Initial:26; Min:0; Max:100; Step:0.1),
    (Name:'発生量のばらつき'; Initial:24; Min:0; Max:100; Step:0.1),
    (Name:'傾斜角度'; Initial:26; Min:0; Max:90; Step:0.1),
    (Name:'回転角度'; Initial:0; Min:-180; Max:180; Step:0.1),
    (Name:'遠近感'; Initial:35; Min:0; Max:100; Step:0.1),
    (Name:'奥行'; Initial:100; Min:0; Max:300; Step:0.1),
    (Name:'湯気の太さ'; Initial:17; Min:1; Max:1200; Step:0.1),
    (Name:'湯気の高さ'; Initial:200; Min:1; Max:4000; Step:1),
    (Name:'湯気の密度'; Initial:38; Min:0; Max:150; Step:0.1),
    (Name:'広がり'; Initial:63; Min:0; Max:300; Step:0.1),
    (Name:'揺らぎの強さ'; Initial:46; Min:0; Max:200; Step:0.1),
    (Name:'揺らぎ速度'; Initial:58; Min:0; Max:300; Step:0.1),
    (Name:'渦の強さ'; Initial:48; Min:0; Max:200; Step:0.1),
    (Name:'内部構造の細かさ'; Initial:58; Min:0; Max:100; Step:0.1),
    (Name:'形状のばらつき'; Initial:48; Min:0; Max:100; Step:0.1),
    (Name:'上昇速度'; Initial:64; Min:0; Max:1200; Step:0.1),
    (Name:'拡散速度'; Initial:17; Min:0; Max:400; Step:0.1),
    (Name:'横方向への広がり'; Initial:38; Min:0; Max:300; Step:0.1),
    (Name:'移動速度のばらつき'; Initial:26; Min:0; Max:100; Step:0.1),
    (Name:'上昇に伴う減速'; Initial:24; Min:0; Max:100; Step:0.1),
    (Name:'滞留の強さ'; Initial:8; Min:0; Max:100; Step:0.1),
    (Name:'噴射方向'; Initial:0; Min:-180; Max:180; Step:0.1),
    (Name:'噴射角度'; Initial:0; Min:-85; Max:85; Step:0.1),
    (Name:'噴射速度'; Initial:240; Min:0; Max:2400; Step:0.1),
    (Name:'噴射範囲'; Initial:12; Min:0; Max:120; Step:0.1),
    (Name:'噴出口の太さ'; Initial:12; Min:1; Max:500; Step:0.1),
    (Name:'噴射の強さ'; Initial:90; Min:0; Max:180; Step:0.1),
    (Name:'噴射後の拡散'; Initial:58; Min:0; Max:300; Step:0.1),
    (Name:'噴射後の減速'; Initial:60; Min:0; Max:100; Step:0.1),
    (Name:'放出時間'; Initial:0.75; Min:0.08; Max:12; Step:0.01),
    (Name:'放出間隔'; Initial:3.0; Min:0.12; Max:60; Step:0.01),
    (Name:'放出時間のばらつき'; Initial:18; Min:0; Max:100; Step:0.1),
    (Name:'放出間隔のばらつき'; Initial:20; Min:0; Max:100; Step:0.1),
    (Name:'放出量のばらつき'; Initial:22; Min:0; Max:100; Step:0.1),
    (Name:'放出開始位置・位相'; Initial:0; Min:0; Max:120; Step:0.01),
    (Name:'風向'; Initial:90; Min:-180; Max:180; Step:0.1),
    (Name:'風速'; Initial:0; Min:0; Max:1200; Step:0.1),
    (Name:'風の揺らぎ'; Initial:22; Min:0; Max:100; Step:0.1),
    (Name:'風の変化速度'; Initial:44; Min:0; Max:300; Step:0.1),
    (Name:'湯気の濃さ'; Initial:62; Min:0; Max:150; Step:0.1),
    (Name:'内部の明暗差'; Initial:29; Min:0; Max:100; Step:0.1),
    (Name:'ぼかし'; Initial:24; Min:0; Max:100; Step:0.1),
    (Name:'輪郭の柔らかさ'; Initial:76; Min:0; Max:100; Step:0.1),
    (Name:'湯気の寿命'; Initial:3.25; Min:0.15; Max:12; Step:0.01),
    (Name:'寿命のばらつき'; Initial:28; Min:0; Max:100; Step:0.1),
    (Name:'出現時のフェード'; Initial:0.16; Min:0; Max:6; Step:0.01),
    (Name:'消失時のフェード'; Initial:1.25; Min:0; Max:12; Step:0.01),
    (Name:'拡散に伴う透明度の変化'; Initial:60; Min:0; Max:100; Step:0.1));

function ClampSteamTrack(Track: TSteamTrack; Value: Double): Double;
function DefaultSteamSettings: TSteamSettings;
// 間欠・瞬間スタイルの連続設定には、スタイル既定の放出方式を使う。
function EffectiveRelease(const S: TSteamSettings): TSteamRelease;

implementation

uses System.Math;

function ClampSteamTrack(Track: TSteamTrack; Value: Double): Double;
begin
  if IsNan(Value) then
    Exit(STEAM_TRACKS[Track].Initial);
  Result := EnsureRange(Value, STEAM_TRACKS[Track].Min, STEAM_TRACKS[Track].Max);
end;

function DefaultSteamSettings: TSteamSettings;
var
  Track: TSteamTrack;
begin
  Result.Style := ssSurface;
  Result.Source := scCircle;
  Result.Circle := ciArea;
  Result.Release := srContinuous;
  Result.Color := $FFFFFF;
  for Track := Low(TSteamTrack) to High(TSteamTrack) do
    Result.Value[Track] := STEAM_TRACKS[Track].Initial;
end;

function EffectiveRelease(const S: TSteamSettings): TSteamRelease;
begin
  Result := S.Release;
  if Result = srContinuous then
    case S.Style of
      ssIntermittent: Result := srPeriodic;
      ssBurst: Result := srOneShot;
    end;
end;

end.
