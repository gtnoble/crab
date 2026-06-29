--  Crab_LZW — Pure Ada LZW compression with bounded/unbounded dictionary
--  and dictionary-priming support for mutual-information scoring
--  Uses a hash-table data structure.
--  When --lzw-max-codes N is set, LRU leaf eviction with a clock-algorithm
--  second-chance policy bounds memory to O(N).  The decompressor mirrors
--  eviction deterministically — no extra bits in the compressed stream.

with Ada.Containers.Vectors;
with Ada.Finalization;
with Crab_Buffers;

package Crab_LZW is

   LZW_Error : exception;

   function Compress_Bound (Input_Size : Natural) return Natural;
   --  Conservative upper bound for compressed size.
   --  Computed dynamically from the worst-case bit expansion
   --  as the code width grows without bound.

   type LZW_Stream is new Ada.Finalization.Limited_Controlled with private;
   --  An LZW streaming compression context.
   --  Finalize frees all internal hash-table storage.

   procedure Init_Roots (S : in out LZW_Stream);
   --  Initialise the stream with 256 single-byte root nodes
   --  and an empty hash table.  Must be called before first use
   --  and after Reset_Stream if reusing a stream.

   procedure Set_Max_Codes (S : in out LZW_Stream; N : Natural);
   --  Set the maximum number of active codes (codes 256 and above).
   --  0 = unbounded (default).  When N > 0, the string table is bounded
   --  to at most N active codes; LRU leaf eviction with clock-algorithm
   --  second-chance policy reuses code slots when the table is full.
   --  Must be called after Init_Roots and before Load_Dict / Compress_Stream.

   procedure Load_Dict (S : in out LZW_Stream; Dict : String);
   --  Prime the string table by compressing Dict through it
   --  (no output produced).  Must be called before Compress_Stream.
   --  After Compress_Stream finishes, the stream state is consumed;
   --  Load_Dict must be called again before the next Compress_Stream.

   procedure Compress_Stream
     (S        : in out LZW_Stream;
      Source   : String;
      Dest     : in out Crab_Buffers.Byte_Buffer;
      Level    : Integer;
      Dest_Len : out Natural);
   --  Compress Source using the primed string table.
   --  Level is accepted for interface compatibility but ignored
   --  (LZW has no compression-level tuning).
   --  Dest must be at least Compress_Bound (Source'Length) bytes.
   --  Raises LZW_Error if compression fails or output overflows Dest.

   procedure Reset_Stream (S : in out LZW_Stream);
   --  Reset the stream to its initial state (256 single-byte roots,
   --  empty string table).  Preserves the Max_Codes setting.
   --  Preserves the allocation; faster than destroying and recreating
   --  the stream.

   function Compress_Bare
     (Source : String;
      Dict   : String) return Natural;
   --  Convenience: Init_Roots → Load_Dict → Compress_Stream.
   --  Returns compressed size.  Uses unbounded mode (Max_Codes = 0).

   --  Decompression (for roundtrip testing)
   function Decompress
     (Source     : Crab_Buffers.Byte_Buffer;
      Source_Len : Natural) return String;
   --  Reconstruct the original string from LZW-compressed data.
   --  Raises LZW_Error on malformed input.

private

   type LZW_Node is record
      Suffix     : Character;
      Prefix     : Natural;     -- parent code; next-free when Free=True
      Ref_Count  : Natural;     -- how many codes have this as their Prefix
      Referenced : Boolean;     -- clock-algorithm second-chance bit
      Free       : Boolean;     -- True if this slot is in the free list
   end record;

   package Node_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Natural,
      Element_Type => LZW_Node);

   --  Custom open-addressing hash table for O(1) forward lookup.
   --  Replaces Ada.Containers.Hashed_Maps to avoid the overhead of
   --  controlled types, cursors, and per-node allocation.
   type Word64 is mod 2**64;
   type Word64_Array is array (Natural range <>) of Word64;
   type Word64_Array_Access is access all Word64_Array;
   type Natural_Array is array (Natural range <>) of Natural;
   type Natural_Array_Access is access all Natural_Array;

   --  Managed array wrappers — auto-free on finalization or explicit
   --  replacement.  Eliminates manual Unchecked_Deallocation for the
   --  hash-table arrays.
   type Managed_Word64_Array is
     new Ada.Finalization.Limited_Controlled with record
      Data : Word64_Array_Access;
   end record;

   overriding procedure Finalize (A : in out Managed_Word64_Array);

   procedure Set_Array
     (A : in out Managed_Word64_Array; Ptr : Word64_Array_Access);
   --  Free old Data (if any), take ownership of Ptr.

   procedure Clear_Array (A : in out Managed_Word64_Array);
   --  Free Data (if any), set to null.

   function Ptr (A : Managed_Word64_Array) return Word64_Array_Access
     with Inline;
   --  Direct pointer for zero-overhead indexed access.

   type Managed_Natural_Array is
     new Ada.Finalization.Limited_Controlled with record
      Data : Natural_Array_Access;
   end record;

   overriding procedure Finalize (A : in out Managed_Natural_Array);

   procedure Set_Array
     (A : in out Managed_Natural_Array; Ptr : Natural_Array_Access);

   procedure Clear_Array (A : in out Managed_Natural_Array);

   function Ptr (A : Managed_Natural_Array) return Natural_Array_Access
     with Inline;

   type LZW_Stream is new Ada.Finalization.Limited_Controlled with record
      Nodes        : Node_Vectors.Vector;
      Next_Code    : Natural := 256;
      Code_Bits    : Natural := 9;
      Have_Prefix  : Boolean := False;
      Resid_Prefix : Natural := 0;
      --  Open-addressing hash table: (Prefix, Suffix) → Code
      Hash_Keys    : Managed_Word64_Array;
      Hash_Vals    : Managed_Natural_Array;
      Hash_Mask    : Natural := 0;
      Hash_Count   : Natural := 0;
      Hash_Deleted_Count : Natural := 0;
      --  Bounded-mode fields
      Max_Codes    : Natural := 10_000_000;  -- 0 = unbounded
      Active_Codes : Natural := 0;    -- count of non-evicted codes ≥ 256
      Clock_Hand   : Natural := 256;  -- sweeps through codes for eviction
      Free_Head    : Natural := 0;    -- head of free list, 0 = empty
   end record;

end Crab_LZW;
