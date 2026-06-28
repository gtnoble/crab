--  Crab_TopK -- Bounded binary heap maintaining top-k scored chunks

with Ada.Strings.Unbounded;

package Crab_TopK is

   type Heap (K : Positive) is private;
   --  Bounded binary heap of at most K Scored_Entry values.
   --  K is a discriminant specifying the heap capacity.

   function Create (K : Positive; Invert : Boolean) return Heap;
   --  Initialise an empty heap with capacity K.
   --  Invert=False -> top-k (best scores kept).
   --  Invert=True  -> bottom-k (worst scores kept).

   procedure Insert
     (Heap      : in out Crab_TopK.Heap;
      Score     : Integer;
      File_Path : String;
      Offset    : Natural;
      Data      : String);
   --  Insert a scored chunk.  If the heap is full and the new score
   --  does not beat the root, the entry is discarded.

   function Is_Empty (Heap : Crab_TopK.Heap) return Boolean;
   --  True if no entries have been inserted.

   function Count (Heap : Crab_TopK.Heap) return Natural;
   --  Current number of entries in the heap.

   procedure Print (Heap : in out Crab_TopK.Heap);
   --  Extract entries in sorted order (best first), print headers
   --  and chunk data to Standard_Output.

   procedure Print_File_Scores (Heap : in out Crab_TopK.Heap);
   --  Extract entries in sorted order (best first), print one line
   --  per entry: "filename score" to Standard_Output.
   --  No chunk data, no headers -- file-mode output.

   function Entry_Data (Heap : Crab_TopK.Heap; Rank : Positive) return String
     with Pre => Rank <= Count (Heap);
   --  Return the Data string of the Rank-th entry when sorted best-first.
private

   type Scored_Entry is record
      Score     : Integer;
      File_Path : Ada.Strings.Unbounded.Unbounded_String;
      Offset    : Natural;
      Data      : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   type Entry_Array is array (Positive range <>) of Scored_Entry;

   type Heap (K : Positive) is record
      Entries : Entry_Array (1 .. K);
      Size    : Natural := 0;
      Invert  : Boolean;
   end record;

end Crab_TopK;
