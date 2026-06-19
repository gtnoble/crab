with Ada.Strings.Unbounded;

package body Crab_Scorer is

   package UBS renames Ada.Strings.Unbounded;

   function Init
     (Query      : String;
      Chunk_Size : Positive;
      Algo       : Crab_Compression.Algorithm;
      Level      : Integer) return State
   is
      Query_CS : Natural;
   begin
      --  Compress query once (one-shot, temp buffer freed on return)
      Query_CS := Crab_Compression.Compress (Algo, Query, Level);

      return (Algo      => Algo,
              Level     => Level,
              Query_Str => UBS.To_Unbounded_String (Query),
              Query_CS  => Query_CS,
              Chunk_Buf => new Crab_Compression.Byte_Array
                (1 .. Crab_Compression.Compress_Bound
                        (Algo, Chunk_Size)),
              Joint_Buf => new Crab_Compression.Byte_Array
                (1 .. Crab_Compression.Compress_Bound
                        (Algo, Query'Length + Chunk_Size)));
   end Init;

   function Score (S : State; Chunk : String) return Integer is
      Chunk_CS  : Natural;
      Joint_Str : constant String := UBS.To_String (S.Query_Str) & Chunk;
      Joint_CS  : Natural;
   begin
      --  Chunk compression into persistent buffer
      Crab_Compression.Compress_Into
        (Algo     => S.Algo,
         Source   => Chunk,
         Level    => S.Level,
         Dest     => S.Chunk_Buf.all,
         Dest_Len => Chunk_CS);

      --  Joint compression into persistent buffer
      Crab_Compression.Compress_Into
        (Algo     => S.Algo,
         Source   => Joint_Str,
         Level    => S.Level,
         Dest     => S.Joint_Buf.all,
         Dest_Len => Joint_CS);

      return Integer (S.Query_CS) + Integer (Chunk_CS)
        - Integer (Joint_CS);
   end Score;

end Crab_Scorer;
