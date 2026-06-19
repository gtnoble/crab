package body Crab_Chunker is

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

end Crab_Chunker;
