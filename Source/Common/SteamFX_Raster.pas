unit SteamFX_Raster;

// Copyright (c) 2026 VRAMの魔術師
// SPDX-License-Identifier: GPL-3.0-only
// GPU を使えないときに、同じ密度・明度の積分を CPU で評価する。

interface

uses AviUtl2FilterTypes, SteamFX_Field;

type
  TSteamPixels = array of TPIXEL_RGBA;

  // Pixels は呼出側所有。シーンサイズのストレートアルファ RGBA を書き出す。
  // 大きく広がる湯気は粗い格子で積分した後、双線形補間して転送する。
  procedure RasterSteam(const Frame: TSteamFrame; Width, Height: Integer;
    var Pixels: TSteamPixels);

implementation

uses System.Math;

type
  TSteamCell = record
    Depth, Light: Single;
  end;
  TSteamCells = array of TSteamCell;

function EvaluatePuff(const P: TSteamPuff; const Frame: TSteamFrame;
  DX, DY: Single; out Light: Single): Single;
var
  U, V, NX, NY, N, M, Curl, Radial, Edge, Texture, Filament, Detail: Single;
begin
  Result := 0;
  U := DX * P.AcrossX + DY * P.AcrossY;
  V := DX * P.AlongX + DY * P.AlongY;
  if (Abs(U) > 1.1 + P.Warp + P.Curl * 0.4) or
     (Abs(V) > 1.1 + P.Warp + P.Curl * 0.4) then Exit;
  NX := U * 2.08 + P.Seed;
  NY := V * 1.58 - P.Evolution * 0.78;
  N := SteamNoise(NX, NY) - 0.5;
  M := SteamNoise(NX + 19.37, NY * 1.26 + 8.52) - 0.5;
  Curl := P.Curl * (M + N * 0.46);
  U := U + N * P.Warp + Curl * V * 0.48;
  V := V + M * P.Warp - Curl * U * 0.48;
  Radial := U * U + V * V;
  if Radial >= 1 then Exit;
  Edge := 1 - Radial;
  Edge := Edge * Edge * (1 + Radial * (1 - Frame.Softness));
  Detail := Frame.Detail;
  Texture := SteamNoise((NX + N * 0.82) * Detail, (NY + M) * (Detail * 0.77));
  Filament := SteamSmooth(0.34 + N * 0.94 + M * 0.46 + Texture * 0.61);
  Result := P.Strength * Edge * (0.18 + 0.82 * Filament) *
    (1 - P.Variation * 0.25 + P.Variation * 0.45 * Texture);
  Light := P.Light * (1 - Frame.Contrast * (1 - Filament) * 0.66);
end;

function SampleCell(const Cells: TSteamCells; Offset, NextOffset: Integer;
  U, V: Single): TSteamCell; inline;
var A, B: Single;
begin
  A := Cells[Offset].Depth + (Cells[Offset + 1].Depth - Cells[Offset].Depth) * U;
  B := Cells[NextOffset].Depth + (Cells[NextOffset + 1].Depth - Cells[NextOffset].Depth) * U;
  Result.Depth := A + (B - A) * V;
  A := Cells[Offset].Light + (Cells[Offset + 1].Light - Cells[Offset].Light) * U;
  B := Cells[NextOffset].Light + (Cells[NextOffset + 1].Light - Cells[NextOffset].Light) * U;
  Result.Light := A + (B - A) * V;
end;

procedure RasterSteam(const Frame: TSteamFrame; Width, Height: Integer;
  var Pixels: TSteamPixels);
var
  Cells: TSteamCells;
  Cell: TSteamCell;
  Pixel: PPIXEL_RGBA;
  P: TSteamPuff;
  Left, Top, Right, Bottom, GridWidth, GridHeight, Step, I, X, Y, X0, X1, Y0, Y1,
  Offset, NextOffset: Integer;
  Work: Double;
  DX, DY, Weight, Light, U, V, Alpha: Single;
begin
  SetLength(Pixels, Width * Height);
  FillChar(Pixels[0], Length(Pixels) * SizeOf(TPIXEL_RGBA), 0);
  if Frame.Count = 0 then Exit;

  Work := 0;
  for I := 0 to Round(Frame.Count) - 1 do
  begin
    P := Frame.Puffs[I];
    Work := Work + (Min(Width, P.X + P.BoundX) - Max(0, P.X - P.BoundX)) *
      (Min(Height, P.Y + P.BoundY) - Max(0, P.Y - P.BoundY));
  end;
  Work := Max(Work / 1500000, ((Min(Width, Frame.Right) - Max(0, Frame.Left)) *
    (Min(Height, Frame.Bottom) - Max(0, Frame.Top))) / 3000000);
  Step := Max(1, Ceil(Sqrt(Work)));
  Left := Max(0, Floor(Frame.Left) - Step);
  Top := Max(0, Floor(Frame.Top) - Step);
  Right := Min(Width, Ceil(Frame.Right) + Step);
  Bottom := Min(Height, Ceil(Frame.Bottom) + Step);
  GridWidth := (Right - Left + Step - 1) div Step + 1;
  GridHeight := (Bottom - Top + Step - 1) div Step + 1;
  SetLength(Cells, GridWidth * GridHeight);

  for I := 0 to Round(Frame.Count) - 1 do
  begin
    P := Frame.Puffs[I];
    X0 := Max(0, Ceil((P.X - P.BoundX - Left - 0.5) / Step));
    X1 := Min(GridWidth - 1, Floor((P.X + P.BoundX - Left - 0.5) / Step));
    Y0 := Max(0, Ceil((P.Y - P.BoundY - Top - 0.5) / Step));
    Y1 := Min(GridHeight - 1, Floor((P.Y + P.BoundY - Top - 0.5) / Step));
    for Y := Y0 to Y1 do
    begin
      DY := Top + Y * Step + 0.5 - P.Y;
      Offset := Y * GridWidth + X0;
      for X := X0 to X1 do
      begin
        DX := Left + X * Step + 0.5 - P.X;
        Weight := EvaluatePuff(P, Frame, DX, DY, Light);
        if Weight > 0 then
        begin
          Cells[Offset].Depth := Cells[Offset].Depth + Weight;
          Cells[Offset].Light := Cells[Offset].Light + Weight * Light;
        end;
        Inc(Offset);
      end;
    end;
  end;

  for Y := Top to Bottom - 1 do
  begin
    Y0 := ((Y - Top) div Step) * GridWidth;
    V := ((Y - Top) mod Step) / Step;
    Pixel := @Pixels[Y * Width + Left];
    for X := Left to Right - 1 do
    begin
      Offset := Y0 + (X - Left) div Step;
      if Step = 1 then
        Cell := Cells[Offset]
      else
      begin
        NextOffset := Offset + GridWidth;
        U := ((X - Left) mod Step) / Step;
        Cell := SampleCell(Cells, Offset, NextOffset, U, V);
      end;
      if Cell.Depth > 0.001 then
      begin
        Alpha := 0.94 * (1 - Exp(-Cell.Depth));
        Pixel^.A := Round(255 * Alpha);
        if Pixel^.A > 0 then
        begin
          Light := 255 * Cell.Light / Cell.Depth;
          Pixel^.R := Round(Frame.Red * Light);
          Pixel^.G := Round(Frame.Green * Light);
          Pixel^.B := Round(Frame.Blue * Light);
        end;
      end;
      Inc(Pixel);
    end;
  end;
end;

end.
