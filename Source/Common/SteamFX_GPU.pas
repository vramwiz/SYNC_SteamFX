unit SteamFX_GPU;

// Copyright (c) 2026 VRAMの魔術師
// SPDX-License-Identifier: GPL-3.0-only
// AviUtl2 の D3D11 ピクセルシェーダー API でオブジェクト画像を直接生成する。

interface

uses AviUtl2FilterTypes, SteamFX_Field;

// 成功時にホストのオブジェクト画像を更新する。現在フレームのポインターは保存しない。
function TryRenderSteamGPU(Video: PFILTER_PROC_VIDEO; Width, Height: Integer;
  const Frame: TSteamFrame): Boolean;

implementation

uses
  System.SysUtils, System.SyncObjs, Winapi.Windows, Winapi.D3DCommon, Winapi.D3DCompiler;

const
  // HLSL は DLL に内蔵する。実行に .cso やテクスチャーファイルは必要ない。
  ShaderSource: AnsiString =
{$I SteamFX_Shader.inc}
  ;

var
  ShaderLock: TCriticalSection;
  ShaderAttempted: Boolean;
  CompiledShader: ID3DBlob;

function GetShader: ID3DBlob;
var
  Errors: ID3DBlob;
begin
  ShaderLock.Acquire;
  try
    if not ShaderAttempted then
    begin
      ShaderAttempted := True;
      try
        if Failed(D3DCompile(PAnsiChar(ShaderSource), Length(ShaderSource), nil,
          nil, nil, 'SteamPixel', 'ps_5_0', D3DCOMPILE_OPTIMIZATION_LEVEL3, 0,
          CompiledShader, Errors)) then
        begin
          CompiledShader := nil;
          if Errors <> nil then
            OutputDebugStringA(PAnsiChar(Errors.GetBufferPointer));
        end;
      except
        on E: Exception do
          OutputDebugString(PWideChar('SYNC_SteamFX shader: ' + E.Message));
      end;
    end;
    Result := CompiledShader;
  finally
    ShaderLock.Release;
  end;
end;

function TryRenderSteamGPU(Video: PFILTER_PROC_VIDEO; Width, Height: Integer;
  const Frame: TSteamFrame): Boolean;
var Shader: ID3DBlob;
begin
  Result := False;
  if not Assigned(Video^.ExecPixelshaderData) then Exit;
  Shader := GetShader;
  if Shader = nil then Exit;
  Video^.SetImageData(nil, Width, Height);
  // シェーダーはホストのテクスチャー規約どおり RGB にアルファを乗算して返す。
  Result := Video^.ExecPixelshaderData(Shader.GetBufferPointer, Shader.GetBufferSize,
    nil, nil, 0, @Frame, SizeOf(Frame), nil, nil);
end;

initialization
  ShaderLock := TCriticalSection.Create;
finalization
  CompiledShader := nil;
  ShaderLock.Free;
end.
