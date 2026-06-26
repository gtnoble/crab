--  Crab_Buffers — Controlled heap-allocated byte buffer shared across
--  all compression modules.  Finalize frees the underlying storage
--  automatically, eliminating manual Unchecked_Deallocation.

with Ada.Finalization;
with Ada.Streams;
with System;

package Crab_Buffers is

   type Byte_Buffer is new Ada.Finalization.Limited_Controlled with private;
   --  Heap-allocated byte buffer with automatic cleanup.
   --  Finalize frees the underlying storage.

   procedure Resize (B : in out Byte_Buffer; Size : Natural);
   --  Reallocate to hold at least Size bytes.  Old contents are
   --  discarded.  If Size = 0 the buffer is deallocated.

   function Length (B : Byte_Buffer) return Natural;
   --  Current allocated size in bytes.  Returns 0 if unallocated.

   function Data_Address (B : Byte_Buffer) return System.Address;
   --  Address of the first byte, for C FFI overlays.
   --  Returns System.Null_Address if Length = 0.

   function Element
     (B : Byte_Buffer; Index : Positive) return Ada.Streams.Stream_Element
     with Pre => Index <= B.Length;

   procedure Set_Element
     (B : in out Byte_Buffer; Index : Positive;
      Value : Ada.Streams.Stream_Element)
     with Pre => Index <= B.Length;
   --  Indexed access (1-based).  For non-performance-critical use.

   --  Direct access for performance-sensitive code (LZW bit-writer)
   type Element_Array is array (Natural range <>) of
     Ada.Streams.Stream_Element;
   type Element_Array_Access is access all Element_Array;

   function Raw_Data (B : Byte_Buffer) return Element_Array_Access;
   --  Direct pointer to the underlying array.  Caller must not free.
   --  Returns null if Length = 0.  The array bounds are 1 .. Length.

   overriding procedure Finalize (B : in out Byte_Buffer);

private

   type Byte_Buffer is new Ada.Finalization.Limited_Controlled with record
      Data : Element_Array_Access;
   end record;

end Crab_Buffers;
