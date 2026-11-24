unit SteamFX_Presets;

// Copyright (c) 2026 VRAMの魔術師
// SPDX-License-Identifier: GPL-3.0-only
// 用途に合わせた推奨値を返す。プリセット番号は描画に使わない。

interface

uses SteamFX_Settings;

type
  TSteamPreset = (spFood, spRice, spRamen, spHotPot, spSoup, spCoffee,
    spSteamed, spRiceCooker, spKettle, spPressure, spLid,
    spBath, spOutdoorBath, spSpaTown, spShower, spSauna, spBathroom,
    spBreath, spCoolDrink, spBody, spAnimal, spHead,
    spLocomotive, spPipe, spBoiler, spManhole, spIron, spHumidifier,
    spGeothermal, spGeyser, spWater, spGround);

const
  STEAM_PRESET_NAMES: array[TSteamPreset] of PWideChar = (
    '温かい料理', '炊きたてのご飯', 'ラーメン', '鍋料理', 'スープ', 'コーヒー・お茶',
    '蒸し料理', '炊飯器', 'やかん', '圧力鍋', '鍋の蓋を開けた瞬間',
    'お風呂', '露天風呂', '温泉街の湯けむり', 'シャワー', 'サウナ', '浴室に充満する湯気',
    '冬場の白い息', '飲み物を吹いて冷ます息', '身体から立ち上る湯気', '動物の白い息', '頭から立ち上る湯気',
    '蒸気機関車', '蒸気配管', '蒸気ボイラー', 'マンホール', 'スチームアイロン', '加湿器',
    '地熱による蒸気', '間欠泉', '水面から立ち上る湯気', '熱せられた地面からの蒸気');

function SteamPreset(Preset: TSteamPreset): TSteamSettings;

implementation

function SteamPreset(Preset: TSteamPreset): TSteamSettings;
var
  S: TSteamSettings;

  procedure Source(Kind: TSteamSource; Count, Width, Depth: Integer);
  begin
    S.Source := Kind;
    S.Value[trSources] := Count;
    S.Value[trWidth] := Width;
    S.Value[trDepth] := Depth;
    S.Value[trDiameter] := Width;
  end;

  procedure Shape(Thickness, Height, Density, Spread, Sway: Double);
  begin
    S.Value[trThickness] := Thickness;
    S.Value[trHeight] := Height;
    S.Value[trDensity] := Density;
    S.Value[trSpread] := Spread;
    S.Value[trSway] := Sway;
  end;

  procedure Motion(Rise, Diffusion, Life, Hang: Double);
  begin
    S.Value[trRise] := Rise;
    S.Value[trDiffusion] := Diffusion;
    S.Value[trLife] := Life;
    S.Value[trHang] := Hang;
    S.Value[trFadeOut] := Life * 0.40;
  end;

  procedure Release(Mode: TSteamRelease; Duration, Interval, Variation: Double);
  begin
    S.Release := Mode;
    S.Value[trReleaseTime] := Duration;
    S.Value[trInterval] := Interval;
    S.Value[trIntervalVar] := Variation;
  end;

  procedure Wind(Direction, Speed, Variation: Double);
  begin
    S.Value[trWindDirection] := Direction;
    S.Value[trWindSpeed] := Speed;
    S.Value[trWindVariation] := Variation;
  end;

  procedure Jet(Direction, Pitch, Speed, Cone, Nozzle, Force, Diffusion, Drag: Double);
  begin
    S.Style := ssJet;
    S.Value[trJetDirection] := Direction;
    S.Value[trJetPitch] := Pitch;
    S.Value[trJetSpeed] := Speed;
    S.Value[trJetRange] := Cone;
    S.Value[trNozzle] := Nozzle;
    S.Value[trJetForce] := Force;
    S.Value[trJetDiffusion] := Diffusion;
    S.Value[trJetDrag] := Drag;
    S.Value[trFadeIn] := 0.045;
  end;

  procedure Mist(Thickness, Density, Speed, Lifetime: Double);
  begin
    S.Style := ssLingering;
    Shape(Thickness, 260, Density, 120, 34);
    Motion(Speed, 30, Lifetime, 69);
    S.Value[trHorizontal] := 108;
    S.Value[trBlur] := 60;
    S.Value[trContrast] := 18;
  end;

  procedure Breath(Thickness, Height, Density, Speed, Duration, Interval: Double);
  begin
    S.Style := ssIntermittent;
    Source(scPoint, 1, 0, 0);
    Shape(Thickness, Height, Density, 78, 31);
    Motion(21, 32, 1.55, 16);
    Wind(90, Speed, 12);
    Release(srPeriodic, Duration, Interval, 36);
    S.Value[trFadeIn] := 0.08;
    S.Value[trPhase] := 0.15;
    S.Value[trBlur] := 42;
  end;

begin
  S := DefaultSteamSettings;
  case Preset of
    spFood: ;
    spRice:
      begin
        Source(scCircle, 11, 111, 0);
        Shape(14, 142, 39, 72, 60);
        Motion(46, 16, 2.75, 7);
        S.Value[trDetail] := 72;
      end;
    spRamen:
      begin
        Source(scCircle, 9, 183, 0);
        Shape(19, 225, 49, 86, 72);
        Motion(63, 23, 3.45, 10);
        S.Value[trVortex] := 70;
      end;
    spHotPot:
      begin
        Source(scCircle, 13, 253, 0);
        Shape(32, 258, 57, 95, 65);
        Motion(68, 28, 3.70, 16);
        S.Value[trSpeedVariation] := 43;
      end;
    spSoup:
      begin
        Source(scCircle, 5, 121, 0);
        Shape(19, 162, 38, 64, 38);
        Motion(43, 16, 3.00, 16);
      end;
    spCoffee:
      begin
        S.Style := ssPoint;
        Source(scPoint, 1, 0, 0);
        Shape(11, 151, 36, 84, 76);
        Motion(44, 13, 3.05, 9);
        S.Value[trVortex] := 83;
      end;
    spSteamed:
      begin
        Source(scRectangle, 11, 195, 90);
        Shape(27, 242, 64, 89, 47);
        Motion(69, 26, 3.50, 22);
        S.Value[trSoftness] := 91;
      end;
    spRiceCooker:
      begin
        Source(scPoint, 1, 0, 0);
        Jet(-8, 15, 180, 14, 9, 81, 64, 76);
        Shape(17, 180, 61, 72, 52);
        Motion(38, 22, 2.35, 10);
        Release(srPeriodic, 0.90, 2.60, 42);
      end;
    spKettle:
      begin
        Source(scPoint, 1, 0, 0);
        Jet(36, 0, 170, 9, 6, 78, 62, 58);
        Shape(14, 202, 45, 76, 62);
        Motion(37, 17, 2.75, 10);
      end;
    spPressure:
      begin
        Source(scPoint, 1, 0, 0);
        Jet(6, -8, 385, 6, 5, 127, 47, 50);
        Shape(13, 244, 74, 54, 39);
        Motion(35, 24, 1.75, 4);
        Release(srPeriodic, 0.48, 1.30, 27);
      end;
    spLid:
      begin
        S.Style := ssBurst;
        Source(scCircle, 12, 202, 0);
        Shape(53, 260, 81, 142, 62);
        Motion(139, 58, 2.55, 15);
        Release(srOneShot, 0.38, 3.0, 0);
        S.Value[trFadeIn] := 0.05;
        S.Value[trPhase] := 0.12;
      end;
    spBath:
      begin
        Mist(47, 42, 26, 4.3);
        Source(scRectangle, 13, 395, 208);
      end;
    spOutdoorBath:
      begin
        Mist(55, 52, 23, 4.8);
        Source(scRectangle, 15, 560, 305);
        Wind(104, 42, 51);
        S.Value[trTilt] := 17;
      end;
    spSpaTown:
      begin
        Mist(84, 59, 29, 6.2);
        Source(scRandom, 16, 740, 520);
        Wind(-62, 55, 43);
        S.Value[trSpaceDepth] := 163;
      end;
    spShower:
      begin
        Mist(42, 44, 22, 3.7);
        Source(scLine, 7, 178, 0);
        Wind(-30, 19, 34);
        S.Value[trSwaySpeed] := 105;
      end;
    spSauna:
      begin
        Mist(72, 55, 14, 5.8);
        Source(scCircle, 10, 300, 0);
        Release(srRandom, 1.8, 4.5, 70);
        S.Value[trHang] := 90;
      end;
    spBathroom:
      begin
        Mist(105, 38, 10, 7.1);
        Source(scRectangle, 24, 880, 540);
        S.Value[trTilt] := 48;
        S.Value[trSoftness] := 95;
      end;
    spBreath:
      Breath(22, 92, 47, 150, 0.68, 3.25);
    spCoolDrink:
      begin
        Breath(12, 54, 23, 125, 0.38, 1.85);
        Wind(114, 125, 9);
        S.Value[trLife] := 0.92;
        S.Value[trFadeOut] := 0.49;
      end;
    spBody:
      begin
        Source(scRectangle, 12, 177, 120);
        Shape(20, 180, 33, 89, 52);
        Motion(41, 15, 3.2, 34);
        S.Value[trTilt] := 63;
      end;
    spAnimal:
      begin
        Breath(30, 111, 58, 135, 0.78, 2.6);
        Source(scLine, 2, 16, 0);
        Release(srRandom, 0.78, 2.6, 61);
        S.Value[trLifeVariation] := 55;
      end;
    spHead:
      begin
        Source(scCircle, 4, 81, 0);
        Shape(12, 147, 39, 89, 77);
        Motion(48, 12, 2.57, 5);
        S.Value[trPositionVariation] := 13;
      end;
    spLocomotive:
      begin
        Source(scPoint, 1, 0, 0);
        Jet(26, -14, 310, 24, 43, 139, 160, 67);
        Shape(55, 355, 87, 122, 61);
        Motion(72, 56, 3.18, 24);
        Release(srPeriodic, 0.48, 1.02, 19);
        Wind(111, 41, 23);
      end;
    spPipe:
      begin
        Source(scPoint, 1, 0, 0);
        Jet(70, 22, 276, 17, 16, 93, 58, 53);
        Shape(22, 285, 61, 78, 61);
        Motion(45, 27, 2.22, 15);
      end;
    spBoiler:
      begin
        Source(scLine, 3, 72, 0);
        Jet(-24, -12, 235, 28, 28, 112, 142, 69);
        Shape(41, 320, 68, 92, 43);
        Motion(44, 38, 3.2, 26);
        Release(srRandom, 1.22, 3.5, 65);
      end;
    spManhole:
      begin
        Source(scCircle, 10, 145, 0);
        S.Circle := ciRim;
        Shape(28, 297, 64, 90, 87);
        Motion(61, 34, 4.0, 30);
        Wind(103, 23, 56);
      end;
    spIron:
      begin
        Source(scLine, 5, 105, 0);
        Jet(154, 0, 185, 31, 7, 96, 115, 81);
        Shape(19, 120, 54, 116, 38);
        Motion(26, 29, 1.6, 9);
        Release(srRandom, 0.45, 2.1, 76);
      end;
    spHumidifier:
      begin
        Source(scPoint, 1, 0, 0);
        Jet(-3, 9, 115, 9, 13, 70, 114, 87);
        Shape(17, 178, 31, 93, 26);
        Motion(22, 35, 2.9, 50);
        S.Value[trBlur] := 58;
      end;
    spGeothermal:
      begin
        Mist(55, 61, 42, 5.4);
        Source(scRandom, 10, 360, 225);
        Wind(-72, 33, 57);
        S.Value[trVortex] := 76;
      end;
    spGeyser:
      begin
        Source(scCircle, 6, 90, 0);
        Jet(4, -18, 405, 37, 57, 131, 146, 57);
        Shape(50, 485, 72, 132, 63);
        Motion(91, 51, 4.05, 20);
        Release(srPeriodic, 1.35, 6.6, 51);
        S.Value[trPhase] := 0.30;
      end;
    spWater:
      begin
        Mist(62, 32, 19, 5.4);
        Source(scRectangle, 18, 730, 390);
        Wind(90, 29, 31);
        S.Value[trTilt] := 12;
      end;
    spGround:
      begin
        Mist(45, 40, 27, 4.25);
        Source(scRandom, 17, 630, 242);
        Release(srRandom, 2.4, 4.1, 84);
        S.Value[trDetail] := 68;
        Wind(-35, 23, 56);
      end;
  end;
  Result := S;
end;

end.
