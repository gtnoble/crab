--  Crab_Zlib — Thin Ada binding to libz compress2 / compressBound

with Interfaces.C;

package Crab_Zlib is

   Zlib_Error : exception;

   type Byte_Array is array (Natural range <>) of
     Interfaces.C.unsigned_char;
   --  Byte buffer type used for all compression I/O.

   function Compress_Bound (Source_Len : Natural) return Natural;
   --  Upper bound (bytes) for the compressed size of Source_Len bytes.

   procedure Compress_Into
     (Source   : String;
      Level    : Integer;
      Dest     : in out Byte_Array;
      Dest_Len : out Natural);
   --  Compress Source into the pre-allocated Dest buffer.
   --  Dest must be at least Compress_Bound (Source'Length) bytes.
   --  Raises Zlib_Error on failure.
   --  Level translation:
   --    crab -1 = stored blocks  → zlib 0 (Z_NO_COMPRESSION)
   --    crab  0 = default (6)    → zlib -1 (Z_DEFAULT_COMPRESSION)
   --    crab 1-9 = pass through

   function Compress (Source : String; Level : Integer) return Natural;
   --  Convenience wrapper: auto-allocates buffer,
   --  compresses, returns compressed size.

end Crab_Zlib;
