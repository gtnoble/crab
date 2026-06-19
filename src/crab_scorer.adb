
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

   function Score (S : in out State; Chunk : String) return Integer is
      Chunk_CS  : Natural;
      Joint_Str : constant String := UBS.To_String (S.Query_Str) & Chunk;
      Joint_CS  : Natural;
   begin
      --  Chunk compression into persistent buffer
      --  Ensure persistent buffers can hold this chunk + joint string.
      --  For byte-mode chunking, Init pre-allocated the correct size;
      --  for line mode the buffers grow lazily on the first call.
      declare
         Q_Len : constant Natural := UBS.Length (S.Query_Str);
         Needed_Chunk : constant Natural :=
           Crab_Compression.Compress_Bound (S.Algo, Chunk'Length);
         Needed_Joint : constant Natural :=
           Crab_Compression.Compress_Bound (S.Algo, Chunk'Length + Q_Len);
      begin
         if Needed_Chunk > S.Chunk_Buf'Length then
            S.Chunk_Buf := new Crab_Compression.Byte_Array
              (1 .. Positive'Max (Needed_Chunk, S.Chunk_Buf'Length * 2));
         end if;
         if Needed_Joint > S.Joint_Buf'Length then
            S.Joint_Buf := new Crab_Compression.Byte_Array
              (1 .. Positive'Max (Needed_Joint, S.Joint_Buf'Length * 2));
         end if;
      end;
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
