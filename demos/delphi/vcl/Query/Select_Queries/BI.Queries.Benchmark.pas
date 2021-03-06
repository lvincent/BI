unit BI.Queries.Benchmark;

interface

uses
  System.Classes, System.SysUtils, BI.Data;

type
  TQueryBenchmark=record
  public
    class function BenchmarkAll(const AItems:TStrings):TDataItem; static;

    class function Benchmark(const AIndex:Integer;
                             out AIterations:Integer;
                             out Rows:Int64):Int64; static;

    class function MultiCPU(const IsMultiCPU,IsThreadLoop:Boolean):Int64; static;
  end;

implementation

uses
  BI.Arrays, BI.DataSource, System.Diagnostics, BI.Tests.SelectSamples,
  System.Threading;

class function TQueryBenchmark.Benchmark(const AIndex:Integer;
                                         out AIterations:Integer;
                                         out Rows:Int64):Int64;

  function GetIterations:Integer;
  begin
    if AIndex=25 then
       result:=100  // slow distinct ProductID, Discount
    else
    if AIndex=22 then
       result:=100  // slow "movies"
    else
    if AIndex=19 then
       result:=1000  // slow "Year"
    else
       result:=10000;
  end;

var t1 : TStopWatch;
    tmp : TDataSelect;
    Item : TDataItem;
    t : Integer;
begin
  t1:=TStopwatch.StartNew;

  tmp:=TSelectSamples.CreateSelect(nil,AIndex);
  try
    Item:=nil;
    try
      AIterations:=GetIterations;

      for t:=1 to AIterations do
      begin
        if Item=nil then
           Item:=tmp.Calculate
        else
        begin
          // Query is calculated "on top" of existing results instead of
          // recreating the results again, for a more stressed benchmark.

          Item.Resize(0);
          tmp.Calculate(Item);
        end;
      end;

      if Item=nil then
         Rows:=0
      else
         Rows:=Item.Count;
    finally
      Item.Free;
    end;
  finally
    tmp.Free;
  end;

  result:=t1.ElapsedMilliseconds;
end;

class function TQueryBenchmark.BenchmarkAll(const AItems:TStrings):TDataItem;
var t : Integer;
    tmpIterations : Integer;
    tmpPerSecond : Single;

    Rows,
    tmpElapsed : Int64;

    D : TDataItem;
begin
  D:=TDataItem.Create(True);

  D.Items.Add('#',TDataKind.dkInt32);
  D.Items.Add('Test',TDataKind.dkText);
  D.Items.Add('Iterations',TDataKind.dkInt32);
  D.Items.Add('Msec',TDataKind.dkInt64);
  D.Items.Add('Iter/Second',TDataKind.dkSingle);
  D.Items.Add('Rows',TDataKind.dkInt64);

  D.Resize(AItems.Count);

  for t:=0 to D.Count-1 do
  begin
    D.Item[0].Int32Data[t]:=t;
    D.Item[1].TextData[t]:=AItems[t];

    if t<>21 then  // <-- 21 fails because the second time Average is calculated, it is an AsTable result !
    begin
      tmpElapsed:=TQueryBenchmark.Benchmark(t,tmpIterations,Rows);

      D.Item[3].Int64Data[t]:=tmpElapsed;
      D.Item[2].Int32Data[t]:=tmpIterations;

      if tmpElapsed=0 then
         tmpPerSecond:=0
      else
         tmpPerSecond:=1000*tmpIterations/tmpElapsed;

      D.Item[4].SingleData[t]:=tmpPerSecond;
      D.Item[5].Int64Data[t]:=Rows;
    end;
  end;

  D.Name:='Total: '+D.Item[3].Int64Data.Sum.ToString+' msec';

  result:=D;
end;

class function TQueryBenchmark.MultiCPU(const IsMultiCPU,IsThreadLoop:Boolean):Int64;

var Data : Array of TDataItem;
    Query : Array of TDataSelect;
    tmpMax : Integer;

  procedure FreeDatas;
  var t : Integer;
  begin
    for t:=0 to tmpMax-1 do
    begin
      Data[t].Free;
      Query[t].Free;
    end;
  end;

const
  MaxLoop=1000;

  procedure BenchQuery(N:Integer);
  var Query : TDataSelect;
      Data : TDataItem;
      Loop : Integer;
  begin
    for Loop:=1 to MaxLoop do
    begin
      Query:=TSelectSamples.CreateSelect(nil,N);
      Data:=Query.Calculate;

      Data.Free;
      Query.Free;
    end;
  end;

var Loop,
    t : Integer;
    t1 : TStopWatch;
begin
  t1:=TStopwatch.StartNew;

  tmpMax:=23;//ListBox1.Count;

  SetLength(Data,tmpMax);
  SetLength(Query,tmpMax);

  if IsMultiCPU then
  begin
    if IsThreadLoop then
       TParallel.&For(0,tmpMax-1, procedure(N:Integer)
       var Query : TDataSelect;
           Data : TDataItem;
           Loop : Integer;
       begin
         for Loop:=1 to MaxLoop do
         begin
           Query:=TSelectSamples.CreateSelect(nil,N);
           Data:=Query.Calculate;

           Data.Free;
           Query.Free;
         end;
       end)
    else
    begin
      for Loop:=1 to MaxLoop do
      begin
        TParallel.&For(0,tmpMax-1,procedure(N:Integer)
        begin
          Query[N]:=TSelectSamples.CreateSelect(nil,N);
          Data[N]:=Query[N].Calculate;
        end);

        FreeDatas;
      end;
    end;
  end
  else
  begin
    if IsThreadLoop then
       for t:=0 to tmpMax-1 do
           BenchQuery(t)
    else
    begin
      for Loop:=1 to MaxLoop do
      begin
        for t:=0 to tmpMax-1 do
        begin
          Query[t]:=TSelectSamples.CreateSelect(nil,t);
          Data[t]:=Query[t].Calculate;
        end;

        FreeDatas;
      end;
    end;
  end;

  result:=t1.ElapsedMilliseconds;
end;

end.
