--  Crab_Chunker — Streaming iterator over fixed-size overlapping chunks

with Ada.Containers.Vectors;
with Ada.Finalization;

package Crab_Chunker is

   type State is private;
   --  Iterator state: holds a reference to the input buffer
   --  and the current cursor position.

   function Start
     (Buf     : String;
      Size    : Positive;
      Overlap : Natural) return State;
   --  Initialise a chunk iterator over Buf.
   --  Size is the chunk size in bytes.
   --  Overlap is the overlap percentage [0, 99].

   function Has_Next (S : State) return Boolean;
   --  True if more chunks remain.

   function Next (S : in out State) return String;
   --  Advance the iterator and return the next chunk as a slice of
   --  the original buffer.  The returned String is valid only until
   --  the next call to Next (or until S / the buffer go out of scope).
   --  The last chunk may be shorter than Size.

   --  Line-mode chunking
   --  ===================

   type Line_State is new Ada.Finalization.Limited_Controlled with private;
   --  Iterator state for line-based chunking. Holds a reference
   --  to the input buffer and pre-computed line-start offsets.
   --  Finalize frees the line-offset vector automatically.

   function Start_Lines
     (Buf        : String;
      Line_Count : Positive;
      Overlap    : Natural) return Line_State;
   --  Initialise a line-mode chunk iterator over Buf.
   --  Line_Count is the number of lines per chunk.
   --  Overlap is the overlap percentage [0, 99] applied to lines.

   function Has_Next (S : Line_State) return Boolean;
   --  True if more chunks remain.

   function Next (S : in out Line_State) return String;
   --  Advance the iterator and return the next chunk (a slice of Buf).
   --  The last chunk may contain fewer than Line_Count lines.

   function Start_Line (S : Line_State) return Natural;
   --  Return the 0‑based line offset of the chunk most recently
   --  returned by Next.  Before the first call to Next, returns 0.

   overriding procedure Finalize (S : in out Line_State);
   --  Free the line-offset vector.

private

   type Buf_Access is access constant String;

   type State is record
      Buf    : Buf_Access;
      Size   : Positive;
      Step   : Natural;
      Cursor : Natural;
   end record;

   package Line_Offset_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Natural);
   --  Byte offsets of each line start within the buffer.

   type Line_State is new Ada.Finalization.Limited_Controlled with record
      Buf         : Buf_Access;
      Line_Count  : Positive;   --  lines per chunk
      Last_Start_Line : Natural := 0;  -- 1‑based line idx of last chunk start
      Step        : Natural;     --  lines to advance per chunk
      Num_Lines   : Positive;   --  total lines in buffer
      Line_Starts : Line_Offset_Vectors.Vector;
      Cursor      : Positive;   --  current line index (1-based)
   end record;

end Crab_Chunker;
