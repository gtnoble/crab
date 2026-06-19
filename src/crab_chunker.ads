--  Crab_Chunker — Streaming iterator over fixed-size overlapping chunks

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

   type Line_State is private;
   --  Iterator state for line-based chunking. Holds a reference
   --  to the input buffer and pre-computed line-start offsets.

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

private

   type Buf_Access is access constant String;

   type State is record
      Buf    : Buf_Access;
      Size   : Positive;
      Step   : Natural;
      Cursor : Natural;
   end record;

   type Line_Array is array (Positive range <>) of Natural;
   type Line_Array_Access is access Line_Array;
   --  Byte offsets of each line start within the buffer.

   type Line_State is record
      Buf         : Buf_Access;
      Line_Count  : Positive;   --  lines per chunk
      Step        : Natural;     --  lines to advance per chunk
      Num_Lines   : Positive;   --  total lines in buffer
      Line_Starts : Line_Array_Access;
      Cursor      : Positive;   --  current line index (1-based)
   end record;

end Crab_Chunker;
