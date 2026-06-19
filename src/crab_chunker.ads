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

private
   type Buf_Access is access constant String;

   type State is record
      Buf    : Buf_Access;
      Size   : Positive;
      Step   : Natural;
      Cursor : Natural;
   end record;
end Crab_Chunker;
