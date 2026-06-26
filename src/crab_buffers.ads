--  Crab_Buffers — Pure-Ada byte buffer type shared across all
--  compression modules.  Replaces the C-oriented Byte_Array that
--  previously lived in Crab_Zlib.

with Ada.Streams;

package Crab_Buffers is
   pragma Pure;

   type Byte_Buffer is array (Natural range <>) of Ada.Streams.Stream_Element;
   --  Pure-Ada byte buffer.  Stream_Element is mod 2**Storage_Unit
   --  (8 bits on all supported platforms), making this equivalent to
   --  an array of octets without any C-type dependency.

end Crab_Buffers;
