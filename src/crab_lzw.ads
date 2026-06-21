--  Crab_LZW — Pure Ada LZW compression with unbounded dictionary
--  and dictionary-priming support for mutual-information scoring
--  Uses a hash-table data structure: no arbitrary size limits.

with Crab_Zlib;
with Interfaces.C;
with Ada.Containers.Vectors;
with Ada.Containers.Hashed_Maps;

package Crab_LZW is

   LZW_Error : exception;

   function Compress_Bound (Input_Size : Natural) return Natural;
   --  Conservative upper bound for compressed size.
   --  Computed dynamically from the worst-case bit expansion
   --  as the code width grows without bound.

   type LZW_Stream is limited private;
   --  An LZW streaming compression context.
   --  Limited to prevent copying; managed via Init_Stream / Free_Stream.

   type LZW_Stream_Access is access all LZW_Stream;

   function Init_Stream return LZW_Stream_Access;
   --  Allocate and initialise a new LZW stream with 256 single-byte
   --  root nodes.  Raises LZW_Error if allocation fails.

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

   subtype UC is Interfaces.C.unsigned_char;

   type LZW_Node is record
      Suffix      : UC;
      Prefix      : Natural;     -- parent code; 0 for single-byte roots
   end record;

   package Node_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Natural,
      Element_Type => LZW_Node);

   --  Hash table for O(1) forward lookup
   type LZW_Key is record
      Prefix : Natural;
      Suffix : Natural;
   end record;

   function LZW_Hash (K : LZW_Key) return Ada.Containers.Hash_Type;

   package LZW_Code_Maps is new Ada.Containers.Hashed_Maps
     (Key_Type        => LZW_Key,
      Element_Type    => Natural,
      Hash            => LZW_Hash,
      Equivalent_Keys => "=");

   type LZW_Stream is limited record
      Nodes       : Node_Vectors.Vector;
      Next_Code   : Natural := 256;
      Code_Bits   : Natural := 9;
      Have_Prefix : Boolean := False;
      Resid_Prefix : Natural := 0;
      Code_Map    : LZW_Code_Maps.Map;
   end record;

end Crab_LZW;
