with Ada.Characters.Latin_1;

package body Crab_Chunker is

   LF : constant Character := Ada.Characters.Latin_1.LF;

   --  =================================================================
   --  Byte-mode chunking
   --  =================================================================

   function Start
     (Buf     : String;
      Size    : Positive;
      Overlap : Natural) return State
   is
      Step : constant Natural :=
        Natural'Max (1, (Size * (100 - Overlap)) / 100);
   begin
      return (Buf    => Buf'Unrestricted_Access,
              Size   => Size,
              Step   => Step,
              Cursor => Buf'First);
   end Start;

   function Has_Next (S : State) return Boolean is
      (S.Cursor <= S.Buf.all'Last);

   function Next (S : in out State) return String is
      End_Pos : constant Natural :=
        Natural'Min (S.Cursor + S.Size - 1, S.Buf.all'Last);
      Chunk   : constant String := S.Buf (S.Cursor .. End_Pos);
   begin
      S.Cursor := S.Cursor + S.Step;
      return Chunk;
   end Next;

   --  =================================================================
   --  Line-mode chunking
   --  =================================================================

   function Start_Lines
     (Buf        : String;
      Line_Count : Positive;
      Overlap    : Natural) return Line_State
   is
      Step      : constant Natural :=
        Natural'Max (1, (Line_Count * (100 - Overlap)) / 100);
      Num_Lines : Positive := 1;  --  at least the first line
   begin
      --  Count lines by counting newline characters
      for I in Buf'Range loop
         if Buf (I) = LF then
            Num_Lines := Num_Lines + 1;
         end if;
      end loop;

      declare
         LS   : constant Line_Array_Access :=
           new Line_Array (1 .. Num_Lines);
         Idx  : Positive := 1;
      begin
         LS (1) := Buf'First;

         for I in Buf'Range loop
            if Buf (I) = LF and then I < Buf'Last then
               Idx := Idx + 1;
               LS (Idx) := I + 1;
            end if;
         end loop;

         return (Buf             => Buf'Unrestricted_Access,
                 Line_Count      => Line_Count,
                 Step            => Step,
                 Num_Lines       => Num_Lines,
                 Line_Starts     => LS,
                 Cursor          => 1,
                 Last_Start_Line => 1);
      end;
   end Start_Lines;

   function Has_Next (S : Line_State) return Boolean is
      (S.Cursor <= S.Num_Lines);

   function Next (S : in out Line_State) return String is
      First_Line : constant Positive := S.Cursor;
      Last_Line  : constant Natural :=
        Natural'Min (First_Line + S.Line_Count - 1, S.Num_Lines);
      Start_Pos  : constant Natural := S.Line_Starts (First_Line);
      End_Pos    : constant Natural :=
        (if Last_Line = S.Num_Lines
         then S.Buf.all'Last
         else S.Line_Starts (Last_Line + 1) - 1);
   begin
      S.Last_Start_Line := First_Line;
      S.Cursor := S.Cursor + S.Step;
      return S.Buf (Start_Pos .. End_Pos);
   end Next;

   function Start_Line (S : Line_State) return Natural is
   begin
      if S.Last_Start_Line = 0 then
         return 0;
      end if;
      return S.Last_Start_Line - 1;
   end Start_Line;

end Crab_Chunker;
