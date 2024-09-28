program XmpPlay;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Classes, SysUtils, CustApp, raylib, uos_libxmp, Math;

type
  { TRayApplication }
  TRayApplication = class(TCustomApplication)
  protected
    procedure DoRun; override;
  public
    constructor Create(TheOwner: TComponent); override;
    destructor Destroy; override;
  end;

  const
    AppTitle = 'raylib - basic window';
    SampleRate = 44100;
    BufferSize = 8192 ; // buffer size=8192 is now Ok  !!!

var
  playing: boolean;
  ctx: xmp_context;
  stream: TAudioStream;
  mi: xmp_module_info;
  fi: xmp_frame_info;
  moduleName: string;
  format : string;
  rec: TRectangle;
  width: Single = 600.0;
  height: Single = 400.0;
  DropText: PChar = 'drop chiptune file here for play';
  BadText: PChar = 'file is not support';
  badFile: Boolean;
  averageVolume: array[0..600] of single;  // Average volume history
  exponent: single = 1.0;                  // Audio exponentiation value

procedure FillAudio(bufferData: Pointer; frames: LongWord); cdecl;
begin
  if xmp_play_buffer(ctx, bufferData, frames * 4, 0) < 0 then
    playing := False;
end;

procedure ProcessAudio(buffer: pointer; frames:LongWord); cdecl;
var samples, left, right: psingle;
    average: single;
    frame: integer;
    i: integer;
begin
  samples:= buffer; // Samples internally stored as <float>s
  average:= 0.0;    // Temporary average volume

  for frame:=0 to frames-1 do
  begin
    left := @samples[frame * 2 + 0];
    right := @samples[frame * 2 + 1];
    if left^ < 0.0 then  left^:=power(abs(left^),exponent) * -1.0
    else
    left^:=power(abs(left^),exponent) * 1.0;

    if right^< 0.0 then right^ :=power(abs(right^),exponent) * -1.0
    else
    right^ :=power(abs(right^),exponent) * 1.0;
    average += abs(left^) / frames;   // accumulating average volume
    average += abs(right^) / frames;
  end;

  // Moving history to the left
  for  i := 0 to 600 do averageVolume[i] := averageVolume[i + 1];
  averageVolume[600] := average;         // Adding last average value
end;


constructor TRayApplication.Create(TheOwner: TComponent);
var
  thelib: string;
begin
  inherited Create(TheOwner);
  InitWindow(800, 600, AppTitle); // for window settings, look at example - window flags
  {$IFDEF windows}
  thelib := 'libxmp.dll';
  {$Else}
  thelib := 'libxmp-64.so';
  {$ENDIF}

  badFile := False;  playing := False;

  if xmp_Load(GetApplicationDirectory + thelib) then
  ctx := xmp_create_context() else
  TraceLog(LOG_ERROR, 'libxmp load error.');

  InitAudioDevice;
  SetAudioStreamBufferSizeDefault(BufferSize);
  Stream := LoadAudioStream(SampleRate, 16, 2);

  SetAudioStreamCallback(Stream,@FillAudio);
  AttachAudioMixedProcessor(@ProcessAudio);

  SetTargetFPS(60); // Set our game to run at 60 frames-per-second
end;

procedure TRayApplication.DoRun;
var droppedFiles: TFilePathList;
    i: integer;
begin

  while (not WindowShouldClose) do // Detect window close button or ESC key
  begin
    // Update your variables here
   if IsFileDropped() then
 begin
   droppedFiles := LoadDroppedFiles();
   if droppedFiles.count = 1 then
   begin
     if playing then
     begin
       xmp_stop_module(ctx);
       playing := False;
       StopAudioStream(stream);
     end;
     if xmp_load_module(ctx, droppedFiles.paths[0]) <> 0 then
    begin
      TraceLog(LOG_ERROR, 'Load module error.');
      badFile := True;
    end else
    begin
      xmp_start_player(ctx, SampleRate, 0);
      playing := True;
      badFile := False;
      PlayAudioStream(stream);
    end;
   end;
   UnloadDroppedFiles(droppedFiles);    // Unload filepaths from memory
 end;

    if playing then
    begin
      xmp_get_module_info(ctx, mi);
      xmp_get_frame_info(ctx,fi);
      moduleName := string(mi.module^.name);
      format := string(mi.module^.typ);
    end else
    StopAudioStream(stream);

    rec := RectangleCreate((GetScreenWidth - width)/2 , (GetScreenHeight - height)/2, width, height);

    // Draw
    BeginDrawing();
      ClearBackground(RAYWHITE);

      for i:=0 to 600 do
      begin
       DrawLine(Round((GetScreenWidth - width)/2 + i),  //X
       Round(500 - averageVolume[i] * 256),
       Round((GetScreenWidth - width)/2 + i), //X
       500, Fade(GRAY,0.5));
      end;

      DrawRectangleRoundedLinesEx(rec, 0.0, 0, 8.0, Fade(GRAY, 0.4));
      DrawRectangleRounded(rec, 0.0, 0, Fade(GRAY, 0.2));

      DrawText(DropText, MeasureText(DropText,20), 120, 20, DARKGRAY);

     try
      if  playing then
      begin
      DrawText(Pchar('bmp: ' + IntToStr(fi.bpm)), 110, 200, 20, DARKGRAY);
      DrawText(Pchar('speed: ' + IntToStr(fi.speed)), 110, 220, 20, DARKGRAY);
      DrawText(Pchar('position: ' + IntToStr(fi.pos)), 110, 240, 20, DARKGRAY);
      DrawText(Pchar('pattern: ' + IntToStr(fi.pattern)), 110, 260, 20, DARKGRAY);
      DrawText(Pchar('row: ' + IntToStr(fi.row)), 110, 280, 20, DARKGRAY);
      DrawText(Pchar('module channels: ' + IntToStr(mi.module^.chn)), 110, 300, 20, DARKGRAY);
      DrawText(Pchar('used channels: ' + IntToStr(fi.virt_used)), 110, 320, 20, DARKGRAY);
      DrawText(Pchar('Title : ' +  moduleName), 110, 340, 20, DARKGRAY);
      DrawText(Pchar('type : ' + format), 110, 360, 20, DARKGRAY);
      end;
      if BadFile then DrawText(BadText, MeasureText(DropText,20) , 140 , 20, RED);
     except
       begin
         playing := false;

       end;
     end;
    EndDrawing();
  end;

  // Stop program loop
  Terminate;
end;

destructor TRayApplication.Destroy;
begin
  // De-Initialization
  UnloadAudioStream(stream);   // Close raw audio stream and delete buffers from RAM
  CloseAudioDevice();         // Close audio device (music streaming is automatically stopped)

  xmp_end_player(ctx);
  xmp_release_module(ctx);
  xmp_free_context(ctx);
  xmp_UnLoad();
  CloseWindow(); // Close window and OpenGL context
  inherited Destroy;
end;

var
  Application: TRayApplication;
begin
  Application:=TRayApplication.Create(nil);
  Application.Title:=AppTitle;
  Application.Run;
  Application.Free;
end.

