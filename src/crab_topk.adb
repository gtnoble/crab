with Ada.Streams.Stream_IO;
with Ada.Containers.Generic_Array_Sort;

package body Crab_TopK is

   package UBS renames Ada.Strings.Unbounded;

   function Image (N : Integer) return String is
      S : constant String := Integer'Image (N);
   begin
      if S (S'First) = ' ' then
         return S (S'First + 1 .. S'Last);
      end if;
      return S;
   end Image;

   --  ------------------------------------------------------------------
   --  Heap comparison: is A "worse" than B?
   --  In normal mode (min-heap): worse = smaller score.
   --    Scores equal -> later offset is worse (REQ-032).
   --  In invert mode (max-heap): worse = larger score.
   --    Scores equal -> later offset is worse.
   --  ------------------------------------------------------------------

   function Heap_Less
     (A, B   : Scored_Entry;
      Invert : Boolean) return Boolean
   is
   begin
      if A.Score /= B.Score then
         if Invert then
            return A.Score > B.Score;
         else
            return A.Score < B.Score;
         end if;
      else
         return A.Offset > B.Offset;
      end if;
   end Heap_Less;

   --  ------------------------------------------------------------------
   --  Sort comparison: best first for Print.
   --  Controlled by Sort_Is_Invert, set before each sort.
   --  ------------------------------------------------------------------

   Sort_Is_Invert : Boolean := False;

   function "<" (A, B : Scored_Entry) return Boolean is
   begin
      if A.Score /= B.Score then
         if Sort_Is_Invert then
            return A.Score < B.Score;
         else
            return A.Score > B.Score;
         end if;
      else
         return A.Offset < B.Offset;
      end if;
   end "<";

   --  ------------------------------------------------------------------
   --  Should_Replace: should the new score replace the root?
   --  Normal (min-heap): replace if new > root (better than worst).
   --  Invert (max-heap): replace if new < root (worse than best).
   --  ------------------------------------------------------------------

   function Should_Replace (H : Heap; Score : Integer) return Boolean is
   begin
      if H.Invert then
         return Score < H.Entries (1).Score;
      else
         return Score > H.Entries (1).Score;
      end if;
   end Should_Replace;

   --  ------------------------------------------------------------------
   --  Heap operations (1-based array)
   --  ------------------------------------------------------------------

   procedure Sift_Up (H : in out Heap; Idx : Positive) is
      Child  : Positive := Idx;
      Parent : Positive;
      Tmp    : Scored_Entry;
   begin
      while Child > 1 loop
         Parent := Child / 2;
         if Heap_Less (H.Entries (Child), H.Entries (Parent), H.Invert) then
            Tmp := H.Entries (Child);
            H.Entries (Child) := H.Entries (Parent);
            H.Entries (Parent) := Tmp;
            Child := Parent;
         else
            exit;
         end if;
      end loop;
   end Sift_Up;

   procedure Sift_Down (H : in out Heap; Idx : Positive) is
      Root     : Positive := Idx;
      Left     : Positive;
      Right    : Positive;
      Smallest : Positive;
      Tmp      : Scored_Entry;
   begin
      loop
         Left  := 2 * Root;
         Right := 2 * Root + 1;
         Smallest := Root;
         if Left <= H.Size
           and then Heap_Less
             (H.Entries (Left), H.Entries (Smallest), H.Invert)
         then
            Smallest := Left;
         end if;
         if Right <= H.Size
           and then Heap_Less
             (H.Entries (Right), H.Entries (Smallest), H.Invert)
         then
            Smallest := Right;
         end if;
         exit when Smallest = Root;
         Tmp := H.Entries (Root);
         H.Entries (Root) := H.Entries (Smallest);
         H.Entries (Smallest) := Tmp;
         Root := Smallest;
      end loop;
   end Sift_Down;

   --  ------------------------------------------------------------------
   --  Public operations
   --  ------------------------------------------------------------------

   function Create (K : Positive; Invert : Boolean) return Heap is
      Dummy_Entry : constant Scored_Entry :=
        (Score     => 0,
         File_Path => UBS.Null_Unbounded_String,
         Offset    => 0,
         Data      => UBS.Null_Unbounded_String);
   begin
      return (K       => K,
              Entries => (others => Dummy_Entry),
              Size    => 0,
              Invert  => Invert);
   end Create;

   procedure Insert
     (Heap      : in out Crab_TopK.Heap;
      Score     : Integer;
      File_Path : String;
      Offset    : Natural;
      Data      : String)
   is
   begin
      if Heap.Size < Heap.K then
         Heap.Size := Heap.Size + 1;
         Heap.Entries (Heap.Size) :=
           (Score     => Score,
            File_Path => UBS.To_Unbounded_String (File_Path),
            Offset    => Offset,
            Data      => UBS.To_Unbounded_String (Data));
         Sift_Up (Heap, Heap.Size);
      else
         if Should_Replace (Heap, Score) then
            Heap.Entries (1) :=
              (Score     => Score,
               File_Path => UBS.To_Unbounded_String (File_Path),
               Offset    => Offset,
               Data      => UBS.To_Unbounded_String (Data));
            Sift_Down (Heap, 1);
         end if;
      end if;
   end Insert;

   function Is_Empty (Heap : Crab_TopK.Heap) return Boolean is
      (Heap.Size = 0);

   function Count (Heap : Crab_TopK.Heap) return Natural is
      (Heap.Size);

   --  ------------------------------------------------------------------
   --  Print -- extract sorted entries and output
   --  ------------------------------------------------------------------

   procedure Print (Heap : in out Crab_TopK.Heap) is
      type Sort_Array is array (Positive range <>) of Scored_Entry;

      procedure Sort is new Ada.Containers.Generic_Array_Sort
        (Index_Type   => Positive,
         Element_Type => Scored_Entry,
         Array_Type   => Sort_Array);

      subtype Index_Range is Positive range 1 .. Heap.Size;
      Arr : Sort_Array (Index_Range);

      Stdout : Ada.Streams.Stream_IO.File_Type;

      procedure Write_Str (S : String) is
         Buf : Ada.Streams.Stream_Element_Array
           (1 .. Ada.Streams.Stream_Element_Offset (S'Length));
      begin
         for I in S'Range loop
            Buf (Ada.Streams.Stream_Element_Offset (I - S'First + 1)) :=
              Ada.Streams.Stream_Element (Character'Pos (S (I)));
         end loop;
         Ada.Streams.Stream_IO.Write (Stdout, Buf);
      end Write_Str;
   begin
      --  Copy entries
      for I in Index_Range loop
         Arr (I) := Heap.Entries (I);
      end loop;

      --  Set sort direction and sort
      Sort_Is_Invert := Heap.Invert;
      Sort (Arr);

      Ada.Streams.Stream_IO.Open
        (Stdout, Ada.Streams.Stream_IO.Out_File, "/dev/stdout");

      for Rank in Index_Range loop
         declare
            E : Scored_Entry renames Arr (Rank);
         begin
            Write_Str ("## chunk=" & Image (Rank)
                       & " score=" & Image (E.Score)
                       & " file=" & UBS.To_String (E.File_Path)
                       & " offset=" & Image (E.Offset)
                       & Character'Val (10));
            Write_Str (UBS.To_String (E.Data));
            if Rank < Heap.Size then
               Write_Str (Character'Val (10) & Character'Val (10));
            end if;
         end;
      end loop;

      Ada.Streams.Stream_IO.Close (Stdout);
   end Print;

end Crab_TopK;
