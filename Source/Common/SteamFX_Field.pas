unit SteamFX_Field;

// Copyright (c) 2026 VRAMの魔術師
// SPDX-License-Identifier: GPL-3.0-only
// 発生源の投影と湯気の軌道を秒単位で評価し、CPU と D3D11 に同じ描画データを渡す。

interface

uses SteamFX_Settings;

const
  STEAM_MAX_PUFFS = 96;

type
  // HLSL の float4 配列と同じ 16 バイト境界で並ぶ描画定数。
  TSteamPuff = packed record
    X, Y, BoundX, BoundY: Single;
    AcrossX, AcrossY, AlongX, AlongY: Single;
    Strength, Seed, Evolution, Light: Single;
    Warp, Curl, Variation, Reserved: Single;
  end;
  TSteamFrame = packed record
    Left, Top, Right, Bottom: Single;
    Red, Green, Blue, Reserved: Single;
    Detail, Softness, Contrast, Count: Single;
    Puffs: array[0..STEAM_MAX_PUFFS - 1] of TSteamPuff;
  end;
  TSteamAmountSampler = function(Context: Pointer; Time: Double): Double;

  // Context は呼出中だけ借用する。Sampler=nil の場合は発生量を一定として扱う。
procedure BuildSteamFrame(const S: TSteamSettings; Width, Height: Integer;
  Time: Double; Sampler: TSteamAmountSampler; Context: Pointer; out Frame: TSteamFrame);

// 連続したノイズと、0..1 へ滑らかに遷移する補間。CPU ラスターからも使用する。
function SteamNoise(X, Y: Single): Single;
function SteamUnit(Value: Double): Double; inline;
function SteamSmooth(Value: Double): Double; inline;

implementation

uses System.Math;

type
  TSteamValues = array[TSteamTrack] of Double;
  PSteamValues = ^TSteamValues;

  TSteamScene = record
    V: PSteamValues;
    Style: TSteamStyle;
    Source: TSteamSource;
    Circle: TSteamCircle;
    SourceCount: Integer;
    TiltSin, TiltCos, RotationSin, RotationCos: Double;
    WindX, WindY, WindSpeed, WindChange: Double;
    OriginX, OriginY, Lens: Double;
    BaseStrength, LifeVariation: Double;
  end;

function SteamUnit(Value: Double): Double;
begin
  Result := EnsureRange(Value, 0.0, 1.0);
end;

function SteamSmooth(Value: Double): Double;
begin
  Value := SteamUnit(Value);
  Result := Value * Value * (3 - 2 * Value);
end;

{$Q-}{$R-}
function Mix(Bits: Cardinal): Cardinal; inline;
begin
  Bits := (Bits xor (Bits shr 16)) * Cardinal($7FEB352D);
  Bits := (Bits xor (Bits shr 15)) * Cardinal($846CA68B);
  Result := Bits xor (Bits shr 16);
end;

function RandomAt(Tick: Int64; Channel: Cardinal): Double; inline;
begin
  Result := (Mix(Cardinal(Tick) xor (Channel * Cardinal($9E3779B9))) and $FFFFFF) / 16777215.0;
end;

function SignedAt(Tick: Int64; Channel: Cardinal): Double; inline;
begin
  Result := 2 * RandomAt(Tick, Channel) - 1;
end;

function Lattice(X, Y: Integer): Single; inline;
var Bits: Cardinal;
begin
  Bits := Cardinal(X) * Cardinal($9E3779B9) xor Cardinal(Y) * Cardinal($85EBCA6B);
  Result := (Mix(Bits) and $FFFF) * (1.0 / 65535.0);
end;
{$R+}{$Q+}

function SteamNoise(X, Y: Single): Single;
var
  IX, IY: Integer;
  U, V, A, B: Single;
begin
  IX := Floor(X);
  IY := Floor(Y);
  U := X - IX;
  V := Y - IY;
  U := U * U * (3 - 2 * U);
  V := V * V * (3 - 2 * V);
  A := Lattice(IX, IY);
  B := Lattice(IX, IY + 1);
  A := A + U * (Lattice(IX + 1, IY) - A);
  B := B + U * (Lattice(IX + 1, IY + 1) - B);
  Result := A + V * (B - A);
end;

function MixValue(A, B, F: Double): Double; inline;
begin
  Result := A + (B - A) * F;
end;

procedure InitScene(const S: TSteamSettings; Width, Height: Integer; out Scene: TSteamScene);
var V: PSteamValues;
begin
  V := @S.Value;
  Scene.V := V;
  Scene.Style := S.Style;
  Scene.Source := S.Source;
  Scene.Circle := S.Circle;
  Scene.SourceCount := Round(V^[trSources]);
  if Scene.Source = scPoint then
    Scene.SourceCount := 1;
  SinCos(DegToRad(V^[trTilt]), Scene.TiltSin, Scene.TiltCos);
  SinCos(DegToRad(V^[trRotation]), Scene.RotationSin, Scene.RotationCos);
  Scene.WindSpeed := V^[trWindSpeed];
  Scene.WindX := 0;
  Scene.WindY := 0;
  Scene.WindChange := 0;
  if Scene.WindSpeed > 0 then
  begin
    SinCos(DegToRad(V^[trWindDirection]), Scene.WindX, Scene.WindY);
    Scene.WindY := -Scene.WindY;
    Scene.WindChange := V^[trWindChange] * 0.016;
  end;
  // 画面内の XY オフセットを投影後の位置に加え、遠近感による拡大縮小から外す。
  Scene.OriginX := Width * 0.5 + V^[trOriginX];
  Scene.OriginY := Height * 0.5 + V^[trOriginY];
  Scene.Lens := Max(640.0, Height * 1.15);
  Scene.BaseStrength := V^[trDensity] * V^[trConcentration] * 0.000073;
  Scene.LifeVariation := V^[trLifeVariation] * 0.006;
end;

procedure SourceXY(const Scene: TSteamScene; Index: Integer; Tick: Int64;
  out X, Y, Z: Double);
var U, V, R, A, Offset, Spread, C, N, Depth: Double;
begin
  U := (Index + 0.5) / Scene.SourceCount;
  V := Frac((Index + 0.5) * 0.61803398875);
  Offset := Scene.V^[trPositionVariation] * 0.01;
  case Scene.Source of
    scLine:
      begin
        U := SteamUnit(U + SignedAt(Tick, 1) * Offset / Scene.SourceCount);
        U := (U - 0.5) * Scene.V^[trWidth];
        V := 0;
      end;
    scCircle:
      begin
        A := 2 * Pi * (V + SignedAt(Tick, 1) * Offset / Max(3, Scene.SourceCount));
        if Scene.Circle = ciRim then
          R := 1
        else
          R := Sqrt(SteamUnit(U + SignedAt(Tick, 2) * Offset / Scene.SourceCount));
        SinCos(A, C, N);
        R := R * Scene.V^[trDiameter] * 0.5;
        U := R * N;
        V := R * C;
      end;
    scRectangle, scRandom:
      begin
        if Scene.Source = scRandom then
        begin
          U := RandomAt(Index, 21);
          V := RandomAt(Index, 22);
        end;
        Spread := Offset / Sqrt(Scene.SourceCount);
        U := (SteamUnit(U + SignedAt(Tick, 1) * Spread) - 0.5) * Scene.V^[trWidth];
        V := (SteamUnit(V + SignedAt(Tick, 2) * Spread) - 0.5) * Scene.V^[trDepth];
      end;
  else
    R := Scene.V^[trThickness] * Offset * 0.16;
    U := SignedAt(Tick, 1) * R;
    V := SignedAt(Tick, 2) * R;
  end;
  if Scene.Style = ssPoint then
  begin
    U := U * 0.70;
    V := V * 0.70;
  end;
  X := U * Scene.RotationCos - V * Scene.RotationSin;
  Depth := U * Scene.RotationSin + V * Scene.RotationCos;
  Y := Depth * Scene.TiltSin;
  Z := -Depth * Scene.TiltCos * Scene.V^[trSpaceDepth] * 0.01;
end;

function ReleaseWindow(Tick: Int64; SlotStart, SlotEnd, Start, Duration,
  Variation: Double; var Birth: Double): Double;
var OverlapStart, OverlapEnd, Progress: Double;
begin
  Result := 0;
  OverlapStart := Max(SlotStart, Start);
  OverlapEnd := Min(SlotEnd, Start + Duration);
  if OverlapEnd <= OverlapStart then Exit;
  Birth := MixValue(OverlapStart, OverlapEnd, 0.22 + 0.56 * RandomAt(Tick, 3));
  Progress := (Birth - Start) / Duration;
  Result := SteamSmooth(Progress / 0.25) * SteamSmooth((1 - Progress) / 0.42);
  Result := Result * (OverlapEnd - OverlapStart) / (SlotEnd - SlotStart) * Variation;
end;

function ReleaseGate(const S: TSteamSettings; Mode: TSteamRelease; Tick: Int64;
  SlotStart, SlotEnd: Double; var Birth: Double): Double;
var
  EventIndex, I: Int64;
  Phase, Interval, Duration, Shift, Start, Strength, Candidate, CandidateBirth: Double;
begin
  if Mode = srContinuous then Exit(1);
  Phase := S.Value[trPhase];

  if Mode = srOneShot then
  begin
    Duration := S.Value[trReleaseTime] *
      (1 + SignedAt(0, 12) * S.Value[trReleaseTimeVar] * 0.008);
    Strength := 1 + SignedAt(0, 13) * S.Value[trReleaseAmountVar] * 0.008;
    Exit(ReleaseWindow(Tick, SlotStart, SlotEnd, Phase, Duration, Strength, Birth));
  end;
  Interval := S.Value[trInterval];
  EventIndex := Floor((Max(SlotStart, 0.0) - Phase) / Interval);
  // 直前から続く放出と、この区間で始まる放出の両方を考慮する。
  Result := 0;
  for I := Max(0, EventIndex - 1) to Max(0, Floor((SlotEnd - Phase) / Interval)) do
  begin
    Shift := S.Value[trIntervalVar] * 0.0038;
    if Mode = srRandom then
      Shift := 0.28 + Shift;
    Start := Phase + (I + Shift * RandomAt(I, 11)) * Interval;
    Duration := Min(Interval, S.Value[trReleaseTime] *
      (1 + SignedAt(I, 12) * S.Value[trReleaseTimeVar] * 0.008));
    Strength := 1 + SignedAt(I, 13) * S.Value[trReleaseAmountVar] * 0.008;
    Candidate := ReleaseWindow(Tick, SlotStart, SlotEnd, Start, Duration, Strength, CandidateBirth);
    if Candidate > Result then
    begin
      Result := Candidate;
      Birth := CandidateBirth;
    end;
  end;
end;

procedure PuffXY(const Scene: TSteamScene; Index: Integer; Tick: Int64; Birth,
  Age, Life, Progress: Double; var X, Y, Z, AX, AY, JetDiffusion: Double);
var
  V: PSteamValues;
  Drift, WindAge, WindWave, Speed, RiseAge, Hang, Height, DetailTime, Offset,
  Sway, JetX, JetY, PitchSin, PitchCos, JetAge, JetTravel, Cone, Pressure: Double;
begin
  V := Scene.V;
  Hang := V^[trHang] * 0.01;
  if Scene.Style = ssLingering then
    Hang := 0.55 + Hang * 0.45;
  Speed := 1 + SignedAt(Index, 23) * V^[trSpeedVariation] * 0.005 +
    SignedAt(Tick, 4) * V^[trSpeedVariation] * 0.002;
  RiseAge := Age * (1 - 0.71 * Hang) / (1 + V^[trRiseDrag] * 0.018 * Progress);
  if Scene.Style = ssBurst then
    RiseAge := RiseAge * (1.44 - 0.48 * SteamSmooth(Progress));
  Height := V^[trHeight];
  Y := Y - Height * (1 - Exp(-V^[trRise] * Speed * RiseAge / Height));
  AX := 0;
  AY := -Max(3.0, V^[trRise] * Speed * (1 - Hang));

  if Scene.Style = ssJet then
  begin
    Pressure := V^[trJetForce] * 0.01;
    Cone := SignedAt(Tick, 5) * V^[trJetRange] * 0.5;
    SinCos(DegToRad(V^[trJetDirection] + Cone), JetX, JetY);
    JetY := -JetY;
    SinCos(DegToRad(V^[trJetPitch] + SignedAt(Tick, 6) * V^[trJetRange] * 0.24),
      PitchSin, PitchCos);
    JetAge := 1 + V^[trJetDrag] * 0.038 * Progress;
    JetTravel := V^[trJetSpeed] * Speed * (0.6 + 0.4 * Pressure) * Age / JetAge;
    X := X + JetX * PitchCos * JetTravel;
    Y := Y + JetY * PitchCos * JetTravel;
    Z := Z + PitchSin * JetTravel;
    AX := AX + JetX * V^[trJetSpeed] * PitchCos / Sqr(JetAge);
    AY := AY + JetY * V^[trJetSpeed] * PitchCos / Sqr(JetAge);
    JetDiffusion := V^[trJetDiffusion] * 0.01;
  end;

  if Scene.WindSpeed > 0 then
  begin
    WindAge := Age * MixValue(0.24, 1, SteamSmooth(Age / 0.85));
    if Scene.Style = ssIntermittent then
      WindAge := Age / (1 + 0.42 * Age);
    WindWave := 1;
    if V^[trWindVariation] > 0 then
      WindWave := WindWave + (2 * SteamNoise(Birth * Scene.WindChange + 9.2,
        Age * Scene.WindChange + 2.8) - 1) * V^[trWindVariation] * 0.009;
    X := X + Scene.WindX * Scene.WindSpeed * WindAge * WindWave;
    Y := Y + Scene.WindY * Scene.WindSpeed * WindAge * WindWave;
    AX := AX + Scene.WindX * Scene.WindSpeed * WindWave;
    AY := AY + Scene.WindY * Scene.WindSpeed * WindWave;
  end;

  Drift := (V^[trHorizontal] * 0.18 + V^[trDiffusion] * 0.30) * (1 + 2 * Hang);
  X := X + (0.7 * SignedAt(Index, 24) + 0.3 * SignedAt(Tick, 7)) * Drift * Age;
  Z := Z + SignedAt(Index, 25) * Drift * Age * Hang;
  if V^[trSway] > 0 then
  begin
    DetailTime := V^[trSwaySpeed] * 0.018;
    Offset := RandomAt(Index, 26) * 32;
    Sway := SteamNoise(Birth * DetailTime + Offset, Age * 1.05 + Offset) - 0.5;
    X := X + Sway * V^[trSway] * (2 + 0.45 * V^[trVortex] * 0.01) *
      SteamSmooth(Age / Max(0.25, Life * 0.55));
    AX := AX + Sway * V^[trSway] * 0.55;
  end;
end;

function BuildPuff(const Scene: TSteamScene; Tick: Int64; Birth, Age, Amount, Gate,
  SampleWeight: Double; out Puff: TSteamPuff): Boolean;
var
  V: PSteamValues;
  Emitter: Integer;
  X, Y, Z, Factor, AgeFrac, Life, Fade, Width, Length, RadiusX, RadiusY,
  AxisX, AxisY, AxisLength, Expansion, Strength, JetDiffusion, Variation, Rate: Double;
begin
  Result := False;
  V := Scene.V;
  Life := V^[trLife] * (1 + SignedAt(Tick, 8) * Scene.LifeVariation);
  if (Age < 0) or (Age >= Life) then Exit;
  Rate := Min(1.0, 0.08 + 0.75 * Sqrt(Amount));
  if RandomAt(Tick, 9) > Rate then Exit;
  AgeFrac := Age / Life;
  Fade := SteamSmooth(Age / Max(0.026, V^[trFadeIn])) *
    SteamSmooth((Life - Age) / Max(0.034, V^[trFadeOut]));
  if Fade < 0.0001 then Exit;
  Emitter := Integer(((Tick mod Scene.SourceCount) + Scene.SourceCount) mod Scene.SourceCount);
  SourceXY(Scene, Emitter, Tick, X, Y, Z);
  JetDiffusion := 0;
  PuffXY(Scene, Emitter, Tick, Birth, Age, Life, AgeFrac, X, Y, Z,
    AxisX, AxisY, JetDiffusion);
  Factor := Scene.Lens / Max(Scene.Lens * 0.24,
    Scene.Lens + Z * V^[trPerspective] * 0.018);
  Puff.X := Scene.OriginX + X * Factor;
  Puff.Y := Scene.OriginY + Y * Factor;

  Variation := V^[trShapeVariation] * 0.01;
  Width := V^[trThickness] * (0.57 + SignedAt(Tick, 10) * Variation * 0.21);
  Expansion := V^[trDiffusion] * Age * (0.16 + V^[trSpread] * 0.0040) *
    (0.5 + V^[trHorizontal] * 0.0082 + JetDiffusion * 0.57);
  if Scene.Style = ssJet then
    Width := MixValue(V^[trNozzle] * 0.62, Width, SteamSmooth(Age / 0.46));
  if Scene.Style = ssBurst then
    Expansion := Expansion * 1.35;
  Width := (Width + Expansion) * (0.61 + 0.39 * Sqrt(Amount)) *
    (1 + V^[trBlur] * 0.002);
  Length := Width * (1.58 + SignedAt(Tick, 14) * Variation * 0.62);
  case Scene.Style of
    ssPoint:
      begin
        Width := Width * 0.82;
        Length := Length * 1.35;
      end;
    ssLingering:
      begin
        Length := Width * 1.8;
        Width := Width * 0.72;
        AxisX := 1;
        AxisY := AxisY * 0.023;
      end;
    ssJet:
      Length := Length * (1 + 0.53 * (1 - SteamSmooth(Age / 0.7)));
    ssBurst:
      Length := Length * 0.86;
  end;
  Width := Max(0.65, Width * Factor);
  Length := Max(0.65, Length * Factor);
  AxisLength := Sqrt(Sqr(AxisX) + Sqr(AxisY));
  if AxisLength < 0.001 then
  begin
    AxisY := -1;
    AxisLength := 1;
  end;
  AxisX := AxisX / AxisLength;
  AxisY := AxisY / AxisLength;
  Puff.AcrossX := -AxisY / Width;
  Puff.AcrossY := AxisX / Width;
  Puff.AlongX := AxisX / Length;
  Puff.AlongY := AxisY / Length;
  RadiusX := Sqrt(Sqr(AxisY * Width) + Sqr(AxisX * Length));
  RadiusY := Sqrt(Sqr(AxisX * Width) + Sqr(AxisY * Length));
  Puff.Warp := V^[trSway] * 0.004 + Variation * 0.24;
  Puff.Curl := V^[trVortex] * 0.0038;
  Puff.BoundX := RadiusX * (1.1 + Puff.Warp + Puff.Curl * 0.40);
  Puff.BoundY := RadiusY * (1.1 + Puff.Warp + Puff.Curl * 0.40);

  Strength := Scene.BaseStrength * Gate * Fade * Power(Amount, 0.42) * SampleWeight;
  Strength := Strength * (1 - V^[trDiffusionFade] * 0.0088 * SteamSmooth(AgeFrac));
  Strength := Strength * (1 + SignedAt(Emitter, 27) * V^[trSourceVariation] * 0.007);
  if Scene.Style = ssJet then
    Strength := Strength * (V^[trJetForce] * 0.01) *
      (0.76 + 0.85 * (1 - SteamSmooth(Age / 0.58)));
  if Scene.Style = ssBurst then
    Strength := Strength * 1.48;
  Puff.Strength := Min(2.5, Strength);
  Puff.Seed := RandomAt(Tick, 15) * 115;
  Puff.Evolution := Age * (0.38 + V^[trSwaySpeed] * 0.013);
  Puff.Light := 0.92 + 0.08 * SteamUnit(Factor);
  Puff.Variation := Variation;
  Puff.Reserved := 0;
  Result := Puff.Strength > 0.00004;
end;

procedure BuildSteamFrame(const S: TSteamSettings; Width, Height: Integer;
  Time: Double; Sampler: TSteamAmountSampler; Context: Pointer; out Frame: TSteamFrame);
var
  Scene: TSteamScene;
  Mode: TSteamRelease;
  P: TSteamPuff;
  TimeStep, MaxLife, SlotStart, SlotEnd, Birth, Age, Amount, Gate, Trigger,
    SampleWeight, InitialAmount: Double;
  FirstTick, LastTick, Tick: Int64;
  Count: Integer;

  function AmountAt(AtTime: Double): Double;
  begin
    if not Assigned(Sampler) then Exit(S.Value[trAmount]);
    if AtTime <= 0 then Exit(InitialAmount);
    Result := ClampSteamTrack(trAmount, Sampler(Context, AtTime));
  end;

begin
  Frame := Default(TSteamFrame);
  if IsNan(Time) or IsInfinite(Time) or (Abs(Time) > 100000000) then Exit;
  if (Width <= 0) or (Height <= 0) or (S.Value[trDensity] = 0) or
    (S.Value[trConcentration] = 0) then Exit;
  if (S.Value[trAmount] <= 0) and not Assigned(Sampler) then Exit;
  InitScene(S, Width, Height, Scene);
  Frame.Left := Width;
  Frame.Top := Height;
  Frame.Red := ((S.Color shr 16) and 255) / 255;
  Frame.Green := ((S.Color shr 8) and 255) / 255;
  Frame.Blue := (S.Color and 255) / 255;
  Frame.Detail := 1.35 + S.Value[trDetail] * 0.025;
  Frame.Softness := SteamUnit((S.Value[trBlur] * 0.46 + S.Value[trSoftness] * 0.54) * 0.01);
  Frame.Contrast := S.Value[trContrast] * 0.01;
  Mode := EffectiveRelease(S);
  if (Mode <> srContinuous) and (Time < 0) then Exit;

  MaxLife := S.Value[trLife] * (1 + Scene.LifeVariation);
  TimeStep := Max(1 / 30, MaxLife / (STEAM_MAX_PUFFS - 2));
  SampleWeight := Min(2.5, Sqrt(TimeStep * 30));
  FirstTick := Floor((Time - MaxLife) / TimeStep);
  LastTick := Floor(Time / TimeStep);
  if Mode <> srContinuous then
    FirstTick := Max(0, FirstTick);
  InitialAmount := S.Value[trAmount];
  if Assigned(Sampler) and (FirstTick <= 0) then
    InitialAmount := ClampSteamTrack(trAmount, Sampler(Context, 0));

  Count := 0;
  for Tick := FirstTick to LastTick do
  begin
    SlotStart := Tick * TimeStep;
    SlotEnd := SlotStart + TimeStep;
    Birth := MixValue(SlotStart, SlotEnd, 0.16 + 0.68 * RandomAt(Tick, 3));
    Gate := ReleaseGate(S, Mode, Tick, SlotStart, SlotEnd, Birth);
    if (Mode <> srOneShot) and (Gate <= 0) then Continue;
    Age := Time - Birth;
    if (Age < 0) or (Age >= MaxLife) then Continue;
    Amount := AmountAt(Birth);
    if Amount <= 0 then Continue;
    if (Mode = srOneShot) and Assigned(Sampler) then
    begin
      // 位相での一回放出に加えて、発生量を上げる操作も放出を開始する。
      Trigger := (Amount - AmountAt(Birth - S.Value[trReleaseTime])) * 0.01;
      Gate := Max(Gate, SteamSmooth(Trigger) * 0.85);
    end;
    if Gate <= 0 then Continue;
    if not BuildPuff(Scene, Tick, Birth, Age, Amount * 0.01, Gate, SampleWeight, P) then Continue;
    if (P.X + P.BoundX <= 0) or (P.Y + P.BoundY <= 0) or
      (P.X - P.BoundX >= Width) or (P.Y - P.BoundY >= Height) then Continue;
    Frame.Puffs[Count] := P;
    Inc(Count);
    Frame.Left := Min(Frame.Left, P.X - P.BoundX);
    Frame.Top := Min(Frame.Top, P.Y - P.BoundY);
    Frame.Right := Max(Frame.Right, P.X + P.BoundX);
    Frame.Bottom := Max(Frame.Bottom, P.Y + P.BoundY);
  end;
  Frame.Count := Count;
end;

end.
