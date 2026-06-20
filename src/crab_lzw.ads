--  Crab_LZW — Pure Ada LZW compression with unbounded dictionary
--  and dictionary-priming support for mutual-information scoring

with Crab_Zlib;
with Interfaces.C;

package Crab_LZW is

   LZW_Error : exception;

   function Compress_Bound (Input_Size : Natural) return Natural;
   --  Conservative upper bound for compressed size.
   --  Uses Input_Size * 2 + 16 to account for worst-case code-width
   --  growth on incompressible data.

   type LZW_Stream is limited private;
   --  An LZW streaming compression context.
   --  Limited to prevent copying; managed via Init_Stream / Free_Stream.

   type LZW_Stream_Access is access all LZW_Stream;

   function Init_Stream return LZW_Stream_Access;
   --  Allocate and initialise a new LZW stream with empty string table.
   --  Raises LZW_Error if allocation fails.

   procedure Load_Dict (S : in out LZW_Stream; Dict : String);
   --  Prime the string table by compressing Dict through it
   --  (no output produced).  Must be called before Compress_Stream.
   --  After Compress_Stream finishes, the stream state is consumed;
   --  Load_Dict must be called again before the next Compress_Stream.

   procedure Compress_Stream
     (S        : in out LZW_Stream;
      Source   : String;
      Dest     : in out Crab_Zlib.Byte_Array;
      Level    : Integer;
      Dest_Len : out Natural);
   --  Compress Source using the primed string table.
   --  Level is accepted for interface compatibility but ignored
   --  (LZW has no compression-level tuning).
   --  Dest must be at least Compress_Bound (Source'Length) bytes.
   --  Raises LZW_Error if compression fails or output overflows Dest.

   procedure Free_Stream (S : in out LZW_Stream_Access);
   --  Deallocate the stream and all internal arrays.

   function Compress_Bare
     (Source : String;
      Dict   : String) return Natural;
   --  Convenience: Init_Stream → Load_Dict → Compress_Stream →
   --  Free_Stream.  Returns compressed size.

   --  Decompression (for roundtrip testing)
   function Decompress
     (Source     : Crab_Zlib.Byte_Array;
      Source_Len : Natural) return String;
   --  Reconstruct the original string from LZW-compressed data.
   --  Raises LZW_Error on malformed input.

private

   MAX_DICT    : constant := 262_143;   --  2^18 - 1 entries
   HASH_SIZE   : constant := 524_287;   --  prime > 2 * MAX_DICT
   CLEAR_CODE  : constant := 256;
   FIRST_CODE  : constant := 257;
   INIT_BITS   : constant := 9;

   subtype UC is Interfaces.C.unsigned_char;

   type Dict_Array is array (Natural range <>) of Natural;
   type Byte_Dict_Array is array (Natural range <>) of UC;

   --  Zero-initialised sentinel values for array defaults
   Zero_Byte : constant UC := UC'(0);

   type LZW_Stream is limited record
      --  String table contents
      Prefix     : Dict_Array (0 .. MAX_DICT)       := (others => 0);
      Suffix     : Byte_Dict_Array (0 .. MAX_DICT)  := (others => Zero_Byte);

      --  Hash table for fast lookup of (prefix, byte) → code
      Hash_Code  : Dict_Array (0 .. HASH_SIZE - 1)  := (others => 0);
      Hash_Gen   : Dict_Array (0 .. HASH_SIZE - 1)  := (others => 0);
      Generation : Natural := 0;

      --  Current compression state
      Next_Code  : Natural := FIRST_CODE;
      Code_Bits  : Natural := INIT_BITS;

      --  Residual prefix from Load_Dict for continuation
      Have_Prefix : Boolean := False;
      Resid_Prefix : Natural := 0;
   end record;

end Crab_LZW;
